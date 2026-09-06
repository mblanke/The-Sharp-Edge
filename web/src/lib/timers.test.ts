import { get } from 'svelte/store';
import { describe, expect, it } from 'vitest';
import { active, createTimerStore, isDone, isIdle, remaining, STORAGE_KEY, timerId, type StorageLike } from './timers';

function memoryStorage(): StorageLike & { data: Map<string, string> } {
  const data = new Map<string, string>();
  return {
    data,
    getItem: (k) => data.get(k) ?? null,
    setItem: (k, v) => void data.set(k, v)
  };
}

describe('timer store', () => {
  it('creates one timer per step, idempotently', () => {
    const s = createTimerStore({ clock: () => 0, storage: null });
    const a = s.ensure('goulash', 'Goulash', 2, 600);
    const b = s.ensure('goulash', 'Goulash', 2, 600);
    expect(a.id).toBe(timerId('goulash', 2));
    expect(b).toEqual(a);
    expect(get(s)).toHaveLength(1);
    expect(isIdle(a, 0)).toBe(true);
  });

  it('counts down on the injected clock and survives pause/resume', () => {
    let now = 1_000_000;
    const s = createTimerStore({ clock: () => now, storage: null });
    const { id } = s.ensure('stirfry', 'Stir-fry', 0, 90);

    s.start(id);
    now += 30_000;
    expect(remaining(s.find('stirfry', 0)!, now)).toBe(60);

    s.pause(id);
    now += 60_000; // frozen while paused
    expect(remaining(s.find('stirfry', 0)!, now)).toBe(60);

    s.start(id);
    now += 60_000;
    expect(isDone(s.find('stirfry', 0)!, now)).toBe(true);
  });

  it('reports each completion exactly once through tick()', () => {
    let now = 0;
    const s = createTimerStore({ clock: () => now, storage: null });
    const { id } = s.ensure('stirfry', 'Stir-fry', 0, 10);
    s.start(id);

    now += 5_000;
    expect(s.tick()).toEqual([]);
    now += 6_000;
    expect(s.tick().map((t) => t.id)).toEqual([id]);
    now += 1_000;
    expect(s.tick()).toEqual([]); // fired stays true
    expect(get(s.now)).toBe(12_000);

    s.reset(id);
    expect(isIdle(s.find('stirfry', 0)!, now)).toBe(true);
    s.start(id);
    now += 11_000;
    expect(s.tick().map((t) => t.id)).toEqual([id]); // a restarted timer fires again
  });

  it('persists to storage and reloads from it — a reload mid-cook keeps the timer', () => {
    const storage = memoryStorage();
    let now = 0;
    const first = createTimerStore({ clock: () => now, storage });
    const { id } = first.ensure('goulash', 'Goulash', 4, 2400);
    first.start(id);
    expect(storage.data.has(STORAGE_KEY)).toBe(true);

    now += 600_000;
    const second = createTimerStore({ clock: () => now, storage });
    const t = second.find('goulash', 4)!;
    expect(t.endAt).toBe(2_400_000);
    expect(remaining(t, now)).toBe(1800);
  });

  it('ignores corrupt storage', () => {
    const storage = memoryStorage();
    storage.setItem(STORAGE_KEY, '{not json');
    expect(get(createTimerStore({ storage }))).toEqual([]);
    storage.setItem(STORAGE_KEY, JSON.stringify([{ id: 1 }, { id: 'ok#0', total: 5, left: 5, endAt: null }]));
    expect(get(createTimerStore({ storage }))).toHaveLength(1);
  });

  it('active() hides idle timers and keeps running, paused and finished ones', () => {
    let now = 0;
    const s = createTimerStore({ clock: () => now, storage: null });
    s.ensure('a', 'A', 0, 60); // idle
    s.start(s.ensure('a', 'A', 1, 60).id); // running
    s.start(s.ensure('a', 'A', 2, 60).id);
    now += 10_000;
    s.pause(timerId('a', 2)); // paused mid-way
    s.start(s.ensure('a', 'A', 3, 5).id);
    now += 10_000; // step 3 finished
    expect(active(get(s), now).map((t) => t.step)).toEqual([1, 2, 3]);
    s.remove(timerId('a', 3));
    expect(active(get(s), now).map((t) => t.step)).toEqual([1, 2]);
  });

  it('re-creates the timer when the step duration changed (new recipe version)', () => {
    const s = createTimerStore({ clock: () => 0, storage: null });
    s.start(s.ensure('a', 'A', 0, 60).id);
    const t = s.ensure('a', 'A', 0, 90);
    expect(t.total).toBe(90);
    expect(t.endAt).toBeNull();
    expect(get(s)).toHaveLength(1);
  });
});
