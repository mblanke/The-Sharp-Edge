<script lang="ts">
  import { onMount } from 'svelte';
  import { replaceState } from '$app/navigation';
  import { categoryRank } from '$lib/types';
  import type { RecipeCard } from '$lib/types';
  import { readRecent, type RecentRecipe } from '$lib/prefs';

  let { data } = $props();

  let gfOnly = $state(false);
  let tagFilter = $state<string | null>(null);

  // "what can I make?" — server search across titles, ingredients, and tags.
  // The query lives in the URL (?q=) so back, refresh and a shared link keep it.
  let search = $state('');
  let searchHits = $state<string[] | null>(null); // matching slugs; null = no search
  let searching = $state(false);
  let searchError = $state(false);
  let searchTimer: ReturnType<typeof setTimeout> | undefined;
  let searchSeq = 0;
  let searchEl = $state<HTMLInputElement | null>(null);

  let recent = $state<RecentRecipe[]>([]);
  onMount(() => {
    const url = new URL(location.href);
    const q = url.searchParams.get('q') ?? '';
    if (q) {
      search = q;
      runSearch(q, 0);
    }
    if (url.searchParams.get('focus')) {
      searchEl?.focus();
      url.searchParams.delete('focus');
      replaceState(url, {});
    }
    // only recipes that still exist — a renamed or drafted one drops out quietly
    const live = new Set(data.recipes.map((r: RecipeCard) => r.slug));
    recent = readRecent().filter((r) => live.has(r.slug)).slice(0, 6);
  });

  function syncUrl(term: string) {
    try {
      const url = new URL(location.href);
      if (term) url.searchParams.set('q', term);
      else url.searchParams.delete('q');
      replaceState(url, {});
    } catch {
      // not navigable yet
    }
  }

  function runSearch(value: string, delayMs = 250) {
    clearTimeout(searchTimer);
    const term = value.trim();
    syncUrl(term);
    if (term.length < 2) {
      searchHits = null;
      searching = false;
      searchError = false;
      return;
    }
    searching = true;
    const seq = ++searchSeq;
    searchTimer = setTimeout(async () => {
      try {
        const res = await fetch(`/api/recipes?q=${encodeURIComponent(term)}`);
        if (seq !== searchSeq) return; // a newer keystroke owns the result
        if (!res.ok) throw new Error(String(res.status));
        searchHits = (await res.json()).map((r: RecipeCard) => r.slug);
        searchError = false;
      } catch {
        if (seq !== searchSeq) return;
        // offline or API down: fall back to a local title match rather than
        // showing the whole list as if everything matched
        const t = term.toLowerCase();
        searchHits = data.recipes.filter((r: RecipeCard) => r.title.toLowerCase().includes(t)).map((r) => r.slug);
        searchError = true;
      } finally {
        if (seq === searchSeq) searching = false;
      }
    }, delayMs);
  }

  function clearSearch() {
    search = '';
    runSearch('', 0);
    searchEl?.focus();
  }

  // ⌘K / Ctrl+K from anywhere on the page focuses the search box
  function onKey(e: KeyboardEvent) {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      searchEl?.focus();
      searchEl?.select();
    }
  }

  const visible = $derived(
    (gfOnly ? data.recipes.filter((r: RecipeCard) => r.gf) : data.recipes)
      .filter((r: RecipeCard) => !tagFilter || r.tags?.includes(tagFilter))
      .filter((r: RecipeCard) => searchHits === null || searchHits.includes(r.slug))
  );

  const categories = $derived(
    [...new Set(visible.map((r: RecipeCard) => r.category))].sort(
      (a, b) => categoryRank(a) - categoryRank(b)
    )
  );

  const byCategory = $derived(
    new Map(categories.map((c) => [c, visible.filter((r: RecipeCard) => r.category === c)]))
  );

  const filtered = $derived(searchHits !== null || gfOnly || tagFilter !== null);
</script>

<svelte:head>
  <title>The Sharp Edge — Recipe Master</title>
</svelte:head>

<svelte:window onkeydown={onKey} />

