import { env } from '$env/dynamic/private';
import { error } from '@sveltejs/kit';
import { problemDetail } from './problem';
import type { RecipeCreate, RecipeFull, RecipeUpdate, RecipeCard } from './types';

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

/** Raised when the API rejects a write; `.detail` carries the problem+json message. */
export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number
  ) {
    super(message);
  }
}

/** PUT a new version (append-only, CLAUDE.md §6). Bearer token stays server-side;
 *  the browser never sees it — only call this from load/actions, never the client. */
export async function updateRecipe(
  fetchFn: typeof fetch,
  slug: string,
  payload: RecipeUpdate
): Promise<RecipeFull> {
  const res = await fetchFn(`${API_URL}/api/v1/recipes/${encodeURIComponent(slug)}`, {
    method: 'PUT',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${env.API_TOKEN ?? ''}`
    },
    body: JSON.stringify(payload)
  });
  if (!res.ok) {
    const detail = await problemDetail(res);
    throw new ApiError(detail, res.status);
  }
  return res.json() as Promise<RecipeFull>;
}

/** POST a new recipe. Same server-side-only rule as updateRecipe: the API proxy at
 *  routes/api/[...path] forwards no Authorization header, so this cannot be called
 *  from the browser. A duplicate slug comes back as a 409 for the form to surface. */
export async function createRecipe(
  fetchFn: typeof fetch,
  payload: RecipeCreate
): Promise<RecipeFull> {
  const res = await fetchFn(`${API_URL}/api/v1/recipes`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${env.API_TOKEN ?? ''}`
    },
    body: JSON.stringify(payload)
  });
  if (!res.ok) {
    const detail = await problemDetail(res);
    throw new ApiError(detail, res.status);
  }
  return res.json() as Promise<RecipeFull>;
}
