import { Minus, Plus } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';

interface Props {
  label: string;
  value: number | undefined;
  onChange: (v: number) => void;
  step: number;
  min?: number;
  max?: number;
  suffix?: string;
  decimals?: number;
  inputMode?: 'decimal' | 'numeric';
  size?: 'md' | 'lg';
  placeholder?: string;
}

/** Big ± stepper with hold-to-repeat; tapping the value allows typing. */
export function Stepper({ label, value, onChange, step, min = 0, max = 9999, suffix, decimals = 2, inputMode = 'decimal', size = 'md', placeholder = '–' }: Props) {
  const timer = useRef<ReturnType<typeof setTimeout>>();
  const valRef = useRef(value);
  valRef.current = value;
  const [text, setText] = useState<string | null>(null);

  const clamp = (v: number) => Math.min(max, Math.max(min, Number(v.toFixed(decimals))));
  const bump = (dir: 1 | -1) => onChange(clamp((valRef.current ?? 0) + dir * step));

  const start = (dir: 1 | -1) => {
    bump(dir);
    let delay = 380;
    const loop = () => {
      timer.current = setTimeout(() => {
        bump(dir);
        delay = Math.max(60, delay * 0.8);
        loop();
      }, delay);
    };
    loop();
  };
  const stop = () => clearTimeout(timer.current);
  useEffect(() => stop, []);

  const h = size === 'lg' ? 'h-14' : 'h-12';
  const btn = `flex ${h} w-12 shrink-0 items-center justify-center rounded-btn bg-surface2 text-text active:bg-line active:scale-95 transition-transform`;
  const fmt = (v: number | undefined) => (v == null ? '' : String(Number(v.toFixed(decimals))));

  return (
    <div className="flex min-w-0 items-center gap-1.5" role="group" aria-label={label}>
      <button
        type="button"
        className={btn}
        aria-label={`Decrease ${label}`}
        onPointerDown={(e) => {
          e.preventDefault();
          start(-1);
        }}
        onPointerUp={stop}
        onPointerLeave={stop}
        onPointerCancel={stop}
        onKeyDown={(e) => (e.key === 'Enter' || e.key === ' ') && bump(-1)}
      >
        <Minus size={20} aria-hidden />
      </button>
      <label className="relative min-w-0 flex-1">
        <span className="sr-only">{label}</span>
        <input
          className={`${h} w-full min-w-[3.5rem] rounded-btn bg-transparent text-center text-[22px] font-bold tnum outline-none focus:bg-surface2`}
          inputMode={inputMode}
          value={text ?? fmt(value)}
          placeholder={placeholder}
          onFocus={(e) => {
            setText(fmt(value));
            requestAnimationFrame(() => e.target.select());
          }}
          onChange={(e) => setText(e.target.value.replace(',', '.'))}
          onBlur={() => {
            if (text != null && text !== '' && !Number.isNaN(Number(text))) onChange(clamp(Number(text)));
            setText(null);
          }}
          onKeyDown={(e) => e.key === 'Enter' && (e.target as HTMLInputElement).blur()}
        />
        {suffix && <span className="pointer-events-none absolute bottom-0.5 left-0 right-0 text-center text-[11px] font-medium text-muted">{suffix}</span>}
      </label>
      <button
        type="button"
        className={btn}
        aria-label={`Increase ${label}`}
        onPointerDown={(e) => {
          e.preventDefault();
          start(1);
        }}
        onPointerUp={stop}
        onPointerLeave={stop}
        onPointerCancel={stop}
        onKeyDown={(e) => (e.key === 'Enter' || e.key === ' ') && bump(1)}
      >
        <Plus size={20} aria-hidden />
      </button>
    </div>
  );
}
