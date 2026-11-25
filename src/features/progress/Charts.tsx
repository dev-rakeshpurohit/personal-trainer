import { format, parseISO } from 'date-fns';
import { Bar, BarChart, CartesianGrid, ComposedChart, Line, ReferenceLine, ResponsiveContainer, Scatter, Tooltip, XAxis, YAxis } from 'recharts';

const axis = { stroke: 'rgb(var(--muted))', fontSize: 12, tickLine: false, axisLine: false } as const;
const tip = {
  contentStyle: { background: 'rgb(var(--surface2))', border: '1px solid rgb(var(--line))', borderRadius: 12, color: 'rgb(var(--text))', fontSize: 14 },
  labelStyle: { color: 'rgb(var(--muted))' },
};

export interface WeightRow {
  t: number;
  raw?: number;
  avg?: number;
  proj?: number;
}

export function WeightChart({ rows, goal, targetDate, unit }: { rows: WeightRow[]; goal?: number; targetDate?: number; unit: string }) {
  const vals = rows.flatMap((r) => [r.raw, r.avg, r.proj]).filter((v): v is number => v != null);
  if (goal != null) vals.push(goal);
  const min = Math.floor(Math.min(...vals) - 0.5);
  const max = Math.ceil(Math.max(...vals) + 0.5);
  return (
    <div className="h-64 w-full" role="img" aria-label="Weight chart: daily weigh-ins, 7-day average and goal">
      <ResponsiveContainer>
        <ComposedChart data={rows} margin={{ top: 8, right: 8, bottom: 0, left: -18 }}>
          <CartesianGrid stroke="rgb(var(--line))" strokeOpacity={0.5} vertical={false} />
          <XAxis dataKey="t" type="number" scale="time" domain={['dataMin', 'dataMax']} tickFormatter={(t) => format(t, 'd MMM')} {...axis} minTickGap={28} />
          <YAxis domain={[min, max]} {...axis} width={44} />
          <Tooltip {...tip} labelFormatter={(t) => format(Number(t), 'EEE d MMM')} formatter={(v: number, n: string) => [`${v.toFixed(1)} ${unit}`, n === 'raw' ? 'Weigh-in' : n === 'avg' ? '7-day avg' : 'Projection']} />
          {goal != null && <ReferenceLine y={goal} stroke="rgb(var(--success))" strokeDasharray="4 4" label={{ value: 'Goal', fill: 'rgb(var(--success))', fontSize: 12, position: 'insideTopRight' }} />}
          {targetDate && <ReferenceLine x={targetDate} stroke="rgb(var(--info))" strokeDasharray="2 4" />}
          <Scatter dataKey="raw" fill="rgb(var(--muted))" fillOpacity={0.45} isAnimationActive={false} />
          <Line dataKey="avg" stroke="rgb(var(--primary))" strokeWidth={3} dot={false} connectNulls isAnimationActive={false} />
          <Line dataKey="proj" stroke="rgb(var(--primary))" strokeWidth={2} strokeDasharray="6 5" dot={false} connectNulls isAnimationActive={false} />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}

export function SimpleLine({ rows, label, unit, color = 'rgb(var(--info))' }: { rows: { t: number; v: number }[]; label: string; unit: string; color?: string }) {
  return (
    <div className="h-40 w-full" role="img" aria-label={label}>
      <ResponsiveContainer>
        <ComposedChart data={rows} margin={{ top: 8, right: 8, bottom: 0, left: -18 }}>
          <CartesianGrid stroke="rgb(var(--line))" strokeOpacity={0.5} vertical={false} />
          <XAxis dataKey="t" type="number" scale="time" domain={['dataMin', 'dataMax']} tickFormatter={(t) => format(t, 'd MMM')} {...axis} minTickGap={28} />
          <YAxis domain={['auto', 'auto']} {...axis} width={44} />
          <Tooltip {...tip} labelFormatter={(t) => format(Number(t), 'd MMM')} formatter={(v: number) => [`${v} ${unit}`, label]} />
          <Line dataKey="v" stroke={color} strokeWidth={3} dot={{ r: 3, fill: color }} isAnimationActive={false} />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}

export function WeekBars({ rows, target }: { rows: { week: string; done: number }[]; target: number }) {
  return (
    <div className="h-44 w-full" role="img" aria-label="Sessions per week">
      <ResponsiveContainer>
        <BarChart data={rows} margin={{ top: 8, right: 8, bottom: 0, left: -12 }}>
          <CartesianGrid stroke="rgb(var(--line))" strokeOpacity={0.5} vertical={false} />
          <XAxis dataKey="week" tickFormatter={(w) => format(parseISO(w), 'd MMM')} {...axis} />
          <YAxis allowDecimals={false} domain={[0, Math.max(target, ...rows.map((r) => r.done))]} {...axis} width={40} />
          <ReferenceLine y={target} stroke="rgb(var(--success))" strokeDasharray="4 4" />
          <Tooltip {...tip} cursor={{ fill: 'rgb(var(--surface2))' }} labelFormatter={(w) => `Week of ${format(parseISO(String(w)), 'd MMM')}`} formatter={(v: number) => [v, 'Sessions']} />
          <Bar dataKey="done" fill="rgb(var(--primary))" radius={[6, 6, 0, 0]} isAnimationActive={false} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
