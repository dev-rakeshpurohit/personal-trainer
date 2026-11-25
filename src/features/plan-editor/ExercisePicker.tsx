import { useLiveQuery } from 'dexie-react-hooks';
import { Plus, Search } from 'lucide-react';
import { useState } from 'react';
import { Button, Chip } from '@/components/ui';
import { Field, TextInput, Toggle } from '@/components/Field';
import { Sheet } from '@/components/Sheet';
import { db } from '@/data/db';
import { slugify } from '@/data/seed-import';
import type { Category, Exercise, Unit } from '@/domain/types';
import { demoSrc } from '@/lib/clips';

/** Pick an exercise from the library, or create a custom one. */
export function ExercisePicker({ open, onClose, onPick, title = 'Add exercise' }: { open: boolean; onClose: () => void; onPick: (id: string) => void; title?: string }) {
  const [q, setQ] = useState('');
  const [creating, setCreating] = useState(false);
  const list = useLiveQuery(() => db.exercises.orderBy('name').toArray(), []);
  const shown = (list ?? []).filter((e) => !q || e.name.toLowerCase().includes(q.toLowerCase())).slice(0, 60);
  return (
    <Sheet open={open} onClose={() => { setCreating(false); onClose(); }} title={creating ? 'Custom exercise' : title} tall>
      {creating ? (
        <CustomForm
          initialName={q}
          onDone={(id) => {
            setCreating(false);
            onPick(id);
            onClose();
          }}
        />
      ) : (
        <div className="pb-3">
          <label className="relative block">
            <span className="sr-only">Search exercises</span>
            <Search size={20} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted" aria-hidden />
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search 190+ exercises" className="min-h-[48px] w-full rounded-btn border border-line bg-surface2 pl-11 pr-4 text-[17px] outline-none focus:border-primary" />
          </label>
          <button type="button" onClick={() => setCreating(true)} className="mt-2 flex min-h-[52px] w-full items-center gap-2 rounded-btn px-2 font-semibold text-primary-ink active:bg-surface2">
            <Plus size={20} aria-hidden /> Create custom exercise{q ? `: "${q}"` : ''}
          </button>
          <ul className="mt-1">
            {shown.map((e) => {
              const t = demoSrc(e.freeDbId, 0);
              return (
                <li key={e.id}>
                  <button type="button" onClick={() => { onPick(e.id); onClose(); }} className="flex min-h-[60px] w-full items-center gap-3 border-b border-line/40 py-1.5 text-left">
                    <span className="h-11 w-11 shrink-0 overflow-hidden rounded-btn bg-white">{t && <img src={t} alt="" className="h-full w-full object-cover" loading="lazy" />}</span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate font-semibold">{e.name}</span>
                      <span className="block truncate text-caption capitalize text-muted">{[...e.primaryMuscles, ...e.equipment].join(' · ') || e.category}</span>
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        </div>
      )}
    </Sheet>
  );
}

const CATS: Category[] = ['strength', 'core', 'cardio', 'power', 'mobility'];
const UNITS: Unit[] = ['reps', 'seconds', 'minutes', 'meters'];

function CustomForm({ initialName, onDone }: { initialName: string; onDone: (id: string) => void }) {
  const [name, setName] = useState(initialName);
  const [muscles, setMuscles] = useState('');
  const [equipment, setEquipment] = useState('');
  const [cue, setCue] = useState('');
  const [cat, setCat] = useState<Category>('strength');
  const [unit, setUnit] = useState<Unit>('reps');
  const [bw, setBw] = useState(false);
  const save = async () => {
    let id = slugify(name) || 'custom';
    if (await db.exercises.get(id)) id = `${id}-${Date.now().toString(36)}`;
    const ex: Exercise = {
      id,
      name: name.trim(),
      primaryMuscles: muscles.split(',').map((m) => m.trim().toLowerCase()).filter(Boolean),
      equipment: equipment.split(',').map((m) => m.trim().toLowerCase()).filter(Boolean),
      category: cat,
      cue: cue.trim() || undefined,
      custom: true,
      isBodyweight: bw,
      defaultUnit: unit,
    };
    await db.exercises.add(ex);
    onDone(id);
  };
  return (
    <div className="space-y-4 pb-3">
      <Field label="Name">
        <TextInput value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Cable Y-raise" />
      </Field>
      <Field label="Main muscles (comma separated)">
        <TextInput value={muscles} onChange={(e) => setMuscles(e.target.value)} placeholder="shoulders, upper back" />
      </Field>
      <Field label="Equipment">
        <TextInput value={equipment} onChange={(e) => setEquipment(e.target.value)} placeholder="cable" />
      </Field>
      <Field label="Coaching cue">
        <TextInput value={cue} onChange={(e) => setCue(e.target.value)} placeholder="One line you'd tell yourself" />
      </Field>
      <div>
        <p className="mb-1.5 text-[14px] font-semibold text-muted">Type</p>
        <div className="flex flex-wrap gap-2">
          {CATS.map((c) => (
            <Chip key={c} active={cat === c} onClick={() => setCat(c)} className="capitalize">
              {c}
            </Chip>
          ))}
        </div>
      </div>
      <div>
        <p className="mb-1.5 text-[14px] font-semibold text-muted">Measured in</p>
        <div className="flex flex-wrap gap-2">
          {UNITS.map((u) => (
            <Chip key={u} active={unit === u} onClick={() => setUnit(u)} className="capitalize">
              {u}
            </Chip>
          ))}
        </div>
      </div>
      <Toggle checked={bw} onChange={setBw} label="Bodyweight only" sub="Hides the weight field" />
      <Button block size="lg" onClick={save} disabled={!name.trim()}>
        Save exercise
      </Button>
    </div>
  );
}
