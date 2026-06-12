/**
 * Issue #10 A5 — `gbrain query ""` must exit nonzero.
 *
 * An empty positional defeats the dispatcher's `=== undefined` required-param
 * check, so the empty query used to reach the op handler's throw — and the
 * resulting exit code was then clobbered to 0 by PGLite's clean WASM exit
 * during engine.disconnect(). The fix validates blank query text at the CLI
 * layer (before any engine work) and exits 1 with a usage example; the MCP
 * layer keeps returning the shared handler's structured error.
 *
 * Spawns `bun run src/cli.ts` so the real dispatcher flow is exercised
 * end-to-end. GBRAIN_HOME points at a nonexistent dir — the validation fires
 * before any config/engine load, so no brain is needed.
 */

import { describe, test, expect } from 'bun:test';
import { spawnSync } from 'node:child_process';

function runCli(args: string[]): { stdout: string; stderr: string; status: number } {
  const result = spawnSync('bun', ['run', 'src/cli.ts', ...args], {
    cwd: process.cwd(),
    encoding: 'utf8',
    env: { ...process.env, GBRAIN_HOME: '/tmp/gbrain-test-query-empty-nonexistent' },
  });
  return {
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    status: result.status ?? -1,
  };
}

describe('`gbrain query ""` exits 1 with the validation message', () => {
  test('empty string', () => {
    const { stderr, status } = runCli(['query', '']);
    expect(status).toBe(1);
    expect(stderr).toContain('query requires either `query` (text) or `image` (base64 bytes)');
    expect(stderr).toContain('Try: gbrain query "alice meeting notes"');
  });

  test('whitespace-only string', () => {
    const { stderr, status } = runCli(['query', '   ']);
    expect(status).toBe(1);
    expect(stderr).toContain('query requires either `query` (text) or `image` (base64 bytes)');
  });

  test('missing positional (no --image) exits 1 with the same message', () => {
    const { stderr, status } = runCli(['query']);
    expect(status).toBe(1);
    expect(stderr).toContain('query requires either `query` (text) or `image` (base64 bytes)');
  });
});
