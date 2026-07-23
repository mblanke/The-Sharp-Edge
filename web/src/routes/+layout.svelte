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
