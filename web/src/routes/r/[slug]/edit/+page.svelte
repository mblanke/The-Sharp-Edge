<script lang="ts">
  import { enhance } from '$app/forms';
  import { gfRisks } from '$lib/gf';
  import { ALLOWED_UNITS, CATEGORY_ORDER } from '$lib/types';
  import type { Ingredient, PageRef, RecipeUpdate, Step } from '$lib/types';

  let { data, form } = $props();

  const recipe = data.recipe;
  const v = recipe.current_version;

  // --- editable state, seeded from the current version ---
  let title = $state(recipe.title);
  let category = $state(recipe.category);
  let meta = $state(recipe.meta ?? '');
  let base_yield = $state(recipe.base_yield);
  let yield_word = $state(recipe.yield_word);
  let gf = $state(recipe.gf);
  let noscale = $state(recipe.noscale);
  let source = $state(recipe.source ?? '');
  let label = $state('');

  let ingredients = $state<Ingredient[]>(v.ingredients.map((i) => ({ ...i })));
  let steps = $state<Step[]>(v.steps.map((s) => ({ ...s })));
  let notes = $state<string[]>([...v.notes]);
  let tags = $state<string[]>([...(recipe.tags ?? [])]);
  let newTag = $state('');
  let pages = $state<PageRef[]>((recipe.pages ?? []).map((p) => ({ ...p })));

  function addTag() {
    const t = newTag.trim();
    if (t && !tags.some((x) => x.toLowerCase() === t.toLowerCase())) tags.push(t);
    newTag = '';
  }

  // photo import: a returned draft prefills the fields — nothing saved until
  // the cook reviews and hits Save
  interface PhotoDraft {
    title?: string;
    meta?: string | null;
    base_yield?: number;
    yield_word?: string;
    ingredients?: Ingredient[];
    steps?: Step[];
    notes?: string[];
  }
  let photoBusy = $state(false);
  let appliedDraft: unknown = null;
  $effect(() => {
    const draft = form && 'draft' in form ? (form.draft as PhotoDraft) : null;
    if (!draft || draft === appliedDraft) return;
    appliedDraft = draft;
    title = draft.title ?? title;
    if (draft.meta) meta = draft.meta;
    base_yield = draft.base_yield ?? base_yield;
    yield_word = draft.yield_word ?? yield_word;
    if (draft.ingredients?.length) ingredients = draft.ingredients.map((i) => ({ ...i }));
    if (draft.steps?.length) steps = draft.steps.map((s) => ({ ...s }));
    if (draft.notes?.length) notes = [...draft.notes];
    label = label || 'from photo';
  });

  let saving = $state(false);

  // --- list helpers ---
  function move<T>(arr: T[], i: number, dir: -1 | 1) {
    const j = i + dir;
    if (j < 0 || j >= arr.length) return;
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }

  const addIngredient = () => ingredients.push({ amount: 0, unit: '', name: '' });
  const addStep = () => steps.push({ text: '' });
  const addNote = () => notes.push('');

  // --- payload sent to the server action (typed, so JSON keeps number/bool types) ---
  const payload = $derived<RecipeUpdate>({
    title: title.trim(),
    category,
    meta: meta.trim() || null,
    base_yield,
    yield_word: yield_word.trim(),
    gf,
    noscale,
    source: source.trim() || null,
    label: label.trim() || null,
    ingredients: ingredients.map((i) => ({
      amount: Number(i.amount) || 0,
      unit: i.unit ?? '',
      name: (i.name ?? '').trim(),
      ...(i.note?.trim() ? { note: i.note.trim() } : {}),
      ...(i.section?.trim() ? { section: i.section.trim() } : {})
    })),
    steps: steps
      .filter((s) => s.text.trim())
      .map((s) => ({
        text: s.text.trim(),
        ...(s.timer_seconds != null && s.timer_seconds !== ('' as unknown)
          ? { timer_seconds: Number(s.timer_seconds) }
          : {})
      })),
    notes: notes.map((n) => n.trim()).filter(Boolean),
    tags,
    pages: pages
      .filter((p) => Number(p.page_number) >= 1)
      .map((p) => ({
        page_number: Number(p.page_number),
        section: p.section?.trim() || null
      }))
  });

  const payloadJson = $derived(JSON.stringify(payload));

  const labelCls = 'font-mono-label text-[10.5px] uppercase tracking-widest';
  const inputCls =
    'w-full rounded-lg border bg-[var(--card)] px-3 py-2 text-[15px] outline-none focus:border-[var(--green)]';
  const btnGhost =
    'font-mono-label min-h-[44px] rounded-full border px-4 text-[11px] uppercase tracking-widest';
</script>

