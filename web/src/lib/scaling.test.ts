import { describe, expect, it } from 'vitest';
import { formatAmount, scaledDisplay } from './scaling';

// Mirror of api/tests/test_scaling.py FRACTION_TABLE — keep in sync.
const TABLE: Array<[number, string, string]> = [
  [0, 'tsp', '—'],
  [0, '', '—'],
  [120, 'ml', '120 ml'],
  [187.5, 'g', '188 g'],
  [199.4, 'g', '199 g'],
  [250, 'g', '250 g'],
  [252, 'g', '250 g'],
  [253, 'g', '255 g'],
  [375, 'g', '375 g'],
  [562.5, 'ml', '565 ml'], // exact half rounds up (matches the Python server)
  [(900 * 14) / 6, 'g', '2100 g'],
  [0.125, 'tsp', '⅛ tsp'],
  [0.25, 'cup', '¼ cup'],
  [1 / 3, 'cup', '⅓ cup'],
  [0.375, 'tsp', '⅜ tsp'],
  [0.5, 'tsp', '½ tsp'],
  [0.625, 'cup', '⅝ cup'],
  [2 / 3, 'cup', '⅔ cup'],
  [0.75, 'cup', '¾ cup'],
  [0.875, 'tsp', '⅞ tsp'],
  [1.5, 'cup', '1 ½ cup'],
  [2.25, 'tbsp', '2 ¼ tbsp'],
  [7.0, 'tbsp', '7 tbsp'],
  [0.7, 'cup', '⅔ cup'],
  [0.8, 'cup', '¾ cup'],
  [2.95, 'cup', '3 cup'],
  [1.02, 'tsp', '1 tsp'],
  [3, '', '3'],
  [1.5, '', '1 ½'],
  [0.5, '', '½'],
  [0.02, 'tsp', 'pinch']
];

describe('formatAmount mirrors the server table', () => {
  for (const [value, unit, expected] of TABLE) {
    it(`${value} ${unit} → ${expected}`, () => {
      expect(formatAmount(value, unit)).toBe(expected);
    });
  }
});

describe('goulash 6 → 14', () => {
  const f = 14 / 6;
  it('2 lb beef → 4 ⅔ lb', () => expect(scaledDisplay(2, 'lb', f)).toBe('4 ⅔ lb'));
  it('3 tbsp paprika → 7 tbsp', () => expect(scaledDisplay(3, 'tbsp', f)).toBe('7 tbsp'));
  it('to-taste stays em dash', () => expect(scaledDisplay(0, '', f)).toBe('—'));
});

describe('never raw decimals for fraction units', () => {
  for (const v of [0.75, 1.5, 2.25, 0.333, 4.666]) {
    for (const u of ['cup', 'tbsp', 'tsp', 'lb', 'oz', '']) {
      it(`${v} ${u}`, () => expect(formatAmount(v, u)).not.toContain('.'));
    }
  }
});
