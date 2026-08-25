<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { chime, createCountdown, formatDuration, matchIngredients, type Countdown } from '$lib/cook';
  import { listen, parseCommand, speak, type VoiceListener } from '$lib/voice';
  import { keepAwake, type WakeLockHandle } from '$lib/wakelock';

  let { data } = $props();

  const recipe = $derived(data.recipe);
  const steps = $derived(data.recipe.current_version.steps);
  const scaled = $derived(data.scaled);

  let stepIndex = $state(0);
  const finished = $derived(stepIndex >= steps.length);
  let drawerOpen = $state(false);

  // --- timers: one per step with timer_seconds, created lazily, survive navigation ---
  const timers = new Map<number, Countdown>();
  let chimed = new Set<number>();
  let tick = $state(0); // 1 Hz re-render driver for countdown text
  let interval: ReturnType<typeof setInterval> | undefined;

  function timerFor(i: number): Countdown | null {
    const secs = steps[i]?.timer_seconds;
    if (!secs) return null;
    if (!timers.has(i)) timers.set(i, createCountdown(secs));
    return timers.get(i)!;
  }

  // --- wake lock + session start stamp ---
  let wake: WakeLockHandle | null = null;
  let startedAt = $state('');
  // evening cooks default to kitchen-dark unless the cook chose a theme
  let themeWasForced = false;
  onMount(() => {
    startedAt = new Date().toISOString();
    try {
      const hour = new Date().getHours();
      const chosen = localStorage.getItem('sharp-edge-theme');
      if (!chosen && (hour >= 18 || hour < 7) && !document.documentElement.dataset.theme) {
        document.documentElement.dataset.theme = 'dark';
        themeWasForced = true;
      }
    } catch {
      // storage blocked — stay on the current theme
    }
    wake = keepAwake();
    interval = setInterval(() => {
      tick++;
      for (const [i, t] of timers) {
        if (t.running && t.done() && !chimed.has(i)) {
          chimed.add(i);
          chime();
        }
      }
    }, 500);
  });
  onDestroy(() => {
    wake?.release();
    voice?.stop();
    clearInterval(interval);
    if (themeWasForced) document.documentElement.dataset.theme = '';
  });

  function go(delta: number) {
    stepIndex = Math.min(steps.length, Math.max(0, stepIndex + delta));
  }

  // --- voice control (F1): on-device recognition, nothing leaves the browser ---
  let voice: VoiceListener | null = null;
  let voiceOn = $state(false);
  let voiceHeard = $state('');
  const voiceAvailable =
    typeof window !== 'undefined' &&
    ('SpeechRecognition' in window || 'webkitSpeechRecognition' in window);

  function onVoice(transcript: string) {
    voiceHeard = transcript.trim();
    const intent = parseCommand(transcript, scaled);
    if (!intent) return;
    if (intent.type === 'next') go(1);
    else if (intent.type === 'back') go(-1);
    else if (intent.type === 'repeat' && !finished) speak(steps[stepIndex].text.replace(/\*\*/g, ''));
    else if (intent.type === 'how-much') {
      const ing = scaled[intent.ingredient];
      speak(`${ing.display === '—' ? 'to taste' : ing.display} ${ing.name.split(',')[0]}`);
    } else {
      const t = timerFor(stepIndex);
      if (!t) return;
      if (intent.type === 'timer-start') {
        chimed.delete(stepIndex);
        t.start();
      } else if (intent.type === 'timer-pause') t.pause();
      else if (intent.type === 'timer-reset') {
        t.reset();
        chimed.delete(stepIndex);
      }
      tick++;
    }
  }

  function toggleVoice() {
    if (voiceOn) {
      voice?.stop();
      voice = null;
      voiceOn = false;
      return;
    }
    voice = listen(onVoice);
    voiceOn = voice.supported;
    if (!voice.supported) voiceHeard = 'voice not available on this device';
  }

  // --- tap zones + swipe ---
  let touchX: number | null = null;
  function onTouchStart(e: TouchEvent) {
    touchX = e.touches[0]?.clientX ?? null;
  }
  function onTouchEnd(e: TouchEvent) {
    if (touchX === null) return;
    const dx = (e.changedTouches[0]?.clientX ?? touchX) - touchX;
    if (Math.abs(dx) > 60) go(dx < 0 ? 1 : -1);
    touchX = null;
  }
  function onTap(e: MouseEvent) {
    if (finished || drawerOpen) return;
    const target = e.target as HTMLElement;
    if (target.closest('button, a')) return;
    const x = e.clientX / window.innerWidth;
    if (x < 0.33) go(-1);
    else if (x > 0.67) go(1);
  }
  function onKey(e: KeyboardEvent) {
    if (e.key === 'ArrowRight' || e.key === ' ') go(1);
    if (e.key === 'ArrowLeft') go(-1);
  }

  /** Renders "**Lead-in:** rest" bold markers. */
  function boldParts(text: string): Array<{ bold: boolean; t: string }> {
    const parts: Array<{ bold: boolean; t: string }> = [];
    const re = /\*\*(.+?)\*\*/g;
    let last = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(text)) !== null) {
      if (m.index > last) parts.push({ bold: false, t: text.slice(last, m.index) });
      parts.push({ bold: true, t: m[1] });
      last = m.index + m[0].length;
    }
    if (last < text.length) parts.push({ bold: false, t: text.slice(last) });
    return parts;
  }

  const stepIngredients = $derived(
    finished ? [] : matchIngredients(steps[stepIndex]?.text ?? '', scaled).map((i) => scaled[i])
  );
