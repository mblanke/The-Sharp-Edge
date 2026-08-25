/** Meal orchestration (F2): merge 2–3 recipes into one timeline that walks
 *  backward from a shared "plates hit the table" moment. Pure and fully
 *  unit-tested — the page supplies clock times and liveness. */

import type { Step } from './types';

export interface PlanRecipe {
  slug: string;
  title: string;
  steps: Step[];
}

export interface TimelineEntry {
  slug: string;
  title: string;
  stepIndex: number;
  text: string;
  /** seconds relative to the target moment (negative = before plating) */
  startOffset: number;
  durationSeconds: number;
  /** true when the duration came from an explicit timer_seconds */
  timed: boolean;
}

export interface Timeline {
  entries: TimelineEntry[];
  /** seconds the whole cook takes (longest recipe) */
  totalSeconds: number;
}

export const DEFAULT_STEP_SECONDS = 180; // untimed step estimate — prep-sized

/** Each recipe ends exactly at the target; its steps stack back from there.
 *  Entries are merged and sorted by start time (ties: recipe order, then step). */
export function orchestrate(
  recipes: PlanRecipe[],
  opts: { defaultStepSeconds?: number } = {}
): Timeline {
  const fallback = opts.defaultStepSeconds ?? DEFAULT_STEP_SECONDS;
  const entries: TimelineEntry[] = [];
  let totalSeconds = 0;

  recipes.forEach((recipe) => {
    const durations = recipe.steps.map((s) => s.timer_seconds ?? fallback);
    const recipeTotal = durations.reduce((a, b) => a + b, 0);
    totalSeconds = Math.max(totalSeconds, recipeTotal);
    let offset = -recipeTotal;
    recipe.steps.forEach((step, stepIndex) => {
      entries.push({
        slug: recipe.slug,
        title: recipe.title,
        stepIndex,
        text: step.text,
        startOffset: offset,
        durationSeconds: durations[stepIndex],
        timed: step.timer_seconds != null,
      });
      offset += durations[stepIndex];
    });
  });

  const order = new Map(recipes.map((r, i) => [r.slug, i]));
  entries.sort(
    (a, b) =>
      a.startOffset - b.startOffset ||
      (order.get(a.slug) ?? 0) - (order.get(b.slug) ?? 0) ||
      a.stepIndex - b.stepIndex
  );
  return { entries, totalSeconds };
}

/** "6:10 pm" clock label for an entry given the target wall-clock time (ms). */
export function clockLabel(targetMs: number, offsetSeconds: number): string {
  return new Date(targetMs + offsetSeconds * 1000).toLocaleTimeString('en-CA', {
    hour: 'numeric',
    minute: '2-digit'
  });
}

/** Index of the entry that should be underway at `nowMs` (-1 before start). */
export function currentEntry(timeline: Timeline, targetMs: number, nowMs: number): number {
  const offset = (nowMs - targetMs) / 1000;
  let current = -1;
  timeline.entries.forEach((e, i) => {
    if (e.startOffset <= offset) current = i;
  });
  return current;
}
