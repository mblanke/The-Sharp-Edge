import { env } from '$env/dynamic/private';
import { error } from '@sveltejs/kit';
import { problemDetail } from './problem';
import type {
  Ingredient,
  RecipeCard,
  RecipeCreate,
  RecipeFull,
  RecipeUpdate,
  RecipeVersion,
  ShoppingItem
} from './types';

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

/** Full version history, newest first. */
export const getVersions = (fetchFn: typeof fetch, slug: string) =>
  get<RecipeVersion[]>(fetchFn, `/recipes/${encodeURIComponent(slug)}/versions`);

export interface ScaledIngredient extends Ingredient {
  scaled_amount: number;
  display: string;
}

/** Server-canonical scaling (§8) — used by cook mode and the shopping list. */
export async function scaleRecipe(
  fetchFn: typeof fetch,
  slug: string,
  targetYield: number
): Promise<ScaledIngredient[]> {
  const res = await fetchFn(`${API_URL}/api/v1/recipes/${encodeURIComponent(slug)}/scale`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ target_yield: targetYield })
  });
  if (!res.ok) throw error(502, 'scaling failed');
  const body = (await res.json()) as { ingredients: ScaledIngredient[] };
  return body.ingredients;
}

/** Raised when the API rejects a write; `.detail` carries the problem+json message. */
export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number
  ) {
    super(message);
  }
}

// ---------------------------------------------------------------- cook sessions

export interface CookSession {
  id: string;
  started_at: string;
  finished_at: string;
  scaled_yield: number;
  notes: string | null;
}

export const getCookSessions = (fetchFn: typeof fetch, slug: string, limit = 1) =>
  get<CookSession[]>(fetchFn, `/recipes/${encodeURIComponent(slug)}/sessions?limit=${limit}`);

/** Server-side only (token from env). */
export async function logCookSession(
  fetchFn: typeof fetch,
  slug: string,
  payload: { started_at?: string; scaled_yield: number; notes?: string }
): Promise<CookSession> {
  const res = await fetchFn(`${API_URL}/api/v1/recipes/${encodeURIComponent(slug)}/sessions`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${env.API_TOKEN ?? ''}`
    },
    body: JSON.stringify(payload)
  });
  if (!res.ok) throw new ApiError(await problemDetail(res), res.status);
  return res.json() as Promise<CookSession>;
}

// ---------------------------------------------------------------- meal plan

export interface PlanEntry {
  id: string;
  date: string;
  meal: 'breakfast' | 'lunch' | 'dinner';
  scaled_yield: number;
  recipe_slug: string;
  recipe_title: string;
  gf: boolean;
}

export interface WeekPlan {
  week: string; // Monday
  entries: PlanEntry[];
}

export const getWeekPlan = (fetchFn: typeof fetch, week?: string) =>
  get<WeekPlan>(fetchFn, `/plan${week ? `?week=${week}` : ''}`);

/** Authorized plan mutations — server-side only (token from env, like updateRecipe). */
async function planWrite<T>(
  fetchFn: typeof fetch,
  method: string,
  path: string,
  body?: unknown
): Promise<T> {
  const res = await fetchFn(`${API_URL}/api/v1${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${env.API_TOKEN ?? ''}`
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  if (!res.ok) throw new ApiError(await problemDetail(res), res.status);
  return res.json() as Promise<T>;
}

export const planUpsert = (
  fetchFn: typeof fetch,
  entry: { date: string; meal: string; recipe_slug: string; scaled_yield?: number }
) => planWrite<WeekPlan>(fetchFn, 'POST', '/plan', entry);

export const planRemove = (fetchFn: typeof fetch, entryId: string) =>
  planWrite<WeekPlan>(fetchFn, 'DELETE', `/plan/${entryId}`);

/** Push the week's planned recipes into the running shopping list (shared with iOS). */
export const planPushToShopping = (fetchFn: typeof fetch, week: string) =>
  planWrite<{ items: ShoppingItem[] }>(fetchFn, 'POST', `/plan/shopping-list?week=${week}`);

// ---------------------------------------------------------------- shopping list

export const getShopping = async (fetchFn: typeof fetch) =>
  (await get<{ items: ShoppingItem[] }>(fetchFn, '/shopping')).items;

/** Plain text for pasting into Notes or AnyList — one item per line, aisle headings. */
export async function getShoppingText(fetchFn: typeof fetch): Promise<string> {
  const res = await fetchFn(`${API_URL}/api/v1/shopping/text`);
  return res.ok ? res.text() : '';
}

export async function setChecked(fetchFn: typeof fetch, id: string, checked: boolean) {
  const res = await fetchFn(`${API_URL}/api/v1/shopping/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${env.API_TOKEN ?? ''}` },
    body: JSON.stringify({ checked })
  });
  if (!res.ok) throw new ApiError(await problemDetail(res), res.status);
}

export async function clearShopping(fetchFn: typeof fetch, checkedOnly: boolean) {
  const res = await fetchFn(`${API_URL}/api/v1/shopping?checked_only=${checkedOnly}`, {
    method: 'DELETE',
    headers: { authorization: `Bearer ${env.API_TOKEN ?? ''}` }
  });
  if (!res.ok) throw new ApiError(await problemDetail(res), res.status);
}

export async function addRecipeToShopping(
  fetchFn: typeof fetch,
  slug: string,
  targetYield: number | null
) {
  const res = await fetchFn(`${API_URL}/api/v1/shopping/add`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${env.API_TOKEN ?? ''}` },
    body: JSON.stringify({ slug, target_yield: targetYield })
  });
  if (!res.ok) throw new ApiError(await problemDetail(res), res.status);
}

/** Translate a draft's words into another language; amounts never change. */
export async function translateRecipe(
  fetchFn: typeof fetch,
  payload: Record<string, unknown>,
  target = 'en'
): Promise<Record<string, unknown>> {
  const res = await fetchFn(`${API_URL}/api/v1/recipes/translate`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${env.API_TOKEN ?? ''}`
    },
    body: JSON.stringify({ ...payload, target })
  });
  if (!res.ok) throw new ApiError(await problemDetail(res), res.status);
  return res.json() as Promise<Record<string, unknown>>;
}

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
  if (!res.ok) throw new ApiError(await problemDetail(res), res.status);
  return res.json() as Promise<RecipeFull>;
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
