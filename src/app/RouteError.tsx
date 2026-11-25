import { useRouteError } from 'react-router-dom';

/** Friendly error boundary for routes. Data is safe in IndexedDB, so a reload is always OK. */
export function RouteError() {
  const err = useRouteError() as Error | undefined;
  return (
    <div className="app-shell flex flex-col items-center justify-center gap-4 p-6 text-center pt-safe">
      <div className="text-[44px]" aria-hidden>
        🧰
      </div>
      <h1 className="text-title">Something went wrong</h1>
      <p className="max-w-xs text-[15px] text-muted">Your data is safe on this phone. Reloading usually fixes it.</p>
      {err?.message && <p className="max-w-xs text-caption text-muted/70">{err.message}</p>}
      <div className="flex gap-2">
        <button type="button" onClick={() => window.location.assign('/today')} className="min-h-[48px] rounded-btn bg-surface2 px-5 font-semibold">
          Go home
        </button>
        <button type="button" onClick={() => window.location.reload()} className="min-h-[48px] rounded-btn bg-primary px-5 font-semibold text-on-primary">
          Reload
        </button>
      </div>
    </div>
  );
}
