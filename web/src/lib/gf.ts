/** Client mirror of the load-bearing core of api/app/services/gf_audit.py —
 *  powers the live editor warning. The server audit is authoritative and
 *  broader; keep the two in sync when rules change. */

import type { Ingredient } from './types';

const RISK =
  /soy sauce|\bshoyu\b|worcestershire|\bmalt(ed)?\b|\bbarley\b|\brye\b|\bwheat\b|\bflour\b|\bpanko\b|breadcrumbs?|hoisin|oyster sauce|\bmiso\b|\bbeer\b|\bseitan\b|bouillon|wasabi (oil|paste|powder)/i;

const CLEARED =
  /gluten[- ]free|\bgf\b|certified gf|tamari|rice flour|almond flour|corn flour|chickpea flour|buckwheat|potato flour|oat flour/i;

export function gfRisks(ingredients: Ingredient[]): string[] {
  return ingredients
    .filter((i) => {
      const text = `${i.name ?? ''} ${i.note ?? ''}`;
      return RISK.test(text) && !CLEARED.test(text);
    })
    .map((i) => i.name);
}
