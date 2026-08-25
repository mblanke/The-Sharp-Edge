<script lang="ts">
  let { data } = $props();

  const labelCls = 'font-mono-label text-[10.5px] uppercase tracking-widest';
  const cardCls = 'mt-4 rounded-2xl border p-4';
</script>

<svelte:head>
  <title>Admin — The Sharp Edge</title>
</svelte:head>

<section class="pt-7 pb-16">
  <div class={labelCls} style="color: var(--copper)">Housekeeping</div>
  <h2 class="font-display mt-1 text-[clamp(24px,5.6vw,32px)] leading-tight">Admin</h2>

  <!-- GF audit -->
  <div class={cardCls} style="border-color: var(--line); background: var(--card)">
    <h3 class={labelCls} style="color: var(--green)">Hidden-gluten audit</h3>
    {#if !data.audit}
      <p class="mt-2 text-[13.5px]" style="color: var(--faint)">Audit unavailable (API or token).</p>
    {:else}
      {#if data.audit.warnings.length === 0}
        <p class="mt-2 text-[14px]" style="color: var(--green-deep)" data-testid="gf-clean">
          ✓ No GF-flagged recipe contains a hidden-gluten risk.
        </p>
      {:else}
        {#each data.audit.warnings as w (w.slug)}
          <div class="mt-2 rounded-lg border px-3 py-2" style="border-color: var(--copper); background: var(--warn-bg)">
            <a href="/r/{w.slug}" class="text-[14.5px] font-medium no-underline" style="color: var(--copper)">
              {w.title}
            </a>
            <ul class="mt-1 list-none p-0 text-[13px]" style="color: var(--ink)">
              {#each w.risks as risk (risk.ingredient)}
                <li>· {risk.ingredient} — {risk.why}</li>
              {/each}
            </ul>
          </div>
        {/each}
      {/if}
      {#if data.audit.candidates.length}
        <p class="mt-3 text-[13px]" style="color: var(--faint)">
          Possibly GF but unflagged:
          {#each data.audit.candidates as c, i (c.slug)}
            {i > 0 ? ' · ' : ''}<a href="/r/{c.slug}" style="color: var(--green-deep)">{c.title}</a>
          {/each}
        </p>
      {/if}
      <p class="mt-2 text-[12px]" style="color: var(--faint)">{data.audit.ok} recipes look consistent.</p>
    {/if}
  </div>

  <!-- library / rag status -->
  <div class={cardCls} style="border-color: var(--line); background: var(--card)">
    <h3 class={labelCls} style="color: var(--green)">Library</h3>
    <p class="mt-2 text-[13.5px]" style="color: var(--faint)">
      shelf {data.library?.mounted ? `mounted · ${data.library.books.length} items` : 'not mounted'} ·
      rag-api {data.library?.rag_health?.ok ? 'healthy' : 'unreachable'} ·
      photo import {data.health?.photo_import ? 'enabled' : 'off (no Anthropic key)'}
    </p>
    <p class="mt-1 text-[12px]" style="color: var(--faint)">
      Books are ingested by Atlas from the NAS Cooking folder every 6 h.
    </p>
  </div>

  <!-- exports -->
  <div class={cardCls} style="border-color: var(--line); background: var(--card)">
    <h3 class={labelCls} style="color: var(--green)">Exports</h3>
    <div class="mt-2 flex flex-wrap gap-2">
      <a
        href="/admin/export/master.md"
        class="font-mono-label min-h-[44px] rounded-full border px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline"
        style="border-color: var(--green-deep); color: var(--green-deep)"
        download
      >
        master.md
      </a>
      <a
        href="/admin/export/cards.pdf"
        class="font-mono-label min-h-[44px] rounded-full border px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline"
        style="border-color: var(--green-deep); color: var(--green-deep)"
        download
      >
        cards.pdf
      </a>
    </div>
  </div>
</section>
