/** Per-device preferences, all in localStorage under one prefix. The recipe, cook
 *  and settings pages read the same keys; nothing here reaches the server. */

import type { UnitSystem } from './scaling';

export const KEYS = {
  theme: 'sharp-edge-theme',
  units: 'sharp-edge-units',
  cookText: 'sharp-edge-cook-text',
  cookHint: 'sharp-edge-cook-hint',
  recent: 'sharp-edge-recent',
  timers: 'sharp-edge-timers'
} as const;

export function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

export function write(key: string, value: string | null): void {
  try {
    if (value === null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch {
    // private mode — the preference lasts for this page only
  }
}

export type Theme = 'light' | 'dark' | 'system';

export function readTheme(): Theme {
  const v = read(KEYS.theme);
  return v === 'light' || v === 'dark' ? v : 'system';
}

/** Applies and persists. `system` clears the stored choice and follows the OS. */
export function applyTheme(theme: Theme): void {
  if (theme === 'system') {
    write(KEYS.theme, null);
    const dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    document.documentElement.dataset.theme = dark ? 'dark' : '';
  } else {
    write(KEYS.theme, theme);
    document.documentElement.dataset.theme = theme === 'dark' ? 'dark' : '';
  }
  syncThemeColor();
}

/** The browser chrome (iPad status bar, PWA title bar) takes the page's paper
 *  colour, whichever scheme is showing — read from the live token so the CSS
 *  stays the one place a colour is defined. */
export function syncThemeColor(): void {
  try {
    const paper = getComputedStyle(document.documentElement).getPropertyValue('--paper').trim();
    if (!paper) return;
    for (const meta of document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]')) {
      meta.content = paper;
    }
  } catch {
    // no DOM
  }
}

export function readUnits(): UnitSystem {
  const v = read(KEYS.units);
  return v === 'metric' || v === 'imperial' ? v : 'recipe';
}

export interface RecentRecipe {
  slug: string;
  title: string;
  at: number;
}

export function readRecent(): RecentRecipe[] {
  try {
    const list = JSON.parse(read(KEYS.recent) ?? '[]');
    return Array.isArray(list) ? list.filter((r) => r && typeof r.slug === 'string') : [];
  } catch {
    return [];
  }
}

/** Most recent first, one entry per slug, capped. */
export function recordRecent(slug: string, title: string, limit = 8): void {
  const rest = readRecent().filter((r) => r.slug !== slug);
  write(KEYS.recent, JSON.stringify([{ slug, title, at: Date.now() }, ...rest].slice(0, limit)));
}

/** Every per-recipe key this device keeps: ticks and cook positions. */
export function forgetRecipeState(): number {
  let n = 0;
  try {
    const doomed: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (k && (k.startsWith('sharp-edge-checked-') || k.startsWith('sharp-edge-cookpos-'))) doomed.push(k);
    }
    for (const k of doomed) {
      localStorage.removeItem(k);
      n++;
    }
  } catch {
    // storage blocked
  }
  return n;
}
