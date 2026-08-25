import { fail, redirect } from '@sveltejs/kit';
import { ApiError, getRecipe, logCookSession, scaleRecipe, type ScaledIngredient } from '$lib/api';
import { scaledDisplay } from '$lib/scaling';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, params, url }) => {
  const recipe = await getRecipe(fetch, params.slug);

  const requested = Number(url.searchParams.get('yield')) || recipe.base_yield;
  const target = recipe.noscale
    ? recipe.base_yield
    : Math.min(recipe.base_yield * 4, Math.max(1, requested));

  // Server-canonical amounts (§8); reference cards render unscaled
  const scaled: ScaledIngredient[] = recipe.noscale
    ? recipe.current_version.ingredients.map((i) => ({
        ...i,
        scaled_amount: i.amount,
        display: scaledDisplay(i.amount, i.unit, 1)
      }))
    : await scaleRecipe(fetch, params.slug, target);

  return { recipe, target, scaled };
};

export const actions: Actions = {
  log: async ({ request, params }) => {
    const form = await request.formData();
    const startedAt = form.get('started_at');
    try {
      await logCookSession(fetch, params.slug, {
        scaled_yield: Number(form.get('scaled_yield')) || 1,
        notes: String(form.get('notes') ?? '').trim() || undefined,
        ...(typeof startedAt === 'string' && startedAt ? { started_at: startedAt } : {})
      });
    } catch (e) {
      if (e instanceof ApiError) return fail(e.status >= 500 ? 502 : e.status, { message: e.message });
      throw e;
    }
    throw redirect(303, `/r/${params.slug}`);
  }
};
