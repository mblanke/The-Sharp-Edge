<script lang="ts">
  import { enhance } from '$app/forms';
  import { ALLOWED_UNITS, CATEGORY_ORDER } from '$lib/types';
  import type { Ingredient, RecipeFull, RecipeUpdate, Step } from '$lib/types';

  /**
   * The one authoring form. `edit` PUTs a new (append-only) version of an existing
   * recipe; `create` POSTs a new one and adds the slug field — permanent once saved,
   * because QR codes are printed against it (CLAUDE.md §5).
   *
   * Both modes submit through a SvelteKit form action: the API proxy at
   * routes/api/[...path] forwards no Authorization header, so a client-side POST
   * would 401. env.API_TOKEN is injected server-side in lib/api.ts.
   */
  let {
    mode = 'edit',
    recipe = undefined,
    initial = undefined,
    form = undefined,
    eyebrow,
    heading,
    submitLabel,
    cancelHref
  }: {
    mode?: 'edit' | 'create';
    recipe?: RecipeFull;
    initial?: Partial<RecipeFull> & { ingredients?: Ingredient[]; steps?: Step[]; notes?: string[] };
    form?: { message?: string } | null;
    eyebrow: string;
    heading: string;
    submitLabel: string;
    cancelHref: string;
  } = $props();

  const creating = mode === 'create';
  const v = recipe?.current_version;
  const seed = initial ?? {};

  // --- editable state ---
  let slug = $state(recipe?.slug ?? seed.slug ?? '');
  let slugTouched = $state(false);
  let slugNotice = $state<string | null>(null);
  let title = $state(recipe?.title ?? seed.title ?? '');
  let category = $state(recipe?.category ?? seed.category ?? CATEGORY_ORDER[0]);
  let meta = $state(recipe?.meta ?? seed.meta ?? '');
  let base_yield = $state(recipe?.base_yield ?? seed.base_yield ?? 4);
  let yield_word = $state(recipe?.yield_word ?? seed.yield_word ?? 'servings');
  let gf = $state(recipe?.gf ?? seed.gf ?? false);
  let noscale = $state(recipe?.noscale ?? seed.noscale ?? false);
  let source = $state(recipe?.source ?? seed.source ?? '');
  let label = $state('');
  // A half-finished recipe stays out of the index until reviewed. There is no DELETE
  // endpoint, so drafts are the only way back from an accidental save.
  let draft = $state(creating ? true : recipe?.status === 'draft');

  let ingredients = $state<Ingredient[]>(
    (v?.ingredients ?? seed.ingredients ?? []).map((i) => ({ ...i }))
  );
  let steps = $state<Step[]>((v?.steps ?? seed.steps ?? []).map((s) => ({ ...s })));
  let notes = $state<string[]>([...(v?.notes ?? seed.notes ?? [])]);

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

  // --- slug (create only) ---
  // The server owns slug generation so web and iOS produce identical slugs, and it
  // reports a collision before the POST can 409.
  let slugTimer: ReturnType<typeof setTimeout> | undefined;
  function refreshSlug() {
    if (!creating || slugTouched) return;
    clearTimeout(slugTimer);
    const probe = title;
    slugTimer = setTimeout(async () => {
      if (!probe.trim()) return;
      try {
        const res = await fetch('/api/parse/slug', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ title: probe })
        });
        if (!res.ok) return;
        const body = await res.json();
        slug = body.slug;
        slugNotice = body.available ? null : 'That address is already taken — edit it before saving.';
      } catch {
        /* offline: the typed slug still works */
      }
    }, 350);
  }

  // --- payload sent to the server action (typed, so JSON keeps number/bool types) ---
  const payload = $derived<RecipeUpdate & { slug?: string }>({
    ...(creating ? { slug: slug.trim() } : {}),
    title: title.trim(),
    category,
    meta: meta.trim() || null,
    base_yield,
    yield_word: yield_word.trim(),
    gf,
    noscale,
    source: source.trim() || null,
    status: draft ? 'draft' : 'active',
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
    notes: notes.map((n) => n.trim()).filter(Boolean)
  });

  const payloadJson = $derived(JSON.stringify(payload));

  const labelCls = 'font-mono-label text-[10.5px] uppercase tracking-widest';
  const inputCls =
    'w-full rounded-lg border bg-[var(--card)] px-3 py-2 text-[15px] outline-none focus:border-[var(--primary)]';
  const btnGhost =
    'font-mono-label min-h-[44px] rounded-full border px-4 text-[11px] uppercase tracking-widest';
