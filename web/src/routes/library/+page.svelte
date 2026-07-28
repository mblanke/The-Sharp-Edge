<script lang="ts">
  let { data } = $props();

  interface Chunk {
    text: string;
    source_path: string | null;
    title: string | null;
    heading: string | null;
    page: number | null;
    score?: number | null;
    rerank_score: number | null;
  }

  interface BookGroup {
    book: string;
    best: number;
    hits: Chunk[];
  }

  let query = $state('');
  let results = $state<Chunk[]>([]);
  let searching = $state(false);
  let searched = $state(false);
  let errorMsg = $state('');

  async function search() {
    const q = query.trim();
    if (q.length < 2 || searching) return;
    searching = true;
    errorMsg = '';
    try {
      // over-fetch so more references make the cut, then group client-side
      const res = await fetch(`/api/search?q=${encodeURIComponent(q)}&top_k=20`);
      if (!res.ok) throw new Error(`search failed (${res.status})`);
      results = await res.json();
      searched = true;
    } catch (e) {
      errorMsg = e instanceof Error ? e.message : String(e);
    } finally {
      searching = false;
    }
  }

  function bookName(c: Chunk): string {
    if (c.title) return c.title;
    if (c.source_path) return c.source_path.split('/').pop() || c.source_path;
    return 'Unknown source';
  }

  const scoreOf = (c: Chunk): number => c.rerank_score ?? c.score ?? 0;

  /** Group flat hits by reference: collapse repeated pages, sort books by best
   *  relevance, and order each book's hits by page. */
  const grouped = $derived.by<BookGroup[]>(() => {
    // one hit per (book, page) — keeps the strongest, kills index/TOC duplicates
    const byKey = new Map<string, Chunk>();
    for (const c of results) {
      const key = `${bookName(c)}|${c.page ?? 'x' + c.text.slice(0, 40)}`;
      const prev = byKey.get(key);
      if (!prev || scoreOf(c) > scoreOf(prev)) byKey.set(key, c);
    }
    const books = new Map<string, Chunk[]>();
    for (const c of byKey.values()) {
      const b = bookName(c);
      if (!books.has(b)) books.set(b, []);
      books.get(b)!.push(c);
    }
    const out: BookGroup[] = [];
    for (const [book, hits] of books) {
      hits.sort((a, b) => {
        const pa = a.page ?? Infinity;
        const pb = b.page ?? Infinity;
        return pa !== pb ? pa - pb : scoreOf(b) - scoreOf(a);
      });
      out.push({ book, hits, best: Math.max(...hits.map(scoreOf)) });
    }
    return out.sort((a, b) => b.best - a.best);
  });

  function fmtSize(bytes: number | null): string {
    if (bytes == null) return '';
    if (bytes > 1e9) return `${(bytes / 1e9).toFixed(1)} GB`;
    if (bytes > 1e6) return `${(bytes / 1e6).toFixed(0)} MB`;
    return `${Math.max(1, Math.round(bytes / 1e3))} KB`;
  }
</script>

<svelte:head>
  <title>Library — The Sharp Edge</title>
</svelte:head>

