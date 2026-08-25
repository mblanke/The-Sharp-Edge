<script lang="ts">
  import { enhance } from '$app/forms';
  import { goto } from '$app/navigation';
  import type { PlanEntry } from '$lib/api';

  let { data, form } = $props();

  const plan = $derived(data.plan);
  const recipes = $derived(data.recipes);

  const MEALS = ['breakfast', 'lunch', 'dinner'] as const;
  const DAY_MS = 86_400_000;

  const days = $derived(
    Array.from({ length: 7 }, (_, i) => {
      const d = new Date(`${plan.week}T00:00:00`);
      return new Date(d.getTime() + i * DAY_MS);
    })
  );

  function iso(d: Date): string {
    return d.toISOString().slice(0, 10);
  }
  function dayLabel(d: Date): string {
    return d.toLocaleDateString('en-CA', { weekday: 'short', month: 'short', day: 'numeric' });
  }
  function entryFor(d: Date, meal: string): PlanEntry | undefined {
    return plan.entries.find((e) => e.date === iso(d) && e.meal === meal);
  }
  function shiftWeek(delta: number) {
    const monday = new Date(`${plan.week}T00:00:00`);
    const next = new Date(monday.getTime() + delta * 7 * DAY_MS);
    goto(`/plan?week=${iso(next)}`, { invalidateAll: true });
  }

  // recipe picker state: which (date, meal) slot is open
  let picker = $state<{ date: string; meal: string } | null>(null);

  const labelCls = 'font-mono-label text-[10.5px] uppercase tracking-widest';
</script>

<svelte:head>
  <title>Meal plan — The Sharp Edge</title>
</svelte:head>

