import { env } from '$env/dynamic/private';
import { error } from '@sveltejs/kit';
import { problemDetail } from './problem';
import type { Ingredient, RecipeFull, RecipeUpdate, RecipeCard, RecipeVersion } from './types';

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

export interface ShoppingItem {
  id: string;
  name: string;
  amount: string;
  checked: boolean;
  recipe_id: string | null;
}

export interface WeekPlan {
  week: string; // Monday
  entries: PlanEntry[];
  shopping: ShoppingItem[];
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

export const planGenerateList = (fetchFn: typeof fetch, week: string) =>
  planWrite<WeekPlan>(fetchFn, 'POST', `/plan/shopping-list?week=${week}`);

export const planCheckItem = (fetchFn: typeof fetch, itemId: string, checked: boolean) =>
  planWrite<ShoppingItem>(fetchFn, 'PATCH', `/plan/shopping-list/${itemId}`, { checked });

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
