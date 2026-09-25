<script lang="ts">
  import { dismiss, toastStore } from '$lib/toast';

  const colour = (kind: string) =>
    kind === 'error' ? 'var(--copper)' : kind === 'success' ? 'var(--green-deep)' : 'var(--faint)';
</script>

{#each $toastStore as t (t.id)}
  <div
    class="fixed inset-x-0 z-[70] flex justify-center px-4"
    style="bottom: max(calc(var(--bottom-inset, 0px) + 12px), env(safe-area-inset-bottom))"
    role={t.kind === 'error' ? 'alert' : 'status'}
    aria-live={t.kind === 'error' ? 'assertive' : 'polite'}
    data-testid="toast"
  >
    <div
      class="flex max-w-md items-center gap-3 rounded-full border py-2 pr-2 pl-4 text-[13.5px] shadow-lg"
      style="background: var(--card); border-color: {colour(t.kind)}; color: var(--ink)"
    >
      <span class="min-w-0">{t.text}</span>
      {#if t.action}
        <button
          class="font-mono-label min-h-[40px] shrink-0 rounded-full border px-3 text-[10.5px] uppercase tracking-widest"
          style="border-color: var(--line); color: var(--ink-accent)"
          onclick={async () => {
            const id = t.id;
            await t.action?.run();
            dismiss(id);
          }}
          data-testid="toast-action"
        >
          {t.action.label}
        </button>
      {:else if t.href}
        <a
          href={t.href.url}
          class="font-mono-label min-h-[40px] shrink-0 rounded-full border px-3 text-[10.5px] uppercase tracking-widest no-underline leading-[40px]"
          style="border-color: var(--line); color: var(--ink-accent)"
          onclick={() => dismiss(t.id)}
        >
          {t.href.label}
        </a>
      {/if}
      <button
        class="min-h-[40px] min-w-[40px] shrink-0 rounded-full text-[13px]"
        style="color: var(--faint)"
        aria-label="Dismiss"
        onclick={() => dismiss(t.id)}
      >
        ✕
      </button>
    </div>
  </div>
{/each}
