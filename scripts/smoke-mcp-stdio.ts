/**
 * MCP stdio smoke test — proves `gbrain serve` speaks the exact transport
 * GitHub Copilot CLI (and Claude Code/Codex/Cursor) uses, without needing
 * any of those clients installed. Sends initialize → initialized →
 * tools/list over stdio and asserts a sane handshake + tool count.
 *
 * Usage: bun run scripts/smoke-mcp-stdio.ts [command...] (default: bun src/cli.ts serve)
 */
import { spawn } from 'child_process';

const argv = process.argv.slice(2);
const [cmd, ...args] = argv.length > 0 ? argv : ['bun', ['run', 'src/cli.ts', 'serve']].flat() as string[];

const proc = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'pipe'], shell: process.platform === 'win32' });

let buf = '';
const responses: any[] = [];
let done = false;

const timeout = setTimeout(() => {
  if (!done) {
    console.error('SMOKE FAIL: timed out waiting for MCP responses');
    proc.kill();
    process.exit(1);
  }
}, 60_000);

proc.stdout.on('data', (chunk) => {
  buf += chunk.toString();
  let idx;
  while ((idx = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, idx).trim();
    buf = buf.slice(idx + 1);
    if (!line.startsWith('{')) continue;
    try {
      responses.push(JSON.parse(line));
    } catch { /* partial/noise */ }
    check();
  }
});

proc.on('exit', (code) => {
  if (!done) {
    console.error(`SMOKE FAIL: gbrain serve exited early (code ${code}) with ${responses.length} responses`);
    process.exit(1);
  }
});

function check() {
  const init = responses.find((r) => r.id === 1);
  const tools = responses.find((r) => r.id === 2);
  if (!init || !tools) return;
  done = true;
  clearTimeout(timeout);

  const serverInfo = init.result?.serverInfo;
  const toolList = tools.result?.tools ?? [];
  console.log(`serverInfo: ${serverInfo?.name} ${serverInfo?.version}`);
  console.log(`protocolVersion: ${init.result?.protocolVersion}`);
  console.log(`tools: ${toolList.length}`);
  console.log(`sample tools: ${toolList.slice(0, 8).map((t: any) => t.name).join(', ')}`);

  const ok = serverInfo?.name && toolList.length >= 20 &&
    ['search', 'query', 'get_page', 'put_page', 'get_brain_identity'].every(
      (n) => toolList.some((t: any) => t.name === n),
    );
  console.log(ok ? 'SMOKE OK' : 'SMOKE FAIL: missing expected tools or serverInfo');
  proc.kill();
  process.exit(ok ? 0 : 1);
}

function send(obj: unknown) {
  proc.stdin.write(JSON.stringify(obj) + '\n');
}

send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'smoke', version: '0' } } });
send({ jsonrpc: '2.0', method: 'notifications/initialized' });
send({ jsonrpc: '2.0', id: 2, method: 'tools/list' });
