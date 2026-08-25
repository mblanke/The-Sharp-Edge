import { env } from '$env/dynamic/private';
import type { PageServerLoad } from './$types';

const API_URL = env.API_URL ?? 'http://localhost:8000';
const AUTH = { authorization: `Bearer ${env.API_TOKEN ?? ''}` };

export const load: PageServerLoad = async ({ fetch }) => {
  const [auditRes, healthRes, libraryRes] = await Promise.allSettled([
    fetch(`${API_URL}/api/v1/admin/gf-audit`, { headers: AUTH }),
    fetch(`${API_URL}/api/v1/healthz`),
    fetch(`${API_URL}/api/v1/library/books`)
  ]);

  const json = async (r: PromiseSettledResult<Response>) =>
    r.status === 'fulfilled' && r.value.ok ? r.value.json() : null;

  return {
    audit: await json(auditRes),
    health: await json(healthRes),
    library: await json(libraryRes)
  };
};
