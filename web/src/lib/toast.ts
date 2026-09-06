/** One toast primitive for the whole app. Pages used to each invent an inline
 *  string, which meant most actions had no feedback at all and none had undo. */

import { writable } from 'svelte/store';

export interface Toast {
  id: number;
  text: string;
  /** 'error' toasts stay until dismissed; the rest fade. */
  kind: 'info' | 'success' | 'error';
  /** Optional action, e.g. undo. Runs once; the toast closes. */
  action?: { label: string; run: () => void | Promise<void> };
  /** Optional link shown as the action instead. */
  href?: { label: string; url: string };
}

const toasts = writable<Toast[]>([]);
let seq = 0;
const timers = new Map<number, ReturnType<typeof setTimeout>>();

export const toastStore = { subscribe: toasts.subscribe };

export function dismiss(id: number) {
  clearTimeout(timers.get(id));
  timers.delete(id);
  toasts.update((list) => list.filter((t) => t.id !== id));
}

export function toast(
  text: string,
  opts: Partial<Omit<Toast, 'id' | 'text'>> & { ms?: number } = {}
): number {
  const id = ++seq;
  const kind = opts.kind ?? 'info';
  const t: Toast = { id, text, kind, action: opts.action, href: opts.href };
  // one at a time: a stack of stale toasts is worse than none
  toasts.set([t]);
  const ms = opts.ms ?? (kind === 'error' ? 0 : opts.action ? 5000 : 2800);
  if (ms > 0) timers.set(id, setTimeout(() => dismiss(id), ms));
  return id;
}

export const notify = {
  ok: (text: string, opts?: Parameters<typeof toast>[1]) => toast(text, { ...opts, kind: 'success' }),
  error: (text: string, opts?: Parameters<typeof toast>[1]) => toast(text, { ...opts, kind: 'error' })
};
