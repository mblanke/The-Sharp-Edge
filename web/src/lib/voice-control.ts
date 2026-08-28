/** Hands-free cook mode (F1): a small on-device command grammar over the Web
 *  Speech API. Nothing leaves the browser; silently unavailable where the API
 *  is missing. The parser is pure — tested in voice.test.ts. */

import { keywords } from './cook';
import type { Ingredient } from './types';

export type VoiceIntent =
  | { type: 'next' }
  | { type: 'back' }
  | { type: 'repeat' }
  | { type: 'timer-start' }
  | { type: 'timer-pause' }
  | { type: 'timer-reset' }
  | { type: 'how-much'; ingredient: number } // index into the ingredient list
  | { type: 'ask'; question: string } // a real question → the library, mid-cook
  | null;

/** Question-shaped speech: an interrogative opener and enough words to mean it.
 *  Deliberately strict — kitchen chatter must not fire LLM calls, so a bare
 *  exclamation ("what!") or a two-word fragment never counts. */
const QUESTION_OPENER =
  /^(?:hey\s+library[,\s]+)?(how|what|why|when|which|where|can|could|should|do|does|is|are|will)\b/;

export function questionOf(transcript: string): string | null {
  const t = transcript.trim().replace(/\s+/g, ' ');
  if (t.split(' ').length < 4) return null;
  if (!QUESTION_OPENER.test(t.toLowerCase())) return null;
  return t.replace(/^hey\s+library[,\s]+/i, '');
}

/** Map a spoken transcript to an intent. Later phrases win ("okay next"). */
export function parseCommand(transcript: string, ingredients: Ingredient[]): VoiceIntent {
  const t = transcript.trim().toLowerCase();
  if (!t) return null;

  const howMuch = t.match(/how (?:much|many)(?: of)?(?: the)? (.+?)(?:\?|$| do| does| is| are)/);
  if (howMuch) {
    const asked = howMuch[1];
    let best = -1;
    let bestScore = 0;
    ingredients.forEach((ing, i) => {
      const score = keywords(ing.name).filter((w) => asked.includes(w.replace(/s$/, '')) || asked.includes(w)).length;
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    });
    if (best >= 0) return { type: 'how-much', ingredient: best };
    // No such ingredient in this recipe — fall through: the question is still real
    // ("how much saffron does a paella need"), and the library can answer it.
  }

  if (/\b(start|begin|resume)\b.*\btimer\b|\btimer\b.*\b(start|begin|resume)\b/.test(t))
    return { type: 'timer-start' };
  if (/\b(pause|stop|hold)\b.*\btimer\b|\btimer\b.*\b(pause|stop|hold)\b/.test(t))
    return { type: 'timer-pause' };
  if (/\breset\b.*\btimer\b|\btimer\b.*\breset\b/.test(t)) return { type: 'timer-reset' };

  if (/\b(next|continue|forward|done|onwards?)\b/.test(t)) return { type: 'next' };
  if (/\b(back|previous|go back)\b/.test(t)) return { type: 'back' };
  if (/\b(repeat|again|read (it|that))\b/.test(t)) return { type: 'repeat' };

  // Last, after every command has had its chance: a genuine question goes to the
  // library. This also catches "how much saffron" when the recipe has no saffron —
  // an unmatched how-much falls through to become a real question about the shelf.
  const q = questionOf(transcript);
  if (q) return { type: 'ask', question: q };
  return null;
}

export function speak(text: string, onDone?: () => void): void {
  try {
    const u = new SpeechSynthesisUtterance(text);
    u.rate = 1.05;
    if (onDone) {
      u.onend = onDone;
      u.onerror = onDone;
    }
    window.speechSynthesis.cancel();
    window.speechSynthesis.speak(u);
  } catch {
    // no TTS — visual UI still shows everything
    onDone?.();
  }
}

export interface VoiceListener {
  supported: boolean;
  stop(): void;
}

type SpeechRecognitionCtor = new () => {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  onresult: ((e: { results: ArrayLike<ArrayLike<{ transcript: string }>>; resultIndex: number }) => void) | null;
  onend: (() => void) | null;
  onerror: (() => void) | null;
  start(): void;
  stop(): void;
};

/** Start continuous recognition; onTranscript fires per final phrase. */
export function listen(onTranscript: (text: string) => void): VoiceListener {
  const w = window as unknown as Record<string, SpeechRecognitionCtor | undefined>;
  const Ctor = w['SpeechRecognition'] ?? w['webkitSpeechRecognition'];
  if (!Ctor) return { supported: false, stop() {} };

  let stopped = false;
  const rec = new Ctor();
  rec.continuous = true;
  rec.interimResults = false;
  rec.lang = 'en-CA';
  rec.onresult = (e) => {
    const last = e.results[e.results.length - 1];
    const transcript = last?.[0]?.transcript;
    if (transcript) onTranscript(transcript);
  };
  // Safari ends sessions on silence — keep re-arming until stopped
  rec.onend = () => {
    if (!stopped) {
      try {
        rec.start();
      } catch {
        stopped = true;
      }
    }
  };
  rec.onerror = () => {};
  try {
    rec.start();
  } catch {
    return { supported: false, stop() {} };
  }
  return {
    supported: true,
    stop() {
      stopped = true;
      try {
        rec.stop();
      } catch {
        // already stopped
      }
    }
  };
}
