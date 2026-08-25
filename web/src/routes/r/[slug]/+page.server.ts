import { getCookSessions, getRecipe, getVersions } from '$lib/api';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, params }) => {
  const [recipe, versions, sessions] = await Promise.all([
    getRecipe(fetch, params.slug),
    getVersions(fetch, params.slug),
    getCookSessions(fetch, params.slug, 1).catch(() => [])
  ]);
  return { recipe, versions, lastCooked: sessions[0] ?? null };
};
