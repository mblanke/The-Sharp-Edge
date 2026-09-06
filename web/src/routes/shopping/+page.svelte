<script lang="ts">
  import { onMount } from 'svelte';
  import { enhance } from '$app/forms';
  import { replaceState } from '$app/navigation';
  import type { PageData } from './$types';
  import type { ShoppingItem } from '$lib/types';
  import { notify } from '$lib/toast';

  let { data }: { data: PageData } = $props();

  // Ticks are optimistic: the box flips on tap and rolls back if the server says no.
  // Waiting a round-trip per item made a 30-line list feel broken in a shop.
  let overrides = $state<Record<string, boolean>>({});
  $effect(() => {
    data.items; // a fresh load is the truth again
    overrides = {};
  });
  const items = $derived(
    data.items.map((i) => (i.id in overrides ? { ...i, checked: overrides[i.id] } : i))
  );

  // The API returns the list already in walking order (fresh edges first, frozen
  // last), so grouping is just "start a new heading when the aisle changes" — no
  // copy of the aisle table on this side.
  let groups = $derived(
    items.reduce<{ aisle: string; items: ShoppingItem[] }[]>((acc, item) => {
      const last = acc[acc.length - 1];
      if (last && last.aisle === item.aisle) last.items.push(item);
      else acc.push({ aisle: item.aisle, items: [item] });
      return acc;
    }, [])
  );

  let remaining = $derived(items.filter((i) => !i.checked).length);
  let ticked = $derived(items.length - remaining);
  let copied = $state(false);
  let showText = $state(false);
  let confirmClear = $state(false);
  let clearing = $state(false);

  onMount(() => {
    // arriving from "add week to list" on the plan page
    const url = new URL(location.href);
    if (url.searchParams.get('from') === 'plan') {
      notify.ok('The week is on the list');
      url.searchParams.delete('from');
      replaceState(url, {});
    }
  });

  async function copyList() {
    try {
      if (!navigator.clipboard) throw new Error('no clipboard');
      await navigator.clipboard.writeText(data.text);
      copied = true;
      setTimeout(() => (copied = false), 2000);
    } catch {
      // http over the tailnet has no clipboard API: show the text to select by hand
      showText = true;
    }
  }

  async function shareList() {
    try {
      await navigator.share({ title: 'Shopping list', text: data.text });
    } catch {
      // cancelled or unsupported — nothing to report
    }
  }
  const canShare = typeof navigator !== 'undefined' && typeof navigator.share === 'function';
</script>

<svelte:head><title>Shopping list — The Sharp Edge</title></svelte:head>

