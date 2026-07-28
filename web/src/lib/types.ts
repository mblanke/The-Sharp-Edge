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

/** PUT body — appends a new version. Slug never changes. Mirrors the API's
 *  RecipeUpdate schema: metadata optional, ingredients+steps required. */
export interface RecipeUpdate {
  title?: string;
  category?: string;
  meta?: string | null;
  base_yield?: number;
  yield_word?: string;
  gf?: boolean;
  noscale?: boolean;
  source?: string | null;
  status?: string;
  label?: string | null;
  ingredients: Ingredient[];
  steps: Step[];
  notes: string[];
}

/** Units the API accepts (empty = countable; counting noun lives in name). */
/** POST body. Differs from RecipeUpdate only in the caller-supplied, permanent slug —
 *  QR codes are printed against it, so it is generated once and never renamed. */
export interface RecipeCreate extends RecipeUpdate {
  slug: string;
}

export const ALLOWED_UNITS = ['', 'g', 'ml', 'cup', 'tbsp', 'tsp', 'lb', 'oz'] as const;

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


/** Mirrors api/app/schemas/shopping.py. `display` and `aisle` are computed server-side
 *  so the quantity arithmetic and the aisle table stay in one place. */
export interface ShoppingItem {
  id: string;
  name: string;
  amount: number;
  unit: string;
  display: string;
  to_taste: boolean;
  checked: boolean;
  recipes: string[];
  check_gluten: boolean;
  aisle: string;
}
