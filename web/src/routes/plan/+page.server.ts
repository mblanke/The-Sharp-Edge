import { fail } from '@sveltejs/kit';
import {
  ApiError,
  getWeekPlan,
  listRecipes,
  planCheckItem,
  planGenerateList,
  planRemove,
  planUpsert
} from '$lib/api';
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
  generate: async ({ request, fetch }) => {
    const form = await request.formData();
    return guarded(() => planGenerateList(fetch, asString(form.get('week'))).then(() => ({ ok: true })));
  },
  check: async ({ request, fetch }) => {
    const form = await request.formData();
    return guarded(() =>
      planCheckItem(fetch, asString(form.get('item_id')), form.get('checked') === 'true').then(() => ({
        ok: true
      }))
    );
  }
};
