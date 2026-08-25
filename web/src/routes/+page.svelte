<script lang="ts">
  import { categoryRank } from '$lib/types';
  import type { RecipeCard } from '$lib/types';

  let { data } = $props();

  let gfOnly = $state(false);
  let tagFilter = $state<string | null>(null);

  const visible = $derived(
    (gfOnly ? data.recipes.filter((r: RecipeCard) => r.gf) : data.recipes).filter(
      (r: RecipeCard) => !tagFilter || r.tags?.includes(tagFilter)
    )
  );

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
  <div class="flex overflow-hidden rounded-full border" style="border-color: var(--green-deep)">
    <button
      class="min-h-[44px] px-5 text-sm font-medium"
      style:background={gfOnly ? 'transparent' : 'var(--green-deep)'}
      style:color={gfOnly ? 'var(--green-deep)' : '#F4F3EC'}
      onclick={() => (gfOnly = false)}
    >
      All
    </button>
    <button
      class="min-h-[44px] px-5 text-sm font-medium"
      style:background={gfOnly ? 'var(--green-deep)' : 'transparent'}
      style:color={gfOnly ? '#F4F3EC' : 'var(--green-deep)'}
      onclick={() => (gfOnly = true)}
    >
      GF only
    </button>
  </div>
  {#if tagFilter}
    <button
      class="font-mono-label min-h-[44px] rounded-full border px-4 text-[11px] uppercase tracking-widest"
      style="border-color: var(--copper); color: var(--copper)"
      onclick={() => (tagFilter = null)}
    >
      tag: {tagFilter} ✕
    </button>
  {/if}
</nav>

<nav aria-label="Categories" class="flex flex-wrap gap-2 pt-5">
  {#each categories as cat (cat)}
    <a
      href="#cat-{cat}"
      class="font-mono-label rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest no-underline"
      style="border-color: var(--line); color: var(--green-deep); background: var(--card)"
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
        style="border-color: var(--line); color: var(--green)"
      >
        {cat}
      </h2>
      <ul class="mt-2 list-none p-0">
        {#each byCategory.get(cat) ?? [] as r (r.slug)}
          <li
            class="flex min-h-[52px] items-center gap-3 border-b border-dashed"
            style="border-color: var(--line)"
          >
            <a href="/r/{r.slug}" class="min-w-0 flex-1 py-3 no-underline">
              <span class="font-display text-lg leading-tight" style="color: var(--ink)">{r.title}</span>
              {#if r.meta}
                <span class="block text-[13px]" style="color: var(--faint)">{r.meta}</span>
              {/if}
            </a>
            <span class="flex shrink-0 items-center gap-2">
              {#each r.tags ?? [] as tag (tag)}
                <button
                  class="font-mono-label hidden rounded-full border px-2.5 py-1 text-[10.5px] uppercase tracking-widest sm:inline-block"
                  style="border-color: var(--line); color: var(--faint)"
                  onclick={() => (tagFilter = tagFilter === tag ? null : tag)}
                >
                  {tag}
                </button>
              {/each}
              {#if r.gf}
                <span
                  class="font-mono-label rounded-full px-2.5 py-1 text-[10.5px] uppercase tracking-widest"
                  style="background: var(--green); color: #F4F3EC"
                >
                  GF
                </span>
              {/if}
            </span>
          </li>
        {/each}
      </ul>
    </section>
  {/each}
</main>
