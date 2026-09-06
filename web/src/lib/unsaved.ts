/** Warn before leaving a form with unsaved changes — both in-app navigation
 *  (SvelteKit) and a tab close / reload (the browser's own dialog). */

import { beforeNavigate } from '$app/navigation';

export function guardUnsaved(isDirty: () => boolean): () => void {
  beforeNavigate((nav) => {
    if (!isDirty()) return;
    if (nav.type === 'leave') {
      nav.cancel(); // browser shows its own "leave site?" dialog
      return;
    }
    if (!confirm('You have unsaved changes. Leave without saving?')) nav.cancel();
  });
  const onUnload = (e: BeforeUnloadEvent) => {
    if (isDirty()) e.preventDefault();
  };
  window.addEventListener('beforeunload', onUnload);
  return () => window.removeEventListener('beforeunload', onUnload);
}

/** Per-form autosave to localStorage so a killed tab does not lose a half-typed recipe. */
export function draftStore<T>(key: string) {
  const k = `sharp-edge-draft-${key}`;
  return {
    load(): T | null {
      try {
        const raw = localStorage.getItem(k);
        return raw ? (JSON.parse(raw) as T) : null;
      } catch {
        return null;
      }
    },
    save(value: T) {
      try {
        localStorage.setItem(k, JSON.stringify(value));
      } catch {
        // private mode — nothing to do
      }
    },
    clear() {
      try {
        localStorage.removeItem(k);
      } catch {
        // ignore
      }
    }
  };
}
