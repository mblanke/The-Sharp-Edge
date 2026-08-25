import { fail, redirect } from '@sveltejs/kit';
import { ApiError, getWeekPlan, listRecipes, planPushToShopping, planRemove, planUpsert } from '$lib/api';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, url }) => {
  const week = url.searchParams.get('week') ?? undefined;
  const [plan, recipes] = await Promise.all([getWeekPlan(fetch, week), listRecipes(fetch)]);
  return { plan, recipes };
};

function asString(v: FormDataEntryValue | null): string {
  return typeof v === 'string' ? v : '';
}

async function guarded<T>(op: () => Promise<T>) {
  try {
    return await op();
  } catch (e) {
    if (e instanceof ApiError) return fail(e.status >= 500 ? 502 : e.status, { message: e.message });
    throw e;
  }
}

export const actions: Actions = {
  add: async ({ request, fetch }) => {
    const form = await request.formData();
    return guarded(() =>
      planUpsert(fetch, {
        date: asString(form.get('date')),
        meal: asString(form.get('meal')),
        recipe_slug: asString(form.get('recipe_slug')),
        scaled_yield: Number(form.get('scaled_yield')) || undefined
      }).then(() => ({ ok: true }))
    );
  },
  remove: async ({ request, fetch }) => {
    const form = await request.formData();
    return guarded(() => planRemove(fetch, asString(form.get('entry_id'))).then(() => ({ ok: true })));
  },
  // Pushes the week into the running shopping list (the one iOS shares), then
  // lands on it — the list page owns aisles, check-offs, and the share-sheet text.
  generate: async ({ request, fetch }) => {
    const form = await request.formData();
    const week = asString(form.get('week'));
    const result = await guarded(() => planPushToShopping(fetch, week));
    if (result && 'items' in result) throw redirect(303, '/shopping');
    return result;
  }
};
