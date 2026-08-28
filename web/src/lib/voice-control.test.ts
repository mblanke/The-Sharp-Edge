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

  it('noise returns null; an unknown ingredient is now a question for the library', () => {
    // used to be dead air — since the ask intent, a how-much the recipe can't
    // answer goes to the shelf instead of being swallowed
    expect(parseCommand('how much unicorn dust', INGS)).toEqual({
      type: 'ask',
      question: 'how much unicorn dust'
    });
    expect(parseCommand('la la la', INGS)).toBeNull();
    expect(parseCommand('', INGS)).toBeNull();
  });

  it('timer phrasing does not trigger navigation', () => {
    // "stop the timer" contains no nav word; ensure precedence ordering holds
    expect(parseCommand('stop the timer', INGS)).toEqual({ type: 'timer-pause' });
  });
});

describe('ask intent — a question mid-cook goes to the library', () => {
  const ings = [{ amount: 500, unit: 'g', name: 'beef chuck' }];

  it('a genuine question becomes an ask, commands still win', () => {
    expect(parseCommand('how do I know when the raft is set', ings)).toEqual({
      type: 'ask',
      question: 'how do I know when the raft is set'
    });
    // command words always beat the question shape
    expect(parseCommand('can we go to the next step please', ings)).toEqual({ type: 'next' });
  });

  it('kitchen chatter never fires an LLM call', () => {
    expect(parseCommand('what', ings)).toBeNull();
    expect(parseCommand('what a mess', ings)).toBeNull(); // < 4 words
    expect(parseCommand('pass me the towel over there', ings)).toBeNull(); // no interrogative opener
  });

  it('an unmatched how-much falls through to the library', () => {
    // the recipe has no saffron, so the ingredient lookup fails — but the
    // question is real, and the shelf can answer it
    const intent = parseCommand('how much saffron does a paella need', ings);
    expect(intent).toEqual({ type: 'ask', question: 'how much saffron does a paella need' });
  });

  it('a matched how-much never becomes an ask', () => {
    expect(parseCommand('how much beef do I need', ings)).toEqual({ type: 'how-much', ingredient: 0 });
  });

  it('the wake phrase is stripped when used', () => {
    expect(parseCommand('hey library, what temperature should the oil be', ings)).toEqual({
      type: 'ask',
      question: 'what temperature should the oil be'
    });
  });
});
