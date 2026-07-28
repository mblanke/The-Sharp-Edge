import { env } from '$env/dynamic/private';
import { error } from '@sveltejs/kit';
import { problemDetail } from './problem';
import type { RecipeCreate, RecipeFull, RecipeUpdate, RecipeCard, ShoppingItem } from './types';

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


// ---------------------------------------------------------------- shopping list

/** The list, already in walking order — the server sorts by aisle so the aisle table
 *  has one home (Python), mirrored only in Swift and pinned by shared/fixtures. */
export const getShopping = async (fetchFn: typeof fetch) =>
  (await get<{ items: ShoppingItem[] }>(fetchFn, '/shopping')).items;

/** Plain text for pasting into Notes or AnyList — one item per line, aisle headings. */
export async function getShoppingText(fetchFn: typeof fetch): Promise<string> {
  const res = await fetchFn(`${API_URL}/api/v1/shopping/text`);
  return res.ok ? res.text() : '';
}

/** Ticking something off is a write, so the token stays server-side (see updateRecipe). */
export async function setChecked(fetchFn: typeof fetch, id: string, checked: boolean) {
  const res = await fetchFn(`${API_URL}/api/v1/shopping/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${env.API_TOKEN ?? ''}` },
    body: JSON.stringify({ checked })
  });
  if (!res.ok) throw new ApiError(await problemDetail(res), res.status);
}

export async function clearShopping(fetchFn: typeof fetch, checkedOnly: boolean) {
  const res = await fetchFn(
    `${API_URL}/api/v1/shopping?checked_only=${checkedOnly}`,
    { method: 'DELETE', headers: { authorization: `Bearer ${env.API_TOKEN ?? ''}` } }
  );
  if (!res.ok) throw new ApiError(await problemDetail(res), res.status);
}

export async function addRecipeToShopping(
  fetchFn: typeof fetch, slug: string, targetYield: number | null
) {
  const res = await fetchFn(`${API_URL}/api/v1/shopping/add`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${env.API_TOKEN ?? ''}` },
    body: JSON.stringify({ slug, target_yield: targetYield })
  });
  if (!res.ok) throw new ApiError(await problemDetail(res), res.status);
}
