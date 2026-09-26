<script lang="ts">
  import { onMount } from 'svelte';
  import { UNIT_SYSTEMS, type UnitSystem } from '$lib/scaling';
  import { notify } from '$lib/toast';
  import { applyTheme, forgetRecipeState, KEYS, read, readTheme, readUnits, write, type Theme } from '$lib/prefs';

  let theme = $state<Theme>('system');
  let units = $state<UnitSystem>('recipe');
  let cookText = $state(1);
  let cached = $state<number | null>(null);
  let swVersion = $state('');

  const THEMES: { id: Theme; label: string }[] = [
    { id: 'system', label: 'follow the device' },
    { id: 'light', label: 'daylight' },
    { id: 'dark', label: 'evening kitchen' }
  ];
  const UNIT_LABEL: Record<UnitSystem, string> = { recipe: 'as written', metric: 'metric', imperial: 'imperial' };
  const TEXT = ['smaller', 'normal', 'larger', 'largest'];

  onMount(() => {
    theme = readTheme();
    units = readUnits();
    const t = Number(read(KEYS.cookText));
    cookText = Number.isInteger(t) && t >= 0 && t < TEXT.length ? t : 1;
    void countCache();
  });

  async function countCache() {
    try {
      const keys = await caches.keys();
      let n = 0;
      for (const k of keys) {
        if (!k.startsWith('sharp-edge-rt-')) continue;
        swVersion = k.replace('sharp-edge-rt-', '');
        n += (await (await caches.open(k)).keys()).length;
      }
      cached = n;
    } catch {
      cached = null;
    }
  }

  async function clearCache() {
    try {
      const keys = await caches.keys();
      for (const k of keys) if (k.startsWith('sharp-edge-rt-')) await caches.delete(k);
      await countCache();
      notify.ok('Offline copies cleared — open a recipe to cache it again');
    } catch {
      notify.error('Could not clear the cache');
    }
  }

  function setTheme(t: Theme) {
    theme = t;
    applyTheme(t);
  }
  function setUnits(u: UnitSystem) {
    units = u;
    write(KEYS.units, u);
  }
  function setText(i: number) {
    cookText = i;
    write(KEYS.cookText, String(i));
  }
  function forget() {
    const n = forgetRecipeState();
    notify.ok(n ? `Forgot ticks and positions for ${n} ${n === 1 ? 'recipe' : 'recipes'}` : 'Nothing to forget');
  }

  const labelCls = 'font-mono-label text-[11px] uppercase tracking-widest';
  const pill = (on: boolean) =>
    on
      ? 'background: var(--green-deep); border-color: var(--green-deep); color: #F4F3EC'
      : 'border-color: var(--line); color: var(--faint)';
</script>

<svelte:head><title>Settings — The Sharp Edge</title></svelte:head>