<svelte:head>
  <title>Edit {recipe.title} — The Sharp Edge</title>
</svelte:head>

{#if data.photoImport}
  <form
    method="POST"
    action="?/photo"
    enctype="multipart/form-data"
    class="pt-7"
    use:enhance={() => {
      photoBusy = true;
      return async ({ update }) => {
        await update({ reset: false });
        photoBusy = false;
      };
    }}
  >
    <label
      class="font-mono-label inline-flex min-h-[44px] cursor-pointer items-center gap-2 rounded-full border px-5 text-[11px] uppercase tracking-widest"
      style="border-color: var(--copper); color: var(--copper)"
    >
      {photoBusy ? 'reading the page…' : '📷 import from photo'}
      <input
        type="file"
        name="photo"
        accept="image/*"
        capture="environment"
        class="hidden"
        disabled={photoBusy}
        onchange={(e) => (e.currentTarget as HTMLInputElement).form?.requestSubmit()}
      />
    </label>
    <span class="ml-2 text-[12px]" style="color: var(--faint)">
      a page from your notebook becomes a draft — review before saving
    </span>
  </form>
{/if}

<form
  method="POST"
  action="?/save"
  class="pt-7 pb-16"
  use:enhance={() => {
    saving = true;
    return async ({ update }) => {
      await update();
      saving = false;
    };
  }}
>
  <input type="hidden" name="payload" value={payloadJson} />

  <div class="flex items-baseline justify-between">
    <div class="{labelCls}" style="color: var(--copper)">Edit recipe</div>
    <div class="{labelCls}" style="color: var(--faint)">/{recipe.slug}</div>
  </div>
  <h2 class="font-display mt-1 text-[clamp(22px,5vw,30px)] leading-tight">{recipe.title}</h2>

  {#if form?.message}
    <p
      class="mt-3 rounded-lg border px-3 py-2 text-[13.5px]"
      style="border-color: var(--copper); color: var(--copper); background: #FBF0E6"
    >
      {form.message}
    </p>
  {/if}

  <!-- Metadata -->
  <section class="mt-5 grid gap-3">
    <label class="grid gap-1">
      <span class="{labelCls}" style="color: var(--green)">Title</span>
      <input class={inputCls} style="border-color: var(--line)" bind:value={title} required />
    </label>

    <div class="grid grid-cols-2 gap-3">
      <label class="grid gap-1">
        <span class="{labelCls}" style="color: var(--green)">Category</span>
        <select class={inputCls} style="border-color: var(--line)" bind:value={category}>
          {#each CATEGORY_ORDER as c (c)}
            <option value={c}>{c}</option>
          {/each}
        </select>
      </label>
      <label class="grid gap-1">
        <span class="{labelCls}" style="color: var(--green)">Source</span>
        <input class={inputCls} style="border-color: var(--line)" bind:value={source} />
      </label>
    </div>

    <label class="grid gap-1">
      <span class="{labelCls}" style="color: var(--green)">Meta line</span>
      <input class={inputCls} style="border-color: var(--line)" bind:value={meta} />
    </label>

    <div class="grid grid-cols-2 gap-3">
      <label class="grid gap-1">
        <span class="{labelCls}" style="color: var(--green)">Base yield</span>
        <input
          type="number"
          min="1"
          class="{inputCls} font-mono-label"
          style="border-color: var(--line)"
          bind:value={base_yield}
        />
      </label>
      <label class="grid gap-1">
        <span class="{labelCls}" style="color: var(--green)">Yield word</span>
        <input class={inputCls} style="border-color: var(--line)" bind:value={yield_word} />
      </label>
    </div>

    {#if gf}
      {@const risks = gfRisks(ingredients)}
      {#if risks.length}
        <p
          class="rounded-lg border px-3 py-2 text-[13.5px]"
          style="border-color: var(--copper); color: var(--copper); background: #FBF0E6"
          data-testid="gf-warning"
        >
          Marked GF but these may hide gluten: {risks.join(' · ')}. Check labels or swap
          (soy sauce → GF tamari).
        </p>
      {/if}
    {/if}

    <div class="flex gap-5 pt-1">
      <label class="flex items-center gap-2 text-[14px]">
        <input type="checkbox" class="h-5 w-5" bind:checked={gf} />
        <span class="{labelCls}" style="color: var(--green)">Gluten-free</span>
      </label>
      <label class="flex items-center gap-2 text-[14px]">
        <input type="checkbox" class="h-5 w-5" bind:checked={noscale} />
        <span class="{labelCls}" style="color: var(--green)">Doesn't scale</span>
      </label>
    </div>

    <label class="grid gap-1">
      <span class="{labelCls}" style="color: var(--green)">Version label (optional)</span>
      <input
        class={inputCls}
        style="border-color: var(--line)"
        placeholder="e.g. overnight"
        bind:value={label}
      />
    </label>

    <div class="grid gap-1">
      <span class="{labelCls}" style="color: var(--green)">Tags</span>
      <div class="flex flex-wrap items-center gap-2">
        {#each tags as tag, i (tag)}
          <span
            class="font-mono-label inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-[11px] uppercase tracking-widest"
            style="border-color: var(--green); color: var(--green-deep); background: var(--card)"
          >
            {tag}
            <button type="button" aria-label="Remove tag {tag}" style="color: var(--copper)" onclick={() => tags.splice(i, 1)}>✕</button>
          </span>
        {/each}
        <input
          aria-label="Add tag"
          placeholder="+ tag"
          class="w-[8rem] rounded-full border bg-white px-3 py-1.5 text-[13px] outline-none"
          style="border-color: var(--line)"
          bind:value={newTag}
          onkeydown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              addTag();
            }
          }}
          onblur={addTag}
        />
      </div>
    </div>

    <div class="grid gap-1">
      <span class="{labelCls}" style="color: var(--green)">Notebook pages</span>
      {#each pages as p, i (i)}
        <div class="flex items-center gap-2">
          <input
            type="number"
            min="1"
            aria-label="Page number"
            class="qty w-[5.5rem] rounded-lg border bg-white px-2 py-1.5 text-[14px] outline-none"
            style="border-color: var(--line)"
            bind:value={p.page_number}
          />
          <input
            aria-label="Notebook section"
            placeholder="section (e.g. Sauces)"
            class="min-w-0 flex-1 rounded-lg border bg-white px-2 py-1.5 text-[13px] outline-none"
            style="border-color: var(--line)"
            bind:value={p.section}
          />
          <button type="button" aria-label="Remove page" class="h-9 w-9 shrink-0 rounded-lg border" style="border-color: var(--copper); color: var(--copper)" onclick={() => pages.splice(i, 1)}>✕</button>
        </div>
      {/each}
      <button
        type="button"
        class="{btnGhost} justify-self-start"
        style="border-color: var(--green); color: var(--green)"
        onclick={() => pages.push({ page_number: 1, section: null })}
      >
        + notebook page
      </button>
    </div>
  </section>

  <!-- Ingredients -->
  <h3
    class="font-mono-label mt-7 flex items-center justify-between border-b pb-1 text-xs uppercase tracking-widest"
    style="border-color: var(--line); color: var(--green)"
  >
    Ingredients
    <span class="text-[10px] normal-case" style="color: var(--faint)">amount 0 = to taste</span>
  </h3>
  <ul class="mt-2 grid list-none gap-2 p-0">
    {#each ingredients as ing, i (i)}
      <li class="rounded-xl border p-2.5" style="border-color: var(--line); background: var(--card)">
        <div class="flex gap-2">
          <input
            type="number"
            step="0.001"
            min="0"
            aria-label="Amount"
            class="qty w-[5.5rem] shrink-0 rounded-lg border bg-white px-2 py-2 text-[15px] outline-none"
            style="border-color: var(--line)"
            bind:value={ing.amount}
          />
          <select
            aria-label="Unit"
            class="font-mono-label w-[4.5rem] shrink-0 rounded-lg border bg-white px-1 py-2 text-[13px] outline-none"
            style="border-color: var(--line)"
            bind:value={ing.unit}
          >
            {#each ALLOWED_UNITS as u (u)}
              <option value={u}>{u === '' ? '—' : u}</option>
            {/each}
          </select>
          <input
            aria-label="Name"
            placeholder="ingredient"
            class="min-w-0 flex-1 rounded-lg border bg-white px-2 py-2 text-[15px] outline-none"
            style="border-color: var(--line)"
            bind:value={ing.name}
          />
        </div>
        <div class="mt-2 flex gap-2">
          <input
            aria-label="Section"
            placeholder="section (optional)"
            class="min-w-0 flex-1 rounded-lg border bg-white px-2 py-1.5 text-[13px] outline-none"
            style="border-color: var(--line)"
            bind:value={ing.section}
          />
          <input
            aria-label="Note"
            placeholder="note (optional)"
            class="min-w-0 flex-1 rounded-lg border bg-white px-2 py-1.5 text-[13px] outline-none"
            style="border-color: var(--line)"
            bind:value={ing.note}
          />
          <div class="flex shrink-0 gap-1">
            <button
              type="button"
              aria-label="Move up"
              class="h-9 w-9 rounded-lg border"
              style="border-color: var(--line)"
              onclick={() => move(ingredients, i, -1)}>↑</button
            >
            <button
              type="button"
              aria-label="Move down"
              class="h-9 w-9 rounded-lg border"
              style="border-color: var(--line)"
              onclick={() => move(ingredients, i, 1)}>↓</button
            >
            <button
              type="button"
              aria-label="Remove ingredient"
              class="h-9 w-9 rounded-lg border"
              style="border-color: var(--copper); color: var(--copper)"
              onclick={() => ingredients.splice(i, 1)}>✕</button
            >
          </div>
        </div>
      </li>
    {/each}
  </ul>
  <button type="button" class="{btnGhost} mt-2" style="border-color: var(--green); color: var(--green)" onclick={addIngredient}>
    + ingredient
  </button>

  <!-- Steps -->
  <h3
    class="font-mono-label mt-7 border-b pb-1 text-xs uppercase tracking-widest"
    style="border-color: var(--line); color: var(--green)"
  >
    Method
  </h3>
  <ol class="mt-2 grid list-none gap-2 p-0">
    {#each steps as step, i (i)}
      <li class="rounded-xl border p-2.5" style="border-color: var(--line); background: var(--card)">
        <div class="flex gap-2">
          <span
            class="font-mono-label mt-1 flex h-[26px] w-[26px] shrink-0 items-center justify-center rounded-full border text-[12px]"
            style="border-color: var(--green); color: var(--green)">{i + 1}</span
          >
          <textarea
            aria-label="Step {i + 1}"
            rows="2"
            placeholder="step text — **Lead-in:** supported"
            class="min-w-0 flex-1 rounded-lg border bg-white px-2 py-2 text-[15px] outline-none"
            style="border-color: var(--line)"
            bind:value={step.text}
          ></textarea>
        </div>
        <div class="mt-2 flex items-center gap-2">
          <span class="{labelCls}" style="color: var(--faint)">timer (s)</span>
          <input
            type="number"
            min="0"
            aria-label="Timer seconds"
            class="qty w-[6rem] rounded-lg border bg-white px-2 py-1.5 text-[14px] outline-none"
            style="border-color: var(--line)"
            bind:value={step.timer_seconds}
          />
          <div class="ml-auto flex shrink-0 gap-1">
            <button type="button" aria-label="Move up" class="h-9 w-9 rounded-lg border" style="border-color: var(--line)" onclick={() => move(steps, i, -1)}>↑</button>
            <button type="button" aria-label="Move down" class="h-9 w-9 rounded-lg border" style="border-color: var(--line)" onclick={() => move(steps, i, 1)}>↓</button>
            <button type="button" aria-label="Remove step" class="h-9 w-9 rounded-lg border" style="border-color: var(--copper); color: var(--copper)" onclick={() => steps.splice(i, 1)}>✕</button>
          </div>
        </div>
      </li>
    {/each}
  </ol>
  <button type="button" class="{btnGhost} mt-2" style="border-color: var(--green); color: var(--green)" onclick={addStep}>
    + step
  </button>

  <!-- Notes -->
  <h3
    class="font-mono-label mt-7 border-b pb-1 text-xs uppercase tracking-widest"
    style="border-color: var(--line); color: var(--green)"
  >
    Notes
  </h3>
  <ul class="mt-2 grid list-none gap-2 p-0">
    {#each notes as _, i (i)}
      <li class="flex gap-2">
        <input
          aria-label="Note {i + 1}"
          placeholder="note — **Lead-in:** supported"
          class="min-w-0 flex-1 rounded-lg border bg-white px-2 py-2 text-[14px] outline-none"
          style="border-color: var(--line)"
          bind:value={notes[i]}
        />
        <button type="button" aria-label="Remove note" class="h-9 w-9 shrink-0 rounded-lg border" style="border-color: var(--copper); color: var(--copper)" onclick={() => notes.splice(i, 1)}>✕</button>
      </li>
    {/each}
  </ul>
  <button type="button" class="{btnGhost} mt-2" style="border-color: var(--green); color: var(--green)" onclick={addNote}>
    + note
  </button>

  <!-- Actions -->
  <div class="mt-8 flex gap-2">
    <button
      type="submit"
      disabled={saving}
      class="font-mono-label min-h-[48px] flex-1 rounded-full px-5 text-[12px] uppercase tracking-widest disabled:opacity-60"
      style="background: var(--green-deep); color: #F4F3EC"
    >
      {saving ? 'Saving…' : 'Save new version'}
    </button>
    <a
      href="/r/{recipe.slug}"
      class="font-mono-label flex min-h-[48px] items-center rounded-full border px-5 text-[12px] uppercase tracking-widest no-underline"
      style="border-color: var(--green-deep); color: var(--green-deep)"
    >
      Cancel
    </a>
  </div>
</form>
