<script lang="ts">
  import '../app.css';
  import { onMount } from 'svelte';
  import { goto, onNavigate } from '$app/navigation';
  import { navigating, page } from '$app/state';
  import OfflineBanner from '$lib/components/OfflineBanner.svelte';
  import Toast from '$lib/components/Toast.svelte';
  import TimerTray from '$lib/components/TimerTray.svelte';
  import Icon from '$lib/components/Icon.svelte';
  import { startTicker } from '$lib/timers';
  import { applyTheme, readTheme, syncThemeColor } from '$lib/prefs';

  let { children } = $props();

  // one ticker for every cook timer in the app; cook mode renders its own strip
  onMount(() => startTicker());
  const path = $derived(page.url.pathname);
  const inCookMode = $derived(/\/cook$/.test(path));

  // Pages that earn the full width of an iPad: the card grid, the two-column
  // recipe, the week grid, the shelf and the thread list. Everything else is
  // prose and stays at reading width.
  const wide = $derived(
    path === '/' ||
      /^\/r\/[^/]+$/.test(path) ||
      path.startsWith('/plan') ||
      path.startsWith('/library') ||
      path.startsWith('/ask')
  );

  const NAV = [
    { href: '/', label: 'Recipes', icon: 'book', match: (p: string) => p === '/' || p.startsWith('/r/') },
    { href: '/library', label: 'Library', icon: 'shelf', match: (p: string) => p.startsWith('/library') },
    { href: '/ask', label: 'Ask', icon: 'chat', match: (p: string) => p.startsWith('/ask') },
    { href: '/plan', label: 'Plan', icon: 'calendar', match: (p: string) => p.startsWith('/plan') },
    { href: '/shopping', label: 'List', icon: 'basket', match: (p: string) => p.startsWith('/shopping') }
  ] as const;
  const current = (match: (p: string) => boolean) => (match(path) ? 'page' : undefined);

  // A home-screen app has no browser chrome, so a phone needs its own way back
  // from a recipe. In-app history wins; a cold start from a QR code goes home.
  let canGoBack = $state(false);
  onMount(() => {
    canGoBack = history.length > 1;
  });
  function back() {
    if (canGoBack) history.back();
    else goto('/');
  }

  // ⌘K / Ctrl+K from any page: the home search box (home handles it locally)
  function onKey(e: KeyboardEvent) {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k' && path !== '/') {
      e.preventDefault();
      goto('/?focus=1');
    }
  }

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

  // A tap over Tailscale can take a second before anything changes on screen;
  // the hairline says it landed. Only shown for navigations that take a moment.
  let slow = $state(false);
  let slowTimer: ReturnType<typeof setTimeout> | undefined;
  $effect(() => {
    clearTimeout(slowTimer);
    if (navigating.to) {
      slowTimer = setTimeout(() => (slow = true), 150);
    } else {
      slow = false;
    }
    return () => clearTimeout(slowTimer);
  });

  // evening kitchen mode — explicit choice persisted per device; with no choice
  // the app follows the iPad, including when the iPad flips at sunset
  let dark = $state(false);
  $effect(() => {
    dark = document.documentElement.dataset.theme === 'dark';
  });
  onMount(() => {
    syncThemeColor();
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const follow = () => {
      if (readTheme() === 'system') {
        applyTheme('system');
        dark = document.documentElement.dataset.theme === 'dark';
      }
    };
    mq.addEventListener('change', follow);
    return () => mq.removeEventListener('change', follow);
  });
  function toggleTheme() {
    dark = !dark;
    applyTheme(dark ? 'dark' : 'light');
  }
</script>

<svelte:window onkeydown={onKey} />

<a
  href="#main"
  class="font-mono-label sr-only rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-[80]"
  style="background: var(--card); border-color: var(--line); color: var(--ink-accent)"
>
  skip to content
</a>

<div class="nav-progress" class:on={slow} aria-hidden="true"></div>

<div class="shell">
  <!-- rail: tablet + desktop -->
  <aside class="rail" data-testid="rail">
    <a href="/" class="rail-brand" aria-label="The Sharp Edge — home">
      <img src="/logo.jpg" alt="" width="44" height="44" decoding="async" />
      <span>The Sharp Edge</span>
    </a>
    <nav class="rail-nav" aria-label="Primary">
      {#each NAV as item (item.href)}
        <a href={item.href} aria-current={current(item.match)}>
          <Icon name={item.icon} />
          <span>{item.label}</span>
        </a>
      {/each}
    </nav>
    <div class="rail-foot">
      <a href="/new" class="rail-add" aria-current={current((p) => p.startsWith('/new'))}>
        <Icon name="plus" />
        <span>Add recipe</span>
      </a>
      <div class="rail-foot-row">
        <a href="/settings" class="icon-btn" aria-label="Settings" aria-current={current((p) => p.startsWith('/settings'))}>
          <Icon name="gear" />
        </a>
        <button
          class="icon-btn"
          aria-label={dark ? 'Switch to daylight' : 'Switch to evening kitchen mode'}
          onclick={toggleTheme}
        >
          <Icon name={dark ? 'sun' : 'moon'} />
        </button>
      </div>
    </div>
  </aside>

  <div class="shell-content">
    <!-- top bar: phone -->
    <header class="topbar" class:sub={path !== '/'} data-testid="topbar">
      {#if path !== '/'}
        <button class="icon-btn -ml-2" aria-label="Back" onclick={back} data-testid="back">
          <Icon name="back" />
        </button>
      {/if}
      <a href="/" class="topbar-brand">
        <img src="/logo.jpg" alt="" width="34" height="34" decoding="async" />
        <span>The Sharp Edge</span>
      </a>
      <a href="/new" class="icon-btn primary" aria-label="Add recipe" aria-current={current((p) => p.startsWith('/new'))}>
        <Icon name="plus" />
      </a>
      <a href="/settings" class="icon-btn" aria-label="Settings" aria-current={current((p) => p.startsWith('/settings'))}>
        <Icon name="gear" />
      </a>
      <button
        class="icon-btn"
        aria-label={dark ? 'Switch to daylight' : 'Switch to evening kitchen mode'}
        onclick={toggleTheme}
      >
        <Icon name={dark ? 'sun' : 'moon'} />
      </button>
    </header>

    <div class="shell-page" class:wide>
      <h1 class="sr-only">The Sharp Edge</h1>
      <OfflineBanner />
      <div id="main">
        {@render children()}
      </div>
      <footer class="mt-16 border-t pt-4 text-[12.5px]" style="border-color: var(--line); color: var(--faint)">
        Quantities scale from each recipe's base yield · dashes mark to-taste amounts
      </footer>
    </div>
  </div>

  <!-- tab bar: phone. Not while cooking — that screen owns the bottom edge. -->
  {#if !inCookMode}
    <nav class="tabbar" aria-label="Sections" data-testid="tabbar">
      {#each NAV as item (item.href)}
        <a href={item.href} aria-current={current(item.match)}>
          <Icon name={item.icon} />
          <span>{item.label}</span>
        </a>
      {/each}
    </nav>
  {/if}
</div>

{#if !inCookMode}
  <TimerTray />
{/if}
<Toast />
