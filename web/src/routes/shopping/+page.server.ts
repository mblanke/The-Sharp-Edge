import type { PageServerLoad, Actions } from './$types';
import { getShopping, getShoppingText, setChecked, clearShopping } from '$lib/api';

export const load: PageServerLoad = async ({ fetch }) => ({
  items: await getShopping(fetch),
  text: await getShoppingText(fetch)
});

// Form actions rather than client fetches: the bearer token stays server-side, the
// same rule the recipe editor follows (see lib/api.ts).
export const actions: Actions = {
  toggle: async ({ fetch, request }) => {
    const data = await request.formData();
    await setChecked(fetch, String(data.get('id')), data.get('checked') === 'true');
    return { ok: true };
  },
  clear: async ({ fetch, request }) => {
    const data = await request.formData();
    await clearShopping(fetch, data.get('scope') === 'checked');
    return { ok: true };
  }
};
