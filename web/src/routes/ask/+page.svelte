<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { enhance } from '$app/forms';
  import { invalidateAll, replaceState } from '$app/navigation';
  import { renderMd } from '$lib/md';
  import { readSse } from '$lib/sse';
  import { notify } from '$lib/toast';

  let { data } = $props();

  interface Citation {
    n: number;
    title: string | null;
    source_path: string | null;
    heading: string | null;
    page: number | null;
  }
  interface Source extends Citation {
    text: string;
  }
  interface ChatMessage {
    id?: string;
    role: 'user' | 'assistant';
    content: string;
    citations?: Citation[];
    sources?: Source[];
    ungrounded?: boolean;
    attribution?: Attribution | null;
    feedback?: 'up' | 'down' | null;
    /** the stream was stopped by the cook before the model finished */
    stopped?: boolean;
  }
  /** Set when the question named an authority the shelf can't actually answer for.
   *  `ungrounded` catches an answer with no citations; this catches one whose
   *  citations point at the wrong book. */
  interface Attribution {
    absent: string[];
    unretrieved: string[];
    sources: string[];
    note: string;
  }

  let question = $state('');
  let scopeBook = $state<string>(''); // '' = whole library
  let messages = $state<ChatMessage[]>([]);
  let busy = $state(false);
  let errorMsg = $state('');
  let conversationId = $state<string | null>(null);
  let followups = $state<string[]>([]);
  // keyed "messageIndex:n" so a chip only opens its own message's panel
  let openSource = $state<string | null>(null);
  let abort: AbortController | null = null;
  let endEl = $state<HTMLDivElement | null>(null);
  let inputEl = $state<HTMLInputElement | null>(null);
  let renaming = $state<string | null>(null);
  let renameTitle = $state('');

  const EXAMPLES = [
    'How does Keller cook short ribs sous vide?',
    'What can I use instead of soy sauce that is gluten-free?',
    'Why does my hollandaise split, and how do I bring it back?',
    'How long does a 2 kg pork shoulder take at 150 °C?'
  ];

  onMount(() => {
    const c = new URL(location.href).searchParams.get('c');
    if (c) void loadConversation(c);
  });

  function syncUrl(id: string | null) {
    try {
      const url = new URL(location.href);
      if (id) url.searchParams.set('c', id);
      else url.searchParams.delete('c');
      replaceState(url, {});
    } catch {
      // not navigable yet
    }
  }

  // follow the answer as it streams, but only when the cook is already at the bottom
  let scrollPending = false;
  function followStream() {
    if (scrollPending) return;
    scrollPending = true;
    requestAnimationFrame(() => {
      scrollPending = false;
      const nearBottom = window.innerHeight + window.scrollY >= document.body.scrollHeight - 240;
      if (nearBottom) endEl?.scrollIntoView({ block: 'end' });
    });
  }

  async function send(text = question) {
    const q = text.trim();
    if (!q || busy) return;
    question = '';
    errorMsg = '';
    followups = [];
    busy = true;
    abort = new AbortController();
    messages = [...messages, { role: 'user', content: q }, { role: 'assistant', content: '' }];
    const idx = messages.length - 1;
    await tick();
    endEl?.scrollIntoView({ block: 'end' });
    try {
      const res = await fetch('/api/ask', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        signal: abort.signal,
        body: JSON.stringify({
          question: q,
          conversation_id: conversationId,
          scope: { recipe_slug: data.recipeSlug, books: scopeBook ? [scopeBook] : [] }
        })
      });
      if (!res.ok) throw new Error(`ask failed (${res.status})`);
      await readSse(res, (event, payload) => {
        const p = payload as Record<string, unknown>;
        if (event === 'meta') {
          const isNew = conversationId === null;
          conversationId = p.conversation_id as string;
          syncUrl(conversationId);
          if (isNew) void invalidateAll(); // the list on the right gains a row
        } else if (event === 'token') {
          messages[idx] = { ...messages[idx], content: messages[idx].content + (p.t as string) };
          followStream();
        } else if (event === 'done') {
          messages[idx] = {
            ...messages[idx],
            id: p.message_id as string,
            citations: p.citations as Citation[],
            sources: p.sources as Source[],
            ungrounded: p.ungrounded as boolean,
            attribution: p.attribution as Attribution | null
          };
        } else if (event === 'followups') {
          followups = (p.questions as string[]) ?? [];
        } else if (event === 'error') {
          errorMsg = String(p.detail ?? 'stream error');
        }
      });
    } catch (e) {
      if (e instanceof DOMException && e.name === 'AbortError') {
        messages[idx] = { ...messages[idx], stopped: true };
      } else {
        errorMsg = e instanceof Error ? e.message : String(e);
      }
    } finally {
      busy = false;
      abort = null;
    }
  }

  function stop() {
    abort?.abort();
  }

  /** Ask the last question again. The previous answer stays in the server's history;
   *  on screen the pair is replaced, so the page reads as one thread. */
  function regenerate() {
    if (busy) return;
    const lastUser = [...messages].reverse().find((m) => m.role === 'user');
    if (!lastUser) return;
    const cut = messages.lastIndexOf(lastUser);
    messages = messages.slice(0, cut);
    void send(lastUser.content);
  }

  async function copyAnswer(text: string) {
    const plain = text.replace(/\[(\d+|R)\]/g, '').replace(/\*\*/g, '');
    try {
      await navigator.clipboard.writeText(plain);
      notify.ok('Answer copied');
    } catch {
      notify.error('Copy needs https — select the text instead');
    }
  }

  async function loadConversation(id: string) {
    if (busy) stop();
    errorMsg = '';
    followups = [];
    try {
      const res = await fetch(`/api/conversations/${id}`);
      if (!res.ok) throw new Error(String(res.status));
      const conv = await res.json();
      conversationId = conv.id;
      messages = conv.messages.map((m: ChatMessage) => ({ ...m }));
      syncUrl(conv.id);
      await tick();
      endEl?.scrollIntoView({ block: 'end' });
    } catch {
      notify.error('Could not open that conversation');
      syncUrl(null);
    }
  }

  function newConversation() {
    if (busy) stop();
    conversationId = null;
    messages = [];
    followups = [];
    errorMsg = '';
    syncUrl(null);
    inputEl?.focus();
  }

  function bookName(path: string | null): string {
    if (!path) return 'source';
    const parts = path.split('/');
    return parts[parts.length - 1] || path;
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape' && busy) stop();
  }

  const last = $derived(messages[messages.length - 1]);
  const showFollowups = $derived(!busy && followups.length > 0 && last?.role === 'assistant');
