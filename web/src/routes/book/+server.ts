import { env } from '$env/dynamic/private';
import { error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

/** One page of a source book, streamed through with the bearer token attached.
 *
 *  The generic /api proxy deliberately forwards no Authorization header, and
 *  /library/source needs one — it returns actual book content rather than metadata or a
 *  short quoted passage (CLAUDE.md §1). So this is its own route: the token stays
 *  server-side, and the browser gets a PDF it can render natively.
 *
 *  Same reachability caveat as the rest of the web app: anything that can reach this
 *  container can read it, which is why the deployment is Tailscale-only.
 */
const API_URL = env.API_URL ?? 'http://localhost:8000';

export const GET: RequestHandler = async ({ url, fetch }) => {
  const path = url.searchParams.get('path');
  const page = url.searchParams.get('page');
  if (!path || !page) throw error(400, 'path and page are required');

  const target =
    `${API_URL}/api/v1/library/source?path=${encodeURIComponent(path)}&page=${encodeURIComponent(page)}`;
  const res = await fetch(target, {
    headers: { authorization: `Bearer ${env.API_TOKEN ?? ''}` }
  });
  if (!res.ok) throw error(res.status === 404 ? 404 : 502, 'That page could not be opened.');

  return new Response(res.body, {
    headers: {
      'content-type': 'application/pdf',
      // inline so the browser renders it rather than downloading a stack of files
      'content-disposition': `inline; filename="page-${page}.pdf"`,
      'cache-control': 'private, max-age=3600'
    }
  });
};
