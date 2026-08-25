import { getRecipe, listRecipes } from '$lib/api';
import type { RecipeFull } from '$lib/types';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, url }) => {
  const slugs = (url.searchParams.get('slugs') ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .slice(0, 3);
  const [recipes, selected] = await Promise.all([
    listRecipes(fetch),
    Promise.all(slugs.map((s) => getRecipe(fetch, s).catch(() => null)))
  ]);
  return {
    recipes: recipes.filter((r) => !r.noscale),
    selected: selected.filter((r): r is RecipeFull => r !== null)
  };
};
