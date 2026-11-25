/** Tiny dependency-free line chart (used where Recharts would be overkill). */
export function Sparkline({ values, width = 320, height = 80, color = 'rgb(var(--primary))', label, dots = true }: { values: number[]; width?: number; height?: number; color?: string; label: string; dots?: boolean }) {
  if (values.length < 2)
    return (
      <div className="flex items-center justify-center text-caption text-muted" style={{ height }}>
        Not enough data yet
      </div>
    );
  const min = Math.min(...values);
  const max = Math.max(...values);
  const pad = 6;
  const x = (i: number) => pad + (i * (width - pad * 2)) / (values.length - 1);
  const y = (v: number) => (max === min ? height / 2 : pad + (height - pad * 2) * (1 - (v - min) / (max - min)));
  const d = values.map((v, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(' ');
  const area = `${d} L${x(values.length - 1)},${height} L${x(0)},${height} Z`;
  return (
    <svg viewBox={`0 0 ${width} ${height}`} className="h-auto w-full" role="img" aria-label={label} preserveAspectRatio="none">
      <defs>
        <linearGradient id="spark" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={color} stopOpacity="0.3" />
          <stop offset="1" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={area} fill="url(#spark)" />
      <path d={d} fill="none" stroke={color} strokeWidth={2.5} strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
      {dots && values.map((v, i) => <circle key={i} cx={x(i)} cy={y(v)} r={3} fill={color} />)}
    </svg>
  );
}
