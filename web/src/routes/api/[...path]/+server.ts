import { env } from '$env/dynamic/private';
import type { RequestHandler } from './$types';

/** Same-origin proxy to the FastAPI backend — keeps the browser off CORS and
 *  lets SSE from /ask stream straight through. */
const API_URL = env.API_URL ?? 'http://localhost:8000';

const proxy: RequestHandler = async ({ params, request, url }) => {
  const target = `${API_URL}/api/v1/${params.path}${url.search}`;
  const headers = new Headers();
  const contentType = request.headers.get('content-type');
  if (contentType) headers.set('content-type', contentType);

  const res = await fetch(target, {
    method: request.method,
    headers,
    body: request.method === 'GET' || request.method === 'HEAD' ? undefined : request.body,
    // @ts-expect-error node fetch requires duplex for streaming bodies
    duplex: 'half'
  });

  return new Response(res.body, {
    status: res.status,
    headers: {
      'content-type': res.headers.get('content-type') ?? 'application/json',
      'cache-control': 'no-cache'
    }
  });
};

export const GET = proxy;
export const POST = proxy;