<search class="relative pt-5">
  <input
    type="search"
    bind:value={search}
    bind:this={searchEl}
    oninput={() => runSearch(search)}
    placeholder="what can I make? — search titles, ingredients, tags…"
    aria-label="Search recipes"
    aria-keyshortcuts="Meta+K Control+K"
    class="min-h-[48px] w-full rounded-full border pr-12 pl-5 text-[15px]"
    style="border-color: var(--line); background: var(--card); color: var(--ink)"
  />
  {#if search}
    <button
      class="absolute top-5 right-1 grid h-[48px] w-[44px] place-items-center rounded-full text-[15px]"
      style="color: var(--faint)"
      aria-label="Clear search"
      onclick={clearSearch}
    >
      ✕
    </button>
  {/if}
</search>

<p class="qty mt-1.5 min-h-[18px] text-[11.5px]" style="color: var(--faint)" aria-live="polite">
  {#if searching}
    searching…
  {:else if searchError}
    <span style="color: var(--copper)">server unreachable — matching titles only</span>
  {:else if searchHits !== null}
    {visible.length} {visible.length === 1 ? 'recipe' : 'recipes'} for “{search.trim()}”
  {/if}
</p>

<nav aria-label="Filters" class="flex items-center gap-3 pt-3">
  <span class="font-mono-label text-[11px] uppercase tracking-widest" style="color: var(--faint)">Show</span>
  <div class="flex overflow-hidden rounded-full border" style="border-color: var(--green-deep)">
    <button
      class="min-h-[44px] px-5 text-sm font-medium"
      style:background={gfOnly ? 'transparent' : 'var(--green-deep)'}
      style:color={gfOnly ? 'var(--green-deep)' : '#F4F3EC'}
      aria-pressed={!gfOnly}
      onclick={() => (gfOnly = false)}
    >
      All
    </button>
    <button
      class="min-h-[44px] px-5 text-sm font-medium"
      style:background={gfOnly ? 'var(--green-deep)' : 'transparent'}
      style:color={gfOnly ? '#F4F3EC' : 'var(--green-deep)'}
      aria-pressed={gfOnly}
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

{#if recent.length && !filtered}
  <nav aria-label="Recently viewed" class="pt-5" data-testid="recent">
    <span class="font-mono-label text-[11px] uppercase tracking-widest" style="color: var(--faint)">Recently viewed</span>
    <div class="mt-2 flex gap-2 overflow-x-auto pb-1" style="scrollbar-width: none">
      {#each recent as r (r.slug)}
        <a
          href="/r/{r.slug}"
          class="font-display shrink-0 rounded-2xl border px-4 py-2.5 text-[15px] no-underline"
          style="border-color: var(--line); background: var(--card); color: var(--ink); max-width: 16rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap"
        >
          {r.title}
        </a>
      {/each}
    </div>
  </nav>
{/if}

<main>
  {#if data.unavailable}
    <div class="mt-10 rounded-2xl border p-6 text-center" style="border-color: var(--copper); background: var(--card)" data-testid="api-down">
      <p class="font-display text-[22px]" style="color: var(--ink)">The server is not answering.</p>
      <p class="mt-2 text-[14px]" style="color: var(--faint)">
        Recipes you have opened before still cook offline — scan a card or use the address bar.
      </p>
      <button
        class="font-mono-label mt-4 min-h-[44px] rounded-full border px-5 text-[11px] uppercase tracking-widest"
        style="border-color: var(--line); color: var(--green-deep)"
        onclick={() => location.reload()}
      >
        try again
      </button>
    </div>
  {:else if data.recipes.length === 0}
    <div class="mt-10 text-center" data-testid="empty-notebook">
      <p class="font-display text-[22px]" style="color: var(--ink)">An empty notebook.</p>
      <p class="mt-2 text-[14px]" style="color: var(--faint)">Add the first recipe — typed, dictated, or photographed.</p>
      <a
        href="/new"
        class="font-mono-label mt-4 inline-block min-h-[44px] rounded-full px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline"
        style="background: var(--green-deep); color: #F4F3EC"
      >
        + add a recipe
      </a>
    </div>
  {:else if visible.length === 0 && filtered && !searching}
    <div class="mt-10 text-center" data-testid="no-results">
      <p class="font-display text-[22px]" style="color: var(--ink)">Nothing matches.</p>
      <p class="mt-2 text-[14px]" style="color: var(--faint)">
        {#if searchHits !== null}No recipe mentions “{search.trim()}”.{/if}
        {#if gfOnly} Try showing all, not just GF.{/if}
        {#if tagFilter} Or drop the tag.{/if}
      </p>
      <div class="mt-4 flex flex-wrap justify-center gap-2">
        {#if searchHits !== null}
          <button class="font-mono-label min-h-[44px] rounded-full border px-5 text-[11px] uppercase tracking-widest" style="border-color: var(--line); color: var(--green-deep)" onclick={clearSearch}>clear search</button>
        {/if}
        {#if gfOnly}
          <button class="font-mono-label min-h-[44px] rounded-full border px-5 text-[11px] uppercase tracking-widest" style="border-color: var(--line); color: var(--green-deep)" onclick={() => (gfOnly = false)}>show all</button>
        {/if}
        {#if tagFilter}
          <button class="font-mono-label min-h-[44px] rounded-full border px-5 text-[11px] uppercase tracking-widest" style="border-color: var(--line); color: var(--green-deep)" onclick={() => (tagFilter = null)}>drop tag</button>
        {/if}
      </div>
    </div>
  {/if}

  {#each categories as cat (cat)}
    <section
      id="cat-{cat}"
      class="mt-9 scroll-mt-4 border-l-2 pl-3"
      style="border-color: var(--green)"
    >
      <h2
        class="font-mono-label sticky top-0 z-10 border-b pb-1 pt-1 text-[11px] uppercase tracking-widest"
        style="border-color: var(--line); color: var(--green); background: var(--paper)"
      >
        {cat}
      </h2>
      <ul class="mt-2 list-none p-0">
        {#each byCategory.get(cat) ?? [] as r (r.slug)}
          <li
            class="lift flex min-h-[52px] flex-wrap items-center gap-x-3 border-b border-dashed"
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
                  class="font-mono-label hidden min-h-[32px] rounded-full border px-2.5 py-1 text-[10.5px] uppercase tracking-widest sm:inline-block"
                  style="border-color: {tagFilter === tag ? 'var(--copper)' : 'var(--line)'}; color: {tagFilter === tag ? 'var(--copper)' : 'var(--faint)'}"
                  aria-pressed={tagFilter === tag}
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
            {#if r.tags?.length}
              <!-- tags are reachable on a phone too: a row under the title, tap to filter -->
              <span class="flex basis-full flex-wrap gap-1.5 pb-2 sm:hidden">
                {#each r.tags.slice(0, 3) as tag (tag)}
                  <button
                    class="font-mono-label min-h-[32px] rounded-full border px-2.5 text-[10px] uppercase tracking-widest"
                    style="border-color: {tagFilter === tag ? 'var(--copper)' : 'var(--line)'}; color: {tagFilter === tag ? 'var(--copper)' : 'var(--faint)'}"
                    aria-pressed={tagFilter === tag}
                    onclick={() => (tagFilter = tagFilter === tag ? null : tag)}
                  >
                    {tag}
                  </button>
                {/each}
              </span>
            {/if}
          </li>
        {/each}
      </ul>
    </section>
  {/each}
</main>
