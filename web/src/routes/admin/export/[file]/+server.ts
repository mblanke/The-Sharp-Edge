import { env } from '$env/dynamic/private';
import { error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const API_URL = env.API_URL ?? 'http://localhost:8000';
const ALLOWED = new Set(['master.md', 'cards.pdf']);

/** Authorized export proxy — the bearer token stays server-side. */
export const GET: RequestHandler = async ({ params }) => {
  if (!ALLOWED.has(params.file)) throw error(404, 'Not found');
  const res = await fetch(`${API_URL}/api/v1/export/${params.file}`, {
    headers: { authorization: `Bearer ${env.API_TOKEN ?? ''}` }
  });
  if (!res.ok) throw error(502, `export failed (${res.status})`);
  return new Response(res.body, {
    headers: {
      'content-type': res.headers.get('content-type') ?? 'application/octet-stream',
      'content-disposition': res.headers.get('content-disposition') ?? 'attachment'
    }
  });
};
