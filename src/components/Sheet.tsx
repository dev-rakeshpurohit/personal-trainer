import { X } from 'lucide-react';
import { useEffect, useId, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';

interface Props {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  footer?: ReactNode;
  tall?: boolean;
}

/** Accessible bottom sheet (modal dialog) respecting the home-indicator safe area. */
export function Sheet({ open, onClose, title, children, footer, tall }: Props) {
  const id = useId();
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const prev = document.activeElement as HTMLElement | null;
    ref.current?.focus();
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('keydown', onKey);
      prev?.focus?.();
    };
  }, [open, onClose]);
  if (!open) return null;
  return createPortal(
    <div className="fixed inset-0 z-[60] flex flex-col justify-end">
      <button type="button" aria-label="Close" tabIndex={-1} className="absolute inset-0 animate-fade-in bg-black/60" onClick={onClose} />
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-labelledby={id}
        tabIndex={-1}
        className={`relative flex animate-slide-up flex-col rounded-t-[24px] border-t border-line/60 bg-surface outline-none ${tall ? 'max-h-[92dvh]' : 'max-h-[85dvh]'}`}
      >
        <div className="mx-auto mt-2 h-1.5 w-10 rounded-full bg-line" aria-hidden />
        <div className="flex items-center justify-between px-5 pb-1 pt-2">
          <h2 id={id} className="text-title">
            {title}
          </h2>
          <button type="button" onClick={onClose} aria-label="Close" className="-mr-2 flex h-12 w-12 items-center justify-center rounded-full text-muted active:bg-surface2">
            <X size={22} />
          </button>
        </div>
        <div className="flex-1 overflow-y-auto overscroll-contain px-5 pb-4">{children}</div>
        {footer && <div className="border-t border-line/50 px-5 pb-[calc(12px+env(safe-area-inset-bottom))] pt-3">{footer}</div>}
        {!footer && <div className="pb-[env(safe-area-inset-bottom)]" />}
      </div>
    </div>,
    document.body,
  );
}
