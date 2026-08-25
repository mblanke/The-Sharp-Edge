import { describe, expect, it } from 'vitest';
import { createCountdown, formatDuration, keywords, matchIngredients } from './cook';

const GOULASH_INGS = [
  { amount: 2, unit: 'lb', name: 'beef chuck, cut into 1-inch cubes' },
  { amount: 3, unit: 'tbsp', name: 'vegetable oil or lard' },
  { amount: 3, unit: '', name: 'yellow onions, diced' },
  { amount: 3, unit: 'tbsp', name: 'sweet Hungarian paprika (certified GF)' },
  { amount: 2, unit: 'tbsp', name: 'tomato paste' },
  { amount: 3, unit: 'cup', name: 'beef broth (certified GF)' },
  { amount: 1.5, unit: 'lb', name: 'Yukon Gold potatoes, cubed' },
  { amount: 1.5, unit: 'tsp', name: 'salt' },
  { amount: 0, unit: '', name: 'black pepper, to taste' }
];

describe('keywords', () => {
  it('keeps identifying words, drops prep words and parentheticals', () => {
    expect(keywords('beef chuck, cut into 1-inch cubes')).toEqual(['beef', 'chuck']);
    expect(keywords('sweet Hungarian paprika (certified GF)')).toEqual([
      'sweet',
      'hungarian',
      'paprika'
    ]);
    expect(keywords('yellow onions, diced')).toEqual(['yellow', 'onions']);
    expect(keywords('salt')).toEqual(['salt']);
  });
});

describe('matchIngredients', () => {
  it('finds ingredients named in the step', () => {
    const step = 'Sear the beef in batches, then soften the onions in the oil.';
    const hits = matchIngredients(step, GOULASH_INGS);
    expect(hits).toContain(0); // beef chuck
    expect(hits).toContain(1); // oil
    expect(hits).toContain(2); // onions
    expect(hits).not.toContain(3); // paprika
  });

  it('matches singular step text against plural ingredient names', () => {
    const hits = matchIngredients('Add each onion whole.', GOULASH_INGS);
    expect(hits).toContain(2);
  });

  it('does not match on substrings of longer words', () => {
    // "salted" must not match "salt"… but plural "salts" would; boundary check
    const hits = matchIngredients('Bring the unsalted stock to a boil.', GOULASH_INGS);
    expect(hits).not.toContain(7);
  });

  it('matches paprika and broth in the simmer step', () => {
    const step = 'Stir in the paprika and tomato paste, then pour in the broth.';
    const hits = matchIngredients(step, GOULASH_INGS);
    expect(hits).toEqual(expect.arrayContaining([3, 4, 5]));
  });
});

describe('formatDuration', () => {
  it('renders m:ss and h:mm:ss', () => {
    expect(formatDuration(0)).toBe('0:00');
    expect(formatDuration(5)).toBe('0:05');
    expect(formatDuration(90)).toBe('1:30');
    expect(formatDuration(600)).toBe('10:00');
    expect(formatDuration(3661)).toBe('1:01:01');
    expect(formatDuration(-3)).toBe('0:00');
  });
});

describe('createCountdown', () => {
  it('counts down on the injected clock and survives pause/resume', () => {
    let now = 1_000_000;
    const clock = () => now;
    const t = createCountdown(90, clock);

    expect(t.remaining()).toBe(90);
    expect(t.running).toBe(false);

    t.start();
    now += 30_000;
    expect(t.remaining()).toBe(60);
    expect(t.running).toBe(true);

    t.pause();
    now += 60_000; // time passes while paused — remaining frozen
    expect(t.remaining()).toBe(60);

    t.start();
    now += 60_000;
    expect(t.remaining()).toBe(0);
    expect(t.done()).toBe(true);
  });

  it('reset restores the full duration and stops', () => {
    let now = 0;
    const t = createCountdown(120, () => now);
    t.start();
    now += 50_000;
    t.reset();
    expect(t.remaining()).toBe(120);
    expect(t.running).toBe(false);
  });

  it('never goes negative', () => {
    let now = 0;
    const t = createCountdown(10, () => now);
    t.start();
    now += 60_000;
    expect(t.remaining()).toBe(0);
  });
});
