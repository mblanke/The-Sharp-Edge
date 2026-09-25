<script lang="ts">
  import { formatDuration } from '$lib/cook';
  import { active, isDone, isRunning, remaining, timerStore, type CookTimer } from '$lib/timers';

  /** `compact` = the strip inside cook mode; otherwise the floating tray on every page. */
  let { compact = false, exclude = '' }: { compact?: boolean; exclude?: string } = $props();

  const now = timerStore.now;
  const rows = $derived(active($timerStore, $now).filter((t) => t.id !== exclude));

  function label(t: CookTimer): string {
    return `${t.title} · step ${t.step + 1}`;
  }
  function href(t: CookTimer): string {
    return `/r/${t.slug}/cook?step=${t.step + 1}`;
  }
</script>

{#if rows.length}
  <div
    class={compact
      ? 'mx-5 mb-1 flex flex-col gap-1'
      : 'fixed inset-x-0 z-[60] flex flex-col gap-1 border-t px-3 pt-2 pb-2 md:pb-[max(env(safe-area-inset-bottom),8px)]'}
    style={compact ? '' : 'background: var(--card); border-color: var(--line); bottom: var(--bottom-inset, 0px)'}
    role="region"
    aria-label="Running timers"
    data-testid="timer-tray"
  >
    {#each rows as t (t.id)}
      {@const done = isDone(t, $now)}
      <div
        class="flex min-h-[44px] items-center gap-3 rounded-xl border px-3 text-[13px]"
        style="border-color: {done ? 'var(--copper)' : 'var(--line)'}; background: var(--card)"
        data-testid="timer-row"
      >
        <a
          href={href(t)}
          class="font-mono-label min-w-0 flex-1 truncate text-[11px] uppercase tracking-widest no-underline"
          style="color: {done ? 'var(--copper)' : 'var(--faint)'}"
        >
          {label(t)}
        </a>
        <span
          class="qty text-[17px]"
          style="color: {done ? 'var(--copper)' : 'var(--ink-accent)'}"
          aria-live={done ? 'assertive' : 'off'}
        >
          {done ? 'done' : formatDuration(remaining(t, $now))}
        </span>
        {#if !done}
          <button
            class="font-mono-label min-h-[40px] rounded-full border px-3 text-[10.5px] uppercase tracking-widest"
            style="border-color: var(--line); color: var(--ink-accent)"
            onclick={() => (isRunning(t) ? timerStore.pause(t.id) : timerStore.start(t.id))}
            aria-label={isRunning(t) ? `Pause ${label(t)}` : `Resume ${label(t)}`}
          >
            {isRunning(t) ? 'pause' : 'resume'}
          </button>
        {/if}
        <button
          class="font-mono-label min-h-[40px] min-w-[40px] rounded-full border text-[13px]"
          style="border-color: var(--line); color: var(--faint)"
          onclick={() => timerStore.remove(t.id)}
          aria-label={`Dismiss ${label(t)}`}
        >
          ✕
        </button>
      </div>
    {/each}
  </div>
{/if}
