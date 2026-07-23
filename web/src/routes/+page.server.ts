import { listRecipes } from '$lib/api';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch }) => {
  return { recipes: await listRecipes(fetch) };
};
