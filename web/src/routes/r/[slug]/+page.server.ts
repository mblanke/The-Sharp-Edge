import { getRecipe } from '$lib/api';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, params }) => {
  return { recipe: await getRecipe(fetch, params.slug) };
};
