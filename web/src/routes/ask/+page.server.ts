import { env } from '$env/dynamic/private';
import type { PageServerLoad } from './$types';

const API_URL = env.API_URL ?? 'http://localhost:8000';

export const load: PageServerLoad = async ({ fetch, url }) => {
  const recipeSlug = url.searchParams.get('recipe');
  let recipeTitle: string | null = null;
  if (recipeSlug) {
    const res = await fetch(`${API_URL}/api/v1/recipes/${encodeURIComponent(recipeSlug)}`);
    if (res.ok) recipeTitle = (await res.json()).title;
  }
  let conversations: Array<{ id: string; title: string | null; created_at: string }> = [];
  try {
    const res = await fetch(`${API_URL}/api/v1/conversations`);
    if (res.ok) conversations = await res.json();
  } catch {
    // API down — page still renders
  }
  return { recipeSlug, recipeTitle, conversations };
};
