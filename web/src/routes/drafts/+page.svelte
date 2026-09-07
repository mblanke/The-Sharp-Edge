<script lang="ts">
  import { enhance } from '$app/forms';
  import { notify } from '$lib/toast';

  let { data, form } = $props();
  let importing = $state(false);
  let urls = $state('');
  const result = $derived(form && 'result' in form ? form.result : null);
</script>

<svelte:head><title>Drafts — The Sharp Edge</title></svelte:head>

<section class="pt-7 pb-10">
  <div class="font-mono-label text-[11px] uppercase tracking-widest" style="color: var(--copper)">Review queue</div>
  <h2 class="font-display mt-1 text-[clamp(24px,5.6vw,32px)] leading-tight">Drafts</h2>
  <p class="mt-1 text-[13.5px]" style="color: var(--faint)">
    Imported and half-finished recipes wait here, out of the index and the exports, until you open one and save it without the draft flag.
  </p>

  <form
    method="POST"
    action="?/import"
    class="mt-6 grid gap-2"
    use:enhance={() => {
      importing = true;
      return async ({ result, update }) => {
        await update({ reset: false });
        importing = false;
        if (result.type === 'success') {
          urls = '';
          const r = (result.data as { result: { created: unknown[]; failed: unknown[] } }).result;
          notify.ok(`${r.created.length} imported as drafts${r.failed.length ? `, ${r.failed.length} failed` : ''}`);
        } else if (result.type === 'failure') {
          notify.error(String((result.data as { message?: string })?.message ?? 'Import failed'));
        } else if (result.type === 'error') {
          notify.error('Could not reach the server');
        }
      };
    }}
  >
    <label class="font-mono-label text-[10.5px] uppercase tracking-widest" style="color: var(--green)" for="urls">
      Import a list of links
    </label>
    <textarea
      id="urls"
      name="urls"
      bind:value={urls}
      rows="4"
      placeholder="https://… one recipe page per line (up to 50)"
      class="w-full rounded-xl border px-4 py-3 text-[14px]"
      style="border-color: var(--line); background: var(--card); color: var(--ink)"
      disabled={importing}
    ></textarea>
    <button
      class="font-mono-label min-h-[48px] justify-self-start rounded-full px-6 text-[12px] uppercase tracking-widest disabled:opacity-60"
      style="background: var(--green-deep); color: #F4F3EC"
      disabled={importing || !urls.trim()}
      data-testid="batch-import"
    >
      {importing ? 'importing… (a few seconds per link)' : 'import as drafts'}
    </button>
  </form>

  {#if result?.failed.length}
    <ul class="mt-3 list-none rounded-xl border p-3 text-[13px]" style="border-color: var(--copper); background: var(--warn-bg); color: var(--copper)" data-testid="import-failed">
      {#each result.failed as f (f.item)}
        <li class="py-0.5"><span class="qty">{f.item}</span> — {f.error}</li>
      {/each}
    </ul>
  {/if}

  <h3 class="font-mono-label mt-8 border-b pb-1 text-xs uppercase tracking-widest" style="border-color: var(--line); color: var(--green)">
    Waiting for review · {data.drafts.length}
  </h3>
  {#if data.drafts.length === 0}
    <p class="mt-4 text-[14.5px]" style="color: var(--faint)" data-testid="drafts-empty">Nothing to review.</p>
  {:else}
    <ul class="list-none p-0" data-testid="drafts-list">
      {#each data.drafts as d (d.slug)}
        <li class="flex min-h-[52px] items-center gap-3 border-b border-dashed" style="border-color: var(--line)">
          <a href="/r/{d.slug}/edit" class="min-w-0 flex-1 py-3 no-underline">
            <span class="font-display text-lg leading-tight" style="color: var(--ink)">{d.title}</span>
            <span class="block text-[13px]" style="color: var(--faint)">{d.category}{d.meta ? ` · ${d.meta}` : ''}</span>
          </a>
          <a href="/r/{d.slug}/edit" class="font-mono-label min-h-[44px] rounded-full border px-4 py-2.5 text-[11px] uppercase tracking-widest no-underline" style="border-color: var(--copper); color: var(--copper)">review</a>
        </li>
      {/each}
    </ul>
  {/if}
</section>