<section class="pt-7">
  <div class="font-mono-label text-[11px] uppercase tracking-widest" style="color: var(--accent)">
    Culinary library
  </div>
  <h2 class="font-display mt-1 text-[clamp(24px,5.6vw,32px)] leading-tight">The shelf</h2>
  <p class="mt-1 text-[13.5px]" style="color: var(--faint)">
    Books dropped in the Cooking folder are indexed automatically. Search the shelf, or
    <a href="/ask" style="color: var(--ink-accent)">ask the library</a> a question.
  </p>

  <div
    class="font-mono-label mt-3 inline-block rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest"
    style="border-color: var(--line); color: {data.library.rag_health.ok ? 'var(--ink-accent)' : 'var(--accent)'}; background: var(--card)"
  >
    index: {data.library.rag_health.ok ? 'online' : 'unreachable'}
    {#if data.library.rag_health.qdrant_points}
      · {(data.library.rag_health.qdrant_points / 1e6).toFixed(1)}M chunks total
    {/if}
  </div>

  <form
    class="mt-5 flex gap-2"
    onsubmit={(e) => {
      e.preventDefault();
      search();
    }}
  >
    <input
      bind:value={query}
      placeholder="search the cookbooks… (e.g. beurre blanc)"
      class="min-h-[48px] flex-1 rounded-full border px-5 text-[15px]"
      style="border-color: var(--line); background: var(--card); color: var(--ink)"
    />
    <button
      type="submit"
      class="font-mono-label min-h-[48px] rounded-full px-6 text-[12px] uppercase tracking-widest"
      style="background: var(--primary-deep); color: var(--off-white)"
      disabled={searching || query.trim().length < 2}
    >
      {searching ? '…' : 'Search'}
    </button>
  </form>

  {#if errorMsg}
    <p class="mt-3 text-[13.5px]" style="color: var(--accent)">{errorMsg}</p>
  {/if}

  {#if searched}
    <h3
      class="font-mono-label mt-6 border-b pb-1 text-xs uppercase tracking-widest"
      style="border-color: var(--line); color: var(--primary)"
    >
      Results
    </h3>
    {#if !results.length}
      <p class="mt-2 text-[14px]" style="color: var(--faint)">
        Nothing from the Cooking shelf matched — the books may still be waiting for the next index sweep.
      </p>
    {/if}
    {#each grouped as g (g.book)}
      <section class="mt-5">
        <div class="flex items-baseline justify-between border-b pb-1" style="border-color: var(--line)">
          <h4 class="font-display text-[17px] leading-tight" style="color: var(--ink)">{g.book}</h4>
          <span class="font-mono-label shrink-0 text-[10.5px] uppercase tracking-widest" style="color: var(--faint)">
            {g.hits.length}
            {g.hits.length === 1 ? 'passage' : 'passages'}
          </span>
        </div>
        {#each g.hits as r, i (i)}
          <article class="mt-2 rounded-xl border p-3.5" style="background: var(--card); border-color: var(--line)">
            <div class="font-mono-label flex items-baseline gap-2 text-[10.5px] uppercase tracking-widest">
              {#if r.page != null}
                <span class="qty shrink-0 text-[12px]">p.{r.page}</span>
                {#if r.source_path}
                  <!-- Extracted text is a good index and a poor recipe: a line lost by
                       the text layer is a step never cooked. Read it in the book. -->
                  <a
                    href="/book?path={encodeURIComponent(r.source_path)}&page={r.page}"
                    target="_blank"
                    rel="noopener"
                    class="qty shrink-0 text-[12px] no-underline"
                    style="color: var(--ink-accent)"
                  >open page ↗</a>
                {/if}
              {/if}
              {#if r.heading}
                <span style="color: var(--accent)">{r.heading}</span>
              {/if}
            </div>
            <p class="mt-1.5 text-[14px]" style="color: var(--ink)">
              {r.text.slice(0, 500)}{r.text.length > 500 ? '…' : ''}
            </p>
          </article>
        {/each}
      </section>
    {/each}
  {/if}

  <h3
    class="font-mono-label mt-8 border-b pb-1 text-xs uppercase tracking-widest"
    style="border-color: var(--line); color: var(--primary)"
  >
    On the shelf
  </h3>
  {#if data.library.mounted}
    <ul class="list-none p-0">
      {#each data.library.books as book (book.name)}
        <li
          class="flex min-h-[44px] items-center justify-between gap-3 border-b border-dashed py-2 text-[14px]"
          style="border-color: var(--line)"
        >
          <span>{book.kind === 'folder' ? '▸ ' : ''}{book.name}</span>
          <span class="qty shrink-0 text-[12px]">{fmtSize(book.size_bytes)}</span>
        </li>
      {/each}
    </ul>
  {:else}
    <p class="mt-2 text-[14px]" style="color: var(--faint)">
      Book listing appears when the app runs with the Cooking folder mounted (Atlas deployment).
      The search above works regardless — it queries the index directly.
    </p>
  {/if}
</section>
