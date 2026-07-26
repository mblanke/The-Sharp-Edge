/**
 * Web dictation helpers.
 *
 * Kept as a plain module rather than living inside a `.svelte` file because web has
 * no component tests and no Playwright — this is the part worth pinning with vitest.
 *
 * Parsing itself is not here: `POST /api/v1/parse/ingredients` owns the four-language
 * lexicon so web and iOS behave identically. No model is involved on either side.
 */

export const CAPTURE_LANGUAGES = [
  { code: 'en', tag: 'en-US', name: 'English', flag: '🇬🇧' },
  { code: 'fr', tag: 'fr-FR', name: 'Français', flag: '🇫🇷' },
  { code: 'de', tag: 'de-DE', name: 'Deutsch', flag: '🇩🇪' },
  { code: 'ro', tag: 'ro-RO', name: 'Română', flag: '🇷🇴' }
] as const;

export type CaptureLanguage = (typeof CAPTURE_LANGUAGES)[number]['code'];

export function speechTag(code: CaptureLanguage): string {
  return CAPTURE_LANGUAGES.find((l) => l.code === code)?.tag ?? 'en-US';
}

/**
 * One utterance per line. Dictation renders the pauses between spoken items as
 * sentence punctuation, so that is what we split on — the review screen fixes the rest.
 */
export function splitUtterances(text: string): string[] {
  return text
    .replace(/\n+/g, '. ')
    .split(/[.;]+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

export interface SpeechHandle {
  stop(): void;
}

type SpeechCtor = new () => {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  start(): void;
  stop(): void;
  onresult: ((e: { results: ArrayLike<ArrayLike<{ transcript: string }>> }) => void) | null;
  onerror: ((e: { error?: string }) => void) | null;
  onend: (() => void) | null;
};

function ctor(): SpeechCtor | undefined {
  if (typeof window === 'undefined') return undefined;
  const w = window as unknown as Record<string, SpeechCtor | undefined>;
  return w.SpeechRecognition ?? w.webkitSpeechRecognition;
}

export function speechSupported(): boolean {
  return ctor() !== undefined;
}

/**
 * Safari routes audio to Apple's speech service for every language — the on-device
 * guarantee the iOS app can make for en/fr/de does not apply in a browser. Say so
 * rather than implying otherwise.
 */
export const WEB_SPEECH_NOTICE =
  "Browser dictation is transcribed by your browser vendor's speech service, not on this device.";

export function listen(
  code: CaptureLanguage,
  onText: (text: string) => void,
  onEnd?: (error?: string) => void
): SpeechHandle | null {
  const Recognition = ctor();
  if (!Recognition) return null;

  const recognition = new Recognition();
  recognition.lang = speechTag(code);
  recognition.continuous = true;
  recognition.interimResults = true;

  recognition.onresult = (event) => {
    let out = '';
    for (let i = 0; i < event.results.length; i++) out += event.results[i][0].transcript;
    onText(out);
  };
  recognition.onerror = (event) => onEnd?.(event.error);
  recognition.onend = () => onEnd?.();
  recognition.start();

  return { stop: () => recognition.stop() };
}