</script>

<svelte:head>
  <title>Ask the library — The Sharp Edge</title>
</svelte:head>

<svelte:window onkeydown={onKey} />

<section class="pt-7">
  <div class="font-mono-label text-[11px] uppercase tracking-widest" style="color: var(--copper)">
    Culinary library
  </div>
  <h2 class="font-display mt-1 text-[clamp(24px,5.6vw,32px)] leading-tight">Ask the library</h2>
  <p class="mt-1 text-[13.5px]" style="color: var(--faint)">
    Answers come from the cookbooks on the shelf, cited by source and page. Local models only.
  </p>

  {#if data.recipeSlug}
    <div
      class="font-mono-label mt-3 inline-flex items-center gap-2 rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest"
      style="border-color: var(--green); color: var(--ink-accent); background: var(--card)"
    >
      scoped to: {data.recipeTitle ?? data.recipeSlug}
      <a href="/ask" class="no-underline" style="color: var(--copper)" title="Clear scope">✕</a>
    </div>
  {/if}

  {#if data.books.length}
    <label class="mt-3 flex items-center gap-2">
      <span class="font-mono-label text-[11px] uppercase tracking-widest" style="color: var(--faint)">
        Shelf
      </span>
      <select
        class="font-mono-label min-h-[44px] max-w-[70vw] rounded-full border px-4 text-[11.5px]"
        style="border-color: {scopeBook ? 'var(--green)' : 'var(--line)'}; background: var(--card); color: var(--ink-accent)"
        bind:value={scopeBook}
        aria-label="Restrict answers to one book"
      >
        <option value="">Whole library</option>
        {#each data.books as book (book)}
          <option value={book}>{book}</option>
        {/each}
      </select>
    </label>
  {/if}

  {#if messages.length === 0}
    <div class="mt-6" data-testid="ask-empty">
      <p class="font-mono-label text-[10.5px] uppercase tracking-widest" style="color: var(--faint)">try asking</p>
      <div class="mt-2 flex flex-wrap gap-2">
        {#each EXAMPLES as ex (ex)}
          <button
            class="rounded-2xl border px-4 py-2.5 text-left text-[14px]"
            style="border-color: var(--line); background: var(--card); color: var(--ink-accent)"
            onclick={() => send(ex)}
          >
            {ex}
          </button>
        {/each}
      </div>
    </div>
  {/if}

  <div class="mt-5 flex flex-col gap-4" aria-live="polite" aria-busy={busy}>
    {#each messages as msg, i (i)}
      {#if msg.role === 'user'}
        <div
          class="self-end rounded-2xl rounded-br-sm px-4 py-2.5 text-[15px]"
          style="background: var(--green-deep); color: #F4F3EC; max-width: 85%"
        >
          {msg.content}
        </div>
      {:else}
        <div
          class="answer self-start rounded-2xl rounded-bl-sm border px-4 py-3 text-[15px]"
          style="background: var(--card); border-color: var(--line); max-width: 92%"
          data-testid="answer"
        >
          {#if msg.content}
            <!-- eslint-disable-next-line svelte/no-at-html-tags -- renderMd escapes first -->
            <div class="prose-answer">{@html renderMd(msg.content)}</div>
            {#if busy && i === messages.length - 1}
              <span class="cursor" aria-hidden="true"></span>
            {/if}
          {:else if busy && i === messages.length - 1}
            <div class="font-mono-label text-[12px]" style="color: var(--faint)">consulting the shelf…</div>
          {/if}
          {#if msg.stopped}
            <div class="font-mono-label mt-2 text-[10.5px] uppercase tracking-widest" style="color: var(--faint)">stopped</div>
          {/if}
          {#if msg.attribution}
            <!-- Asked about Escoffier, who isn't on this shelf, the model used to answer
                 "according to Escoffier's method" and cite the CIA. The answer is still
                 worth having — it just has to say whose book it came from. -->
            <div
              class="mt-3 rounded-xl border px-3 py-2 text-[13px]"
              style="border-color: var(--accent); background: var(--accent-wash); color: var(--ink)"
            >
              {msg.attribution.note}
            </div>
          {/if}
          {#if msg.ungrounded}
            <div
              class="font-mono-label mt-3 inline-block rounded-full border px-3 py-1.5 text-[10.5px] uppercase tracking-widest"
              style="border-color: var(--copper); color: var(--copper)"
            >
              no citations — not grounded in the library
            </div>
          {/if}
          {#if msg.citations?.length}
            <div class="mt-3 flex flex-wrap gap-2 border-t pt-3" style="border-color: var(--line)">
              {#each msg.citations as c (c.n)}
                {#if c.n === 0}
                  <!-- [R]: the working notebook recipe — links straight to it -->
                  <a
                    href={c.source_path}
                    class="font-mono-label rounded-full border px-3 py-1.5 text-[10.5px] tracking-wide no-underline"
                    style="border-color: var(--copper); color: var(--copper)"
                  >
                    [R] {c.title}
                  </a>
                {:else}
                  <button
                    class="font-mono-label min-h-[36px] rounded-full border px-3 py-1.5 text-[10.5px] tracking-wide"
                    style="border-color: var(--green); color: var(--ink-accent)"
                    aria-expanded={openSource === `${i}:${c.n}`}
                    onclick={() => (openSource = openSource === `${i}:${c.n}` ? null : `${i}:${c.n}`)}
                  >
                    [{c.n}] {c.title ?? bookName(c.source_path)}{c.page != null ? ` · p.${c.page}` : ''}
                  </button>
                {/if}
              {/each}
            </div>
            {#if openSource?.startsWith(`${i}:`)}
              {@const src = msg.sources?.find((s) => s.n === Number(openSource?.split(':')[1]))}
              {#if src}
                <div class="mt-2 rounded-xl border p-3 text-[13px]" style="border-color: var(--line); color: var(--faint)">
                  <div class="font-mono-label mb-1 text-[10.5px] uppercase tracking-widest" style="color: var(--copper)">
                    {src.source_path}{src.page != null ? ` · p.${src.page}` : ''}
                  </div>
                  {src.text.slice(0, 600)}{src.text.length > 600 ? '…' : ''}
                  {#if src.text.length >= 120}
                    <!-- the read loop closes: a cited passage can become a notebook
                         draft (review-first; lands marked private, out of exports) -->
                    <form method="POST" action="/new?/passage" class="mt-2">
                      <input type="hidden" name="text" value={src.text} />
                      <input type="hidden" name="source_title" value={src.title ?? bookName(src.source_path)} />
                      {#if src.page != null}<input type="hidden" name="page" value={src.page} />{/if}
                      <button
                        class="font-mono-label rounded-full border px-3 py-1.5 text-[10.5px] uppercase tracking-widest"
                        style="border-color: var(--copper); color: var(--copper)"
                      >draft into notebook →</button>
                    </form>
                  {/if}
                </div>
              {/if}
            {/if}
          {/if}

          {#if msg.content && !(busy && i === messages.length - 1)}
            <!-- answer tools: rate it (feeds the retrieval golden set), copy, redo -->
            <div class="mt-3 flex flex-wrap items-center gap-1 border-t pt-2" style="border-color: var(--line)" data-print="hide">
              {#if msg.id && conversationId}
                <form
                  method="POST"
                  action="?/feedback"
                  class="flex gap-1"
                  use:enhance={({ formData }) => {
                    const next = String(formData.get('feedback')) as 'up' | 'down';
                    const previous = msg.feedback ?? null;
                    const cleared = previous === next;
                    if (cleared) formData.set('feedback', '');
                    messages[i] = { ...messages[i], feedback: cleared ? null : next };
                    return async ({ result }) => {
                      if (result.type !== 'success') {
                        messages[i] = { ...messages[i], feedback: previous };
                        notify.error('Could not save that — is the server reachable?');
                      }
                    };
                  }}
                >
                  <input type="hidden" name="conversation_id" value={conversationId} />
                  <input type="hidden" name="message_id" value={msg.id} />
                  <button
                    name="feedback"
                    value="up"
                    class="min-h-[36px] min-w-[36px] rounded-full border text-[13px]"
                    style="border-color: {msg.feedback === 'up' ? 'var(--green-deep)' : 'var(--line)'}; background: {msg.feedback === 'up' ? 'var(--green-deep)' : 'transparent'}; color: {msg.feedback === 'up' ? '#F4F3EC' : 'var(--faint)'}"
                    aria-label="Good answer"
                    aria-pressed={msg.feedback === 'up'}
                    data-testid="thumb-up"
                  >
                    👍
                  </button>
                  <button
                    name="feedback"
                    value="down"
                    class="min-h-[36px] min-w-[36px] rounded-full border text-[13px]"
                    style="border-color: {msg.feedback === 'down' ? 'var(--copper)' : 'var(--line)'}; background: {msg.feedback === 'down' ? 'var(--copper)' : 'transparent'}; color: {msg.feedback === 'down' ? '#FFF' : 'var(--faint)'}"
                    aria-label="Poor answer"
                    aria-pressed={msg.feedback === 'down'}
                    data-testid="thumb-down"
                  >
                    👎
                  </button>
                </form>
              {/if}
              <button
                class="font-mono-label min-h-[36px] rounded-full border px-3 text-[10.5px] uppercase tracking-widest"
                style="border-color: var(--line); color: var(--faint)"
                onclick={() => copyAnswer(msg.content)}
              >
                copy
              </button>
              {#if i === messages.length - 1}
                <button
                  class="font-mono-label min-h-[36px] rounded-full border px-3 text-[10.5px] uppercase tracking-widest"
                  style="border-color: var(--line); color: var(--faint)"
                  onclick={regenerate}
                  data-testid="regenerate"
                >
                  ask again
                </button>
              {/if}
            </div>
          {/if}
        </div>
      {/if}
    {/each}

    {#if showFollowups}
      <div class="flex flex-wrap gap-2 self-start" data-testid="followups">
        {#each followups as f (f)}
          <button
            class="rounded-2xl border px-3.5 py-2 text-left text-[13.5px]"
            style="border-color: var(--green); background: var(--card); color: var(--ink-accent)"
            onclick={() => send(f)}
          >
            {f} →
          </button>
        {/each}
      </div>
    {/if}
    <div bind:this={endEl}></div>
  </div>

  {#if errorMsg}
    <p class="mt-3 flex items-center gap-3 text-[13.5px]" style="color: var(--copper)" role="alert">
      {errorMsg}
      <button
        class="font-mono-label min-h-[36px] rounded-full border px-3 text-[10.5px] uppercase tracking-widest"
        style="border-color: var(--copper); color: var(--copper)"
        onclick={regenerate}
      >
        try again
      </button>
    </p>
  {/if}

  <form
    class="sticky bottom-[max(env(safe-area-inset-bottom),8px)] mt-5 flex gap-2 rounded-full"
    style="background: var(--paper)"
    onsubmit={(e) => {
      e.preventDefault();
      send();
    }}
  >
    <input
      bind:value={question}
      bind:this={inputEl}
      placeholder={data.recipeSlug ? 'Ask about this recipe…' : 'e.g. how does Keller cook short ribs sous vide?'}
      aria-label="Your question"
      class="min-h-[48px] flex-1 rounded-full border px-5 text-[15px]"
      style="border-color: var(--line); background: var(--card); color: var(--ink)"
      disabled={busy}
    />
    {#if busy}
      <button
        type="button"
        class="font-mono-label min-h-[48px] rounded-full border px-5 text-[12px] uppercase tracking-widest"
        style="border-color: var(--copper); color: var(--copper); background: var(--card)"
        onclick={stop}
        data-testid="stop"
      >
        ■ stop
      </button>
    {:else}
      <button
        type="submit"
        class="font-mono-label min-h-[48px] rounded-full px-6 text-[12px] uppercase tracking-widest disabled:opacity-50"
        style="background: var(--green-deep); color: #F4F3EC"
        disabled={!question.trim()}
      >
        Ask
      </button>
    {/if}
  </form>

  {#if messages.length}
    <button
      class="font-mono-label mt-3 min-h-[44px] rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest"
      style="border-color: var(--line); color: var(--faint)"
      onclick={newConversation}
    >
      new conversation
    </button>
  {/if}

  {#if data.conversations.length}
    <h3
      class="font-mono-label mt-8 border-b pb-1 text-xs uppercase tracking-widest"
      style="border-color: var(--line); color: var(--green)"
    >
      Recent conversations
    </h3>
    <ul class="list-none p-0">
      {#each data.conversations.slice(0, 10) as conv (conv.id)}
        <li class="flex items-center gap-2 border-b border-dashed" style="border-color: var(--line)">
          {#if renaming === conv.id}
            <form
              method="POST"
              action="?/rename"
              class="flex min-w-0 flex-1 gap-2 py-1"
              use:enhance={() => {
                return async ({ result, update }) => {
                  await update({ reset: false });
                  renaming = null;
                  if (result.type === 'success') void invalidateAll();
                  else notify.error('Could not rename it');
                };
              }}
            >
              <input type="hidden" name="id" value={conv.id} />
              <!-- svelte-ignore a11y_autofocus -->
              <input
                name="title"
                bind:value={renameTitle}
                autofocus
                maxlength="120"
                aria-label="New title"
                class="min-h-[40px] min-w-0 flex-1 rounded-lg border px-3 text-[14px]"
                style="border-color: var(--line); background: var(--card); color: var(--ink)"
                onkeydown={(e) => e.key === 'Escape' && (renaming = null)}
              />
              <button class="font-mono-label min-h-[40px] rounded-full border px-3 text-[10.5px] uppercase tracking-widest" style="border-color: var(--green-deep); color: var(--ink-accent)">save</button>
            </form>
          {:else}
            <button
              class="min-h-[44px] min-w-0 flex-1 truncate py-2 text-left text-[14px]"
              style="color: {conversationId === conv.id ? 'var(--copper)' : 'var(--ink-accent)'}"
              aria-current={conversationId === conv.id ? 'true' : undefined}
              onclick={() => loadConversation(conv.id)}
            >
              {conv.title ?? 'untitled'}
            </button>
            <button
              class="font-mono-label min-h-[40px] rounded-full px-2 text-[10.5px] uppercase tracking-widest"
              style="color: var(--faint)"
              aria-label="Rename {conv.title ?? 'untitled'}"
              onclick={() => {
                renaming = conv.id;
                renameTitle = conv.title ?? '';
              }}
            >
              rename
            </button>
            <form
              method="POST"
              action="?/delete"
              use:enhance={({ cancel }) => {
                if (!confirm(`Delete “${conv.title ?? 'untitled'}”? This cannot be undone.`)) {
                  cancel();
                  return;
                }
                return async ({ result }) => {
                  if (result.type === 'success') {
                    if (conversationId === conv.id) newConversation();
                    notify.ok('Conversation deleted');
                    void invalidateAll();
                  } else {
                    notify.error('Could not delete it');
                  }
                };
              }}
            >
              <input type="hidden" name="id" value={conv.id} />
              <button
                class="font-mono-label min-h-[40px] rounded-full px-2 text-[10.5px] uppercase tracking-widest"
                style="color: var(--copper)"
                aria-label="Delete {conv.title ?? 'untitled'}"
              >
                delete
              </button>
            </form>
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
</section>

<style>
  .prose-answer :global(p) {
    margin: 0 0 0.6em;
  }
  .prose-answer :global(p:last-child) {
    margin-bottom: 0;
  }
  .prose-answer :global(ul),
  .prose-answer :global(ol) {
    margin: 0.2em 0 0.6em 1.2em;
    padding: 0;
  }
  .prose-answer :global(li) {
    margin: 0.15em 0;
  }
  .prose-answer :global(code) {
    font-family: 'Spline Sans Mono', ui-monospace, monospace;
    font-size: 0.92em;
    background: var(--paper);
    padding: 0 0.3em;
    border-radius: 4px;
  }
  .prose-answer :global(sup.cite) {
    font-family: 'Spline Sans Mono', ui-monospace, monospace;
    font-size: 0.7em;
    color: var(--ink-accent);
    margin-left: 1px;
  }
  .cursor {
    display: inline-block;
    width: 0.5em;
    height: 1em;
    margin-left: 2px;
    vertical-align: -0.15em;
    background: var(--copper);
    animation: blink 1s steps(2) infinite;
  }
  @keyframes blink {
    to {
      visibility: hidden;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .cursor {
      animation: none;
    }
  }
</style>
