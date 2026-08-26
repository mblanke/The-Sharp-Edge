import { env } from '$env/dynamic/private';
import { fail, redirect } from '@sveltejs/kit';
import { ApiError, getRecipe, translateRecipe, updateRecipe } from '$lib/api';
import type { RecipeUpdate } from '$lib/types';
import type { Actions, PageServerLoad } from './$types';

const API_URL = env.API_URL ?? 'http://localhost:8000';

export const load: PageServerLoad = async ({ fetch, params }) => {
  let photoImport = false;
  try {
    const res = await fetch(`${API_URL}/api/v1/healthz`);
    if (res.ok) photoImport = Boolean((await res.json()).photo_import);
  } catch {
    // API down — editor still loads
  }
  return { recipe: await getRecipe(fetch, params.slug), photoImport };
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
  },

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
    // draft lands in `form.draft`; the editor prefills from it — nothing saved yet
    return { draft: await res.json() };
  },

  url: async ({ request, fetch }) => {
    const form = await request.formData();
    const url = String(form.get('url') ?? '').trim();
    if (!url) return fail(400, { message: 'Paste a recipe URL first' });
    const res = await fetch(`${API_URL}/api/v1/recipes/import-url`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${env.API_TOKEN ?? ''}`
      },
      body: JSON.stringify({ url })
    });
    if (!res.ok) {
      const detail = await res
        .json()
        .then((b: { detail?: string }) => b.detail)
        .catch(() => null);
      return fail(res.status >= 500 ? 502 : res.status, {
        message: detail ?? `import failed (${res.status})`
      });
    }
    const body = await res.json();
    return { draft: body.draft, source: body.source, gfRisks: body.gf_risks };
  },

  // Words only: the API keeps every amount, unit and timer, so a translation can
  // never quietly change a quantity. Result reseeds the form for review.
  translate: async ({ request, fetch }) => {
    const form = await request.formData();
    const raw = form.get('payload');
    if (typeof raw !== 'string') return fail(400, { message: 'Missing form payload' });
    try {
      const draft = await translateRecipe(fetch, JSON.parse(raw), 'en');
      return { draft };
    } catch (e) {
      if (e instanceof ApiError) return fail(e.status >= 500 ? 502 : e.status, { message: e.message });
      return fail(400, { message: 'Could not translate this recipe' });
    }
  }
};
