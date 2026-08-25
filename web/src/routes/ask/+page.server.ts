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
  // book names for the scope selector (degrades to whole-library only)
  let books: string[] = [];
  try {
    const res = await fetch(`${API_URL}/api/v1/library/books`);
    if (res.ok) {
      const lib = await res.json();
      books = (lib.books ?? [])
        .filter((b: { kind: string }) => b.kind === 'file')
        .map((b: { name: string }) => b.name);
    }
  } catch {
    // rag-api down — selector hides
  }
  return { recipeSlug, recipeTitle, conversations, books };
};
