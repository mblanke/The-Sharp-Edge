import { env } from '$env/dynamic/private';
import { fail } from '@sveltejs/kit';
import { addRecipeToShopping, getCookSessions, getRecipe, getVersions } from '$lib/api';
import type { Actions, PageServerLoad } from './$types';

const API_URL = env.API_URL ?? 'http://localhost:8000';

export interface Translation {
  lang: string;
  title: string;
  meta: string | null;
  ingredients: { amount: number; unit: string; name: string; section?: string | null }[];
  steps: { text: string; timer_seconds: number | null }[];
  notes: string[];
}

export interface Annotation {
  step_index: number;
  phrase: string;
  title: string | null;
  source_path: string | null;
  heading: string | null;
  page: number | null;
  snippet: string | null;
}

export const load: PageServerLoad = async ({ fetch, params }) => {
  const [recipe, versions, sessions, annotations, english] = await Promise.all([
    getRecipe(fetch, params.slug),
    getVersions(fetch, params.slug),
    getCookSessions(fetch, params.slug, 1).catch(() => []),
    fetch(`${API_URL}/api/v1/recipes/${encodeURIComponent(params.slug)}/annotations`)
      .then((r) => (r.ok ? r.json() : { annotated: false, annotations: [] }))
      .catch(() => ({ annotated: false, annotations: [] })),
    fetch(`${API_URL}/api/v1/recipes/${encodeURIComponent(params.slug)}/translations/en`)
      .then((r) => (r.ok ? r.json() : { available: false }))
      .catch(() => ({ available: false }))
  ]);
  return {
    recipe,
    // API order is oldest-first (the iOS contract); the switcher shows newest first
    versions: [...versions].sort((a, b) => b.version - a.version),
    lastCooked: sessions[0] ?? null,
    annotated: Boolean(annotations.annotated),
    annotations: (annotations.annotations ?? []) as Annotation[],
    english: english.available ? (english as Translation) : null
  };
};

export const actions: Actions = {
  // Reading aid, not an edit: the stored recipe keeps the cook's own language.
  // The API caches per version, so this is slow once and instant afterwards.
  translate: async ({ fetch, params }) => {
    const res = await fetch(
      `${API_URL}/api/v1/recipes/${encodeURIComponent(params.slug)}/translations/en`,
      { method: 'POST', headers: { authorization: `Bearer ${env.API_TOKEN ?? ''}` } }
    );
    if (!res.ok) return fail(res.status >= 500 ? 502 : res.status,
                             { message: 'Could not translate this recipe' });
    return { translated: true };
  },

  // A write, so the bearer token stays server-side — the same rule the editor follows.
  addToList: async ({ fetch, params, request }) => {
    const data = await request.formData();
    const target = Number(data.get('target')) || null;
    await addRecipeToShopping(fetch, params.slug, target);
    return { added: true };
  },

  illuminate: async ({ fetch, params }) => {
    const res = await fetch(
      `${API_URL}/api/v1/recipes/${encodeURIComponent(params.slug)}/annotate`,
      { method: 'POST', headers: { authorization: `Bearer ${env.API_TOKEN ?? ''}` } }
    );
    if (!res.ok) return fail(res.status >= 500 ? 502 : res.status, { message: 'annotation failed' });
    return { ok: true };
  }
};
