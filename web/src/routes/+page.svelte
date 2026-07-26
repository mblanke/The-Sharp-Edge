<script lang="ts">
  import { categoryRank } from '$lib/types';
  import type { RecipeCard } from '$lib/types';

  let { data } = $props();

  let gfOnly = $state(false);

  const visible = $derived(gfOnly ? data.recipes.filter((r: RecipeCard) => r.gf) : data.recipes);

  const categories = $derived(
    [...new Set(visible.map((r: RecipeCard) => r.category))].sort(
      (a, b) => categoryRank(a) - categoryRank(b)
    )
  );

  const byCategory = $derived(
    new Map(categories.map((c) => [c, visible.filter((r: RecipeCard) => r.category === c)]))
  );
</script>

<svelte:head>
  <title>The Sharp Edge — Recipe Master</title>
</svelte:head>

<nav aria-label="Filters" class="flex items-center gap-3 pt-5">
  <span class="font-mono-label text-[11px] uppercase tracking-widest" style="color: var(--faint)">Show</span>
  <div class="flex overflow-hidden rounded-full border" style="border-color: var(--primary-deep)">
    <button
      class="min-h-[44px] px-5 text-sm font-medium"
      style:background={gfOnly ? 'transparent' : 'var(--primary-deep)'}
      style:color={gfOnly ? 'var(--primary-deep)' : 'var(--off-white)'}
      onclick={() => (gfOnly = false)}
    >
      All
    </button>
    <button
      class="min-h-[44px] px-5 text-sm font-medium"
      style:background={gfOnly ? 'var(--primary-deep)' : 'transparent'}
      style:color={gfOnly ? 'var(--off-white)' : 'var(--primary-deep)'}
      onclick={() => (gfOnly = true)}
    >
      GF only
    </button>
  </div>
</nav>

<nav aria-label="Categories" class="flex flex-wrap gap-2 pt-5">
  {#each categories as cat (cat)}
    <a
      href="#cat-{cat}"
      class="font-mono-label rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest no-underline"
      style="border-color: var(--line); color: var(--primary-deep); background: var(--card)"
    >
      {cat}
    </a>
  {/each}
</nav>

<main>
  {#each categories as cat (cat)}
    <section id="cat-{cat}" class="mt-9 scroll-mt-4">
      <h2
        class="font-mono-label border-b pb-1 text-[11px] uppercase tracking-widest"
        style="border-color: var(--line); color: var(--primary)"
      >
        {cat}
      </h2>
      <ul class="mt-2 list-none p-0">
        {#each byCategory.get(cat) ?? [] as r (r.slug)}
          <li class="border-b border-dashed" style="border-color: var(--line)">
            <a href="/r/{r.slug}" class="flex min-h-[52px] items-center justify-between gap-3 py-3 no-underline">
              <span>
                <span class="font-display text-lg leading-tight" style="color: var(--ink)">{r.title}</span>
                {#if r.meta}
                  <span class="block text-[13px]" style="color: var(--faint)">{r.meta}</span>
                {/if}
              </span>
              <span class="flex shrink-0 items-center gap-2">
                {#if r.gf}
                  <span
                    class="font-mono-label rounded-full px-2.5 py-1 text-[10.5px] uppercase tracking-widest"
                    style="background: var(--primary); color: var(--off-white)"
                  >
                    GF
                  </span>
                {/if}
              </span>
            </a>
          </li>
        {/each}
      </ul>
    </section>
  {/each}
</main>
