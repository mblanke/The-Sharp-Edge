<script module lang="ts">
  /** `g` then a letter: section jumps, Gmail-style. Exported for the test. */
  export const JUMPS: Record<string, { href: string; label: string }> = {
    r: { href: '/', label: 'Recipes' },
    l: { href: '/library', label: 'Library' },
    a: { href: '/ask', label: 'Ask' },
    p: { href: '/plan', label: 'Plan' },
    s: { href: '/shopping', label: 'Shopping list' },
    n: { href: '/new', label: 'Add a recipe' }
  };

  /** Typing in a field must never trigger a shortcut. */
  export function isTyping(target: EventTarget | null): boolean {
    const el = target as HTMLElement | null;
    if (!el) return false;
    const tag = el.tagName;
    return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || el.isContentEditable === true;
  }
</script>

<script lang="ts">
  import { tick } from 'svelte';
  import { goto } from '$app/navigation';

  let { inCookMode = false }: { inCookMode?: boolean } = $props();

  let open = $state(false);
  let sheetEl = $state<HTMLDivElement | null>(null);
  let lastFocus: HTMLElement | null = null;

  // a pending `g` waits one second for its letter
  let leader = false;
  let leaderTimer: ReturnType<typeof setTimeout> | undefined;

  async function show() {
    lastFocus = document.activeElement as HTMLElement | null;
    open = true;
    await tick();
    sheetEl?.focus();
  }
  function hide() {
    open = false;
    lastFocus?.focus?.();
    lastFocus = null;
  }

  function onKey(e: KeyboardEvent) {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (open) {
      if (e.key === 'Escape' || e.key === '?') {
        e.preventDefault();
        hide();
      }
      return;
    }
    if (isTyping(e.target)) return;
    // cook mode owns its single keys (space, t, i, arrows); only `?` reaches it
    if (e.key === '?') {
      e.preventDefault();
      show();
      return;
    }
    if (inCookMode) return;
    if (leader) {
      leader = false;
      clearTimeout(leaderTimer);
      const jump = JUMPS[e.key.toLowerCase()];
      if (jump) {
        e.preventDefault();
        goto(jump.href);
      }
      return;
    }
    if (e.key === 'g') {
      leader = true;
      leaderTimer = setTimeout(() => (leader = false), 1000);
    }
  }
</script>

<svelte:window onkeydown={onKey} />

{#if open}
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div class="keys-backdrop" onclick={hide} data-testid="shortcuts">
    <div
      class="keys-sheet outline-none"
      role="dialog"
      aria-modal="true"
      aria-labelledby="keys-title"
      tabindex="-1"
      bind:this={sheetEl}
      onclick={(e) => e.stopPropagation()}
    >
      <div class="flex items-baseline justify-between gap-3">
        <h2 id="keys-title" class="font-display text-[24px]" style="color: var(--ink)">Keyboard</h2>
        <button
          class="font-mono-label min-h-[40px] rounded-full border px-3 text-[10.5px] uppercase tracking-widest"
          style="border-color: var(--line); color: var(--faint)"
          onclick={hide}
        >
          close
        </button>
      </div>

      <h3 class="font-mono-label mt-4 text-[10.5px] uppercase tracking-widest" style="color: var(--green)">Anywhere</h3>
      <dl>
        <dt><kbd>⌘</kbd><kbd>K</kbd></dt>
        <dd>find a recipe</dd>
        {#each Object.entries(JUMPS) as [key, jump] (key)}
          <dt><kbd>g</kbd><kbd>{key}</kbd></dt>
          <dd>{jump.label}</dd>
        {/each}
        <dt><kbd>?</kbd></dt>
        <dd>this sheet</dd>
      </dl>

      <h3 class="font-mono-label mt-5 text-[10.5px] uppercase tracking-widest" style="color: var(--green)">Cook mode</h3>
      <dl>
        <dt><kbd>→</kbd><kbd>space</kbd></dt>
        <dd>next step</dd>
        <dt><kbd>←</kbd></dt>
        <dd>previous step</dd>
        <dt><kbd>⌘</kbd><kbd>Z</kbd></dt>
        <dd>undo a step change</dd>
        <dt><kbd>t</kbd></dt>
        <dd>start or pause the step timer</dd>
        <dt><kbd>i</kbd></dt>
        <dd>all ingredients</dd>
        <dt><kbd>+</kbd><kbd>−</kbd></dt>
        <dd>text size</dd>
        <dt><kbd>esc</kbd></dt>
        <dd>close, then leave cook mode</dd>
      </dl>
    </div>
  </div>
{/if}
