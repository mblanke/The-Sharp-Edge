<script lang="ts">
  import '../app.css';

  let { children } = $props();
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
      <a href="/" class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--ink-accent)">Recipes</a>
      <a href="/library" class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--ink-accent)">Library</a>
      <a href="/ask" class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--ink-accent)">Ask</a>
      <a href="/new" class="rounded-full border px-4 py-2 no-underline" style="border-color: var(--line); color: var(--ink-accent)">Add</a>
    </nav>
  </header>

  {@render children()}

  <footer class="mt-16 border-t-2 pt-4 text-[12.5px]" style="border-color: var(--ink); color: var(--faint)">
    Quantities scale from each recipe's base yield · dashes mark to-taste amounts
    <br />
    <a href="#top" class="font-mono-label mt-2 inline-block text-[11px] uppercase tracking-widest" style="color: var(--ink-accent)">
      ↑ back to top
    </a>
  </footer>
</div>
