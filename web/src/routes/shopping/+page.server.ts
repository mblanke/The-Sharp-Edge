import { fail } from '@sveltejs/kit';
import type { PageServerLoad, Actions } from './$types';
import { ApiError, getShopping, getShoppingText, setChecked, clearShopping } from '$lib/api';

async function guarded<T>(op: () => Promise<T>) {
  try {
    return await op();
  } catch (e) {
    if (e instanceof ApiError) return fail(e.status >= 500 ? 502 : e.status, { message: e.message });
    return fail(502, { message: 'Could not reach the server' });
  }
}

export const load: PageServerLoad = async ({ fetch }) => ({
  items: await getShopping(fetch),
  text: await getShoppingText(fetch)
});

// Form actions rather than client fetches: the bearer token stays server-side, the
// same rule the recipe editor follows (see lib/api.ts).
export const actions: Actions = {
  toggle: async ({ fetch, request }) => {
    const data = await request.formData();
    return guarded(() => setChecked(fetch, String(data.get('id')), data.get('checked') === 'true').then(() => ({ ok: true })));
  },
  clear: async ({ fetch, request }) => {
    const data = await request.formData();
    return guarded(() => clearShopping(fetch, data.get('scope') === 'checked').then(() => ({ ok: true })));
  }
};
