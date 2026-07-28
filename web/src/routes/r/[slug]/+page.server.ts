import { getRecipe, addRecipeToShopping } from '$lib/api';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ fetch, params }) => {
  return { recipe: await getRecipe(fetch, params.slug) };
};

export const actions: Actions = {
  // A write, so the bearer token stays server-side — the same rule the editor follows.
  addToList: async ({ fetch, params, request }) => {
    const data = await request.formData();
    const target = Number(data.get('target')) || null;
    await addRecipeToShopping(fetch, params.slug, target);
    return { added: true };
  }
};
