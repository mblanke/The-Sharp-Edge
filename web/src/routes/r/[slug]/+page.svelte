<script lang="ts">
  import { onMount } from 'svelte';
  import { enhance } from '$app/forms';
  import { gfRisks } from '$lib/gf';
  import { notify } from '$lib/toast';
  import { convertDisplay, scaledDisplay, UNIT_SYSTEMS, type UnitSystem } from '$lib/scaling';
  import { recordRecent } from '$lib/prefs';
  import type { Ingredient } from '$lib/types';

  let { data, form } = $props();

  let illuminating = $state(false);
  let adding = $state(false);
  let added = $state(false);
  let openNote = $state<number | null>(null); // step_index of the expanded margin note
  const notesByStep = $derived(new Map(data.annotations.map((a) => [a.step_index, a])));

  const recipe = $derived(data.recipe);

  // Version switcher — null shows the current version (marinade pattern, §5)
  let selectedVersionId = $state<string | null>(null);
  const shown = $derived(
    data.versions.find((v) => v.id === selectedVersionId) ?? recipe.current_version
  );

  // Reading in English is a lens over the page, never a change to it: the stored
  // recipe keeps the cook's own words, and the quantities shown stay the ones
  // the notebook holds.
  let readEnglish = $state(false);
  let translating = $state(false);
  const english = $derived(data.english);
  const shownTitle = $derived(readEnglish && english ? english.title : recipe.title);
  const shownMeta = $derived(readEnglish && english ? english.meta : recipe.meta);
  const shownNotes = $derived(readEnglish && english ? english.notes : shown.notes);

  function ingredientName(index: number, fallback: string): string {
    return readEnglish && english?.ingredients[index]
      ? english.ingredients[index].name
      : fallback;
  }
  function stepText(index: number, fallback: string): string {
    return readEnglish && english?.steps[index] ? english.steps[index].text : fallback;
  }

  let target = $state(0);

  // --- ticks: tap an ingredient as it goes in; persisted per recipe so a reload
  // mid-prep keeps them. Cleared with one tap or when the version changes.
  let checked = $state<Set<number>>(new Set());
  const checkKey = $derived(`sharp-edge-checked-${recipe.slug}`);
  function toggleCheck(i: number) {
    const next = new Set(checked);
    if (next.has(i)) next.delete(i);
    else next.add(i);
    checked = next;
    try {
      if (next.size) localStorage.setItem(checkKey, JSON.stringify([...next]));
      else localStorage.removeItem(checkKey);
    } catch {
      // storage blocked
    }
  }
  function clearChecks() {
    checked = new Set();
    try {
      localStorage.removeItem(checkKey);
    } catch {
      // storage blocked
    }
  }

  // --- units: a reading lens over the scaled amount, never a change to the recipe
  let units = $state<UnitSystem>('recipe');
  function setUnits(u: UnitSystem) {
    units = u;
    try {
      localStorage.setItem('sharp-edge-units', u);
    } catch {
      // storage blocked
    }
  }
  const UNIT_LABEL: Record<UnitSystem, string> = { recipe: 'as written', metric: 'metric', imperial: 'imperial' };

  onMount(() => {
    recordRecent(recipe.slug, recipe.title);
    try {
      const saved = localStorage.getItem('sharp-edge-units') as UnitSystem | null;
      if (saved && UNIT_SYSTEMS.includes(saved)) units = saved;
      const ticks = JSON.parse(localStorage.getItem(checkKey) ?? '[]');
      if (Array.isArray(ticks)) checked = new Set(ticks.filter((n) => Number.isInteger(n)));
    } catch {
      // storage blocked — fresh page
    }
  });

  /** What one ingredient row shows: server display when reconciled and unconverted,
   *  otherwise the client mirror (which the unit lens always goes through). */
  function rowDisplay(ing: Ingredient, i: number): string {
    if (ing.amount === 0) return '—';
    if (units === 'recipe') return serverDisplays?.[i] ?? scaledDisplay(ing.amount, ing.unit, factor);
    return convertDisplay(ing.amount * factor, ing.unit, units);
  }

  // hidden-gluten flags on the read page, not just in the editor (CLAUDE.md §1)
  const risky = $derived(new Set(gfRisks(shown.ingredients)));

  // --- stepper: hold to repeat, tap the number to type, ½× / 2× presets
  let holdTimer: ReturnType<typeof setTimeout> | undefined;
  let holdInterval: ReturnType<typeof setInterval> | undefined;
  function holdStart(delta: number) {
    holdStop();
    holdTimer = setTimeout(() => {
      holdInterval = setInterval(() => setTarget(target + delta), 120);
    }, 400);
  }
  function holdStop() {
    clearTimeout(holdTimer);
    clearInterval(holdInterval);
    holdTimer = undefined;
    holdInterval = undefined;
  }
  let typingYield = $state(false);
  let typedYield = $state('');
  function commitTyped() {
    const n = Number(typedYield);
    if (Number.isFinite(n) && n >= 1) setTarget(Math.round(n));
    typingYield = false;
  }

  async function share() {
    const url = location.href;
    try {
      if (navigator.share) {
        await navigator.share({ title: shownTitle, text: `${shownTitle} — The Sharp Edge`, url });
      } else {
        await navigator.clipboard.writeText(url);
        notify.ok('Link copied');
      }
    } catch {
      // cancelled or unsupported
    }
  }
  // The client mirror renders instantly; the server response is canonical
  // (CLAUDE.md §8) and reconciles shortly after the stepper settles.
  let serverDisplays = $state<string[] | null>(null);
  let reconcileTimer: ReturnType<typeof setTimeout> | undefined;

  $effect.pre(() => {
    // reset when navigating between recipes
    target = data.recipe.base_yield;
    serverDisplays = null;
    selectedVersionId = null;
    checked = new Set();
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
    {shownTitle}
    {#if recipe.gf}
      <span
        class="font-mono-label ml-2 inline-block translate-y-[-3px] rounded-full px-2.5 py-1 align-middle text-[10.5px] uppercase tracking-widest"
        style="background: var(--green); color: #F4F3EC"
      >
        GF
      </span>
    {/if}
  </h2>
  {#if shownMeta}
    <p class="mt-1 text-[13.5px]" style="color: var(--faint)">{shownMeta}</p>
  {/if}

  <!-- Language lens. Only offered when the page is worth translating. -->
  {#if english}
    <button
      class="font-mono-label mt-2 rounded-full border px-4 py-2 text-[10.5px] uppercase tracking-widest"
      style={readEnglish
        ? 'background: var(--green-deep); border-color: var(--green-deep); color: #F4F3EC'
        : 'border-color: var(--line); color: var(--faint)'}
      onclick={() => (readEnglish = !readEnglish)}
      data-testid="english-toggle"
    >
      {readEnglish ? '⇄ showing English · tap for original' : '⇄ read in English'}
    </button>
  {:else if shown.is_current}
    <form
      method="POST"
      action="?/translate"
      use:enhance={() => {
        translating = true;
        return async ({ result, update }) => {
          await update();
          translating = false;
          if (result.type === 'success') readEnglish = true;
          else notify.error('Could not translate this recipe — the model may be busy. Try again.');
        };
      }}
    >
      <button
        type="submit"
        disabled={translating}
        class="font-mono-label mt-2 rounded-full border px-4 py-2 text-[10.5px] uppercase tracking-widest disabled:opacity-60"
        style="border-color: var(--copper); color: var(--copper)"
        data-testid="translate-recipe"
      >
        {translating ? 'translating…' : '⇄ read in English'}
      </button>
    </form>
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

  <!-- On a landscape iPad the scaler and the ingredients pin to the left while
       the method scrolls on the right; below that width it is one column. -->
  <div class="recipe-cols">
  <aside class="recipe-side" aria-label="Scale and ingredients">
  {#if !recipe.noscale}
    <div
      class="mt-4 flex flex-wrap items-center gap-x-3 gap-y-2 rounded-2xl px-4 py-3"
      style="background: var(--green-deep); color: #F4F3EC"
    >
      <span class="font-mono-label text-[11px] uppercase tracking-widest opacity-80">Scale</span>
      <button
        aria-label="Fewer {recipe.yield_word}"
        class="h-11 w-11 rounded-xl text-xl select-none"
        style="background: rgba(255,255,255,.14); color: #F4F3EC"
        onclick={() => setTarget(target - 1)}
        onpointerdown={() => holdStart(-1)}
        onpointerup={holdStop}
        onpointerleave={holdStop}
        onpointercancel={holdStop}
        oncontextmenu={(e) => e.preventDefault()}
      >
        −
      </button>
      {#if typingYield}
        <!-- svelte-ignore a11y_autofocus -->
        <input
          type="number"
          inputmode="numeric"
          min="1"
          max={maxYield}
          bind:value={typedYield}
          autofocus
          aria-label="Type the number of {recipe.yield_word}"
          class="font-display h-11 w-[4ch] rounded-lg text-center text-[22px]"
          style="background: rgba(255,255,255,.14); color: #F4F3EC"
          onblur={commitTyped}
          onkeydown={(e) => {
            if (e.key === 'Enter') commitTyped();
            if (e.key === 'Escape') typingYield = false;
          }}
        />
      {:else}
        <button
          class="font-display min-w-[2.2ch] rounded-lg px-1 text-center text-[26px]"
          aria-label="{target} {recipe.yield_word} — tap to type a number"
          onclick={() => {
            typedYield = String(target);
            typingYield = true;
          }}
        >
          {target}
        </button>
      {/if}
      <button
        aria-label="More {recipe.yield_word}"
        class="h-11 w-11 rounded-xl text-xl select-none"
        style="background: rgba(255,255,255,.14); color: #F4F3EC"
        onclick={() => setTarget(target + 1)}
        onpointerdown={() => holdStart(1)}
        onpointerup={holdStop}
        onpointerleave={holdStop}
        onpointercancel={holdStop}
        oncontextmenu={(e) => e.preventDefault()}
      >
        +
      </button>
      <span class="text-[13px] opacity-80">{recipe.yield_word}</span>
      <span class="ml-auto flex gap-1">
        <button
          class="font-mono-label min-h-[44px] rounded-full border px-2.5 text-[11px] uppercase tracking-widest"
          style="border-color: rgba(255,255,255,.4); color: #F4F3EC"
          aria-label="Halve the recipe"
          onclick={() => setTarget(Math.max(1, Math.round(recipe.base_yield / 2)))}
        >
          ½×
        </button>
        <button
          class="font-mono-label min-h-[44px] rounded-full border px-2.5 text-[11px] uppercase tracking-widest"
          style="border-color: rgba(255,255,255,.4); color: #F4F3EC"
          aria-label="Double the recipe"
          onclick={() => setTarget(recipe.base_yield * 2)}
        >
          2×
        </button>
        <button
          class="font-mono-label min-h-[44px] rounded-full border px-3 text-[11px] uppercase tracking-widest"
          style="border-color: rgba(255,255,255,.4); color: #F4F3EC"
          onclick={() => setTarget(recipe.base_yield)}
        >
          base {recipe.base_yield}
        </button>
      </span>
    </div>
    <div class="mt-2 flex flex-wrap items-center gap-1" role="group" aria-label="Units" data-print="hide">
      <span class="font-mono-label mr-1 text-[10.5px] uppercase tracking-widest" style="color: var(--faint)">amounts</span>
      {#each UNIT_SYSTEMS as u (u)}
        <button
          class="font-mono-label min-h-[36px] rounded-full border px-3 text-[10.5px] uppercase tracking-widest"
          style={units === u
            ? 'background: var(--green-deep); border-color: var(--green-deep); color: #F4F3EC'
            : 'border-color: var(--line); color: var(--faint)'}
          aria-pressed={units === u}
          onclick={() => setUnits(u)}
          data-testid="units-{u}"
        >
          {UNIT_LABEL[u]}
        </button>
      {/each}
    </div>
  {/if}

  {#if shown.ingredients.length}
    <div class="mt-6 flex items-end justify-between border-b pb-1" style="border-color: var(--line)">
      <h3 class="font-mono-label text-xs uppercase tracking-widest" style="color: var(--green)">
        Ingredients
      </h3>
      {#if checked.size}
        <button
          class="font-mono-label min-h-[32px] text-[10.5px] uppercase tracking-widest"
          style="color: var(--faint)"
          onclick={clearChecks}
          data-print="hide"
        >
          {checked.size}/{shown.ingredients.length} in · clear
        </button>
      {/if}
    </div>
    {#if risky.size}
      <p
        class="mt-2 rounded-lg border px-3 py-2 text-[12.5px]"
        style="border-color: var(--copper); color: var(--copper); background: var(--warn-bg)"
        data-testid="gf-risks"
      >
        ⚠ check the label for gluten: {[...risky].map((n) => n.split(',')[0]).join(' · ')}
      </p>
    {/if}
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
        <li class="flex items-baseline gap-2 text-[15px]">
          <button
            class="flex min-h-[44px] min-w-0 flex-1 items-baseline gap-2 text-left"
            aria-pressed={checked.has(i)}
            onclick={() => toggleCheck(i)}
            data-testid="ingredient-row"
          >
            <span
              class="min-w-0"
              style="text-decoration: {checked.has(i) ? 'line-through' : 'none'}; opacity: {checked.has(i) ? 0.45 : 1}"
            >
              {ingredientName(i, ing.name)}
              {#if risky.has(ing.name)}
                <span class="font-mono-label ml-1 text-[9.5px] uppercase tracking-widest" style="color: var(--copper)" title="check the label for gluten">gf?</span>
              {/if}
            </span>
            <span class="leader-dots flex-1" aria-hidden="true"></span>
            <span
              class="qty shrink-0 text-right text-[14px]"
              class:flash={flashing && ing.amount !== 0}
              style="opacity: {checked.has(i) ? 0.45 : 1}"
            >
              {rowDisplay(ing, i)}
            </span>
          </button>
        </li>
      {/each}
    </ul>
  {/if}
  </aside>
  <div class="recipe-main">

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
        {#each boldParts(stepText(i, step.text)) as part, j (j)}
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
        return async ({ result, update }) => {
          await update();
          illuminating = false;
          if (result.type !== 'success') notify.error('The library could not annotate this recipe right now.');
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

  {#if shownNotes.length}
    <h3
      class="font-mono-label mt-6 border-b pb-1 text-xs uppercase tracking-widest"
      style="border-color: var(--line); color: var(--green)"
    >
      Notes
    </h3>
    <ul class="mt-2 list-none rounded-xl border p-4" style="background: var(--card); border-color: var(--line)">
      {#each shownNotes as note, i (i)}
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
        class="font-mono-label press inline-block min-h-[44px] rounded-full px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline"
        style="background: var(--copper); color: #FFF; box-shadow: 0 2px 8px rgba(200,122,46,.3)"
        data-testid="start-cooking"
      >
        ▶ Cook
      </a>
    {/if}
    {#if !recipe.noscale}
      <form
        method="POST"
        action="?/addToList"
        use:enhance={() => {
          adding = true;
          return async ({ result, update }) => {
            await update({ reset: false });
            adding = false;
            if (result.type === 'success') {
              added = true;
              setTimeout(() => (added = false), 4000);
              notify.ok(`Added ×${target} to the list`, { href: { label: 'open list', url: '/shopping' } });
            } else {
              notify.error('Could not add to the list — is the server reachable?');
            }
          };
        }}
      >
        <input type="hidden" name="target" value={target} />
        <button
          class="font-mono-label min-h-[44px] rounded-full border px-5 py-2.5 text-[11px] uppercase tracking-widest disabled:opacity-60"
          style="border-color: var(--green); color: var(--ink-accent)"
          disabled={adding}
          data-testid="add-to-list"
        >
          {adding ? 'adding…' : added ? '✓ on the list' : '+ shopping list'}
        </button>
      </form>
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
    <button
      class="font-mono-label min-h-[44px] rounded-full border px-5 py-2.5 text-[11px] uppercase tracking-widest"
      style="border-color: var(--line); color: var(--faint)"
      onclick={share}
      aria-label="Share this recipe"
    >
      ↗ share
    </button>
    <button
      class="font-mono-label min-h-[44px] rounded-full border px-5 py-2.5 text-[11px] uppercase tracking-widest"
      style="border-color: var(--line); color: var(--faint)"
      onclick={() => window.print()}
    >
      print
    </button>
    <a
      href="/"
      class="font-mono-label inline-block min-h-[44px] rounded-full border px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline"
      style="border-color: var(--green-deep); color: var(--ink-accent)"
    >
      ← all recipes
    </a>
  </div>
  </div>
  </div>
</article>
