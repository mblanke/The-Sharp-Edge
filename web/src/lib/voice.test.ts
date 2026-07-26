import { describe, expect, it } from 'vitest';
import { CAPTURE_LANGUAGES, speechTag, splitUtterances } from './voice';

describe('splitUtterances', () => {
  it('turns a continuous take into one line per item', () => {
    expect(splitUtterances('200 grams of butter. two eggs. a pinch of salt')).toEqual([
      '200 grams of butter',
      'two eggs',
      'a pinch of salt'
    ]);
  });

  it('treats newlines as breaks too', () => {
    expect(splitUtterances('one\ntwo\nthree')).toEqual(['one', 'two', 'three']);
  });

  it('drops empty fragments from trailing or doubled punctuation', () => {
    expect(splitUtterances('one.. two.  ')).toEqual(['one', 'two']);
  });

  it('keeps content that has no punctuation at all', () => {
    expect(splitUtterances('zweieinhalb Esslöffel Paprikapulver')).toEqual([
      'zweieinhalb Esslöffel Paprikapulver'
    ]);
  });

  it('returns nothing for empty input', () => {
    expect(splitUtterances('   ')).toEqual([]);
  });
});

describe('speechTag', () => {
  it('maps every capture language to a BCP-47 tag', () => {
    expect(speechTag('en')).toBe('en-US');
    expect(speechTag('fr')).toBe('fr-FR');
    expect(speechTag('de')).toBe('de-DE');
    expect(speechTag('ro')).toBe('ro-RO');
  });

  it('covers the whole language list', () => {
    for (const l of CAPTURE_LANGUAGES) expect(speechTag(l.code)).toBe(l.tag);
  });
});
