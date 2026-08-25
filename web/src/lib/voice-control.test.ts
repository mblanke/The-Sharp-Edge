import { describe, expect, it } from 'vitest';
import { parseCommand } from './voice-control';

const INGS = [
  { amount: 2, unit: 'lb', name: 'beef chuck, cut into 1-inch cubes' },
  { amount: 3, unit: 'tbsp', name: 'sweet Hungarian paprika (certified GF)' },
  { amount: 1.5, unit: 'tsp', name: 'salt' },
  { amount: 3, unit: 'cup', name: 'beef broth (certified GF)' }
];

describe('parseCommand', () => {
  it('navigation', () => {
    expect(parseCommand('next', INGS)).toEqual({ type: 'next' });
    expect(parseCommand('okay next step please', INGS)).toEqual({ type: 'next' });
    expect(parseCommand('go back', INGS)).toEqual({ type: 'back' });
    expect(parseCommand('repeat that', INGS)).toEqual({ type: 'repeat' });
  });

  it('timer control', () => {
    expect(parseCommand('start the timer', INGS)).toEqual({ type: 'timer-start' });
    expect(parseCommand('timer start', INGS)).toEqual({ type: 'timer-start' });
    expect(parseCommand('pause the timer', INGS)).toEqual({ type: 'timer-pause' });
    expect(parseCommand('reset timer', INGS)).toEqual({ type: 'timer-reset' });
  });

  it('how much resolves the right ingredient', () => {
    expect(parseCommand('how much paprika', INGS)).toEqual({ type: 'how-much', ingredient: 1 });
    expect(parseCommand('how much salt do I need', INGS)).toEqual({ type: 'how-much', ingredient: 2 });
    // "beef broth" beats "beef chuck" on keyword overlap
    expect(parseCommand('how much beef broth', INGS)).toEqual({ type: 'how-much', ingredient: 3 });
  });

  it('unknown ingredient and noise return null', () => {
    expect(parseCommand('how much unicorn dust', INGS)).toBeNull();
    expect(parseCommand('la la la', INGS)).toBeNull();
    expect(parseCommand('', INGS)).toBeNull();
  });

  it('timer phrasing does not trigger navigation', () => {
    // "stop the timer" contains no nav word; ensure precedence ordering holds
    expect(parseCommand('stop the timer', INGS)).toEqual({ type: 'timer-pause' });
  });
});
