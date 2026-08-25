import { env } from '$env/dynamic/private';
import { fail } from '@sveltejs/kit';
import { getCookSessions, getRecipe, getVersions } from '$lib/api';
import type { Actions, PageServerLoad } from './$types';

const API_URL = env.API_URL ?? 'http://localhost:8000';

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
  const [recipe, versions, sessions, annotations] = await Promise.all([
    getRecipe(fetch, params.slug),
    getVersions(fetch, params.slug),
    getCookSessions(fetch, params.slug, 1).catch(() => []),
    fetch(`${API_URL}/api/v1/recipes/${encodeURIComponent(params.slug)}/annotations`)
      .then((r) => (r.ok ? r.json() : { annotated: false, annotations: [] }))
      .catch(() => ({ annotated: false, annotations: [] }))
  ]);
  return {
    recipe,
    versions,
    lastCooked: sessions[0] ?? null,
    annotated: Boolean(annotations.annotated),
    annotations: (annotations.annotations ?? []) as Annotation[]
  };
};

export const actions: Actions = {
  illuminate: async ({ fetch, params }) => {
    const res = await fetch(
      `${API_URL}/api/v1/recipes/${encodeURIComponent(params.slug)}/annotate`,
      { method: 'POST', headers: { authorization: `Bearer ${env.API_TOKEN ?? ''}` } }
    );
    if (!res.ok) return fail(res.status >= 500 ? 502 : res.status, { message: 'annotation failed' });
    return { ok: true };
  }
};
