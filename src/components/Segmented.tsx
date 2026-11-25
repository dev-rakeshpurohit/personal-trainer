interface Props<T extends string> {
  value: T;
  options: { value: T; label: string }[];
  onChange: (v: T) => void;
  label: string;
}

export function Segmented<T extends string>({ value, options, onChange, label }: Props<T>) {
  return (
    <div role="tablist" aria-label={label} className="flex rounded-btn bg-surface2 p-1">
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role="tab"
          aria-selected={value === o.value}
          onClick={() => onChange(o.value)}
          className={`min-h-[44px] flex-1 rounded-[10px] text-[15px] font-semibold transition-colors ${value === o.value ? 'bg-surface text-text shadow' : 'text-muted'}`}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}