</script>

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
    <div class="{labelCls}" style="color: var(--accent)">{eyebrow}</div>
    {#if !creating}
      <div class="{labelCls}" style="color: var(--faint)">/{slug}</div>
    {/if}
  </div>
  <h2 class="font-display mt-1 text-[clamp(22px,5vw,30px)] leading-tight">{heading}</h2>

  {#if form?.message}
    <p
      class="mt-3 rounded-lg border px-3 py-2 text-[13.5px]"
      style="border-color: var(--accent); color: var(--accent); background: var(--accent-wash)"
    >
      {form.message}
    </p>
  {/if}

  <!-- Metadata -->
  <section class="mt-5 grid gap-3">
    <label class="grid gap-1">
      <span class="{labelCls}" style="color: var(--primary)">Title</span>
      <input
        class={inputCls}
        style="border-color: var(--line)"
        bind:value={title}
        oninput={refreshSlug}
        required
      />
    </label>

    {#if creating}
      <label class="grid gap-1">
        <span class="{labelCls}" style="color: var(--primary)">Web address</span>
        <input
          class="{inputCls} font-mono-label"
          style="border-color: var(--line)"
          bind:value={slug}
          oninput={() => (slugTouched = true)}
          pattern="[a-z0-9][a-z0-9-]*"
          required
        />
        <span class="text-[11.5px]" style="color: var(--faint)">
          /r/{slug || '…'} — permanent once saved. Printed QR codes point at it.
        </span>
        {#if slugNotice}
          <span class="text-[12px]" style="color: var(--accent)">{slugNotice}</span>
        {/if}
      </label>
    {/if}

    <div class="grid grid-cols-2 gap-3">
      <label class="grid gap-1">
        <span class="{labelCls}" style="color: var(--primary)">Category</span>
        <select class={inputCls} style="border-color: var(--line)" bind:value={category}>
          {#each CATEGORY_ORDER as c (c)}
            <option value={c}>{c}</option>
          {/each}
        </select>
      </label>
      <label class="grid gap-1">
        <span class="{labelCls}" style="color: var(--primary)">Source</span>
        <input class={inputCls} style="border-color: var(--line)" bind:value={source} />
      </label>
    </div>

    <label class="grid gap-1">
      <span class="{labelCls}" style="color: var(--primary)">Meta line</span>
      <input class={inputCls} style="border-color: var(--line)" bind:value={meta} />
    </label>

    <div class="grid grid-cols-2 gap-3">
      <label class="grid gap-1">
        <span class="{labelCls}" style="color: var(--primary)">Base yield</span>
        <input
          type="number"
          min="1"
          class="{inputCls} font-mono-label"
          style="border-color: var(--line)"
          bind:value={base_yield}
        />
      </label>
      <label class="grid gap-1">
        <span class="{labelCls}" style="color: var(--primary)">Yield word</span>
        <input class={inputCls} style="border-color: var(--line)" bind:value={yield_word} />
      </label>
    </div>

    <div class="flex flex-wrap gap-5 pt-1">
      <label class="flex items-center gap-2 text-[14px]">
        <input type="checkbox" class="h-5 w-5" bind:checked={gf} />
        <span class="{labelCls}" style="color: var(--primary)">Gluten-free</span>
      </label>
      <label class="flex items-center gap-2 text-[14px]">
        <input type="checkbox" class="h-5 w-5" bind:checked={noscale} />
        <span class="{labelCls}" style="color: var(--primary)">Doesn't scale</span>
      </label>
      <label class="flex items-center gap-2 text-[14px]">
        <input type="checkbox" class="h-5 w-5" bind:checked={draft} />
        <span class="{labelCls}" style="color: var(--primary)">Keep as draft</span>
      </label>
    </div>

    {#if !creating}
      <label class="grid gap-1">
        <span class="{labelCls}" style="color: var(--primary)">Version label (optional)</span>
        <input
          class={inputCls}
          style="border-color: var(--line)"
          placeholder="e.g. overnight"
          bind:value={label}
        />
      </label>
    {/if}
  </section>

  <!-- Ingredients -->
  <h3
    class="font-mono-label mt-7 flex items-center justify-between border-b pb-1 text-xs uppercase tracking-widest"
    style="border-color: var(--line); color: var(--primary)"
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
            class="qty w-[5.5rem] shrink-0 rounded-lg border bg-[var(--card)] px-2 py-2 text-[15px] outline-none"
            style="border-color: var(--line)"
            bind:value={ing.amount}
          />
          <select
            aria-label="Unit"
            class="font-mono-label w-[4.5rem] shrink-0 rounded-lg border bg-[var(--card)] px-1 py-2 text-[13px] outline-none"
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
            class="min-w-0 flex-1 rounded-lg border bg-[var(--card)] px-2 py-2 text-[15px] outline-none"
            style="border-color: var(--line)"
            bind:value={ing.name}
          />
        </div>
        <div class="mt-2 flex gap-2">
          <input
            aria-label="Section"
            placeholder="section (optional)"
            class="min-w-0 flex-1 rounded-lg border bg-[var(--card)] px-2 py-1.5 text-[13px] outline-none"
            style="border-color: var(--line)"
            bind:value={ing.section}
          />
          <input
            aria-label="Note"
            placeholder="note (optional)"
            class="min-w-0 flex-1 rounded-lg border bg-[var(--card)] px-2 py-1.5 text-[13px] outline-none"
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
              style="border-color: var(--accent); color: var(--accent)"
              onclick={() => ingredients.splice(i, 1)}>✕</button
            >
          </div>
        </div>
      </li>
    {/each}
  </ul>
  <button
    type="button"
    class="{btnGhost} mt-2"
    style="border-color: var(--primary); color: var(--primary)"
    onclick={addIngredient}
  >
    + ingredient
  </button>

  <!-- Steps -->
  <h3
    class="font-mono-label mt-7 border-b pb-1 text-xs uppercase tracking-widest"
    style="border-color: var(--line); color: var(--primary)"
  >
    Method
  </h3>
  <ol class="mt-2 grid list-none gap-2 p-0">
    {#each steps as step, i (i)}
      <li class="rounded-xl border p-2.5" style="border-color: var(--line); background: var(--card)">
        <div class="flex gap-2">
          <span
            class="font-mono-label mt-1 flex h-[26px] w-[26px] shrink-0 items-center justify-center rounded-full border text-[12px]"
            style="border-color: var(--primary); color: var(--primary)">{i + 1}</span
          >
          <textarea
            aria-label="Step {i + 1}"
            rows="2"
            placeholder="step text — **Lead-in:** supported"
            class="min-w-0 flex-1 rounded-lg border bg-[var(--card)] px-2 py-2 text-[15px] outline-none"
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
            class="qty w-[6rem] rounded-lg border bg-[var(--card)] px-2 py-1.5 text-[14px] outline-none"
            style="border-color: var(--line)"
            bind:value={step.timer_seconds}
          />
          <div class="ml-auto flex shrink-0 gap-1">
            <button type="button" aria-label="Move up" class="h-9 w-9 rounded-lg border" style="border-color: var(--line)" onclick={() => move(steps, i, -1)}>↑</button>
            <button type="button" aria-label="Move down" class="h-9 w-9 rounded-lg border" style="border-color: var(--line)" onclick={() => move(steps, i, 1)}>↓</button>
            <button type="button" aria-label="Remove step" class="h-9 w-9 rounded-lg border" style="border-color: var(--accent); color: var(--accent)" onclick={() => steps.splice(i, 1)}>✕</button>
          </div>
        </div>
      </li>
    {/each}
  </ol>
  <button
    type="button"
    class="{btnGhost} mt-2"
    style="border-color: var(--primary); color: var(--primary)"
    onclick={addStep}
  >
    + step
  </button>

  <!-- Notes -->
  <h3
    class="font-mono-label mt-7 border-b pb-1 text-xs uppercase tracking-widest"
    style="border-color: var(--line); color: var(--primary)"
  >
    Notes
  </h3>
  <ul class="mt-2 grid list-none gap-2 p-0">
    {#each notes as _, i (i)}
      <li class="flex gap-2">
        <input
          aria-label="Note {i + 1}"
          placeholder="note — **Lead-in:** supported"
          class="min-w-0 flex-1 rounded-lg border bg-[var(--card)] px-2 py-2 text-[14px] outline-none"
          style="border-color: var(--line)"
          bind:value={notes[i]}
        />
        <button type="button" aria-label="Remove note" class="h-9 w-9 shrink-0 rounded-lg border" style="border-color: var(--accent); color: var(--accent)" onclick={() => notes.splice(i, 1)}>✕</button>
      </li>
    {/each}
  </ul>
  <button
    type="button"
    class="{btnGhost} mt-2"
    style="border-color: var(--primary); color: var(--primary)"
    onclick={addNote}
  >
    + note
  </button>

  <!-- Actions -->
  <div class="mt-8 flex gap-2">
    <button
      type="submit"
      disabled={saving}
      class="font-mono-label min-h-[48px] flex-1 rounded-full px-5 text-[12px] uppercase tracking-widest disabled:opacity-60"
      style="background: var(--primary-deep); color: var(--off-white)"
    >
      {saving ? 'Saving…' : submitLabel}
    </button>
    <a
      href={cancelHref}
      class="font-mono-label flex min-h-[48px] items-center rounded-full border px-5 text-[12px] uppercase tracking-widest no-underline"
      style="border-color: var(--ink-accent); color: var(--ink-accent)"
    >
      Cancel
    </a>
  </div>
</form>
