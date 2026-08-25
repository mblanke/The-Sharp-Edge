<script lang="ts">
  import '../app.css';
  import { onNavigate } from '$app/navigation';

  let { children } = $props();

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

<div class="mx-auto max-w-[680px] px-[18px] pb-20">
  <header id="top" class="border-b-2 py-6 text-center" style="border-color: var(--ink)">
    <a href="/" class="inline-block">
      <img src="/logo.jpg" alt="The Sharp Edge — chef's recipe notebook" class="mx-auto w-40 rounded-xl" />
    </a>
    <h1 class="sr-only">The Sharp Edge</h1>
    <p class="mx-auto mt-2 max-w-[44ch] text-sm" style="color: var(--faint)">
      Scan a card, land on its recipe, rescale the servings.
    </p>
    <nav class="font-mono-label mt-3 flex justify-center gap-2 text-[11px] uppercase tracking-widest">
      <a href="/" class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--green-deep)">Recipes</a>
      <a href="/library" class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--green-deep)">Library</a>
      <a href="/ask" class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--green-deep)">Ask</a>
      <a href="/plan" class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--green-deep)">Plan</a>
      <button
        aria-label={dark ? 'Switch to daylight' : 'Switch to evening kitchen mode'}
        class="rounded-full border px-3 py-2"
        style="border-color: var(--line); color: var(--faint)"
        onclick={toggleTheme}
      >
        {dark ? '☀' : '☾'}
      </button>
    </nav>
  </header>

  {@render children()}

  <footer class="mt-16 border-t-2 pt-4 text-[12.5px]" style="border-color: var(--ink); color: var(--faint)">
    Quantities scale from each recipe's base yield · dashes mark to-taste amounts
    <br />
    <a href="#top" class="font-mono-label mt-2 inline-block text-[11px] uppercase tracking-widest" style="color: var(--green-deep)">
      ↑ back to top
    </a>
  </footer>
</div>
