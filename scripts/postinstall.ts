/**
 * Cross-platform postinstall (replaces the POSIX `command -v ... 1>&2`
 * one-liner, which bun's Windows shell cannot parse).
 *
 * If the gbrain CLI is already on PATH (global installs), run schema
 * migrations. Otherwise — or on any failure — print the manual-recovery
 * hint and exit 0: postinstall must never fail the install itself.
 */
import { spawnSync } from 'child_process';

const onWindows = process.platform === 'win32';
const HINT =
  '[gbrain] postinstall skipped. If installed via bun install -g github:...: ' +
  'run `gbrain doctor` and `gbrain apply-migrations --yes` manually. ' +
  'See https://github.com/jaypetez/gbrain-copilot#install';

try {
  const probe = spawnSync('gbrain', ['--version'], { stdio: 'ignore', shell: onWindows, timeout: 15_000 });
  if (probe.status === 0) {
    const run = spawnSync('gbrain', ['apply-migrations', '--yes', '--non-interactive'], {
      stdio: 'inherit',
      shell: onWindows,
      timeout: 600_000,
    });
    if (run.status !== 0) console.error(HINT);
  } else {
    console.error(HINT);
  }
} catch {
  console.error(HINT);
}
process.exit(0);
