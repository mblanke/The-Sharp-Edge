import { env } from '$env/dynamic/private';
import type { PageServerLoad } from './$types';

const API_URL = env.API_URL ?? 'http://localhost:8000';

export const load: PageServerLoad = async ({ fetch }) => {
  try {
    const res = await fetch(`${API_URL}/api/v1/library/books`);
    if (res.ok) return { library: await res.json() };
  } catch {
    // fall through to degraded state
  }
  return { library: { mounted: false, library_dir: null, books: [], rag_health: { ok: false } } };
};
