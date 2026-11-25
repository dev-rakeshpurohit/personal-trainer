import { useEffect, useState } from 'react';

/**
 * Keeps the screen awake while mounted. Uses the Screen Wake Lock API, re-requested on visibilitychange.
 * Fallback (API missing or failing in standalone mode on older iOS): a tiny muted looping inline video.
 */
export function useWakeLock(enabled: boolean): 'on' | 'fallback' | 'off' {
  const [state, setState] = useState<'on' | 'fallback' | 'off'>('off');
  useEffect(() => {
    if (!enabled) return;
    let sentinel: WakeLockSentinel | undefined;
    let video: HTMLVideoElement | undefined;
    let cancelled = false;

    const startFallback = () => {
      if (video) return;
      video = document.createElement('video');
      video.src = '/wake.mp4';
      video.muted = true;
      video.loop = true;
      video.playsInline = true;
      video.setAttribute('playsinline', '');
      video.setAttribute('aria-hidden', 'true');
      Object.assign(video.style, { position: 'fixed', width: '1px', height: '1px', opacity: '0.01', pointerEvents: 'none', bottom: '0', left: '0' });
      document.body.appendChild(video);
      void video.play().catch(() => undefined);
      setState('fallback');
    };

    const request = async () => {
      if (cancelled || document.visibilityState !== 'visible') return;
      if ('wakeLock' in navigator) {
        try {
          sentinel = await navigator.wakeLock.request('screen');
          setState('on');
          return;
        } catch {
          /* fall through */
        }
      }
      startFallback();
    };
    void request();
    const onVis = () => {
      if (document.visibilityState === 'visible') {
        if (video) void video.play().catch(() => undefined);
        else void request();
      }
    };
    document.addEventListener('visibilitychange', onVis);
    return () => {
      cancelled = true;
      document.removeEventListener('visibilitychange', onVis);
      void sentinel?.release().catch(() => undefined);
      video?.remove();
      setState('off');
    };
  }, [enabled]);
  return state;
}
