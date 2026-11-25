/** Session sequencing: supersets alternate A1 → A2 → A1 … (doc 02 §3.3). Pure. */
export interface FlowExercise {
  sets: number;
  supersetGroup?: string;
}
export interface Step {
  ex: number;
  set: number;
}

export function buildFlow(exs: FlowExercise[]): Step[] {
  const steps: Step[] = [];
  let i = 0;
  while (i < exs.length) {
    const g = exs[i].supersetGroup;
    let j = i + 1;
    if (g) while (j < exs.length && exs[j].supersetGroup === g) j++;
    const block = exs.slice(i, j).map((e, k) => ({ idx: i + k, sets: e.sets }));
    const maxSets = Math.max(...block.map((b) => b.sets));
    for (let s = 0; s < maxSets; s++) for (const b of block) if (s < b.sets) steps.push({ ex: b.idx, set: s });
    i = j;
  }
  return steps;
}

const key = (s: Step) => `${s.ex}:${s.set}`;

/** Next pending step after `from` (wrapping), or undefined if everything is done. */
export function nextStep(flow: Step[], done: Set<string>, from?: Step): Step | undefined {
  const start = from ? flow.findIndex((s) => s.ex === from.ex && s.set === from.set) : -1;
  for (let k = 1; k <= flow.length; k++) {
    const s = flow[(start + k + flow.length) % flow.length];
    if (!done.has(key(s))) return s;
  }
  return undefined;
}

export const stepKey = key;
