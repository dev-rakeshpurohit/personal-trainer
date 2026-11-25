/**
 * Rest-timer alerts. iOS: no vibrate, so we use a Web Audio chime (unlocked on the first tap),
 * a full-screen colour flash, and (if installed + permitted) a SW notification.
 */
let ctx: AudioContext | undefined;

function audio(): AudioContext | undefined {
  if (ctx) return ctx;
  const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!AC) return undefined;
  ctx = new AC();
  return ctx;
}

export function unlockAudioOnFirstTap(): () => void {
  const unlock = () => {
    const a = audio();
    if (a && a.state === 'suspended') void a.resume();
    // play a silent buffer: required by iOS to fully unlock
    if (a) {
      const b = a.createBuffer(1, 1, 22050);
      const s = a.createBufferSource();
      s.buffer = b;
      s.connect(a.destination);
      s.start(0);
    }
  };
  window.addEventListener('pointerdown', unlock, { once: true, capture: true });
  return () => window.removeEventListener('pointerdown', unlock, { capture: true });
}

export function chime(kind: 'end' | 'tick' = 'end') {
  const a = audio();
  if (!a) return;
  if (a.state === 'suspended') void a.resume();
  const now = a.currentTime;
  const notes = kind === 'end' ? [880, 1174.66, 1567.98] : [660];
  notes.forEach((freq, i) => {
    const o = a.createOscillator();
    const g = a.createGain();
    o.type = 'sine';
    o.frequency.value = freq;
    const t = now + i * 0.14;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.35, t + 0.02);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.45);
    o.connect(g).connect(a.destination);
    o.start(t);
    o.stop(t + 0.5);
  });
}

export function vibrate(pattern: number | number[]) {
  try {
    navigator.vibrate?.(pattern);
  } catch {
    /* iOS: unsupported */
  }
}

export const notificationsSupported = () => 'Notification' in window && 'serviceWorker' in navigator;

export async function requestNotificationPermission(): Promise<NotificationPermission | 'unsupported'> {
  if (!notificationsSupported()) return 'unsupported';
  try {
    return await Notification.requestPermission();
  } catch {
    return 'denied';
  }
}

async function postToSW(msg: object) {
  try {
    const reg = await navigator.serviceWorker?.ready;
    reg?.active?.postMessage(msg);
  } catch {
    /* no SW in dev */
  }
}

/** Ask the SW to show a notification at endsAt (works while the SW stays alive; iOS catches up on reopen). */
export function scheduleRestNotification(endsAt: number, body: string) {
  if (!notificationsSupported() || Notification.permission !== 'granted') return;
  void postToSW({ type: 'SCHEDULE_REST', endsAt, title: 'Rest over', body });
}

export function cancelRestNotification() {
  void postToSW({ type: 'CANCEL_REST' });
}
