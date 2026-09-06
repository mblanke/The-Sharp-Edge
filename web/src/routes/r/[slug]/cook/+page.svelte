<script lang="ts">
  import { onDestroy, onMount, tick as flush } from 'svelte';
  import { goto } from '$app/navigation';
  import TimerTray from '$lib/components/TimerTray.svelte';
  import { formatDuration, matchIngredients } from '$lib/cook';
  import { convertDisplay, UNIT_SYSTEMS, type UnitSystem } from '$lib/scaling';
  import { isDone, isRunning, remaining, requestNotifyPermission, timerId, timerStore } from '$lib/timers';
  import { listen, parseCommand, speak, type VoiceListener } from '$lib/voice-control';
  import { readSse } from '$lib/sse';
  import { keepAwake, type WakeLockHandle } from '$lib/wakelock';

  let { data } = $props();

  const recipe = $derived(data.recipe);
  const steps = $derived(data.recipe.current_version.steps);
  // the same unit lens as the recipe page; the server's display is the recipe's own units
  let units = $state<UnitSystem>('recipe');
  const scaled = $derived(
    units === 'recipe'
      ? data.scaled
      : data.scaled.map((i) => (i.amount === 0 ? i : { ...i, display: convertDisplay(i.scaled_amount, i.unit, units) }))
  );

  let stepIndex = $state(0);
  const finished = $derived(stepIndex >= steps.length);
  let drawerOpen = $state(false);
  let drawerEl = $state<HTMLDivElement | null>(null);

  // --- timers live in the app-level store (survive steps, pages, reloads) ---
  const now = timerStore.now;
  const currentTimerId = $derived(timerId(recipe.slug, stepIndex));
  const currentTimer = $derived($timerStore.find((t) => t.id === currentTimerId) ?? null);
  const currentTotal = $derived(finished ? 0 : (steps[stepIndex]?.timer_seconds ?? 0));
  const currentRemaining = $derived(currentTimer ? remaining(currentTimer, $now) : currentTotal);
  const currentDone = $derived(currentTimer ? isDone(currentTimer, $now) : false);
  const currentRunning = $derived(currentTimer ? isRunning(currentTimer) : false);

  function startTimer(step = stepIndex) {
    const secs = steps[step]?.timer_seconds;
    if (!secs) return;
    requestNotifyPermission();
    const t = timerStore.ensure(recipe.slug, recipe.title, step, secs);
    if (isDone(t, $now)) timerStore.reset(t.id);
    timerStore.start(t.id);
  }
  function pauseTimer(step = stepIndex) {
    timerStore.pause(timerId(recipe.slug, step));
  }
  function resetTimer(step = stepIndex) {
    timerStore.reset(timerId(recipe.slug, step));
  }

  // --- position: persisted per recipe so a reload or a closed tab resumes ---
  const posKey = $derived(`sharp-edge-cookpos-${recipe.slug}`);
  let resumeOffer = $state<number | null>(null); // saved step to offer, 0-based
  function savePos(i: number) {
    try {
      if (i > 0 && i < steps.length) localStorage.setItem(posKey, String(i));
      else localStorage.removeItem(posKey);
    } catch {
      // storage blocked
    }
  }

  // --- text size: A⁻ / A⁺, persisted ---
  const SCALES = [0.85, 1, 1.2, 1.45];
  let scaleIdx = $state(1);
  const textScale = $derived(SCALES[scaleIdx]);
  function bumpText(delta: number) {
    scaleIdx = Math.min(SCALES.length - 1, Math.max(0, scaleIdx + delta));
    try {
      localStorage.setItem('sharp-edge-cook-text', String(scaleIdx));
    } catch {
      // storage blocked
    }
  }

  // --- first-run hint for the invisible tap zones ---
  let showHint = $state(false);
  function dismissHint() {
    if (!showHint) return;
    showHint = false;
    try {
      localStorage.setItem('sharp-edge-cook-hint', '1');
    } catch {
      // storage blocked
    }
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
      const savedScale = Number(localStorage.getItem('sharp-edge-cook-text'));
      if (Number.isInteger(savedScale) && savedScale >= 0 && savedScale < SCALES.length) scaleIdx = savedScale;
      showHint = !localStorage.getItem('sharp-edge-cook-hint');
      const savedUnits = localStorage.getItem('sharp-edge-units') as UnitSystem | null;
      if (savedUnits && UNIT_SYSTEMS.includes(savedUnits)) units = savedUnits;

      // ?step=N (1-based, from the timer tray) wins; otherwise offer the saved position
      const wanted = Number(new URL(location.href).searchParams.get('step'));
      const saved = Number(localStorage.getItem(posKey));
      if (Number.isInteger(wanted) && wanted >= 1 && wanted <= steps.length) {
        stepIndex = wanted - 1;
      } else if (Number.isInteger(saved) && saved > 0 && saved < steps.length) {
        resumeOffer = saved;
      }
    } catch {
      // storage blocked — start at step 1 on the current theme
    }
    if (showHint) setTimeout(dismissHint, 6000);
    wake = keepAwake();
  });
  onDestroy(() => {
    wake?.release();
    voice?.stop();
    clearTimeout(undoTimer);
    if (themeWasForced) document.documentElement.dataset.theme = '';
  });

  // --- navigation with a 3 s undo for a stray tap ---
  let undo = $state<{ from: number } | null>(null);
  let undoTimer: ReturnType<typeof setTimeout> | undefined;
  function go(delta: number, { undoable = true } = {}) {
    const from = stepIndex;
    const next = Math.min(steps.length, Math.max(0, from + delta));
    if (next === from) return;
    stepIndex = next;
    savePos(next);
    dismissHint();
    clearTimeout(undoTimer);
    if (undoable) {
      undo = { from };
      undoTimer = setTimeout(() => (undo = null), 3000);
    } else {
      undo = null;
    }
  }
  function undoGo() {
    if (!undo) return;
    stepIndex = undo.from;
    savePos(stepIndex);
    undo = null;
    clearTimeout(undoTimer);
  }
  function exit() {
    goto(`/r/${recipe.slug}`);
  }

  // --- voice control (F1): on-device recognition, nothing leaves the browser ---
  let voice: VoiceListener | null = null;
  let voiceOn = $state(false);
  let voiceHeard = $state('');
  const voiceAvailable =
    typeof window !== 'undefined' &&
    ('SpeechRecognition' in window || 'webkitSpeechRecognition' in window);

  // --- mid-cook questions: a spoken question goes to the library, scoped to this
  // recipe, and the answer comes back on a card and out loud. Recognition pauses
  // while the answer is spoken so the mic doesn't transcribe our own voice. ---
  let ask = $state<{ question: string; answer: string; busy: boolean; error: string } | null>(null);
  let askConversationId: string | undefined; // one thread per cook session
  let askAbort: AbortController | null = null;
  let askEl = $state<HTMLDivElement | null>(null);

  async function askShelf(question: string) {
    if (ask?.busy) return;
    ask = { question, answer: '', busy: true, error: '' };
    askAbort = new AbortController();
    try {
      const res = await fetch('/api/ask', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        signal: askAbort.signal,
        body: JSON.stringify({
          question,
          conversation_id: askConversationId,
          scope: { recipe_slug: recipe.slug }
        })
      });
      if (!res.ok) throw new Error(`ask failed (${res.status})`);
      await readSse(res, (event, payload) => {
        const p = payload as Record<string, unknown>;
        if (event === 'meta') askConversationId = p.conversation_id as string;
        else if (event === 'token' && ask) {
          ask = { ...ask, answer: ask.answer + (p.t as string) };
          void flush().then(() => askEl?.scrollTo({ top: askEl.scrollHeight }));
        } else if (event === 'error' && ask) ask = { ...ask, error: String(p.detail ?? 'stream error') };
      });
      if (ask) {
        ask = { ...ask, busy: false };
        // speak the gist (first sentences), pausing the mic so it doesn't hear us
        const gist = ask.answer.replace(/\[\d+\]/g, '').split(/(?<=[.!?])\s+/).slice(0, 3).join(' ');
        if (gist && voiceOn) {
          voice?.stop();
          speak(gist.slice(0, 400), () => {
            if (voiceOn) voice = listen(onVoice);
          });
        }
      }
    } catch (e) {
      const aborted = e instanceof DOMException && e.name === 'AbortError';
      if (ask) ask = { ...ask, busy: false, error: aborted ? '' : e instanceof Error ? e.message : String(e) };
    } finally {
      askAbort = null;
    }
  }
  function stopAsk() {
    askAbort?.abort();
  }

  function onVoice(transcript: string) {
    voiceHeard = transcript.trim();
    const intent = parseCommand(transcript, scaled);
    if (!intent) return;
    if (intent.type === 'ask') askShelf(intent.question);
    else if (intent.type === 'next') go(1);
    else if (intent.type === 'back') go(-1);
    else if (intent.type === 'repeat' && !finished) speak(steps[stepIndex].text.replace(/\*\*/g, ''));
    else if (intent.type === 'how-much') {
      const ing = scaled[intent.ingredient];
      speak(`${ing.display === '—' ? 'to taste' : ing.display} ${ing.name.split(',')[0]}`);
    } else if (intent.type === 'timer-start') startTimer();
    else if (intent.type === 'timer-pause') pauseTimer();
    else if (intent.type === 'timer-reset') resetTimer();
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
    if (finished || drawerOpen || resumeOffer !== null) return;
    const target = e.target as HTMLElement;
    if (target.closest('button, a, input, [data-no-tap]')) return;
    const x = e.clientX / window.innerWidth;
    if (x < 0.33) go(-1);
    else if (x > 0.67) go(1);
  }
  function onKey(e: KeyboardEvent) {
    const tag = (e.target as HTMLElement | null)?.tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA') return;
    if (e.key === 'Escape') {
      if (drawerOpen) drawerOpen = false;
      else if (ask) ask = null;
      else exit();
      return;
    }
    if (drawerOpen) return;
    if (e.key === 'ArrowRight' || e.key === ' ') {
      e.preventDefault();
      go(1);
    } else if (e.key === 'ArrowLeft') go(-1);
    else if (e.key === 'z' && (e.metaKey || e.ctrlKey)) undoGo();
    else if (e.key === 't') (currentRunning ? pauseTimer() : startTimer());
    else if (e.key === 'i') drawerOpen = true;
    else if (e.key === '+' || e.key === '=') bumpText(1);
    else if (e.key === '-') bumpText(-1);
  }

  // the drawer is a dialog: it takes focus on open and gives it back on close
  let lastFocus: HTMLElement | null = null;
  $effect(() => {
    if (drawerOpen) {
      lastFocus = document.activeElement as HTMLElement | null;
      void flush().then(() => drawerEl?.focus());
    } else {
      lastFocus?.focus?.();
      lastFocus = null;
    }
  });

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
  style="background: var(--paper); --cook-scale: {textScale}"
  onclick={onTap}
  ontouchstart={onTouchStart}
  ontouchend={onTouchEnd}
  data-testid="cook-surface"
