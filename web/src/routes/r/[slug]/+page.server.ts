import { getRecipe, getVersions } from '$lib/api';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, params }) => {
  const [recipe, versions] = await Promise.all([
    getRecipe(fetch, params.slug),
    getVersions(fetch, params.slug)
  ]);
  return { recipe, versions };
};
