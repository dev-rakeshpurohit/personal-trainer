/** Keeps 3D demo animations available offline beyond the precached set (see src/sw.ts DEMO_CACHE). */
import { db } from '@/data/db';
import { demoAnimSrc } from './clips';

const CACHE = 'demos-v1';
const supported = () => typeof caches !== 'undefined' && navigator.onLine;

async function missing(urls: string[]): Promise<string[]> {
  const out: string[] = [];
  for (const u of urls) if (!(await caches.match(u))) out.push(u);
  return out;
}

async function fill(urls: string[], onProgress?: (done: number, total: number) => void, signal?: AbortSignal) {
  const cache = await caches.open(CACHE);
  const todo = await missing([...new Set(urls)]);
  let done = 0;
  const queue = [...todo];
  await Promise.all(
    Array.from({ length: 6 }, async () => {
      for (let u = queue.shift(); u && !signal?.aborted; u = queue.shift()) {
        try {
          await cache.add(u);
        } catch {
          /* offline or missing file: try again next time */
        }
        onProgress?.(++done, todo.length);
      }
    }),
  );
  return todo.length;
}

/** Cache the animations for everything in the active plan (planned, swaps and their alternates). */
export async function cachePlanDemos(): Promise<number> {
  if (!supported()) return 0;
  const program = await db.programs.filter((p) => p.active).first();
  if (!program) return 0;
  const days = await db.programDays.where('programId').equals(program.id).primaryKeys();
  const planned = await db.plannedExercises.where('dayId').anyOf(days).toArray();
  const ids = new Set(planned.flatMap((p) => [p.exerciseId, p.swapExerciseId]).filter((x): x is string => !!x));
  const exercises = (await db.exercises.bulkGet([...ids])).filter((e) => !!e);
  for (const e of exercises) for (const a of e!.alternates ?? []) ids.add(a);
  const all = (await db.exercises.bulkGet([...ids])).filter((e) => !!e);
  return fill(all.map((e) => demoAnimSrc(e!)).filter((u): u is string => !!u));
}

/** Every demo in the library (≈40 MB). */
export async function downloadAllDemos(onProgress: (done: number, total: number) => void, signal?: AbortSignal): Promise<number> {
  if (!supported()) return 0;
  const all = await db.exercises.toArray();
  return fill(all.map((e) => demoAnimSrc(e)).filter((u): u is string => !!u), onProgress, signal);
}

/** How many library demos are available offline right now. */
export async function offlineDemoCount(): Promise<{ cached: number; total: number }> {
  const all = (await db.exercises.toArray()).map((e) => demoAnimSrc(e)).filter((u): u is string => !!u);
  const uniq = [...new Set(all)];
  if (typeof caches === 'undefined') return { cached: 0, total: uniq.length };
  let cached = 0;
  for (const u of uniq) if (await caches.match(u)) cached++;
  return { cached, total: uniq.length };
}
