import { describe, expect, it } from 'vitest';
import demoMap from '../../seed/demo-map.json';
import { curatedLibrary, staticLibrary } from './plan-builder';
import { demoAnimSrc, demoIdFor, exerciseThumb } from '@/lib/clips';

const map = demoMap.map as Record<string, string | null>;
const files = demoMap.files as Record<string, string>;

describe('demo map', () => {
  it('covers every curated exercise and nothing else', () => {
    const ids = new Set(curatedLibrary().map((e) => e.id));
    expect(Object.keys(map).sort()).toEqual([...ids].sort());
  });

  it('has a source file for every mapped demo', () => {
    for (const id of Object.values(map)) if (id) expect(files[id], id).toMatch(/^videos\/\d{4}-\w+\.gif$/);
  });

  it('maps most of the library to an animated demo', () => {
    const mapped = Object.values(map).filter(Boolean).length;
    expect(mapped / Object.keys(map).length).toBeGreaterThan(0.9);
  });

  it('full library has unique ids and a demo for every dataset exercise', () => {
    const lib = staticLibrary();
    expect(new Set(lib.map((e) => e.id)).size).toBe(lib.length);
    expect(lib.length).toBeGreaterThan(1300);
    expect(lib.filter((e) => e.source === 'dataset').every((e) => !!e.demoId)).toBe(true);
  });

  it('resolves animated + still sources, falling back to photos', () => {
    expect(demoIdFor({ id: 'dumbbell-goblet-squat' })).toBe('1760');
    expect(demoAnimSrc({ id: 'dumbbell-goblet-squat' })).toBe('/media/demos/1760.webp');
    expect(demoAnimSrc({ id: 'machine-lying-leg-curl', demoId: '0586' })).toBe('/media/demos/0586.webp');
    expect(exerciseThumb({ id: 'dumbbell-goblet-squat', freeDbId: 'Goblet_Squat' })).toBe('/media/demos/1760-t.webp');
    expect(exerciseThumb({ id: 'rowing-machine', freeDbId: 'Rowing_Stationary' })).toBe('/media/exercises/Rowing_Stationary/0.webp');
    expect(exerciseThumb({ id: 'my-custom-move' })).toBeUndefined();
    expect(demoAnimSrc(undefined)).toBeUndefined();
  });
});
