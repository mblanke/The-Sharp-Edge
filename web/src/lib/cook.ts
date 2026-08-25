/** Cook-mode logic: ingredient↔step matching, countdown timers, time formatting.
 *  Pure and clock-injectable — unit-tested in cook.test.ts. */

import type { Ingredient } from './types';

/** Words too generic to identify an ingredient inside step text. */
const STOPWORDS = new Set([
  'the', 'and', 'or', 'a', 'an', 'of', 'for', 'with', 'into', 'cut', 'plus',
  'fresh', 'freshly', 'ground', 'large', 'small', 'medium', 'ripe', 'diced',
  'minced', 'chopped', 'sliced', 'crushed', 'grated', 'peeled', 'seeded',
  'finely', 'thinly', 'optional', 'to', 'taste', 'more', 'divided', 'cubed',
  'certified', 'gf'
]);

/** Significant words from an ingredient name (core part before the first comma). */
export function keywords(name: string): string[] {
  const core = name.split(',')[0].replace(/\(.*?\)/g, '');
  return core
    .toLowerCase()
    .split(/[^a-zà-ÿ]+/)
    .filter((w) => w.length >= 3 && !STOPWORDS.has(w));
}

/** Indices of ingredients whose keywords appear in the step text (word-boundary match). */
export function matchIngredients(stepText: string, ingredients: Ingredient[]): number[] {
  const text = stepText.toLowerCase();
  const out: number[] = [];
  ingredients.forEach((ing, i) => {
    const hit = keywords(ing.name).some((w) => {
      // stem naive plurals both ways: "onions" ↔ "onion", "potatoes" ↔ "potato"
      const base = w.replace(/(es|s)$/, '');
      if (base.length < 3) return false;
      return new RegExp(`(^|[^a-zà-ÿ])${base}(es|s)?([^a-zà-ÿ]|$)`, 'i').test(text);
    });
    if (hit) out.push(i);
  });
  return out;
}

/** "90 → 1:30", "3661 → 1:01:01" — mono countdown rendering. */
export function formatDuration(totalSeconds: number): string {
  const s = Math.max(0, Math.round(totalSeconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`;
  return `${m}:${String(sec).padStart(2, '0')}`;
}

export interface Countdown {
  readonly total: number;
  readonly running: boolean;
  remaining(now?: number): number;
  done(now?: number): boolean;
  start(now?: number): void;
  pause(now?: number): void;
  reset(): void;
}

/** Wall-clock-based countdown — survives render pauses; `now` injectable for tests. */
export function createCountdown(totalSeconds: number, clock: () => number = Date.now): Countdown {
  let endAt: number | null = null; // ms timestamp while running
  let left = totalSeconds; // seconds while paused

  return {
    total: totalSeconds,
    get running() {
      return endAt !== null;
    },
    remaining(now = clock()) {
      return endAt === null ? left : Math.max(0, (endAt - now) / 1000);
    },
    done(now = clock()) {
      return this.remaining(now) <= 0;
    },
    start(now = clock()) {
      if (endAt === null && left > 0) endAt = now + left * 1000;
    },
    pause(now = clock()) {
      if (endAt !== null) {
        left = Math.max(0, (endAt - now) / 1000);
        endAt = null;
      }
    },
    reset() {
      endAt = null;
      left = totalSeconds;
    }
  };
}

/** Three short chime beeps via Web Audio; no assets, offline-safe. */
export function chime(ctx?: AudioContext) {
  try {
    const AC = window.AudioContext ?? (window as never)['webkitAudioContext'];
    const audio = ctx ?? new AC();
    for (let i = 0; i < 3; i++) {
      const osc = audio.createOscillator();
      const gain = audio.createGain();
      osc.frequency.value = 880;
      osc.connect(gain);
      gain.connect(audio.destination);
      const t = audio.currentTime + i * 0.35;
      gain.gain.setValueAtTime(0.0001, t);
      gain.gain.exponentialRampToValueAtTime(0.4, t + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.3);
      osc.start(t);
      osc.stop(t + 0.32);
    }
  } catch {
    // audio blocked — timer still shows 0:00
  }
}
