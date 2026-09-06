<script lang="ts">
  import '../app.css';
  import { onMount } from 'svelte';
  import { onNavigate } from '$app/navigation';
  import { page } from '$app/state';
  import OfflineBanner from '$lib/components/OfflineBanner.svelte';
  import Toast from '$lib/components/Toast.svelte';
  import TimerTray from '$lib/components/TimerTray.svelte';
  import { startTicker } from '$lib/timers';

  let { children } = $props();

  // one ticker for every cook timer in the app; cook mode renders its own strip
  onMount(() => startTicker());
  const inCookMode = $derived(/\/cook$/.test(page.url.pathname));

  // gentle page crossfade where supported (reduced-motion handled in CSS)
  onNavigate((navigation) => {
    if (!document.startViewTransition) return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    return new Promise((resolve) => {
      document.startViewTransition(async () => {
        resolve();
        await navigation.complete;
      });
    });
  });

  // evening kitchen mode — explicit choice persisted per device
  let dark = $state(false);
  $effect(() => {
    dark = document.documentElement.dataset.theme === 'dark';
  });
  function toggleTheme() {
    dark = !dark;
    document.documentElement.dataset.theme = dark ? 'dark' : '';
    try {
      localStorage.setItem('sharp-edge-theme', dark ? 'dark' : 'light');
    } catch {
      // private mode — theme just won't persist
    }
  }
</script>

<a
  href="#main"
  class="font-mono-label sr-only rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-[80]"
  style="background: var(--card); border-color: var(--line); color: var(--green-deep)"
>
  skip to content
</a>
<div class="mx-auto max-w-[680px] px-[18px] pb-20">
  <header id="top" class="border-b-2 py-6 text-center" style="border-color: var(--ink)">
    <a href="/" class="inline-block">
      <img src="/logo.jpg" alt="The Sharp Edge — chef's recipe notebook" class="mx-auto w-40 rounded-xl" width="160" height="160" decoding="async" />
    </a>
    <h1 class="sr-only">The Sharp Edge</h1>
    <p class="mx-auto mt-2 max-w-[44ch] text-sm" style="color: var(--faint)">
      Scan a card, land on its recipe, rescale the servings.
    </p>
    <nav class="font-mono-label mt-3 flex justify-center gap-2 text-[11px] uppercase tracking-widest">
      <a href="/" aria-current={page.url.pathname === '/' ? 'page' : undefined} class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--green-deep)">Recipes</a>
      <a href="/library" aria-current={page.url.pathname.startsWith('/library') ? 'page' : undefined} class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--green-deep)">Library</a>
      <a href="/ask" aria-current={page.url.pathname.startsWith('/ask') ? 'page' : undefined} class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--green-deep)">Ask</a>
      <a href="/plan" aria-current={page.url.pathname.startsWith('/plan') ? 'page' : undefined} class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--green-deep)">Plan</a>
      <a href="/shopping" aria-current={page.url.pathname.startsWith('/shopping') ? 'page' : undefined} class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--green-deep)">List</a>
      <a href="/new" aria-current={page.url.pathname.startsWith('/new') ? 'page' : undefined} class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--green-deep)">Add</a>
      <button
        aria-label={dark ? 'Switch to daylight' : 'Switch to evening kitchen mode'}
        class="rounded-full border px-3 py-2"
        style="border-color: var(--line); color: var(--faint)"
        onclick={toggleTheme}
      >
        {dark ? '☀' : '☾'}
      </button>
    </nav>
    <OfflineBanner />
  </header>

  <div id="main">
    {@render children()}
  </div>

  <footer class="mt-16 border-t-2 pt-4 text-[12.5px]" style="border-color: var(--ink); color: var(--faint)">
    Quantities scale from each recipe's base yield · dashes mark to-taste amounts
    <br />
    <a href="#top" class="font-mono-label mt-2 inline-block text-[11px] uppercase tracking-widest" style="color: var(--green-deep)">
      ↑ back to top
    </a>
  </footer>
</div>

{#if !inCookMode}
  <TimerTray />
{/if}
<Toast />
