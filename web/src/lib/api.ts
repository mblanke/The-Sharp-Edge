import { env } from '$env/dynamic/private';
import { error } from '@sveltejs/kit';
import type { RecipeCard, RecipeFull } from './types';

/** Server-side API client — load functions run in the web container and
 *  reach the api container over the compose network (API_URL). */
const API_URL = env.API_URL ?? 'http://localhost:8000';

async function get<T>(fetchFn: typeof fetch, path: string): Promise<T> {
  const res = await fetchFn(`${API_URL}/api/v1${path}`);
  if (!res.ok) {
    throw error(res.status === 404 ? 404 : 502, res.status === 404 ? 'Not found' : 'API unavailable');
  }
  return res.json() as Promise<T>;
}

export const listRecipes = (fetchFn: typeof fetch) => get<RecipeCard[]>(fetchFn, '/recipes');

export const getRecipe = (fetchFn: typeof fetch, slug: string) =>
  get<RecipeFull>(fetchFn, `/recipes/${encodeURIComponent(slug)}`);
