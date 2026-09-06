<script lang="ts">
  import { onMount } from 'svelte';

  // Opened recipes cook offline (service worker); ask, plan, shopping and the
  // library need the server. Say so, instead of letting a tap silently fail.
  let offline = $state(false);
  onMount(() => {
    const sync = () => (offline = !navigator.onLine);
    sync();
    window.addEventListener('online', sync);
    window.addEventListener('offline', sync);
    return () => {
      window.removeEventListener('online', sync);
      window.removeEventListener('offline', sync);
    };
  });
</script>

{#if offline}
  <p
    class="font-mono-label mt-3 rounded-full border px-4 py-2 text-center text-[10.5px] uppercase tracking-widest"
    style="border-color: var(--copper); color: var(--copper); background: var(--warn-bg)"
    role="status"
    data-testid="offline-banner"
  >
    offline — opened recipes still cook · ask, plan, list and library need the server
  </p>
{/if}
