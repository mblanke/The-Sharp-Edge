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
        // offline navigation to an uncached page → home shell if we have it
        if (event.request.mode === 'navigate') {
          const home = await caches.match('/');
          if (home) return home;
        }
        return Response.error();
      })
  );
});
