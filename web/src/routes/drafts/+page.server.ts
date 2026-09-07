import { fail } from '@sveltejs/kit';
import { ApiError, batchImportUrls, listDrafts } from '$lib/api';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch }) => ({ drafts: await listDrafts(fetch) });

export const actions: Actions = {
  // A list of links → drafts. The token stays server-side, like every write.
  import: async ({ request, fetch }) => {
    const form = await request.formData();
    const urls = String(form.get('urls') ?? '')
      .split(/\s+/)
      .map((u) => u.trim())
      .filter((u) => /^https?:\/\//i.test(u));
    if (!urls.length) return fail(422, { message: 'Paste one or more http(s) links, one per line.' });
    try {
      return { result: await batchImportUrls(fetch, urls.slice(0, 50)) };
    } catch (e) {
      if (e instanceof ApiError) return fail(e.status >= 500 ? 502 : e.status, { message: e.message });
      return fail(502, { message: 'Could not reach the server' });
    }
  }
};
