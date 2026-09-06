import { env } from '$env/dynamic/private';
import type { PageServerLoad } from './$types';

const API_URL = env.API_URL ?? 'http://localhost:8000';

export const load: PageServerLoad = async ({ fetch, url }) => {
  const recipeSlug = url.searchParams.get('recipe');
  let recipeTitle: string | null = null;
  if (recipeSlug) {
    const res = await fetch(`${API_URL}/api/v1/recipes/${encodeURIComponent(recipeSlug)}`);
    if (res.ok) recipeTitle = (await res.json()).title;
  }
  let conversations: Array<{ id: string; title: string | null; created_at: string }> = [];
  try {
    const res = await fetch(`${API_URL}/api/v1/conversations`);
    if (res.ok) conversations = await res.json();
  } catch {
    // API down — page still renders
  }
  // book names for the scope selector (degrades to whole-library only)
  let books: string[] = [];
  try {
    const res = await fetch(`${API_URL}/api/v1/library/books`);
    if (res.ok) {
      const lib = await res.json();
      books = (lib.books ?? [])
        .filter((b: { kind: string }) => b.kind === 'file')
        .map((b: { name: string }) => b.name);
    }
  } catch {
    // rag-api down — selector hides
  }
  return { recipeSlug, recipeTitle, conversations, books };
};

// Writes go through form actions so the bearer token stays server-side — the
// browser proxy at /api forwards no Authorization header (see lib/api.ts).
import { fail } from '@sveltejs/kit';
import { ApiError, deleteConversation, renameConversation, setMessageFeedback } from '$lib/api';
import type { Actions } from './$types';

function str(v: FormDataEntryValue | null): string {
  return typeof v === 'string' ? v : '';
}

async function guarded<T>(op: () => Promise<T>) {
  try {
    await op();
    return { ok: true };
  } catch (e) {
    if (e instanceof ApiError) return fail(e.status >= 500 ? 502 : e.status, { message: e.message });
    return fail(502, { message: 'Could not reach the server' });
  }
}

export const actions: Actions = {
  feedback: async ({ request, fetch }) => {
    const form = await request.formData();
    const raw = str(form.get('feedback'));
    const feedback = raw === 'up' || raw === 'down' ? raw : null;
    return guarded(() =>
      setMessageFeedback(fetch, str(form.get('conversation_id')), str(form.get('message_id')), feedback)
    );
  },
  rename: async ({ request, fetch }) => {
    const form = await request.formData();
    const title = str(form.get('title')).trim();
    if (!title) return fail(422, { message: 'A title is needed' });
    return guarded(() => renameConversation(fetch, str(form.get('id')), title));
  },
  delete: async ({ request, fetch }) => {
    const form = await request.formData();
    return guarded(() => deleteConversation(fetch, str(form.get('id'))));
  }
};
