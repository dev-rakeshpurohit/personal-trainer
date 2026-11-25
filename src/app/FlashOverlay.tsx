import { useEffect, useState } from 'react';
import { useUI } from '@/store/ui';

/** Full-screen colour flash when the rest timer ends (iOS has no vibration). */
export function FlashOverlay() {
  const flash = useUI((s) => s.flash);
  const [show, setShow] = useState(0);
  useEffect(() => {
    if (!flash) return;
    setShow(flash);
    const t = setTimeout(() => setShow(0), 1300);
    return () => clearTimeout(t);
  }, [flash]);
  if (!show) return null;
  return <div key={show} aria-hidden className="pointer-events-none fixed inset-0 z-[70] animate-flash bg-success/40" />;
}
