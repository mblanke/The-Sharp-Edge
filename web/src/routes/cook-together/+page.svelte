<script lang="ts">
  import { goto } from '$app/navigation';
  import { onDestroy, onMount } from 'svelte';
  import { clockLabel, currentEntry, orchestrate } from '$lib/orchestrate';
  import { keepAwake, type WakeLockHandle } from '$lib/wakelock';

  let { data } = $props();

  const timeline = $derived(
    orchestrate(
      data.selected.map((r) => ({
        slug: r.slug,
        title: r.title,
        steps: r.current_version.steps
      }))
    )
  );

  // target time: default = now + total cook + 5 min of headroom
  let targetInput = $state('');
  let now = $state(Date.now());
  let ticker: ReturnType<typeof setInterval> | undefined;
  let wake: WakeLockHandle | null = null;
  let checked = $state<Set<number>>(new Set());

  onMount(() => {
    const def = new Date(Date.now() + (timeline.totalSeconds + 300) * 1000);
    targetInput = `${String(def.getHours()).padStart(2, '0')}:${String(def.getMinutes()).padStart(2, '0')}`;
    ticker = setInterval(() => (now = Date.now()), 15_000);
    wake = keepAwake();
  });
  onDestroy(() => {
    clearInterval(ticker);
    wake?.release();
  });

  const targetMs = $derived.by(() => {
    if (!targetInput) return Date.now();
    const [h, m] = targetInput.split(':').map(Number);
    const d = new Date();
    d.setHours(h, m, 0, 0);
    if (d.getTime() < Date.now() - 60_000) d.setDate(d.getDate() + 1); // tomorrow
    return d.getTime();
  });

  const nowIndex = $derived(currentEntry(timeline, targetMs, now));

  function toggleSlug(slug: string) {
    const current = data.selected.map((r) => r.slug);
    const next = current.includes(slug)
      ? current.filter((s) => s !== slug)
      : [...current, slug].slice(0, 3);
    goto(`/cook-together?slugs=${next.join(',')}`, { invalidateAll: true, noScroll: true });
  }

  const recipeHue: Record<string, string> = {};
  const HUES = ['var(--green-deep)', 'var(--copper)', 'var(--green)'];
  $effect(() => {
    data.selected.forEach((r, i) => (recipeHue[r.slug] = HUES[i % HUES.length]));
  });

  const labelCls = 'font-mono-label text-[10.5px] uppercase tracking-widest';
</script>

<svelte:head>
  <title>Cook together — The Sharp Edge</title>
</svelte:head>

<section class="pt-7 pb-16">
  <div class={labelCls} style="color: var(--copper)">Orchestrated cook</div>
  <h2 class="font-display mt-1 text-[clamp(24px,5.6vw,32px)] leading-tight">Cook together</h2>
  <p class="mt-1 text-[13.5px]" style="color: var(--faint)">
    Pick up to three dishes and a plating time — one interleaved timeline walks everything
    backward so it all lands together.
  </p>

  <!-- recipe picker -->
  <div class="mt-4 flex flex-wrap gap-2">
    {#each data.recipes as r (r.slug)}
      {@const on = data.selected.some((s) => s.slug === r.slug)}
      <button
        class="font-mono-label min-h-[44px] rounded-full border px-4 text-[11px] uppercase tracking-widest"
        style={on
          ? 'background: var(--green-deep); border-color: var(--green-deep); color: #F4F3EC'
          : 'border-color: var(--line); color: var(--faint)'}
        onclick={() => toggleSlug(r.slug)}
      >
        {r.title}
      </button>
    {/each}
  </div>

  {#if data.selected.length >= 2}
    <label class="mt-5 flex items-center gap-3">
      <span class={labelCls} style="color: var(--green)">Plates hit the table at</span>
      <input
        type="time"
        bind:value={targetInput}
        class="qty min-h-[44px] rounded-xl border px-3 text-[16px]"
        style="border-color: var(--line); background: var(--card); color: var(--ink)"
      />
    </label>

    <ol class="mt-5 list-none border-l-2 p-0 pl-0" style="border-color: var(--line)" data-testid="timeline">
      {#each timeline.entries as entry, i (i)}
        {@const done = checked.has(i)}
        {@const live = i === nowIndex}
        <li
          class="relative mb-1 ml-[-2px] border-l-2 py-2 pl-4"
          style="border-color: {live ? 'var(--copper)' : 'transparent'}; opacity: {done ? 0.45 : 1}"
        >
          <button
            class="flex w-full items-baseline gap-3 text-left"
            onclick={() => {
              const next = new Set(checked);
              if (done) next.delete(i);
              else next.add(i);
              checked = next;
            }}
          >
            <span class="qty min-w-[7ch] shrink-0 text-[13px]" style="color: {live ? 'var(--copper)' : 'var(--faint)'}">
              {clockLabel(targetMs, entry.startOffset)}
            </span>
            <span class="min-w-0 flex-1">
              <span class={labelCls} style="color: {recipeHue[entry.slug]}">{entry.title}</span>
              <span class="block text-[14.5px]" style="color: var(--ink); text-decoration: {done ? 'line-through' : 'none'}">
                {entry.text.replace(/\*\*/g, '')}
              </span>
            </span>
            {#if entry.timed}
              <span class="qty shrink-0 text-[11px]" style="color: var(--faint)">
                {Math.round(entry.durationSeconds / 60)} min
              </span>
            {/if}
          </button>
        </li>
      {/each}
    </ol>
    <p class="mt-2 text-[12.5px]" style="color: var(--faint)">
      Untimed steps are estimated at 3 minutes — the copper line tracks where you should be.
    </p>
  {:else}
    <p class="mt-5 text-[13.5px]" style="color: var(--faint)">Pick at least two dishes to build a timeline.</p>
  {/if}
</section>
