import { env } from '$env/dynamic/private';
import { fail, redirect } from '@sveltejs/kit';
import { ApiError, createRecipe } from '$lib/api';
import type { RecipeCreate } from '$lib/types';
import type { Actions, PageServerLoad } from './$types';

const API_URL = env.API_URL ?? 'http://localhost:8000';

export const load: PageServerLoad = async ({ fetch }) => {
  let photoImport = false;
  try {
    const res = await fetch(`${API_URL}/api/v1/healthz`);
    if (res.ok) photoImport = Boolean((await res.json()).photo_import);
  } catch {
    // API down — the typed/dictated paths still work
  }
  return { photoImport };
};

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
  },

  // A photo of the cook's own page → draft for review. Same review-first rule
  // as dictation: nothing saves until the form is submitted.
  photo: async ({ request, fetch }) => {
    const form = await request.formData();
    const photo = form.get('photo');
    if (!(photo instanceof File) || photo.size === 0) {
      return fail(400, { message: 'Choose a photo first' });
    }
    const upstream = new FormData();
    upstream.append('photo', photo, photo.name);
    const res = await fetch(`${API_URL}/api/v1/recipes/parse-photo`, {
      method: 'POST',
      headers: { authorization: `Bearer ${env.API_TOKEN ?? ''}` },
      body: upstream
    });
    if (!res.ok) {
      const detail = await res
        .json()
        .then((b: { detail?: string }) => b.detail)
        .catch(() => null);
      return fail(res.status >= 500 ? 502 : res.status, {
        message: detail ?? `photo import failed (${res.status})`
      });
    }
    return { draft: await res.json() };
  }
};
