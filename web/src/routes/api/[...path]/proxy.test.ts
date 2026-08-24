import { afterEach, describe, expect, it, vi } from 'vitest';
import { DELETE, GET, PATCH, POST, PUT } from './+server';

function makeEvent(method: string, headers: Record<string, string> = {}) {
  const request = new Request('http://web/api/recipes/goulash', {
    method,
    headers,
    body: method === 'GET' || method === 'HEAD' ? undefined : '{"x":1}',
    // @ts-expect-error node fetch requires duplex for streaming bodies
    duplex: 'half'
  });
  return {
    params: { path: 'recipes/goulash' },
    request,
    url: new URL('http://web/api/recipes/goulash?week=2026-08-24')
  } as never;
}

describe('api proxy', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('forwards method, path, query, and Authorization', async () => {
    const fetchMock = vi.fn(async () => new Response('{}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await PUT(makeEvent('PUT', { authorization: 'Bearer tok', 'content-type': 'application/json' }));

    const [target, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(target).toBe('http://localhost:8000/api/v1/recipes/goulash?week=2026-08-24');
    expect(init.method).toBe('PUT');
    const headers = init.headers as Headers;
    expect(headers.get('authorization')).toBe('Bearer tok');
    expect(headers.get('content-type')).toBe('application/json');
  });

  it('omits Authorization when the client sent none', async () => {
    const fetchMock = vi.fn(async () => new Response('{}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await GET(makeEvent('GET'));

    const [, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect((init.headers as Headers).get('authorization')).toBeNull();
  });

  it('exports every write method', () => {
    for (const handler of [GET, POST, PUT, PATCH, DELETE]) {
      expect(typeof handler).toBe('function');
    }
  });

  it('passes status and content-type back through', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(
        async () =>
          new Response('{"title":"Conflict"}', {
            status: 409,
            headers: { 'content-type': 'application/problem+json' }
          })
      )
    );

    const res = await POST(makeEvent('POST'));
    expect(res.status).toBe(409);
    expect(res.headers.get('content-type')).toBe('application/problem+json');
  });
});
