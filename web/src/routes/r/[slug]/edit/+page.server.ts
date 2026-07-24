import { fail, redirect } from '@sveltejs/kit';
import { ApiError, getRecipe, updateRecipe } from '$lib/api';
import type { RecipeUpdate } from '$lib/types';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, params }) => {
  return { recipe: await getRecipe(fetch, params.slug) };
};

export const actions: Actions = {
  save: async ({ request, fetch, params }) => {
    const form = await request.formData();
    const raw = form.get('payload');
    if (typeof raw !== 'string') {
      return fail(400, { message: 'Missing form payload' });
    }
    let payload: RecipeUpdate;
    try {
      payload = JSON.parse(raw);
    } catch {
      return fail(400, { message: 'Malformed form payload' });
    }

    try {
      await updateRecipe(fetch, params.slug, payload);
    } catch (e) {
      if (e instanceof ApiError) {
        // 422 validation → surface as a 400 form error; keep other client errors as-is
        const status = e.status >= 400 && e.status < 500 ? e.status : 400;
        return fail(status, { message: e.message });
      }
      throw e;
    }

    // Success: PUT appended a new current version. Back to the recipe view.
    throw redirect(303, `/r/${params.slug}`);
  }
};
