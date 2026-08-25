import { fail, redirect } from '@sveltejs/kit';
import { ApiError, createRecipe } from '$lib/api';
import type { RecipeCreate } from '$lib/types';
import type { Actions } from './$types';

export const actions: Actions = {
  save: async ({ request, fetch }) => {
    const form = await request.formData();
    const raw = form.get('payload');
    if (typeof raw !== 'string') {
      return fail(400, { message: 'Missing form payload' });
    }
    let payload: RecipeCreate;
    try {
      payload = JSON.parse(raw);
    } catch {
      return fail(400, { message: 'Malformed form payload' });
    }
    if (!payload.slug) {
      return fail(400, { message: 'A web address is required — it is what QR codes point at.' });
    }

    try {
      await createRecipe(fetch, payload);
    } catch (e) {
      if (e instanceof ApiError) {
        // 409 (slug taken) and 422 (validation) are both fixable in the form.
        const status = e.status >= 400 && e.status < 500 ? e.status : 400;
        return fail(status, { message: e.message });
      }
      throw e;
    }

    throw redirect(303, `/r/${payload.slug}`);
  }
};
