/** Keep the screen awake during a cook (CLAUDE.md §7 cook mode).
 *  Primary: Screen Wake Lock API (iPadOS Safari ≥ 16.4), re-acquired on tab
 *  return. Fallback: an invisible looping canvas-stream video (NoSleep-style,
 *  no bundled media). Call release() on unmount. */

export interface WakeLockHandle {
  release(): void;
}

export function keepAwake(): WakeLockHandle {
  let sentinel: WakeLockSentinel | null = null;
  let video: HTMLVideoElement | null = null;
  let released = false;

  async function acquire() {
    if (released || document.visibilityState !== 'visible') return;
    if ('wakeLock' in navigator) {
      try {
        sentinel = await navigator.wakeLock.request('screen');
        return;
      } catch {
        // fall through to the video fallback
      }
    }
    videoFallback();
  }

  function videoFallback() {
    if (video || released) return;
    try {
      const canvas = document.createElement('canvas');
      canvas.width = canvas.height = 2;
      const ctx = canvas.getContext('2d');
      if (!ctx || typeof canvas.captureStream !== 'function') return;
      // repaint keeps the stream live
      const paint = () => {
        if (released) return;
        ctx.fillStyle = '#000';
        ctx.fillRect(0, 0, 2, 2);
        setTimeout(paint, 1000);
      };
      paint();
      video = document.createElement('video');
      video.srcObject = canvas.captureStream(1);
      video.muted = true;
      video.setAttribute('playsinline', '');
      video.style.position = 'fixed';
      video.style.width = '1px';
      video.style.height = '1px';
      video.style.opacity = '0';
      video.style.pointerEvents = 'none';
      document.body.appendChild(video);
      void video.play();
    } catch {
      // screen may sleep — nothing more we can do
    }
  }

  const onVisibility = () => {
    if (document.visibilityState === 'visible') void acquire();
  };
  document.addEventListener('visibilitychange', onVisibility);
  void acquire();

  return {
    release() {
      released = true;
      document.removeEventListener('visibilitychange', onVisibility);
      void sentinel?.release().catch(() => {});
      sentinel = null;
      if (video) {
        video.pause();
        video.remove();
        video = null;
      }
    }
  };
}
