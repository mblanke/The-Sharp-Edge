import { describe, expect, it } from 'vitest';
import { clockLabel, currentEntry, orchestrate } from './orchestrate';

const GOULASH = {
  slug: 'goulash',
  title: 'Goulash',
  steps: [
    { text: 'Sear the beef.', timer_seconds: 600 },
    { text: 'Simmer.', timer_seconds: 3600 },
    { text: 'Add potatoes and finish.', timer_seconds: 1200 }
  ]
};

const SALAD = {
  slug: 'gurkensalat',
  title: 'Gurkensalat',
  steps: [
    { text: 'Slice cucumbers.' }, // untimed → default estimate
    { text: 'Dress and chill.', timer_seconds: 900 }
  ]
};

describe('orchestrate', () => {
  it('stacks each recipe back from the target', () => {
    const t = orchestrate([GOULASH], { defaultStepSeconds: 120 });
    expect(t.totalSeconds).toBe(5400);
    expect(t.entries.map((e) => e.startOffset)).toEqual([-5400, -4800, -1200]);
    // last step ends exactly at the target
    const last = t.entries[2];
    expect(last.startOffset + last.durationSeconds).toBe(0);
  });

  it('interleaves two recipes by start time', () => {
    const t = orchestrate([GOULASH, SALAD], { defaultStepSeconds: 120 });
    expect(t.totalSeconds).toBe(5400); // longest recipe wins
    // salad (1020s total) starts while the goulash simmers
    const order = t.entries.map((e) => `${e.slug}:${e.stepIndex}`);
    expect(order).toEqual([
      'goulash:0', // -5400
      'goulash:1', // -4800
      'goulash:2', // -1200
      'gurkensalat:0', // -1020 — starts during the goulash finish
      'gurkensalat:1' // -900
    ]);
  });

  it('untimed steps use the default estimate and are flagged', () => {
    const t = orchestrate([SALAD], { defaultStepSeconds: 120 });
    expect(t.entries[0].durationSeconds).toBe(120);
    expect(t.entries[0].timed).toBe(false);
    expect(t.entries[1].timed).toBe(true);
  });

  it('deterministic tie-break by recipe order', () => {
    const a = { slug: 'a', title: 'A', steps: [{ text: 'x', timer_seconds: 100 }] };
    const b = { slug: 'b', title: 'B', steps: [{ text: 'y', timer_seconds: 100 }] };
    const t = orchestrate([a, b]);
    expect(t.entries.map((e) => e.slug)).toEqual(['a', 'b']);
  });
});

describe('currentEntry', () => {
  const t = orchestrate([GOULASH], { defaultStepSeconds: 120 });
  const target = 10_000_000_000;

  it('is -1 before the cook starts', () => {
    expect(currentEntry(t, target, target - 6000 * 1000)).toBe(-1);
  });
  it('advances with the clock', () => {
    expect(currentEntry(t, target, target - 5400 * 1000)).toBe(0);
    expect(currentEntry(t, target, target - 3000 * 1000)).toBe(1);
    expect(currentEntry(t, target, target)).toBe(2);
  });
});

describe('clockLabel', () => {
  it('renders wall-clock times', () => {
    const sixPm = new Date('2026-08-24T18:00:00').getTime();
    expect(clockLabel(sixPm, -3600)).toMatch(/5:00/);
    expect(clockLabel(sixPm, 0)).toMatch(/6:00/);
  });
});
