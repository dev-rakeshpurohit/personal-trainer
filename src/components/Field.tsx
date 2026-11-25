import type { InputHTMLAttributes, ReactNode } from 'react';

export function Field({ label, hint, children }: { label: string; hint?: ReactNode; children: ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-[14px] font-semibold text-muted">{label}</span>
      {children}
      {hint && <span className="mt-1 block text-caption text-muted">{hint}</span>}
    </label>
  );
}

export function TextInput(props: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={`min-h-[52px] w-full rounded-btn border border-line bg-surface2 px-4 text-[17px] text-text outline-none placeholder:text-muted/70 focus:border-primary ${props.className ?? ''}`}
    />
  );
}

export function Toggle({ checked, onChange, label, sub }: { checked: boolean; onChange: (v: boolean) => void; label: string; sub?: string }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className="flex min-h-[56px] w-full items-center justify-between gap-3 py-2 text-left"
    >
      <span>
        <span className="block text-body font-medium">{label}</span>
        {sub && <span className="block text-caption text-muted">{sub}</span>}
      </span>
      <span className={`relative h-8 w-[52px] shrink-0 rounded-full transition-colors ${checked ? 'bg-success' : 'bg-line'}`}>
        <span className={`absolute top-1 h-6 w-6 rounded-full bg-white shadow transition-transform ${checked ? 'translate-x-[24px]' : 'translate-x-1'}`} />
      </span>
    </button>
  );
}
