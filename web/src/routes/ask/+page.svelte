<script lang="ts">
  import { readSse } from '$lib/sse';

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
    role: 'user' | 'assistant';
    content: string;
    citations?: Citation[];
    sources?: Source[];
    ungrounded?: boolean;
  }

  let question = $state('');
  let messages = $state<ChatMessage[]>([]);
  let busy = $state(false);
  let errorMsg = $state('');
  let conversationId = $state<string | null>(null);
  let openSource = $state<number | null>(null);

  async function send() {
    const q = question.trim();
    if (!q || busy) return;
    question = '';
    errorMsg = '';
    busy = true;
    messages = [...messages, { role: 'user', content: q }, { role: 'assistant', content: '' }];
    const idx = messages.length - 1;
    try {
      const res = await fetch('/api/ask', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          question: q,
          conversation_id: conversationId,
          scope: { recipe_slug: data.recipeSlug }
        })
      });
      if (!res.ok) throw new Error(`ask failed (${res.status})`);
      await readSse(res, (event, payload) => {
        const p = payload as Record<string, unknown>;
        if (event === 'meta') conversationId = p.conversation_id as string;
        else if (event === 'token') {
          messages[idx] = { ...messages[idx], content: messages[idx].content + (p.t as string) };
        } else if (event === 'done') {
          messages[idx] = {
            ...messages[idx],
            citations: p.citations as Citation[],
            sources: p.sources as Source[],
            ungrounded: p.ungrounded as boolean
          };
        } else if (event === 'error') {
          errorMsg = String(p.detail ?? 'stream error');
        }
      });
    } catch (e) {
      errorMsg = e instanceof Error ? e.message : String(e);
    } finally {
      busy = false;
    }
  }

  async function loadConversation(id: string) {
    const res = await fetch(`/api/conversations/${id}`);
    if (!res.ok) return;
    const conv = await res.json();
    conversationId = conv.id;
    messages = conv.messages.map((m: ChatMessage) => ({ ...m }));
  }

  function newConversation() {
    conversationId = null;
    messages = [];
    errorMsg = '';
  }

  function bookName(path: string | null): string {
    if (!path) return 'source';
    const parts = path.split('/');
    return parts[parts.length - 1] || path;
  }
</script>

<svelte:head>
  <title>Ask the library — The Sharp Edge</title>
</svelte:head>

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
      style="border-color: var(--green); color: var(--green-deep); background: var(--card)"
    >
      scoped to: {data.recipeTitle ?? data.recipeSlug}
      <a href="/ask" class="no-underline" style="color: var(--copper)" title="Clear scope">✕</a>
    </div>
  {/if}

  <div class="mt-5 flex flex-col gap-4">
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
          class="self-start rounded-2xl rounded-bl-sm border px-4 py-3 text-[15px]"
          style="background: var(--card); border-color: var(--line); max-width: 92%"
        >
          {#if msg.content}
            <div class="whitespace-pre-wrap">{msg.content}</div>
          {:else if busy && i === messages.length - 1}
            <div class="font-mono-label text-[12px]" style="color: var(--faint)">thinking…</div>
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
                <button
                  class="font-mono-label rounded-full border px-3 py-1.5 text-[10.5px] tracking-wide"
                  style="border-color: var(--green); color: var(--green-deep)"
                  onclick={() => (openSource = openSource === c.n ? null : c.n)}
                >
                  [{c.n}] {c.title ?? bookName(c.source_path)}{c.page != null ? ` · p.${c.page}` : ''}
                </button>
              {/each}
            </div>
            {#if openSource != null}
              {@const src = msg.sources?.find((s) => s.n === openSource)}
              {#if src}
                <div class="mt-2 rounded-xl border p-3 text-[13px]" style="border-color: var(--line); color: var(--faint)">
                  <div class="font-mono-label mb-1 text-[10.5px] uppercase tracking-widest" style="color: var(--copper)">
                    {src.source_path}{src.page != null ? ` · p.${src.page}` : ''}
                  </div>
                  {src.text}
                </div>
              {/if}
            {/if}
          {/if}
        </div>
      {/if}
    {/each}
  </div>

  {#if errorMsg}
    <p class="mt-3 text-[13.5px]" style="color: var(--copper)">{errorMsg}</p>
  {/if}

  <form
    class="mt-5 flex gap-2"
    onsubmit={(e) => {
      e.preventDefault();
      send();
    }}
  >
    <input
      bind:value={question}
      placeholder={data.recipeSlug ? 'Ask about this recipe…' : 'e.g. how does Keller cook short ribs sous vide?'}
      class="min-h-[48px] flex-1 rounded-full border px-5 text-[15px]"
      style="border-color: var(--line); background: var(--card); color: var(--ink)"
      disabled={busy}
    />
    <button
      type="submit"
      class="font-mono-label min-h-[48px] rounded-full px-6 text-[12px] uppercase tracking-widest"
      style="background: var(--green-deep); color: #F4F3EC"
      disabled={busy || !question.trim()}
    >
      {busy ? '…' : 'Ask'}
    </button>
  </form>

  {#if messages.length}
    <button
      class="font-mono-label mt-3 rounded-full border px-4 py-2 text-[11px] uppercase tracking-widest"
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
        <li class="border-b border-dashed" style="border-color: var(--line)">
          <button
            class="min-h-[44px] w-full py-2 text-left text-[14px]"
            style="color: var(--green-deep)"
            onclick={() => loadConversation(conv.id)}
          >
            {conv.title ?? 'untitled'}
          </button>
        </li>
      {/each}
    </ul>
  {/if}
</section>
