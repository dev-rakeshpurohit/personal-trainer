/**
 * Downloads the animated exercise demos listed in seed/demo-map.json and converts them to
 * animated WebP (≈⅓ the size of the GIF, plays natively in Safari) + a still thumbnail.
 *
 *   pnpm fetch:demos          # skips files that already exist
 *   pnpm fetch:demos --force
 *
 * Media © Gym visual (https://gymvisual.com/), redistributed via hasaneyldrm/exercises-dataset.
 * Personal, non-commercial use only. The files are git-ignored and must never be committed.
 */
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import sharp from 'sharp';
import map from '../seed/demo-map.json' with { type: 'json' };

const BASE = 'https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/';
const OUT = join(import.meta.dirname, '..', 'public', 'media', 'demos');
const force = process.argv.includes('--force');

mkdirSync(OUT, { recursive: true });
const files = map.files as Record<string, string>;
const ids = Object.keys(files);

async function fetchRetry(url: string, tries = 3): Promise<Buffer> {
  for (let i = 1; ; i++) {
    try {
      const r = await fetch(url);
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return Buffer.from(await r.arrayBuffer());
    } catch (e) {
      if (i >= tries) throw e;
      await new Promise((res) => setTimeout(res, 800 * i));
    }
  }
}

let done = 0;
let failed = 0;
const queue = [...ids];
await Promise.all(
  Array.from({ length: 8 }, async () => {
    for (let id = queue.shift(); id; id = queue.shift()) {
      const anim = join(OUT, `${id}.webp`);
      const thumb = join(OUT, `${id}-t.webp`);
      if (!force && existsSync(anim) && existsSync(thumb)) {
        done++;
        continue;
      }
      try {
        const gif = await fetchRetry(BASE + files[id]);
        writeFileSync(anim, await sharp(gif, { animated: true }).webp({ quality: 72, effort: 6, loop: 0 }).toBuffer());
        const pages = (await sharp(gif).metadata()).pages ?? 1;
        // A frame from the second half usually shows the contracted ("peak") position.
        writeFileSync(thumb, await sharp(gif, { page: Math.floor(pages * 0.5) }).webp({ quality: 78 }).toBuffer());
        done++;
      } catch (e) {
        failed++;
        console.warn(`✗ ${id}: ${(e as Error).message}`);
      }
    }
  }),
);
console.log(`demos: ${done}/${ids.length} ready${failed ? `, ${failed} failed` : ''} → public/media/demos`);
if (failed) process.exitCode = 1;