<section class="pt-7 pb-10">
  <div class={labelCls} style="color: var(--copper)">This device</div>
  <h2 class="font-display mt-1 text-[clamp(24px,5.6vw,32px)] leading-tight">Settings</h2>
  <p class="mt-1 text-[13.5px]" style="color: var(--faint)">
    Preferences live on this device. The recipes, the list and the plan live on the server.
  </p>

  <h3 class="{labelCls} mt-8 border-b pb-1" style="border-color: var(--line); color: var(--green)">Theme</h3>
  <div class="mt-3 flex flex-wrap gap-2" role="group" aria-label="Theme">
    {#each THEMES as t (t.id)}
      <button
        class="font-mono-label min-h-[44px] rounded-full border px-4 text-[11px] uppercase tracking-widest"
        style={pill(theme === t.id)}
        aria-pressed={theme === t.id}
        onclick={() => setTheme(t.id)}
        data-testid="theme-{t.id}"
      >
        {t.label}
      </button>
    {/each}
  </div>
  <p class="mt-2 text-[12.5px]" style="color: var(--faint)">
    Cook mode goes dark on its own in the evening unless you have chosen daylight.
  </p>

  <h3 class="{labelCls} mt-8 border-b pb-1" style="border-color: var(--line); color: var(--green)">Amounts</h3>
  <div class="mt-3 flex flex-wrap gap-2" role="group" aria-label="Units">
    {#each UNIT_SYSTEMS as u (u)}
      <button
        class="font-mono-label min-h-[44px] rounded-full border px-4 text-[11px] uppercase tracking-widest"
        style={pill(units === u)}
        aria-pressed={units === u}
        onclick={() => setUnits(u)}
        data-testid="units-{u}"
      >
        {UNIT_LABEL[u]}
      </button>
    {/each}
  </div>
  <p class="mt-2 text-[12.5px]" style="color: var(--faint)">
    A reading lens over the scaled amounts. The recipe, the shopping list and the printed cards keep the units they were written in.
  </p>

  <h3 class="{labelCls} mt-8 border-b pb-1" style="border-color: var(--line); color: var(--green)">Cook mode text</h3>
  <div class="mt-3 flex flex-wrap gap-2" role="group" aria-label="Cook mode text size">
    {#each TEXT as label, i (label)}
      <button
        class="font-mono-label min-h-[44px] rounded-full border px-4 text-[11px] uppercase tracking-widest"
        style={pill(cookText === i)}
        aria-pressed={cookText === i}
        onclick={() => setText(i)}
      >
        {label}
      </button>
    {/each}
  </div>

  <h3 class="{labelCls} mt-8 border-b pb-1" style="border-color: var(--line); color: var(--green)">Offline</h3>
  <p class="mt-3 text-[13.5px]" style="color: var(--ink)">
    {#if cached === null}
      Offline copies are not available in this browser.
    {:else}
      <span class="qty">{cached}</span> cached {cached === 1 ? 'entry' : 'entries'} — opened recipes and their data, ready without the server.
      {#if swVersion}<span class="qty text-[11px]" style="color: var(--faint)"> · build {swVersion.slice(0, 10)}</span>{/if}
    {/if}
  </p>
  <div class="mt-3 flex flex-wrap gap-2">
    <button
      class="font-mono-label min-h-[44px] rounded-full border px-4 text-[11px] uppercase tracking-widest"
      style="border-color: var(--line); color: var(--faint)"
      onclick={clearCache}
      disabled={cached === null}
    >
      clear offline copies
    </button>
    <button
      class="font-mono-label min-h-[44px] rounded-full border px-4 text-[11px] uppercase tracking-widest"
      style="border-color: var(--line); color: var(--faint)"
      onclick={forget}
    >
      forget ticks &amp; cook positions
    </button>
  </div>

  <h3 class="{labelCls} mt-8 border-b pb-1" style="border-color: var(--line); color: var(--green)">Keyboard</h3>
  <ul class="mt-3 list-none p-0 text-[13.5px]" style="color: var(--faint)">
    <li class="py-1"><span class="qty" style="color: var(--ink)">⌘K</span> · find a recipe from anywhere</li>
    <li class="py-1"><span class="qty" style="color: var(--ink)">← → space</span> · move between steps in cook mode</li>
    <li class="py-1"><span class="qty" style="color: var(--ink)">T</span> · start or pause the step timer · <span class="qty" style="color: var(--ink)">I</span> · ingredients · <span class="qty" style="color: var(--ink)">Esc</span> · exit</li>
    <li class="py-1"><span class="qty" style="color: var(--ink)">⌘Z</span> · undo a stray step</li>
    <li class="py-1"><span class="qty" style="color: var(--ink)">g</span> then <span class="qty" style="color: var(--ink)">r l a p s n</span> · jump to recipes, library, ask, plan, list, add</li>
    <li class="py-1"><span class="qty" style="color: var(--ink)">?</span> · every shortcut, on any page</li>
  </ul>
</section>
