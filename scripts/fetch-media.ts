/**
 * Downloads the public-domain (Unlicense) free-exercise-db images listed in seed/free-exercise-db-ids.json,
 * resizes them to 480 px wide WebP (q72) and writes public/media/exercises/<id>/{0,1}.webp + index.json.
 */
import sharp from 'sharp';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const OUT = path.join(ROOT, 'public/media/exercises');
// jsDelivr mirrors the GitHub repo; raw.githubusercontent.com is the fallback.
const BASES = ['https://cdn.jsdelivr.net/gh/yuhonas/free-exercise-db@main', 'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main'];
/** Ids whose free-exercise-db entry has no images: borrow images from the same movement. */
const IMAGE_FALLBACK: Record<string, string> = {
  Kettlebell_Overhead_Triceps_Extension: 'Standing_Dumbbell_Triceps_Extension',
};
const ids: string[] = JSON.parse(readFileSync(path.join(ROOT, 'seed/free-exercise-db-ids.json'), 'utf8'));

interface DbEx {
  id: string;
  name: string;
  instructions: string[];
  primaryMuscles: string[];
  secondaryMuscles?: string[];
  equipment: string | null;
  category: string;
  images: string[];
}

async function get(file: string): Promise<Buffer> {
  for (const base of BASES) {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const r = await fetch(`${base}/${file}`, { signal: AbortSignal.timeout(15000) });
        if (r.ok) return Buffer.from(await r.arrayBuffer());
        if (r.status === 404) break;
      } catch {
        /* retry / next mirror */
      }
      await new Promise((res) => setTimeout(res, 500 * (attempt + 1)));
    }
  }
  throw new Error(`failed to download ${file}`);
}

const all: DbEx[] = JSON.parse((await get('dist/exercises.json')).toString('utf8'));
const byId = new Map(all.map((e) => [e.id, e]));
const index: object[] = [];
let bytes = 0;

for (const id of ids) {
  const meta = byId.get(id);
  if (!meta) {
    console.warn(`! ${id} not found in free-exercise-db`);
    continue;
  }
  const dir = path.join(OUT, id);
  mkdirSync(dir, { recursive: true });
  for (const n of [0, 1]) {
    const file = path.join(dir, `${n}.webp`);
    if (!existsSync(file)) {
      const src = meta.images.length >= 2 ? id : (IMAGE_FALLBACK[id] ?? id);
      const img = await get(`exercises/${src}/${n}.jpg`);
      await sharp(img).resize({ width: 480, withoutEnlargement: true }).webp({ quality: 72 }).toFile(file);
    }
    bytes += readFileSync(file).length;
  }
  index.push({
    id,
    name: meta.name,
    instructions: meta.instructions,
    primaryMuscles: meta.primaryMuscles,
    equipment: meta.equipment ? [meta.equipment] : [],
    category: meta.category,
  });
  process.stdout.write('.');
}
writeFileSync(path.join(OUT, 'index.json'), JSON.stringify(index, null, 1));
console.log(`\n${index.length}/${ids.length} exercises, ${(bytes / 1024 / 1024).toFixed(2)} MB of images`);