<section class="pt-7 pb-16">
  <div class={labelCls} style="color: var(--copper)">Week of</div>
  <div class="mt-1 flex items-center gap-3">
    <h2 class="font-display text-[clamp(24px,5.6vw,32px)] leading-tight">
      {new Date(`${plan.week}T00:00:00`).toLocaleDateString('en-CA', { month: 'long', day: 'numeric' })}
    </h2>
    <div class="ml-auto flex gap-1">
      <button aria-label="Previous week" class="h-11 w-11 rounded-xl border" style="border-color: var(--line); color: var(--green-deep)" onclick={() => shiftWeek(-1)}>←</button>
      <button aria-label="Next week" class="h-11 w-11 rounded-xl border" style="border-color: var(--line); color: var(--green-deep)" onclick={() => shiftWeek(1)}>→</button>
    </div>
  </div>

  {#if form?.message}
    <p class="mt-3 rounded-lg border px-3 py-2 text-[13.5px]" style="border-color: var(--copper); color: var(--copper); background: var(--warn-bg)">
      {form.message}
    </p>
  {/if}

  <!-- week grid -->
  <div class="mt-5 grid gap-2">
    {#each days as day (iso(day))}
      {@const dayEntries = plan.entries.filter((e) => e.date === iso(day))}
      <div class="rounded-2xl border p-3" style="border-color: var(--line); background: var(--card)">
        <div class="flex items-baseline gap-2">
          <div class={labelCls} style="color: var(--green)">{dayLabel(day)}</div>
          {#if dayEntries.length >= 2}
            <a
              href="/cook-together?slugs={dayEntries.map((e) => e.recipe_slug).join(',')}"
              class="{labelCls} ml-auto no-underline"
              style="color: var(--copper)"
            >
              cook together →
            </a>
          {/if}
        </div>
        <div class="mt-1.5 grid gap-1.5">
          {#each MEALS as meal (meal)}
            {@const entry = entryFor(day, meal)}
            {#if entry}
              <div class="flex min-h-[44px] items-center gap-2 rounded-xl px-3 py-1.5" style="background: var(--paper)">
                <span class="{labelCls} w-[4.6rem] shrink-0" style="color: var(--faint)">{meal}</span>
                <a href="/r/{entry.recipe_slug}" class="min-w-0 flex-1 truncate text-[14.5px] no-underline" style="color: var(--green-deep)">
                  {entry.recipe_title}
                </a>
                <span class="qty text-[12px]" style="color: var(--faint)">×{entry.scaled_yield}</span>
                {#if entry.gf}
                  <span class="font-mono-label rounded-full px-2 py-0.5 text-[9.5px] uppercase" style="background: var(--green); color: #F4F3EC">GF</span>
                {/if}
                <form method="POST" action="?/remove" use:enhance>
                  <input type="hidden" name="entry_id" value={entry.id} />
                  <button aria-label="Remove {entry.recipe_title}" class="h-9 w-9 rounded-lg" style="color: var(--copper)">✕</button>
                </form>
              </div>
            {:else if meal === 'dinner' || picker?.date === iso(day)}
              <button
                class="font-mono-label flex min-h-[44px] items-center gap-2 rounded-xl border border-dashed px-3 text-[11px] uppercase tracking-widest"
                style="border-color: var(--line); color: var(--faint)"
                onclick={() => (picker = picker?.date === iso(day) && picker.meal === meal ? null : { date: iso(day), meal })}
              >
                + {meal}
              </button>
            {/if}
          {/each}
          {#if !picker || picker.date !== iso(day)}
            <button
              class="{labelCls} justify-self-start px-3 py-1"
              style="color: var(--faint)"
              onclick={() => (picker = { date: iso(day), meal: 'breakfast' })}
            >
              more meals…
            </button>
          {/if}
        </div>

        {#if picker?.date === iso(day)}
          <div class="mt-2 max-h-[40vh] overflow-y-auto rounded-xl border p-2" style="border-color: var(--green); background: var(--paper)">
            <div class="{labelCls} px-2 pb-1" style="color: var(--copper)">
              add to {picker.meal} · {dayLabel(day)}
            </div>
            {#each recipes.filter((r) => !r.noscale) as r (r.slug)}
              <form method="POST" action="?/add" use:enhance={() => async ({ update }) => {
                picker = null;
                await update();
              }}>
                <input type="hidden" name="date" value={picker.date} />
                <input type="hidden" name="meal" value={picker.meal} />
                <input type="hidden" name="recipe_slug" value={r.slug} />
                <button class="flex min-h-[44px] w-full items-center gap-2 rounded-lg px-2 text-left text-[14px] hover:bg-white">
                  <span class="min-w-0 flex-1 truncate">{r.title}</span>
                  {#if r.gf}
                    <span class="font-mono-label rounded-full px-2 py-0.5 text-[9.5px] uppercase" style="background: var(--green); color: #F4F3EC">GF</span>
                  {/if}
                </button>
              </form>
            {/each}
          </div>
        {/if}
      </div>
    {/each}
  </div>

  <!-- shopping hand-off: one running list, shared with the iPad app -->
  <div class="mt-8 flex items-center justify-between border-b pb-1" style="border-color: var(--line)">
    <h3 class="font-mono-label text-xs uppercase tracking-widest" style="color: var(--green)">
      Shopping
    </h3>
    <div class="flex items-center gap-2">
      <a
        href="/shopping"
        class="font-mono-label min-h-[44px] rounded-full border px-4 py-2.5 text-[11px] uppercase tracking-widest no-underline"
        style="border-color: var(--line); color: var(--green-deep)"
      >
        open the list
      </a>
      <form method="POST" action="?/generate" use:enhance>
        <input type="hidden" name="week" value={plan.week} />
        <button
          class="font-mono-label min-h-[44px] rounded-full px-5 text-[11px] uppercase tracking-widest"
          style="background: var(--green-deep); color: #F4F3EC"
          data-testid="generate-list"
        >
          add week to list
        </button>
      </form>
    </div>
  </div>
  <p class="mt-2 text-[12.5px]" style="color: var(--faint)">
    Adds every planned recipe at its scale to the running list — quantities merge into
    existing lines, and the same list shows up in the iPad app.
  </p>
</section>
