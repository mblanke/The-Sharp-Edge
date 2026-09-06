/** App-level cook timers.
 *
 *  A timer used to live inside the cook page's component state, keyed by step. That
 *  meant it was gone the moment you left the step, the page, or the tab — which is
 *  exactly when a 40-minute braise timer is supposed to keep going. Timers are now a
 *  single wall-clock-based store, persisted to localStorage, ticked once from the
 *  layout, and rendered by a tray on every page.
 *
 *  Pure and injectable: `createTimerStore({ clock, storage })` is what the tests use;
 *  `timerStore` is the browser singleton. */

import { get, writable, type Readable, type Writable } from 'svelte/store';
import { chime } from './cook';

export interface CookTimer {
  /** `${slug}#${step}` — one timer per recipe step. */
  id: string;
  slug: string;
  title: string;
  /** 0-based step index. */
  step: number;
  total: number;
  /** ms timestamp while running, null while paused/idle. */
  endAt: number | null;
  /** seconds left while paused (== total when idle). */
  left: number;
  /** completion has been announced (chime/notification) — never announce twice. */
  fired: boolean;
}

export const STORAGE_KEY = 'sharp-edge-timers';

export function timerId(slug: string, step: number): string {
  return `${slug}#${step}`;
}

export function remaining(t: CookTimer, now: number): number {
  return t.endAt === null ? t.left : Math.max(0, (t.endAt - now) / 1000);
}

export function isRunning(t: CookTimer): boolean {
  return t.endAt !== null;
}

export function isDone(t: CookTimer, now: number): boolean {
  return remaining(t, now) <= 0;
}

/** Idle = never started or reset: full duration, not running. Not worth a tray row. */
export function isIdle(t: CookTimer, now: number): boolean {
  return t.endAt === null && t.left >= t.total && !isDone(t, now);
}

/** Timers the tray should show: running, paused mid-way, or finished and not dismissed. */
export function active(list: CookTimer[], now: number): CookTimer[] {
  return list.filter((t) => !isIdle(t, now));
}

export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

export interface TimerStore extends Readable<CookTimer[]> {
  /** The clock every consumer should render against; advanced by `tick()`. */
  now: Readable<number>;
  /** Find or create the timer for a step. Creating is idempotent and does not start it. */
  ensure(slug: string, title: string, step: number, total: number): CookTimer;
  find(slug: string, step: number): CookTimer | undefined;
  start(id: string): void;
  pause(id: string): void;
  reset(id: string): void;
  remove(id: string): void;
  /** Advance the clock; returns timers that finished since the last tick (each once). */
  tick(): CookTimer[];
}

export function createTimerStore(opts: { clock?: () => number; storage?: StorageLike | null } = {}): TimerStore {
  const clock = opts.clock ?? Date.now;
  const storage = opts.storage === undefined ? safeLocalStorage() : opts.storage;

  const list: Writable<CookTimer[]> = writable(load());
  const now = writable(clock());

  function load(): CookTimer[] {
    try {
      const raw = storage?.getItem(STORAGE_KEY);
      if (!raw) return [];
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed.filter(isTimerShape) : [];
    } catch {
      return [];
    }
  }

  function save(items: CookTimer[]) {
    try {
      storage?.setItem(STORAGE_KEY, JSON.stringify(items));
    } catch {
      // private mode — timers still work for this session
    }
  }

  function update(fn: (items: CookTimer[]) => CookTimer[]) {
    list.update((items) => {
      const next = fn(items);
      save(next);
      return next;
    });
  }

  function patch(id: string, fn: (t: CookTimer) => CookTimer) {
    update((items) => items.map((t) => (t.id === id ? fn(t) : t)));
  }

  return {
    subscribe: list.subscribe,
    now: { subscribe: now.subscribe },
    find(slug, step) {
      return get(list).find((t) => t.id === timerId(slug, step));
    },
    ensure(slug, title, step, total) {
      const id = timerId(slug, step);
      const existing = get(list).find((t) => t.id === id);
      if (existing && existing.total === total) return existing;
      const fresh: CookTimer = { id, slug, title, step, total, endAt: null, left: total, fired: false };
      update((items) => [...items.filter((t) => t.id !== id), fresh]);
      return fresh;
    },
    start(id) {
      const t = clock();
      patch(id, (x) => (x.endAt === null && x.left > 0 ? { ...x, endAt: t + x.left * 1000, fired: false } : x));
    },
    pause(id) {
      const t = clock();
      patch(id, (x) => (x.endAt === null ? x : { ...x, left: Math.max(0, (x.endAt - t) / 1000), endAt: null }));
    },
    reset(id) {
      patch(id, (x) => ({ ...x, endAt: null, left: x.total, fired: false }));
    },
    remove(id) {
      update((items) => items.filter((t) => t.id !== id));
    },
    tick() {
      const t = clock();
      now.set(t);
      const finished: CookTimer[] = [];
      update((items) =>
        items.map((x) => {
          if (!x.fired && x.endAt !== null && isDone(x, t)) {
            finished.push(x);
            return { ...x, fired: true };
          }
          return x;
        })
      );
      return finished;
    }
  };
}

function isTimerShape(x: unknown): x is CookTimer {
  if (!x || typeof x !== 'object') return false;
  const t = x as Record<string, unknown>;
  return typeof t.id === 'string' && typeof t.total === 'number' && typeof t.left === 'number';
}

function safeLocalStorage(): StorageLike | null {
  try {
    if (typeof localStorage === 'undefined') return null;
    localStorage.getItem(STORAGE_KEY);
    return localStorage;
  } catch {
    return null;
  }
}

/** Browser singleton. Safe to import during SSR: it just holds an empty list. */
export const timerStore: TimerStore = createTimerStore();

/** Ask once, from a user gesture, so a backgrounded tab can still shout. */
export function requestNotifyPermission(): void {
  try {
    if (typeof Notification !== 'undefined' && Notification.permission === 'default') {
      void Notification.requestPermission();
    }
  } catch {
    // not supported — the chime still fires when the tab is visible
  }
}

/** Everything we can do to be heard when a timer ends: chime, buzz, system notification. */
export function announce(t: CookTimer): void {
  chime();
  try {
    navigator.vibrate?.([200, 100, 200, 100, 400]);
  } catch {
    // no vibration API
  }
  try {
    if (typeof Notification !== 'undefined' && Notification.permission === 'granted') {
      const n = new Notification(`${t.title} · step ${t.step + 1}`, {
        body: 'Timer done.',
        tag: t.id,
        requireInteraction: true
      });
      n.onclick = () => {
        window.focus();
        n.close();
      };
    }
  } catch {
    // notification blocked
  }
}

/** One ticker for the whole app; call from the root layout. Returns a stop function. */
export function startTicker(store: TimerStore = timerStore, intervalMs = 500): () => void {
  const handle = setInterval(() => {
    for (const t of store.tick()) announce(t);
  }, intervalMs);
  // a tab that comes back from the background should announce immediately, not in 500 ms
  const onVisible = () => {
    if (document.visibilityState === 'visible') for (const t of store.tick()) announce(t);
  };
  document.addEventListener('visibilitychange', onVisible);
  return () => {
    clearInterval(handle);
    document.removeEventListener('visibilitychange', onVisible);
  };
}
