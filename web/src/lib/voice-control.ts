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
  | null;

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
    return best >= 0 ? { type: 'how-much', ingredient: best } : null;
  }

  if (/\b(start|begin|resume)\b.*\btimer\b|\btimer\b.*\b(start|begin|resume)\b/.test(t))
    return { type: 'timer-start' };
  if (/\b(pause|stop|hold)\b.*\btimer\b|\btimer\b.*\b(pause|stop|hold)\b/.test(t))
    return { type: 'timer-pause' };
  if (/\breset\b.*\btimer\b|\btimer\b.*\breset\b/.test(t)) return { type: 'timer-reset' };

  if (/\b(next|continue|forward|done|onwards?)\b/.test(t)) return { type: 'next' };
  if (/\b(back|previous|go back)\b/.test(t)) return { type: 'back' };
  if (/\b(repeat|again|read (it|that))\b/.test(t)) return { type: 'repeat' };
  return null;
}

export function speak(text: string): void {
  try {
    const u = new SpeechSynthesisUtterance(text);
    u.rate = 1.05;
    window.speechSynthesis.cancel();
    window.speechSynthesis.speak(u);
  } catch {
    // no TTS — visual UI still shows everything
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
