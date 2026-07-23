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
