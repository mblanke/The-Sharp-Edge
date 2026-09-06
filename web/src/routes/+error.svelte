<script lang="ts">
  import { page } from '$app/state';

  const status = $derived(page.status);
  const title = $derived(
    status === 404 ? 'No such page.' : status >= 500 ? 'The server is not answering.' : 'Something went wrong.'
  );
  const hint = $derived(
    status === 404
      ? 'A recipe card QR always points at a slug that exists, so this is probably a typo.'
      : status >= 500
        ? 'Recipes you have opened before still work offline. Everything else needs the server back.'
        : (page.error?.message ?? '')
  );
</script>

<svelte:head>
  <title>{status} — The Sharp Edge</title>
</svelte:head>

<section class="pt-12 text-center" data-testid="error-page">
  <div class="font-display text-[clamp(56px,14vw,96px)] leading-none" style="color: var(--line)">
    {status}
  </div>
  <h2 class="font-display mt-2 text-[clamp(22px,5vw,30px)]" style="color: var(--ink)">{title}</h2>
  {#if hint}
    <p class="mx-auto mt-2 max-w-[44ch] text-[14.5px]" style="color: var(--faint)">{hint}</p>
  {/if}
  <div class="mt-6 flex flex-wrap justify-center gap-2">
    <a
      href="/"
      class="font-mono-label inline-block min-h-[44px] rounded-full px-5 py-2.5 text-[11px] uppercase tracking-widest no-underline"
      style="background: var(--green-deep); color: #F4F3EC"
    >
      ← all recipes
    </a>
    <button
      class="font-mono-label min-h-[44px] rounded-full border px-5 py-2.5 text-[11px] uppercase tracking-widest"
      style="border-color: var(--line); color: var(--faint)"
      onclick={() => location.reload()}
    >
      try again
    </button>
  </div>
</section>
