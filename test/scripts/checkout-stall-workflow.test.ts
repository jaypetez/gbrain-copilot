import { describe, expect, test } from 'bun:test';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { load } from 'js-yaml';

// On the Ubicloud runners a checkout's git fetch sometimes runs for 15 to 20 minutes, against about 15 s for a healthy
// one, and no git setting bounds it. Keep every checkout in the suite workflows bounded and retried once on failure.
type Step = { id?: string; if?: string; uses?: string; with?: Record<string, unknown>; 'timeout-minutes'?: number; 'continue-on-error'?: boolean };
type Job = { steps?: Step[] };
type Workflow = { jobs: Record<string, Job> };
const dir = join(import.meta.dir, '../../.github/workflows');
const workflows = ['e2e.yml', 'persistence-validation.yml', 'test.yml'].map(file => ({
  file,
  parsed: load(readFileSync(join(dir, file), 'utf8')) as Workflow,
}));
const isCheckout = (step: Step) => step.uses?.startsWith('actions/checkout@') ?? false;

describe('a stalled checkout is bounded and tried again', () => {
  test.each(workflows.map(w => [w.file, w] as const))('%s pairs every checkout with a bounded retry', (_file, w) => {
    for (const [job, spec] of Object.entries(w.parsed.jobs)) {
      const steps = spec.steps ?? [];
      for (let i = 0; i < steps.length; i++) {
        const first = steps[i];
        if (!isCheckout(first)) continue;
        const where = `${w.file} job ${job} step ${i + 1}`;
        expect({ where, id: typeof first.id, continueOnError: first['continue-on-error'], bounded: (first['timeout-minutes'] ?? 0) > 0 })
          .toEqual({ where, id: 'string', continueOnError: true, bounded: true });
        const retry = steps[i + 1];
        expect({ where, retry: retry && { if: retry.if, uses: retry.uses, with: retry.with, timeout: retry['timeout-minutes'], continueOnError: retry['continue-on-error'] } })
          .toEqual({ where, retry: { if: `steps.${first.id}.outcome == 'failure'`, uses: first.uses, with: first.with, timeout: first['timeout-minutes'], continueOnError: undefined } });
        i++;
      }
    }
  });
});