</script>

<svelte:head>
  <title>Cook — {recipe.title}</title>
</svelte:head>

<svelte:window onkeydown={onKey} />

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div
  class="fixed inset-0 z-40 flex flex-col"
  style="background: var(--paper)"
  onclick={onTap}
  ontouchstart={onTouchStart}
  ontouchend={onTouchEnd}
  data-testid="cook-surface"
>
  <!-- header -->
  <header class="flex items-center gap-3 px-5 pt-[max(env(safe-area-inset-top),16px)] pb-2">
    <a
      href="/r/{recipe.slug}"
      aria-label="Exit cook mode"
      class="font-mono-label flex min-h-[44px] items-center rounded-full border px-4 text-[11px] uppercase tracking-widest no-underline"
      style="border-color: var(--line); color: var(--faint)"
    >
      ✕ exit
    </a>
    <div class="min-w-0 flex-1 truncate text-center">
      <span class="font-mono-label text-[11px] uppercase tracking-widest" style="color: var(--copper)">
        {recipe.title}
      </span>
      <span class="qty ml-2 text-[11px]" style="color: var(--faint)">
        {data.target} {recipe.yield_word}
      </span>
    </div>
    {#if voiceAvailable}
      <button
        aria-label={voiceOn ? 'Stop voice control' : 'Start voice control'}
        aria-pressed={voiceOn}
        class="font-mono-label min-h-[44px] rounded-full border px-3.5 text-[13px]"
        style={voiceOn
          ? 'background: var(--copper); border-color: var(--copper); color: #FFF'
          : 'border-color: var(--line); color: var(--faint)'}
        onclick={toggleVoice}
      >
        🎙
      </button>
    {/if}
    <button
      aria-label="Show all ingredients"
      class="font-mono-label min-h-[44px] rounded-full border px-4 text-[11px] uppercase tracking-widest"
      style="border-color: var(--green); color: var(--green-deep)"
      onclick={() => (drawerOpen = !drawerOpen)}
    >
      list
    </button>
  </header>

  {#if voiceOn}
    <p class="px-5 pb-1 text-center text-[11.5px]" style="color: var(--faint)">
      listening — say "next", "back", "repeat", "start timer", or "how much …"
      {#if voiceHeard}<span class="qty"> · “{voiceHeard}”</span>{/if}
    </p>
  {/if}

  <!-- progress dots -->
  <div class="flex justify-center gap-1.5 pb-1" aria-label="Progress">
    {#each steps as _, i (i)}
      <span
        class="h-1.5 rounded-full transition-all duration-200"
        style:width={i === stepIndex ? '18px' : '6px'}
        style:background={i < stepIndex ? 'var(--green)' : i === stepIndex ? 'var(--copper)' : 'var(--line)'}
      ></span>
    {/each}
  </div>

  <!-- step -->
  <main class="flex min-h-0 flex-1 flex-col justify-center overflow-y-auto px-6 pb-4">
    {#if finished}
      <div class="text-center">
        <div class="font-display text-[clamp(34px,7vw,52px)]" style="color: var(--green-deep)">
          Done.
        </div>
        <p class="mt-2 text-[15px]" style="color: var(--faint)">Every step cooked. Knives down.</p>
        <form method="POST" action="?/log" class="mx-auto mt-6 flex max-w-md flex-col gap-2">
          <input type="hidden" name="started_at" value={startedAt} />
          <input type="hidden" name="scaled_yield" value={data.target} />
          <input
            name="notes"
            placeholder="what did you change? (optional)"
            class="min-h-[48px] rounded-full border px-5 text-[15px]"
            style="border-color: var(--line); background: var(--card); color: var(--ink)"
            maxlength="500"
          />
          <button
            type="submit"
            class="font-mono-label min-h-[48px] rounded-full px-6 text-[12px] uppercase tracking-widest"
            style="background: var(--green-deep); color: #F4F3EC"
            data-testid="log-cook"
          >
            log this cook
          </button>
        </form>
        <a
          href="/r/{recipe.slug}"
          class="font-mono-label mt-3 inline-block rounded-full border px-6 py-3.5 text-[12px] uppercase tracking-widest no-underline"
          style="border-color: var(--line); color: var(--faint)"
        >
          skip · back to the recipe
        </a>
      </div>
    {:else}
      <div class="mx-auto w-full max-w-2xl" data-testid="cook-step">
        <div class="font-display text-[clamp(40px,9vw,64px)] leading-none" style="color: var(--copper)">
          {stepIndex + 1}<span class="text-[0.45em]" style="color: var(--faint)">/{steps.length}</span>
        </div>
        <p class="mt-4 text-[clamp(22px,4.6vw,34px)] leading-snug" style="color: var(--ink)">
          {#each boldParts(steps[stepIndex].text) as part, j (j)}
            {#if part.bold}<strong>{part.t}</strong>{:else}{part.t}{/if}
          {/each}
        </p>

        {#if timerFor(stepIndex)}
          {@const t = timerFor(stepIndex)!}
          {#key tick}
            <div
              class="mt-6 inline-flex items-center gap-4 rounded-2xl border px-5 py-4"
              style="border-color: {t.done() ? 'var(--copper)' : 'var(--line)'}; background: var(--card)"
              data-testid="step-timer"
            >
              <span
                class="qty text-[clamp(30px,6vw,44px)]"
                style="color: {t.done() ? 'var(--copper)' : 'var(--green-deep)'}"
              >
                {formatDuration(t.remaining())}
              </span>
              <div class="flex gap-2">
                {#if t.running}
                  <button
                    class="font-mono-label min-h-[48px] rounded-full border px-5 text-[11px] uppercase tracking-widest"
                    style="border-color: var(--green-deep); color: var(--green-deep)"
                    onclick={() => t.pause()}
                  >
                    pause
                  </button>
                {:else}
                  <button
                    class="font-mono-label min-h-[48px] rounded-full px-5 text-[11px] uppercase tracking-widest"
                    style="background: var(--green-deep); color: #F4F3EC"
                    onclick={() => {
                      chimed.delete(stepIndex);
                      t.start();
                    }}
                    data-testid="timer-start"
                  >
                    {t.remaining() < t.total ? 'resume' : 'start'}
                  </button>
                {/if}
                <button
                  class="font-mono-label min-h-[48px] rounded-full border px-4 text-[11px] uppercase tracking-widest"
                  style="border-color: var(--line); color: var(--faint)"
                  onclick={() => {
                    t.reset();
                    chimed.delete(stepIndex);
                  }}
                >
                  reset
                </button>
              </div>
            </div>
          {/key}
        {/if}

        {#if stepIngredients.length}
          <ul class="mt-6 list-none border-t p-0 pt-3" style="border-color: var(--line)">
            {#each stepIngredients as ing (ing.name)}
              <li class="flex items-baseline gap-3 py-1.5 text-[17px]">
                <span class="qty min-w-[6ch] shrink-0" style="color: var(--green-deep)">{ing.display}</span>
                <span style="color: var(--faint)">{ing.name}</span>
              </li>
            {/each}
          </ul>
        {/if}
      </div>
    {/if}
  </main>

  <!-- nav bar -->
  {#if !finished}
    <footer class="flex gap-2 px-5 pb-[max(env(safe-area-inset-bottom),16px)]">
      <button
        class="font-mono-label min-h-[56px] flex-1 rounded-2xl border text-[12px] uppercase tracking-widest disabled:opacity-40"
        style="border-color: var(--line); color: var(--faint)"
        disabled={stepIndex === 0}
        onclick={() => go(-1)}
      >
        ← back
      </button>
      <button
        class="font-mono-label min-h-[56px] flex-[2] rounded-2xl text-[12px] uppercase tracking-widest"
        style="background: var(--green-deep); color: #F4F3EC"
        onclick={() => go(1)}
        data-testid="next-step"
      >
        {stepIndex === steps.length - 1 ? 'finish' : 'next →'}
      </button>
    </footer>
  {/if}

  <!-- ingredient drawer -->
  {#if drawerOpen}
    <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
    <div class="absolute inset-0 z-50" style="background: rgba(32,36,30,.35)" onclick={() => (drawerOpen = false)}>
      <div
        class="absolute right-0 bottom-0 left-0 max-h-[70%] overflow-y-auto rounded-t-3xl border-t p-5 pb-[max(env(safe-area-inset-bottom),20px)]"
        style="background: var(--card); border-color: var(--line)"
        onclick={(e) => e.stopPropagation()}
      >
        <h3
          class="font-mono-label border-b pb-2 text-xs uppercase tracking-widest"
          style="border-color: var(--line); color: var(--green)"
        >
          Ingredients · {data.target} {recipe.yield_word}
        </h3>
        <ul class="list-none p-0">
          {#each scaled as ing (ing.name)}
            <li class="flex items-baseline gap-3 border-b border-dashed py-2 text-[16px]" style="border-color: var(--line)">
              <span class="qty min-w-[6ch] shrink-0">{ing.display}</span>
              <span>{ing.name}</span>
            </li>
          {/each}
        </ul>
      </div>
    </div>
  {/if}
</div>
