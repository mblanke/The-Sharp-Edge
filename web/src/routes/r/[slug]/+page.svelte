<script lang="ts">
  import { enhance } from '$app/forms';
  import { scaledDisplay } from '$lib/scaling';
  import type { Ingredient } from '$lib/types';

  let { data } = $props();

  let illuminating = $state(false);
  let openNote = $state<number | null>(null); // step_index of the expanded margin note
  const notesByStep = $derived(new Map(data.annotations.map((a) => [a.step_index, a])));

  const recipe = $derived(data.recipe);

  // Version switcher — null shows the current version (marinade pattern, §5)
  let selectedVersionId = $state<string | null>(null);
  const shown = $derived(
    data.versions.find((v) => v.id === selectedVersionId) ?? recipe.current_version
  );

  let target = $state(0);
  // The client mirror renders instantly; the server response is canonical
  // (CLAUDE.md §8) and reconciles shortly after the stepper settles.
  let serverDisplays = $state<string[] | null>(null);
  let reconcileTimer: ReturnType<typeof setTimeout> | undefined;

  $effect.pre(() => {
    // reset when navigating between recipes
    target = data.recipe.base_yield;
    serverDisplays = null;
    selectedVersionId = null;
  });

  const factor = $derived(target / recipe.base_yield);
  const maxYield = $derived(recipe.base_yield * 4);

  let flashing = $state(false);
  let flashTimer: ReturnType<typeof setTimeout> | undefined;

  function reconcile(targetYield: number) {
    clearTimeout(reconcileTimer);
    // POST /scale operates on the current version; historical views stay client-side
    if (targetYield === recipe.base_yield || !shown.is_current) return;
    reconcileTimer = setTimeout(async () => {
      try {
        const res = await fetch(`/api/recipes/${recipe.slug}/scale`, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ target_yield: targetYield })
        });
        if (!res.ok) return;
        const scaled = await res.json();
        if (target === scaled.target_yield) {
          serverDisplays = scaled.ingredients.map((i: { display: string }) => i.display);
        }
      } catch {
        // offline or API down — the client mirror stays on screen
      }
    }, 300);
  }

  function setTarget(next: number) {
    target = Math.min(maxYield, Math.max(1, next));
    serverDisplays = null;
    reconcile(target);
    flashing = true;
    clearTimeout(flashTimer);
    flashTimer = setTimeout(() => (flashing = false), 450);
  }

  /** Render "**Lead-in:** rest" bold markers from step/note text. */
  function boldParts(text: string): Array<{ bold: boolean; t: string }> {
    const parts: Array<{ bold: boolean; t: string }> = [];
    const re = /\*\*(.+?)\*\*/g;
    let last = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(text)) !== null) {
      if (m.index > last) parts.push({ bold: false, t: text.slice(last, m.index) });
      parts.push({ bold: true, t: m[1] });
      last = m.index + m[0].length;
    }
    if (last < text.length) parts.push({ bold: false, t: text.slice(last) });
    return parts;
  }

  function sectionChanged(ings: Ingredient[], i: number): string | null {
    const s = ings[i].section ?? null;
    if (!s) return null;
    return i === 0 || ings[i - 1].section !== s ? s : null;
  }
</script>

<svelte:head>
  <title>{recipe.title} — The Sharp Edge</title>
</svelte:head>

