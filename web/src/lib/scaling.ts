/**
 * Client mirror of api/app/services/scaling.py (CLAUDE.md §8).
 * Instant UI only — the server response is canonical for exports.
 * Any change here must land in both places; the vitest/pytest tables match.
 */

const EM_DASH = '—';

const FRACTIONS: Array<[number, string]> = [
  [0, ''],
  [0.125, '⅛'],
  [0.25, '¼'],
  [1 / 3, '⅓'],
  [0.375, '⅜'],
  [0.5, '½'],
  [0.625, '⅝'],
  [2 / 3, '⅔'],
  [0.75, '¾'],
  [0.875, '⅞'],
  [1, '']
];

const METRIC = new Set(['g', 'ml']);

export function formatAmount(value: number, unit: string): string {
  if (value === 0) return EM_DASH;
  if (METRIC.has(unit)) {
    const rounded = value >= 200 ? Math.round(value / 5) * 5 : Math.round(value);
    return `${rounded} ${unit}`;
  }

  let whole = Math.floor(value);
  const frac = value - whole;
  let bestValue = 0;
  let bestGlyph = '';
  let bestErr = 9;
  for (const [fval, glyph] of FRACTIONS) {
    const err = Math.abs(frac - fval);
    if (err < bestErr) {
      bestErr = err;
      bestValue = fval;
      bestGlyph = glyph;
    }
  }
  if (bestValue === 1) {
    whole += 1;
    bestGlyph = '';
  }

  let amountStr: string;
  if (whole > 0 && bestGlyph) amountStr = `${whole} ${bestGlyph}`;
  else if (whole > 0) amountStr = String(whole);
  else if (bestGlyph) amountStr = bestGlyph;
  else return frac > 0 ? 'pinch' : '0';

  return unit ? `${amountStr} ${unit}` : amountStr;
}

export function scaledDisplay(amount: number, unit: string, factor: number): string {
  if (amount === 0) return EM_DASH;
  return formatAmount(amount * factor, unit);
}

// --- unit systems -------------------------------------------------------------
// Mirror of convert_amount / convert_display in scaling.py; the shared fixture
// scaling.convert_amount.json holds both to the same answers.

export type UnitSystem = 'recipe' | 'metric' | 'imperial';
export const UNIT_SYSTEMS: UnitSystem[] = ['recipe', 'metric', 'imperial'];

const TO_ML: Record<string, number> = { cup: 240, tbsp: 15, tsp: 5 };
const TO_G: Record<string, number> = { lb: 450, oz: 28 };

/** Express an amount in `system`. Counts, to-taste rows and same-system units pass through. */
export function convertAmount(amount: number, unit: string, system: UnitSystem): [number, string] {
  if (amount === 0 || system === 'recipe') return [amount, unit];
  if (system === 'metric') {
    if (unit in TO_ML) return [amount * TO_ML[unit], 'ml'];
    if (unit in TO_G) return [amount * TO_G[unit], 'g'];
    return [amount, unit];
  }
  if (unit === 'ml') {
    if (amount >= 60) return [amount / 240, 'cup'];
    if (amount >= 15) return [amount / 15, 'tbsp'];
    return [amount / 5, 'tsp'];
  }
  if (unit === 'g') {
    if (amount >= 450) return [amount / 450, 'lb'];
    return [amount / 28, 'oz'];
  }
  return [amount, unit];
}

/** `convertAmount` rendered through `formatAmount` — what the screen shows. */
export function convertDisplay(amount: number, unit: string, system: UnitSystem): string {
  const [value, outUnit] = convertAmount(amount, unit, system);
  return formatAmount(value, outUnit);
}