>
  <!-- header -->
  <header class="flex items-center gap-2 px-4 pt-[max(env(safe-area-inset-top),16px)] pb-2">
    <a
      href="/r/{recipe.slug}"
      aria-label="Exit cook mode"
      class="font-mono-label flex min-h-[44px] items-center rounded-full border px-3.5 text-[11px] uppercase tracking-widest no-underline"
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
    <div class="flex" role="group" aria-label="Text size">
      <button
        aria-label="Smaller text"
        class="font-mono-label min-h-[44px] min-w-[40px] rounded-l-full border text-[12px]"
        style="border-color: var(--line); color: var(--faint)"
        disabled={scaleIdx === 0}
        onclick={() => bumpText(-1)}
      >
        A⁻
      </button>
      <button
        aria-label="Larger text"
        class="font-mono-label min-h-[44px] min-w-[40px] rounded-r-full border border-l-0 text-[14px]"
        style="border-color: var(--line); color: var(--faint)"
        disabled={scaleIdx === SCALES.length - 1}
        onclick={() => bumpText(1)}
      >
        A⁺
      </button>
    </div>
    {#if voiceAvailable}
      <button
        aria-label={voiceOn ? 'Stop voice control' : 'Start voice control'}
        aria-pressed={voiceOn}
        class="font-mono-label min-h-[44px] rounded-full border px-3 text-[13px]"
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
      aria-haspopup="dialog"
      aria-expanded={drawerOpen}
      class="font-mono-label min-h-[44px] rounded-full border px-3.5 text-[11px] uppercase tracking-widest"
      style="border-color: var(--green); color: var(--green-deep)"
      onclick={() => (drawerOpen = !drawerOpen)}
    >
      list
    </button>
  </header>

  <!-- other running timers (this step's own timer renders large below) -->
  <TimerTray compact exclude={finished ? '' : currentTimerId} />

  {#if voiceOn}
    <p class="px-5 pb-1 text-center text-[11.5px]" style="color: var(--faint)">
      listening — say "next", "back", "repeat", "start timer", "how much …", or ask the library a question
      {#if voiceHeard}<span class="qty"> · “{voiceHeard}”</span>{/if}
    </p>
  {/if}

  {#if ask}
    <!-- a question asked with flour on your hands: answered on a card and out loud -->
    <div
      class="mx-5 mb-1 rounded-xl border p-3 text-[13.5px]"
      style="background: var(--card); border-color: var(--copper); color: var(--ink)"
      role="status"
      aria-live="polite"
    >
      <div class="flex items-baseline justify-between gap-2">
        <span class="font-mono-label text-[10.5px] uppercase tracking-widest" style="color: var(--copper)">
          “{ask.question}”
        </span>
        <button
          class="font-mono-label min-h-[32px] shrink-0 text-[10.5px] uppercase tracking-widest"
          style="color: var(--faint)"
          onclick={() => (ask?.busy ? stopAsk() : (ask = null))}
        >
          {ask.busy ? 'stop' : 'dismiss'}
        </button>
      </div>
      <div class="mt-1 max-h-[30vh] overflow-y-auto whitespace-pre-wrap" bind:this={askEl}>
        {ask.answer.replace(/\[\d+\]/g, '')}{ask.busy ? ' …' : ''}
      </div>
      {#if ask.error}<p class="mt-1" style="color: var(--copper)">{ask.error}</p>{/if}
    </div>
  {/if}

  <!-- progress dots -->
  <div
    class="flex justify-center gap-1.5 pb-1"
    role="progressbar"
    aria-label="Step progress"
    aria-valuemin={1}
    aria-valuemax={steps.length}
    aria-valuenow={Math.min(stepIndex + 1, steps.length)}
  >
    {#each steps as _, i (i)}
      <span
        class="h-1.5 rounded-full transition-all duration-200"
        style:width={i === stepIndex ? '18px' : '6px'}
        style:background={i < stepIndex ? 'var(--green)' : i === stepIndex ? 'var(--copper)' : 'var(--line)'}
      ></span>
    {/each}
  </div>

  <!-- step: `my-auto` centres when short and scrolls when tall (landscape phones) -->
  <main class="flex min-h-0 flex-1 flex-col overflow-y-auto px-6 pb-4">
    {#if finished}
      <div class="my-auto text-center">
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
      <div class="mx-auto my-auto w-full max-w-2xl" data-testid="cook-step">
        <div class="font-display text-[clamp(40px,9vw,64px)] leading-none" style="color: var(--copper)">
          {stepIndex + 1}<span class="text-[0.45em]" style="color: var(--faint)">/{steps.length}</span>
        </div>
        <p
          class="mt-4 leading-snug"
          style="color: var(--ink); font-size: calc(clamp(22px, 4.6vw, 34px) * var(--cook-scale))"
          aria-live="polite"
        >
          {#each boldParts(steps[stepIndex].text) as part, j (j)}
            {#if part.bold}<strong>{part.t}</strong>{:else}{part.t}{/if}
          {/each}
        </p>

        {#if currentTotal}
          <div
            class="mt-6 inline-flex flex-wrap items-center gap-4 rounded-2xl border px-5 py-4"
            style="border-color: {currentDone ? 'var(--copper)' : 'var(--line)'}; background: var(--card)"
            data-testid="step-timer"
          >
            <span
              class="qty text-[clamp(30px,6vw,44px)]"
              style="color: {currentDone ? 'var(--copper)' : 'var(--green-deep)'}"
              aria-live={currentDone ? 'assertive' : 'off'}
            >
              {formatDuration(currentRemaining)}
            </span>
            <div class="flex gap-2">
              {#if currentRunning}
                <button
                  class="font-mono-label min-h-[48px] rounded-full border px-5 text-[11px] uppercase tracking-widest"
                  style="border-color: var(--green-deep); color: var(--green-deep)"
                  onclick={() => pauseTimer()}
                >
                  pause
                </button>
              {:else}
                <button
                  class="font-mono-label min-h-[48px] rounded-full px-5 text-[11px] uppercase tracking-widest"
                  style="background: var(--green-deep); color: #F4F3EC"
                  onclick={() => startTimer()}
                  data-testid="timer-start"
                >
                  {currentDone ? 'again' : currentRemaining < currentTotal ? 'resume' : 'start'}
                </button>
              {/if}
              <button
                class="font-mono-label min-h-[48px] rounded-full border px-4 text-[11px] uppercase tracking-widest"
                style="border-color: var(--line); color: var(--faint)"
                onclick={() => resetTimer()}
              >
                reset
              </button>
            </div>
          </div>
        {/if}

        {#if stepIngredients.length}
          <ul class="mt-6 list-none border-t p-0 pt-3" style="border-color: var(--line)">
            {#each stepIngredients as ing (ing.name)}
              <li
                class="flex items-baseline gap-3 py-1.5"
                style="font-size: calc(17px * var(--cook-scale))"
              >
                <span class="qty min-w-[6ch] shrink-0" style="color: var(--green-deep)">{ing.display}</span>
                <span style="color: var(--faint)">{ing.name}</span>
              </li>
            {/each}
          </ul>
        {/if}
      </div>
    {/if}
  </main>

  <!-- undo a stray tap -->
  {#if undo}
    <div class="pointer-events-none flex justify-center pb-2">
      <button
        class="font-mono-label pointer-events-auto min-h-[40px] rounded-full border px-4 text-[10.5px] uppercase tracking-widest"
        style="background: var(--card); border-color: var(--line); color: var(--green-deep)"
        onclick={undoGo}
        data-testid="undo-step"
      >
        step {Math.min(stepIndex + 1, steps.length)} · undo
      </button>
    </div>
  {/if}

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

  <!-- first-run hint for the tap zones -->
  {#if showHint && !finished && resumeOffer === null}
    <div
      class="pointer-events-none absolute inset-x-0 top-1/2 flex -translate-y-1/2 justify-between px-4"
      aria-hidden="true"
    >
      <span class="font-mono-label rounded-full px-3 py-2 text-[10.5px] uppercase tracking-widest" style="background: var(--card); color: var(--faint); border: 1px solid var(--line)">← tap</span>
      <span class="font-mono-label rounded-full px-3 py-2 text-[10.5px] uppercase tracking-widest" style="background: var(--card); color: var(--faint); border: 1px solid var(--line)">tap →</span>
    </div>
  {/if}

  <!-- resume where you left off -->
  {#if resumeOffer !== null}
    <div
      class="absolute inset-0 z-50 flex items-end justify-center p-5 sm:items-center"
      style="background: rgba(32,36,30,.35)"
      role="dialog"
      aria-modal="true"
      aria-labelledby="resume-title"
      data-no-tap
    >
      <div class="w-full max-w-sm rounded-2xl border p-5" style="background: var(--card); border-color: var(--line)">
        <p id="resume-title" class="text-[17px]" style="color: var(--ink)">
          Pick up at step <span class="qty">{resumeOffer + 1}</span> of {steps.length}?
        </p>
        <div class="mt-4 flex gap-2">
          <button
            class="font-mono-label min-h-[48px] flex-1 rounded-full border text-[11px] uppercase tracking-widest"
            style="border-color: var(--line); color: var(--faint)"
            onclick={() => {
              resumeOffer = null;
              savePos(0);
            }}
          >
            start over
          </button>
          <button
            class="font-mono-label min-h-[48px] flex-[2] rounded-full text-[11px] uppercase tracking-widest"
            style="background: var(--green-deep); color: #F4F3EC"
            onclick={() => {
              stepIndex = resumeOffer ?? 0;
              resumeOffer = null;
            }}
            data-testid="resume-step"
          >
            resume
          </button>
        </div>
      </div>
    </div>
  {/if}

  <!-- ingredient drawer -->
  {#if drawerOpen}
    <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
    <div class="absolute inset-0 z-50" style="background: rgba(32,36,30,.35)" onclick={() => (drawerOpen = false)}>
      <div
        class="absolute right-0 bottom-0 left-0 max-h-[70%] overflow-y-auto rounded-t-3xl border-t p-5 pb-[max(env(safe-area-inset-bottom),20px)] outline-none"
        style="background: var(--card); border-color: var(--line)"
        role="dialog"
        aria-modal="true"
        aria-labelledby="drawer-title"
        tabindex="-1"
        bind:this={drawerEl}
        onclick={(e) => e.stopPropagation()}
      >
        <div class="flex items-center justify-between border-b pb-2" style="border-color: var(--line)">
          <h3 id="drawer-title" class="font-mono-label text-xs uppercase tracking-widest" style="color: var(--green)">
            Ingredients · {data.target} {recipe.yield_word}
          </h3>
          <button
            class="font-mono-label min-h-[40px] rounded-full border px-3 text-[10.5px] uppercase tracking-widest"
            style="border-color: var(--line); color: var(--faint)"
            onclick={() => (drawerOpen = false)}
          >
            close
          </button>
        </div>
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