<section class="pt-6">
  <div class="flex items-baseline justify-between">
    <h2 class="font-display text-[26px]" style="color: var(--ink)">Shopping list</h2>
    <span class="font-mono-label text-[12px]" style="color: var(--faint)" aria-live="polite">
      {remaining} to buy
    </span>
  </div>

  {#if items.length === 0}
    <div class="mt-8 text-center" data-testid="empty-list">
      <p class="font-display text-[22px]" style="color: var(--ink)">Nothing to buy.</p>
      <p class="mx-auto mt-2 max-w-[40ch] text-[14.5px]" style="color: var(--faint)">
        Open a recipe and add it, or plan a week — quantities merge into any line already here.
      </p>
      <div class="mt-4 flex flex-wrap justify-center gap-2">
        <a href="/" class="font-mono-label inline-block min-h-[44px] rounded-full px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline" style="background: var(--green-deep); color: #F4F3EC">recipes</a>
        <a href="/plan" class="font-mono-label inline-block min-h-[44px] rounded-full border px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline" style="border-color: var(--line); color: var(--green-deep)">plan a week</a>
      </div>
    </div>
  {:else}
    <div class="mt-3 flex flex-wrap gap-2">
      <button
        onclick={copyList}
        class="font-mono-label min-h-[44px] rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest"
        style="border-color: var(--line); color: var(--ink-accent)"
      >
        {copied ? 'Copied' : 'Copy for Notes / AnyList'}
      </button>
      {#if canShare}
        <button
          onclick={shareList}
          class="font-mono-label min-h-[44px] rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest"
          style="border-color: var(--line); color: var(--ink-accent)"
        >
          Share
        </button>
      {/if}
      {#if ticked > 0}
        {#if confirmClear}
          <form
            method="POST"
            action="?/clear"
            use:enhance={() => {
              clearing = true;
              return async ({ result, update }) => {
                await update();
                clearing = false;
                confirmClear = false;
                if (result.type === 'success') notify.ok(`Cleared ${ticked} ticked ${ticked === 1 ? 'item' : 'items'}`);
                else notify.error('Could not clear the list — is the server reachable?');
              };
            }}
          >
            <input type="hidden" name="scope" value="checked" />
            <button
              class="font-mono-label min-h-[44px] rounded-full px-4 py-2 text-[11px] uppercase tracking-widest disabled:opacity-60"
              style="background: var(--copper); color: #FFF"
              disabled={clearing}
              data-testid="clear-confirm"
            >
              {clearing ? 'clearing…' : `remove ${ticked} ticked`}
            </button>
          </form>
          <button
            class="font-mono-label min-h-[44px] rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest"
            style="border-color: var(--line); color: var(--faint)"
            onclick={() => (confirmClear = false)}
          >
            keep
          </button>
        {:else}
          <button
            class="font-mono-label min-h-[44px] rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest"
            style="border-color: var(--line); color: var(--ink-accent)"
            onclick={() => (confirmClear = true)}
          >
            Clear what's ticked
          </button>
        {/if}
      {/if}
    </div>

    {#if showText}
      <div class="mt-3 rounded-xl border p-3" style="border-color: var(--line); background: var(--card)">
        <p class="font-mono-label mb-1 text-[10.5px] uppercase tracking-widest" style="color: var(--faint)">
          copy needs https — select the text instead
        </p>
        <textarea readonly rows="8" class="qty w-full text-[13px]" style="background: transparent; color: var(--ink)" onfocus={(e) => e.currentTarget.select()}>{data.text}</textarea>
      </div>
    {/if}

    {#each groups as group (group.aisle)}
      <h3 class="font-mono-label mt-7 text-[11px] uppercase tracking-widest" style="color: var(--accent)">
        {group.aisle}
      </h3>
      <ul class="mt-2 divide-y" style="border-color: var(--line)">
        {#each group.items as item (item.id)}
          <li class="flex items-start gap-3 py-2">
            <form
              method="POST"
              action="?/toggle"
              use:enhance={() => {
                const next = !item.checked;
                overrides = { ...overrides, [item.id]: next };
                return async ({ result }) => {
                  // no update(): the optimistic tick already shows the state; a reload
                  // from the server here would flicker every other row
                  if (result.type !== 'success') {
                    overrides = { ...overrides, [item.id]: !next };
                    notify.error('Could not save the tick — is the server reachable?');
                  }
                };
              }}
            >
              <input type="hidden" name="id" value={item.id} />
              <input type="hidden" name="checked" value={String(!item.checked)} />
              <button
                aria-label={item.checked ? `Untick ${item.name}` : `Tick ${item.name}`}
                aria-pressed={item.checked}
                class="grid h-11 w-11 place-items-center rounded-xl"
              >
                <span
                  class="grid h-6 w-6 place-items-center rounded-md border"
                  style="border-color: var(--line); background: {item.checked ? 'var(--primary)' : 'transparent'}"
                >
                  {#if item.checked}<span style="color: var(--off-white)">✓</span>{/if}
                </span>
              </button>
            </form>
            <div class="min-w-0 flex-1 pt-2" style="opacity: {item.checked ? 0.45 : 1}">
              <div class="flex flex-wrap items-baseline gap-2">
                <span class="font-mono-label text-[14px]" style="color: var(--ink)">{item.display}</span>
                <span class="text-[15px]" style="color: var(--ink); text-decoration: {item.checked ? 'line-through' : 'none'}">
                  {item.name}
                </span>
              </div>
              {#if item.check_gluten}
                <p class="font-mono-label mt-1 text-[11px]" style="color: var(--accent)">
                  check the label for gluten
                </p>
              {/if}
              {#if item.recipes.length}
                <p class="mt-1 text-[12px]" style="color: var(--faint)">
                  for {item.recipes.join(', ')}
                </p>
              {/if}
            </div>
          </li>
        {/each}
      </ul>
    {/each}
  {/if}
</section>
