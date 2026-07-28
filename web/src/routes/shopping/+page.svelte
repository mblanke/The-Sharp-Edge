<script lang="ts">
  import { enhance } from '$app/forms';
  import type { PageData } from './$types';
  import type { ShoppingItem } from '$lib/types';

  let { data }: { data: PageData } = $props();

  // The API returns the list already in walking order (fresh edges first, frozen
  // last), so grouping is just "start a new heading when the aisle changes" — no
  // copy of the aisle table on this side.
  let groups = $derived(
    data.items.reduce<{ aisle: string; items: ShoppingItem[] }[]>((acc, item) => {
      const last = acc[acc.length - 1];
      if (last && last.aisle === item.aisle) last.items.push(item);
      else acc.push({ aisle: item.aisle, items: [item] });
      return acc;
    }, [])
  );

  let remaining = $derived(data.items.filter((i) => !i.checked).length);
  let copied = $state(false);

  async function copyList() {
    await navigator.clipboard.writeText(data.text);
    copied = true;
    setTimeout(() => (copied = false), 2000);
  }
</script>

<svelte:head><title>Shopping list — The Sharp Edge</title></svelte:head>

<section class="pt-6">
  <div class="flex items-baseline justify-between">
    <h2 class="font-display text-[26px]" style="color: var(--ink)">Shopping list</h2>
    <span class="font-mono-label text-[12px]" style="color: var(--faint)">
      {remaining} to buy
    </span>
  </div>

  {#if data.items.length === 0}
    <p class="mt-6 text-[15px]" style="color: var(--faint)">
      Nothing on the list yet. Open a recipe and add it — quantities are added to any
      line already there, not replaced.
    </p>
  {:else}
    <div class="mt-3 flex flex-wrap gap-2">
      <button
        onclick={copyList}
        class="font-mono-label rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest"
        style="border-color: var(--line); color: var(--ink-accent)"
      >
        {copied ? 'Copied' : 'Copy for Notes / AnyList'}
      </button>
      <form method="POST" action="?/clear" use:enhance>
        <input type="hidden" name="scope" value="checked" />
        <button
          class="font-mono-label rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest"
          style="border-color: var(--line); color: var(--ink-accent)"
        >Clear what's ticked</button>
      </form>
    </div>

    {#each groups as group (group.aisle)}
      <h3 class="font-mono-label mt-7 text-[11px] uppercase tracking-widest" style="color: var(--accent)">
        {group.aisle}
      </h3>
      <ul class="mt-2 divide-y" style="border-color: var(--line)">
        {#each group.items as item (item.id)}
          <li class="flex items-start gap-3 py-3">
            <form method="POST" action="?/toggle" use:enhance class="pt-[2px]">
              <input type="hidden" name="id" value={item.id} />
              <input type="hidden" name="checked" value={String(!item.checked)} />
              <button
                aria-label={item.checked ? 'Untick' : 'Tick'}
                class="grid h-6 w-6 place-items-center rounded-md border"
                style="border-color: var(--line); background: {item.checked ? 'var(--primary)' : 'transparent'}"
              >
                {#if item.checked}<span style="color: var(--off-white)">✓</span>{/if}
              </button>
            </form>
            <div class="min-w-0 flex-1" style="opacity: {item.checked ? 0.45 : 1}">
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
