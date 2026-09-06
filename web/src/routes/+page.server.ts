import { listRecipes } from '$lib/api';
import type { PageServerLoad } from './$types';

// Like library/+page.server.ts: an unreachable API degrades to an explained empty
// shell rather than a bare 500 — the service worker still serves opened recipes.
export const load: PageServerLoad = async ({ fetch }) => {
  try {
    return { recipes: await listRecipes(fetch), unavailable: false };
  } catch {
    return { recipes: [], unavailable: true };
  }
};
