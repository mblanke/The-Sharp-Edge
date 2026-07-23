export interface Ingredient {
  amount: number; // 0 = to taste → em dash, never scales
  unit: string;
  name: string;
  note?: string;
  section?: string;
}

export interface Step {
  text: string;
  timer_seconds?: number;
}

export interface RecipeCard {
  slug: string;
  title: string;
  category: string;
  meta: string | null;
  base_yield: number;
  yield_word: string;
  gf: boolean;
  noscale: boolean;
  status: string;
}

export interface RecipeVersion {
  id: string;
  version: number;
  label: string | null;
  ingredients: Ingredient[];
  steps: Step[];
  notes: string[];
  is_current: boolean;
  created_at: string;
}

export interface RecipeFull extends RecipeCard {
  source: string | null;
  current_version: RecipeVersion;
}

/** Card / glue-in order — CLAUDE.md §10. */
export const CATEGORY_ORDER = [
  'Sauces & Salsas',
  'Marinades',
  'Salads',
  'Soups & Stews',
  'Sandwiches',
  'Pasta',
  'Entrées',
  'Sides',
  'Breakfast',
  'Baking & Desserts',
  'Drinks',
  'Appetizers & Preserves',
  'Reference'
] as const;

export function categoryRank(cat: string): number {
  const i = CATEGORY_ORDER.indexOf(cat as (typeof CATEGORY_ORDER)[number]);
  return i === -1 ? CATEGORY_ORDER.length : i;
}
