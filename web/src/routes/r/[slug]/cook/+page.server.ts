import type { PageServerLoad } from './$types';
import { getRecipe } from '$lib/api';

export const load: PageServerLoad = async ({ fetch, params, url }) => {
  const recipe = await getRecipe(fetch, params.slug);
  const target = Number(url.searchParams.get('yield')) || recipe.base_yield;
  return { recipe, target };
};
