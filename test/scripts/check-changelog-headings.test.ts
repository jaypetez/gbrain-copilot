/**
 * check:changelog-headings (scripts/check-changelog-headings.ts): a CHANGELOG.md
 * that drops any release heading origin/master has is refused; one that only adds
 * an entry on top passes. Fixtures are throwaway git repos.
 */
import { afterAll, describe, expect, test } from 'bun:test';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { load as loadYaml } from 'js-yaml';
import { main } from '../../scripts/check-changelog-headings.ts';
import { DEFAULT_CHECKS } from '../../scripts/release-restamp.ts';

const roots: string[] = [];
afterAll(() => { for (const root of roots) rmSync(root, { recursive: true, force: true }); });
const git = (cwd: string, ...args: string[]) => execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const changelog = (...versions: string[]) => '# Changelog\n\n' + versions.map((v) => '## [' + v + '] - 2026-10-20\n\nEntry ' + v + '.\n').join('\n');

function repo(): string {
  const root = mkdtempSync(join(tmpdir(), 'gbrain-changelog-headings-'));
  roots.push(root);
  git(root, 'init', '-q', '-b', 'master');
  git(root, 'config', 'user.email', 't@t.co');
  git(root, 'config', 'user.name', 't');
  writeFileSync(join(root, 'CHANGELOG.md'), changelog('0.60.322.0', '0.60.321.0', '0.60.46.0'));
  git(root, 'add', '-A');
  git(root, 'commit', '-q', '-m', 'master');
  git(root, 'update-ref', 'refs/remotes/origin/master', 'HEAD');
  return root;
}

function run(root: string, env: Record<string, string> = {}): { code: number; out: string } {
  const lines: string[] = [];
  const code = main({ cwd: root, env, log: (line) => lines.push(line) });
  return { code, out: lines.join('\n') };
}

describe('check:changelog-headings', () => {
  test('a new entry on top of every master heading passes', () => {
    const root = repo();
    writeFileSync(join(root, 'CHANGELOG.md'), changelog('0.60.323.0', '0.60.322.0', '0.60.321.0', '0.60.46.0'));
    expect(run(root).code).toBe(0);
  });

  test('a truncated changelog (the old entries cut off) is refused with a fix line', () => {
    const root = repo();
    writeFileSync(join(root, 'CHANGELOG.md'), changelog('0.60.323.0', '0.60.322.0'));
    const r = run(root);
    expect(r.code).toBe(1);
    expect(r.out).toContain('missing 2 release heading(s)');
    expect(r.out).toContain('## [0.60.321.0]');
    expect(r.out).toContain('Fix:  restore it from the base');
  });

  test('a branch behind master skips only the releases newer than its own VERSION', () => {
    const root = repo();
    writeFileSync(join(root, 'VERSION'), '0.60.321.0\n');
    writeFileSync(join(root, 'CHANGELOG.md'), changelog('0.60.321.0', '0.60.46.0'));
    const r = run(root);
    expect(r.code).toBe(0);
    expect(r.out).toContain('1 newer release heading(s) on origin/master are not on this branch yet');
  });

  test('a branch behind master that cut an older release heading is still refused', () => {
    const root = repo();
    writeFileSync(join(root, 'VERSION'), '0.60.321.0\n');
    writeFileSync(join(root, 'CHANGELOG.md'), changelog('0.60.321.0'));
    const r = run(root);
    expect(r.code).toBe(1);
    expect(r.out).toContain('missing 1 release heading(s)');
    expect(r.out).toContain('## [0.60.46.0]');
  });

  test('without the base ref: refused under CI, skipped locally', () => {
    const root = repo();
    git(root, 'update-ref', '-d', 'refs/remotes/origin/master');
    expect(run(root, { CI: 'true' }).code).toBe(1);
    expect(run(root).out).toContain('GBRAIN_CHECK_SKIPPED');
  });

  test('the verify workflow checks the fork base and still refuses a truncated changelog', () => {
    const root = repo();
    git(root, 'update-ref', 'refs/remotes/origin/main', 'HEAD');
    git(root, 'update-ref', '-d', 'refs/remotes/origin/master');
    const workflow = loadYaml(readFileSync(join(import.meta.dir, '../../.github/workflows/test.yml'), 'utf8')) as {
      env: Record<string, string>;
      jobs: { verify: { env?: Record<string, string>; steps: Array<{ run?: string; env?: Record<string, string> }> } };
    };
    const step = workflow.jobs.verify.steps.find((entry) => entry.run === 'bun run verify');
    expect(step).toBeDefined();
    const env = { ...workflow.env, ...workflow.jobs.verify.env, ...step?.env, CI: 'true' };
    const complete = run(root, env);
    expect(complete.code).toBe(0);
    expect(complete.out).toContain('every release heading on origin/main is present');
    writeFileSync(join(root, 'CHANGELOG.md'), changelog('0.60.322.0'));
    const truncated = run(root, env);
    expect(truncated.code).toBe(1);
    expect(truncated.out).toContain('missing 2 release heading(s)');
  });

  test("release:restamp's drift checks run it", () => {
    expect(DEFAULT_CHECKS.map((c) => c.argv.join(' '))).toContain('bun scripts/check-changelog-headings.ts');
  });
});
