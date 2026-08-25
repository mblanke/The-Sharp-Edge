import { getRecipe, scaleRecipe, type ScaledIngredient } from '$lib/api';
import { scaledDisplay } from '$lib/scaling';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, params, url }) => {
  const recipe = await getRecipe(fetch, params.slug);

  const requested = Number(url.searchParams.get('yield')) || recipe.base_yield;
  const target = recipe.noscale
    ? recipe.base_yield
    : Math.min(recipe.base_yield * 4, Math.max(1, requested));

  // Server-canonical amounts (§8); reference cards render unscaled
  const scaled: ScaledIngredient[] = recipe.noscale
    ? recipe.current_version.ingredients.map((i) => ({
        ...i,
        scaled_amount: i.amount,
        display: scaledDisplay(i.amount, i.unit, 1)
      }))
    : await scaleRecipe(fetch, params.slug, target);

  return { recipe, target, scaled };
};
