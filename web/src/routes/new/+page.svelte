<script lang="ts">
  import RecipeForm from '$lib/components/RecipeForm.svelte';
  import {
    CAPTURE_LANGUAGES,
    WEB_SPEECH_NOTICE,
    listen,
    speechSupported,
    splitUtterances,
    type CaptureLanguage,
    type SpeechHandle
  } from '$lib/voice';
  import type { Ingredient, Step } from '$lib/types';

  let { form } = $props();

  // Dictation fills the same form the typed path uses — there is no parallel flow.
  // The review step is the entire answer to imperfect dictation, so nothing here
  // saves directly.
  let lang = $state<CaptureLanguage>('en');
  let panelOpen = $state(false);
  let listening = $state<'title' | 'category' | 'ingredients' | 'method' | null>(null);
  let handle: SpeechHandle | null = null;
  let building = $state(false);
  let captureError = $state<string | null>(null);

  let heard = $state({ title: '', category: '', ingredients: '', method: '' });
  let seed = $state<
    | { title: string; category: string; ingredients: Ingredient[]; steps: Step[] }
    | undefined
  >(undefined);
  let formKey = $state(0);

  const supported = speechSupported();

  function toggle(field: 'title' | 'category' | 'ingredients' | 'method') {
    if (listening === field) {
      handle?.stop();
      return;
    }
    handle?.stop();
    captureError = null;
    listening = field;
    handle = listen(
      lang,
      (text) => {
        heard[field] =
          field === 'ingredients' || field === 'method'
            ? splitUtterances(text).join('\n')
            : text;
      },
      (error) => {
        listening = null;
        handle = null;
        if (error) captureError = `Dictation stopped: ${error}`;
      }
    );
    if (!handle) {
      listening = null;
      captureError = 'This browser has no speech recognition. Type the recipe instead.';
    }
  }

  async function review() {
    handle?.stop();
    building = true;
    captureError = null;
    try {
      const lines = heard.ingredients.split('\n').filter((l) => l.trim());
      const [parsed, matched] = await Promise.all([
        lines.length
          ? fetch('/api/parse/ingredients', {
              method: 'POST',
              headers: { 'content-type': 'application/json' },
              body: JSON.stringify({ lines, lang })
            }).then((r) => (r.ok ? r.json() : { ingredients: [] }))
          : Promise.resolve({ ingredients: [] }),
        heard.category.trim()
          ? fetch('/api/parse/category', {
              method: 'POST',
              headers: { 'content-type': 'application/json' },
              body: JSON.stringify({ spoken: heard.category, lang })
            }).then((r) => (r.ok ? r.json() : { category: null }))
          : Promise.resolve({ category: null })
      ]);

      seed = {
        title: heard.title.trim(),
        category: matched.category ?? '',
        ingredients: parsed.ingredients ?? [],
        steps: splitUtterances(heard.method).map((text) => ({ text }))
      };
      formKey += 1;
      panelOpen = false;
    } catch {
      captureError = 'Could not reach the parser. Type the recipe instead.';
    } finally {
      building = false;
    }
  }

  const labelCls = 'font-mono-label text-[10.5px] uppercase tracking-widest';
  const prompts = [
    { field: 'title' as const, prompt: "What's it called?", rows: 1 },
    { field: 'category' as const, prompt: 'What kind of recipe?', rows: 1 },
    { field: 'ingredients' as const, prompt: 'What goes in it?', rows: 5 },
    { field: 'method' as const, prompt: 'How do you make it?', rows: 5 }
  ];
</script>

<svelte:head>
  <title>Add a recipe — The Sharp Edge</title>
</svelte:head>

<div class="pt-7">
  <button
    type="button"
    class="font-mono-label min-h-[44px] w-full rounded-full border px-4 text-[11px] uppercase tracking-widest"
    style="border-color: var(--primary); color: var(--primary)"
    onclick={() => (panelOpen = !panelOpen)}
  >
    {panelOpen ? '× close dictation' : '🎙 dictate it instead'}
  </button>

  {#if panelOpen}
    <section
      class="mt-3 rounded-xl border p-3"
      style="border-color: var(--line); background: var(--card)"
    >
      <div class="flex flex-wrap gap-2">
        {#each CAPTURE_LANGUAGES as l (l.code)}
          <button
            type="button"
            class="font-mono-label min-h-[38px] rounded-full border px-3 text-[11px]"
            style="border-color: {lang === l.code
              ? 'var(--primary-deep)'
              : 'var(--line)'}; background: {lang === l.code
              ? 'var(--primary-deep)'
              : 'transparent'}; color: {lang === l.code
              ? 'var(--off-white)'
              : 'var(--primary-deep)'}"
            onclick={() => (lang = l.code)}
          >
            {l.flag} {l.name}
          </button>
        {/each}
      </div>

      <p class="mt-2 text-[11.5px]" style="color: var(--faint)">{WEB_SPEECH_NOTICE}</p>

      {#each prompts as p (p.field)}
        <div class="mt-3 grid gap-1">
          <div class="flex items-center justify-between">
            <span class="{labelCls}" style="color: var(--primary)">{p.prompt}</span>
            <button
              type="button"
              class="font-mono-label min-h-[36px] rounded-full border px-3 text-[10.5px] uppercase tracking-widest"
              style="border-color: {listening === p.field
                ? 'var(--accent)'
                : 'var(--line)'}; color: {listening === p.field
                ? 'var(--accent)'
                : 'var(--primary-deep)'}"
              disabled={!supported}
              onclick={() => toggle(p.field)}
            >
              {listening === p.field ? '■ stop' : '● speak'}
            </button>
          </div>
          <textarea
            rows={p.rows}
            class="w-full rounded-lg border px-2 py-2 text-[14px] outline-none"
            style="border-color: var(--line); background: var(--paper)"
            bind:value={heard[p.field]}
          ></textarea>
        </div>
      {/each}

      {#if captureError}
        <p class="mt-2 text-[12.5px]" style="color: var(--accent)">{captureError}</p>
      {/if}

      <button
        type="button"
        disabled={building || !heard.title.trim()}
        class="font-mono-label mt-4 min-h-[44px] w-full rounded-full px-4 text-[11px] uppercase tracking-widest disabled:opacity-60"
        style="background: var(--primary-deep); color: var(--off-white)"
        onclick={review}
      >
        {building ? 'Reading it back…' : 'Review recipe'}
      </button>
    </section>
  {/if}
</div>

{#key formKey}
  <RecipeForm
    mode="create"
    initial={seed}
    {form}
    eyebrow="New recipe"
    heading={seed?.title || 'Add a recipe'}
    submitLabel="Create recipe"
    cancelHref="/"
  />
{/key}
