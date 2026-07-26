<script lang="ts">
  import { scaledDisplay } from '$lib/scaling';
  import type { Ingredient } from '$lib/types';

  let { data } = $props();

  const recipe = $derived(data.recipe);

  let target = $state(0);
  $effect.pre(() => {
    // reset when navigating between recipes
    target = data.recipe.base_yield;
  });

  const factor = $derived(target / recipe.base_yield);
  const maxYield = $derived(recipe.base_yield * 4);

  let flashing = $state(false);
  let flashTimer: ReturnType<typeof setTimeout> | undefined;

  function setTarget(next: number) {
    target = Math.min(maxYield, Math.max(1, next));
    flashing = true;
    clearTimeout(flashTimer);
    flashTimer = setTimeout(() => (flashing = false), 450);
  }

  /** Render "**Lead-in:** rest" bold markers from step/note text. */
  function boldParts(text: string): Array<{ bold: boolean; t: string }> {
    const parts: Array<{ bold: boolean; t: string }> = [];
    const re = /\*\*(.+?)\*\*/g;
    let last = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(text)) !== null) {
      if (m.index > last) parts.push({ bold: false, t: text.slice(last, m.index) });
      parts.push({ bold: true, t: m[1] });
      last = m.index + m[0].length;
    }
    if (last < text.length) parts.push({ bold: false, t: text.slice(last) });
    return parts;
  }

  function sectionChanged(ings: Ingredient[], i: number): string | null {
    const s = ings[i].section ?? null;
    if (!s) return null;
    return i === 0 || ings[i - 1].section !== s ? s : null;
  }
</script>

<svelte:head>
  <title>{recipe.title} — The Sharp Edge</title>
</svelte:head>

<article class="pt-7">
  <div class="font-mono-label text-[11px] uppercase tracking-widest" style="color: var(--accent)">
    {recipe.category}
  </div>
  <h2 class="font-display mt-1 text-[clamp(24px,5.6vw,32px)] leading-tight">
    {recipe.title}
    {#if recipe.gf}
      <span
        class="font-mono-label ml-2 inline-block translate-y-[-3px] rounded-full px-2.5 py-1 align-middle text-[10.5px] uppercase tracking-widest"
        style="background: var(--primary); color: var(--off-white)"
      >
        GF
      </span>
    {/if}
  </h2>
  {#if recipe.meta}
    <p class="mt-1 text-[13.5px]" style="color: var(--faint)">{recipe.meta}</p>
  {/if}
  {#if recipe.source}
    <p class="mt-1 text-[12.5px] italic" style="color: var(--faint)">source: {recipe.source}</p>
  {/if}

  {#if !recipe.noscale}
    <div
      class="mt-4 flex items-center gap-3 rounded-2xl px-4 py-3"
      style="background: var(--primary-deep); color: var(--off-white)"
    >
      <span class="font-mono-label text-[11px] uppercase tracking-widest opacity-80">Scale</span>
      <button
        aria-label="Fewer {recipe.yield_word}"
        class="h-11 w-11 rounded-xl text-xl"
        style="background: var(--btn-ghost); color: var(--off-white)"
        onclick={() => setTarget(target - 1)}
      >
        −
      </button>
      <span class="font-display min-w-[2.2ch] text-center text-[26px]">{target}</span>
      <button
        aria-label="More {recipe.yield_word}"
        class="h-11 w-11 rounded-xl text-xl"
        style="background: var(--btn-ghost); color: var(--off-white)"
        onclick={() => setTarget(target + 1)}
      >
        +
      </button>
      <span class="text-[13px] opacity-80">{recipe.yield_word}</span>
      <button
        class="font-mono-label ml-auto min-h-[44px] rounded-full border px-3 text-[11px] uppercase tracking-widest"
        style="border-color: var(--btn-outline); color: var(--off-white)"
        onclick={() => setTarget(recipe.base_yield)}
      >
        base {recipe.base_yield}
      </button>
    </div>
  {/if}

  {#if recipe.current_version.ingredients.length}
    <h3
      class="font-mono-label mt-6 border-b pb-1 text-xs uppercase tracking-widest"
      style="border-color: var(--line); color: var(--primary)"
    >
      Ingredients
    </h3>
    <ul class="list-none p-0">
      {#each recipe.current_version.ingredients as ing, i (i)}
        {#if sectionChanged(recipe.current_version.ingredients, i)}
          <li
            class="font-mono-label pt-3 pb-1 text-[10.5px] uppercase tracking-widest"
            style="color: var(--accent)"
          >
            {ing.section}
          </li>
        {/if}
        <li
          class="flex items-baseline gap-3 border-b border-dashed py-2 text-[15px]"
          style="border-color: var(--line)"
        >
          <span class="qty min-w-[5.5ch] shrink-0 text-[14px]" class:flash={flashing}>
            {scaledDisplay(ing.amount, ing.unit, factor)}
          </span>
          <span>{ing.name}</span>
        </li>
      {/each}
    </ul>
  {/if}

  <h3
    class="font-mono-label mt-6 border-b pb-1 text-xs uppercase tracking-widest"
    style="border-color: var(--line); color: var(--primary)"
  >
    {recipe.current_version.ingredients.length ? 'Method' : 'The list'}
  </h3>
  <ol class="list-none p-0" style="counter-reset: st">
    {#each recipe.current_version.steps as step, i (i)}
      <li class="relative py-2 pl-10 text-[15px]">
        <span
          class="font-mono-label absolute top-2 left-0 flex h-[26px] w-[26px] items-center justify-center rounded-full border text-[12px]"
          style="border-color: var(--primary); color: var(--primary)"
        >
          {i + 1}
        </span>
        {#each boldParts(step.text) as part, j (j)}
          {#if part.bold}<strong>{part.t}</strong>{:else}{part.t}{/if}
        {/each}
      </li>
    {/each}
  </ol>

  {#if recipe.current_version.notes.length}
    <h3
      class="font-mono-label mt-6 border-b pb-1 text-xs uppercase tracking-widest"
      style="border-color: var(--line); color: var(--primary)"
    >
      Notes
    </h3>
    <ul class="mt-2 list-none rounded-xl border p-4" style="background: var(--card); border-color: var(--line)">
      {#each recipe.current_version.notes as note, i (i)}
        <li class="py-1 text-[13.5px]" style="color: var(--faint)">
          —
          {#each boldParts(note) as part, j (j)}
            {#if part.bold}<strong>{part.t}</strong>{:else}{part.t}{/if}
          {/each}
        </li>
      {/each}
    </ul>
  {/if}

  <div class="mt-6 flex flex-wrap gap-2">
    <a
      href="/ask?recipe={recipe.slug}"
      class="font-mono-label inline-block min-h-[44px] rounded-full px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline"
      style="background: var(--primary-deep); color: var(--off-white)"
    >
      Ask about this recipe
    </a>
    <a
      href="/r/{recipe.slug}/edit"
      class="font-mono-label inline-block min-h-[44px] rounded-full border px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline"
      style="border-color: var(--accent); color: var(--accent)"
    >
      Edit
    </a>
    <a
      href="/"
      class="font-mono-label inline-block min-h-[44px] rounded-full border px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline"
      style="border-color: var(--primary-deep); color: var(--primary-deep)"
    >
      ← all recipes
    </a>
  </div>
</article>
