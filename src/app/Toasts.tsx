import { useUI } from '@/store/ui';

export function Toasts() {
  const { toasts, dismiss } = useUI();
  return (
    <div
      aria-live="polite"
      className="pointer-events-none fixed inset-x-0 bottom-[calc(84px+env(safe-area-inset-bottom))] z-50 flex flex-col items-center gap-2 px-4"
    >
      {toasts.map((t) => (
        <div
          key={t.id}
          className={`pointer-events-auto flex w-full max-w-md animate-pop items-center justify-between gap-3 rounded-card border px-4 py-3 shadow-2xl ${
            t.tone === 'pr'
              ? 'pr-shimmer animate-shimmer border-warning/50 bg-surface2'
              : t.tone === 'success'
                ? 'border-success/40 bg-surface2'
                : 'border-line bg-surface2'
          }`}
        >
          <span className="text-[15px] font-medium">{t.message}</span>
          {t.undo && (
            <button
              type="button"
              className="min-h-[44px] rounded-btn px-3 text-[15px] font-bold text-primary-ink"
              onClick={async () => {
                await t.undo?.();
                dismiss(t.id);
              }}
            >
              Undo
            </button>
          )}
        </div>
      ))}
    </div>
  );
}
