<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { scaledDisplay } from '$lib/scaling';
  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();

  const version = data.recipe.current_version;
  let step = $state(0);
  const steps = version.steps;

  // Scaled amounts are shown beside the step that uses them, so nobody scrolls back
  // to the ingredient list with wet hands.
  let factor = $derived(data.target / data.recipe.base_yield);
  let rows = $derived(
    version.ingredients.map((i) => ({
      name: i.name,
      display: scaledDisplay(i.amount, i.unit, factor)
    }))
  );

  // Timers come from the recipe's own timer_seconds, so "simmer 40 minutes" is a
  // button rather than something to remember.
  let remaining = $state<number | null>(null);
  let ticking: ReturnType<typeof setInterval> | null = null;
  let wakeLock: any = null;

  function startTimer(seconds: number) {
    remaining = seconds;
    if (ticking) clearInterval(ticking);
    ticking = setInterval(() => {
      if (remaining === null) return;
      remaining -= 1;
      if (remaining <= 0) {
        clearInterval(ticking!);
        remaining = 0;
        navigator.vibrate?.([400, 200, 400]);
      }
    }, 1000);
  }

  function mmss(s: number) {
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  }

  onMount(async () => {
    // Keep the screen alive — a screen that sleeps mid-recipe is the whole reason
    // people prop a paper book open instead.
    try {
      wakeLock = await (navigator as any).wakeLock?.request('screen');
    } catch {
      /* not supported, or denied — cook mode still works */
    }
  });

  onDestroy(() => {
    if (ticking) clearInterval(ticking);
    wakeLock?.release?.();
  });

  const prev = () => (step = Math.max(0, step - 1));
  const next = () => (step = Math.min(steps.length - 1, step + 1));
</script>

<svelte:head><title>{data.recipe.title} — cook — The Sharp Edge</title></svelte:head>
<svelte:window
  onkeydown={(e) => {
    if (e.key === 'ArrowRight' || e.key === ' ') next();
    if (e.key === 'ArrowLeft') prev();
  }}
/>

<section class="pt-6">
  <div class="flex items-baseline justify-between">
    <a href="/r/{data.recipe.slug}" class="font-mono-label text-[11px] uppercase tracking-widest no-underline"
       style="color: var(--ink-accent)">← {data.recipe.title}</a>
    <span class="font-mono-label text-[12px]" style="color: var(--faint)">
      step {step + 1} of {steps.length}
      {#if data.target !== data.recipe.base_yield}· for {data.target} {data.recipe.yield_word}{/if}
    </span>
  </div>

  <article class="mt-6 rounded-2xl border p-6" style="border-color: var(--line); background: var(--card)">
    <p class="text-[24px] leading-[1.45]" style="color: var(--ink)">{steps[step].text}</p>

    {#if steps[step].timer_seconds}
      <div class="mt-5 flex items-center gap-3">
        <button
          onclick={() => startTimer(steps[step].timer_seconds!)}
          class="font-mono-label rounded-full px-5 py-3 text-[12px] uppercase tracking-widest"
          style="background: var(--primary-deep); color: var(--off-white)"
        >Start {mmss(steps[step].timer_seconds!)}</button>
        {#if remaining !== null}
          <span class="font-mono-label text-[22px]" style="color: {remaining === 0 ? 'var(--accent)' : 'var(--ink)'}">
            {remaining === 0 ? 'done' : mmss(remaining)}
          </span>
        {/if}
      </div>
    {/if}
  </article>

  <div class="mt-4 flex gap-3">
    <button onclick={prev} disabled={step === 0}
      class="flex-1 rounded-xl border py-4 text-[16px]"
      style="border-color: var(--line); color: var(--ink); opacity: {step === 0 ? 0.4 : 1}">Back</button>
    <button onclick={next} disabled={step === steps.length - 1}
      class="flex-[2] rounded-xl py-4 text-[16px]"
      style="background: var(--primary-deep); color: var(--off-white); opacity: {step === steps.length - 1 ? 0.4 : 1}"
      >Next step</button>
  </div>

  <h3 class="font-mono-label mt-8 text-[11px] uppercase tracking-widest" style="color: var(--accent)">
    Everything you need
  </h3>
  <ul class="mt-2 divide-y" style="border-color: var(--line)">
    {#each rows as row}
      <li class="flex justify-between gap-4 py-2">
        <span class="text-[15px]" style="color: var(--ink)">{row.name}</span>
        <span class="font-mono-label text-[15px] whitespace-nowrap" style="color: var(--ink-accent)">{row.display}</span>
      </li>
    {/each}
  </ul>
</section>