<article class="pt-7">
  <div class="font-mono-label text-[11px] uppercase tracking-widest" style="color: var(--copper)">
    {recipe.category}
  </div>
  <h2 class="font-display mt-1 text-[clamp(24px,5.6vw,32px)] leading-tight">
    {recipe.title}
    {#if recipe.gf}
      <span
        class="font-mono-label ml-2 inline-block translate-y-[-3px] rounded-full px-2.5 py-1 align-middle text-[10.5px] uppercase tracking-widest"
        style="background: var(--green); color: #F4F3EC"
      >
        GF
      </span>
    {/if}
  </h2>
  {#if recipe.meta}
    <p class="mt-1 text-[13.5px]" style="color: var(--faint)">{recipe.meta}</p>
  {/if}
  {#if recipe.source}
    <p class="mt-1 text-[12.5px] italic" style="color: var(--faint)">source: {recipe.source}</p>
  {/if}
  {#if data.lastCooked}
    <p class="qty mt-1 text-[12px]" style="color: var(--faint)" data-testid="last-cooked">
      last cooked {new Date(data.lastCooked.finished_at).toLocaleDateString('en-CA', {
        month: 'short',
        day: 'numeric'
      })} · ×{data.lastCooked.scaled_yield}{data.lastCooked.notes ? ` · ${data.lastCooked.notes}` : ''}
    </p>
  {/if}

  {#if data.versions.length > 1}
    <div class="mt-3 flex flex-wrap gap-2" role="group" aria-label="Versions">
      {#each data.versions as v (v.id)}
        <button
          class="font-mono-label min-h-[44px] rounded-full border px-4 text-[11px] uppercase tracking-widest"
          style={shown.id === v.id
            ? 'background: var(--green-deep); border-color: var(--green-deep); color: #F4F3EC'
            : 'border-color: var(--line); color: var(--faint)'}
          onclick={() => {
            selectedVersionId = v.is_current ? null : v.id;
            serverDisplays = null;
          }}
        >
          v{v.version}{v.label ? ` · ${v.label}` : ''}{v.is_current ? '' : ' (older)'}
        </button>
      {/each}
    </div>
    {#if !shown.is_current}
      <p
        class="font-mono-label mt-2 inline-block rounded-full border px-3 py-1.5 text-[10.5px] uppercase tracking-widest"
        style="border-color: var(--copper); color: var(--copper)"
      >
        viewing an older version
      </p>
    {/if}
  {/if}

  {#if !recipe.noscale}
    <div
      class="mt-4 flex items-center gap-3 rounded-2xl px-4 py-3"
      style="background: var(--green-deep); color: #F4F3EC"
    >
      <span class="font-mono-label text-[11px] uppercase tracking-widest opacity-80">Scale</span>
      <button
        aria-label="Fewer {recipe.yield_word}"
        class="h-11 w-11 rounded-xl text-xl"
        style="background: rgba(255,255,255,.14); color: #F4F3EC"
        onclick={() => setTarget(target - 1)}
      >
        −
      </button>
      <span class="font-display min-w-[2.2ch] text-center text-[26px]">{target}</span>
      <button
        aria-label="More {recipe.yield_word}"
        class="h-11 w-11 rounded-xl text-xl"
        style="background: rgba(255,255,255,.14); color: #F4F3EC"
        onclick={() => setTarget(target + 1)}
      >
        +
      </button>
      <span class="text-[13px] opacity-80">{recipe.yield_word}</span>
      <button
        class="font-mono-label ml-auto min-h-[44px] rounded-full border px-3 text-[11px] uppercase tracking-widest"
        style="border-color: rgba(255,255,255,.4); color: #F4F3EC"
        onclick={() => setTarget(recipe.base_yield)}
      >
        base {recipe.base_yield}
      </button>
    </div>
  {/if}

  {#if shown.ingredients.length}
    <h3
      class="font-mono-label mt-6 border-b pb-1 text-xs uppercase tracking-widest"
      style="border-color: var(--line); color: var(--green)"
    >
      Ingredients
    </h3>
    <ul class="list-none p-0">
      {#each shown.ingredients as ing, i (i)}
        {#if sectionChanged(shown.ingredients, i)}
          <li
            class="font-mono-label pt-3 pb-1 text-[10.5px] uppercase tracking-widest"
            style="color: var(--copper)"
          >
            {ing.section}
          </li>
        {/if}
        <li class="flex items-baseline gap-2 py-2 text-[15px]">
          <span class="min-w-0">{ing.name}</span>
          <span class="leader-dots flex-1" aria-hidden="true"></span>
          <span class="qty shrink-0 text-right text-[14px]" class:flash={flashing}>
            {serverDisplays?.[i] ?? scaledDisplay(ing.amount, ing.unit, factor)}
          </span>
        </li>
      {/each}
    </ul>
  {/if}

  <h3
    class="font-mono-label mt-6 border-b pb-1 text-xs uppercase tracking-widest"
    style="border-color: var(--line); color: var(--green)"
  >
    {shown.ingredients.length ? 'Method' : 'The list'}
  </h3>
  <ol class="list-none p-0" style="counter-reset: st">
    {#each shown.steps as step, i (i)}
      {@const note = shown.is_current ? notesByStep.get(i) : undefined}
      <li class="relative py-2 pl-10 text-[15px]">
        <span
          class="font-mono-label absolute top-2 left-0 flex h-[26px] w-[26px] items-center justify-center rounded-full border text-[12px]"
          style="border-color: var(--green); color: var(--green)"
        >
          {i + 1}
        </span>
        {#each boldParts(step.text) as part, j (j)}
          {#if part.bold}<strong>{part.t}</strong>{:else}{part.t}{/if}
        {/each}
        {#if note}
          <button
            class="font-mono-label mt-1 block border-b border-dotted pb-0.5 text-[11px] tracking-wide"
            style="color: var(--copper); border-color: var(--copper)"
            onclick={() => (openNote = openNote === i ? null : i)}
            data-testid="margin-note"
          >
            📖 {note.title ?? 'library'} — {note.phrase}{note.page != null ? ` · p.${note.page}` : ''}
          </button>
          {#if openNote === i && note.snippet}
            <div
              class="mt-1.5 rounded-xl border p-3 text-[13px]"
              style="border-color: var(--line); background: var(--card); color: var(--faint)"
            >
              {note.snippet}
            </div>
          {/if}
        {/if}
      </li>
    {/each}
  </ol>

  {#if !data.annotated && shown.is_current && shown.steps.length}
    <form
      method="POST"
      action="?/illuminate"
      use:enhance={() => {
        illuminating = true;
        return async ({ update }) => {
          await update();
          illuminating = false;
        };
      }}
    >
      <button
        type="submit"
        disabled={illuminating}
        class="font-mono-label mt-3 rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest disabled:opacity-60"
        style="border-color: var(--line); color: var(--faint)"
        data-testid="illuminate"
      >
        {illuminating ? 'consulting the shelf…' : '📖 illuminate — let the library annotate the steps'}
      </button>
    </form>
  {/if}

  {#if shown.notes.length}
    <h3
      class="font-mono-label mt-6 border-b pb-1 text-xs uppercase tracking-widest"
      style="border-color: var(--line); color: var(--green)"
    >
      Notes
    </h3>
    <ul class="mt-2 list-none rounded-xl border p-4" style="background: var(--card); border-color: var(--line)">
      {#each shown.notes as note, i (i)}
        <li class="py-1 text-[13.5px]" style="color: var(--faint)">
          —
          {#each boldParts(note) as part, j (j)}
            {#if part.bold}<strong>{part.t}</strong>{:else}{part.t}{/if}
          {/each}
        </li>
      {/each}
    </ul>
  {/if}

  <div class="mt-6 flex flex-wrap gap-2">
    {#if !recipe.noscale}
      <a
        href="/r/{recipe.slug}/cook{target !== recipe.base_yield ? `?yield=${target}` : ''}"
        class="font-mono-label inline-block min-h-[44px] rounded-full px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline"
        style="background: var(--copper); color: #FFF"
        data-testid="start-cooking"
      >
        ▶ Cook
      </a>
    {/if}
    <a
      href="/ask?recipe={recipe.slug}"
      class="font-mono-label inline-block min-h-[44px] rounded-full px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline"
      style="background: var(--green-deep); color: #F4F3EC"
    >
      Ask about this recipe
    </a>
    <a
      href="/r/{recipe.slug}/edit"
      class="font-mono-label inline-block min-h-[44px] rounded-full border px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline"
      style="border-color: var(--copper); color: var(--copper)"
    >
      Edit
    </a>
    <a
      href="/"
      class="font-mono-label inline-block min-h-[44px] rounded-full border px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline"
      style="border-color: var(--green-deep); color: var(--green-deep)"
    >
      ← all recipes
    </a>
  </div>
</article>
