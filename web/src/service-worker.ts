/// <reference types="@sveltejs/kit" />
/// <reference lib="webworker" />

import { build, files, version } from '$service-worker';

const sw = self as unknown as ServiceWorkerGlobalScope;

// Shell cache: built assets + static files (fonts included — no external origins).
const SHELL = `sharp-edge-shell-${version}`;
// Runtime cache: last-viewed recipe pages + API JSON, LRU-capped so a phone
// that browsed the whole library still cooks offline without unbounded growth.
const RUNTIME = `sharp-edge-rt-${version}`;
const RUNTIME_LIMIT = 60; // ~20 recipes × (page + JSON) with headroom

const ASSETS = [...build, ...files];

sw.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(SHELL)
      .then((cache) => cache.addAll(ASSETS))
      .then(() => sw.skipWaiting())
  );
});

sw.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k !== SHELL && k !== RUNTIME).map((k) => caches.delete(k)))
      )
      .then(() => sw.clients.claim())
  );
});

/** put + move-to-end; evict oldest entries beyond the cap (cache.keys() is insertion-ordered). */
async function putLimited(request: Request, response: Response): Promise<void> {
  const cache = await caches.open(RUNTIME);
  await cache.delete(request);
  await cache.put(request, response);
  const keys = await cache.keys();
  for (const key of keys.slice(0, Math.max(0, keys.length - RUNTIME_LIMIT))) {
    await cache.delete(key);
  }
}

/** Only cache what offline cooking needs: recipe pages, home, and recipe JSON.
 *  Never streams (/api/ask) or search results. */
function cacheable(url: URL): boolean {
  if (url.pathname === '/' || url.pathname.startsWith('/r/')) return true;
  if (url.pathname.startsWith('/api/recipes')) return true;
  return false;
}

/** Minimal, self-contained page for a route that needs the server. */
function offlinePage(url: URL): Response {
  const needs =
    url.pathname.startsWith('/ask') ? 'Asking the library' :
    url.pathname.startsWith('/plan') ? 'The meal plan' :
    url.pathname.startsWith('/shopping') ? 'The shopping list' :
    url.pathname.startsWith('/library') ? 'The library' : 'This page';
  const html = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Offline — The Sharp Edge</title>
<style>body{margin:0;padding:48px 18px;font:15px system-ui,sans-serif;color:#14161C;background:#F2F3F5;text-align:center}
h1{font-size:22px;margin:0 0 8px}p{color:#5F6570;max-width:44ch;margin:0 auto 20px}
a{display:inline-block;min-height:44px;line-height:44px;padding:0 20px;border-radius:999px;background:#2c4f36;color:#F4F3EC;text-decoration:none;font:11px ui-monospace,monospace;letter-spacing:.12em;text-transform:uppercase}
@media(prefers-color-scheme:dark){body{color:#E6E9EE;background:#101319}p{color:#98A0AD}}</style>
<h1>You're offline.</h1><p>${needs} needs the server. Recipes you have opened before still cook offline.</p>
<a href="/">← all recipes</a>`;
  return new Response(html, { status: 503, headers: { 'content-type': 'text/html; charset=utf-8' } });
}

sw.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== location.origin) return;

  // cache-first for immutable shell assets
  if (ASSETS.includes(url.pathname)) {
    event.respondWith(caches.match(url.pathname).then((hit) => hit ?? fetch(event.request)));
    return;
  }

  // network-first with cache fallback for pages/JSON
  event.respondWith(
    fetch(event.request)
      .then((res) => {
        if (res.ok && cacheable(url)) {
          const copy = res.clone();
          event.waitUntil(putLimited(event.request, copy));
        }
        return res;
      })
      .catch(async () => {
        const hit = await caches.match(event.request);
        if (hit) return hit;
        // offline navigation to an uncached page: say so, rather than serving the
        // home shell under the wrong URL and letting the tap look like it worked
        if (event.request.mode === 'navigate') return offlinePage(url);
        return Response.error();
      })
  );
});
