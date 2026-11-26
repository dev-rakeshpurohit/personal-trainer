import { DndContext, KeyboardSensor, PointerSensor, TouchSensor, closestCenter, useSensor, useSensors, type DragEndEvent } from '@dnd-kit/core';
import { SortableContext, arrayMove, sortableKeyboardCoordinates, useSortable, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { useLiveQuery } from 'dexie-react-hooks';
import { GripVertical, Plus, Repeat, Shuffle, Trash2 } from 'lucide-react';
import { useState } from 'react';
import { useParams } from 'react-router-dom';
import { BackButton } from '@/components/BackButton';
import { Field, TextInput, Toggle } from '@/components/Field';
import { Sheet } from '@/components/Sheet';
import { Stepper } from '@/components/Stepper';
import { Button, Card, Chip, PageHeader, SectionTitle } from '@/components/ui';
import { db, uid } from '@/data/db';
import { useExerciseMap } from '@/data/hooks';
import type { DayType, Exercise, PlannedExercise, Unit } from '@/domain/types';
import { WEEKDAY_LABEL } from '@/domain/types';
import { exerciseThumb } from '@/lib/clips';
import { useUI } from '@/store/ui';
import { AlternatesSheet } from '@/features/workout/AlternatesSheet';
import { makePermanentSwap } from '@/features/workout/session';
import { ExercisePicker } from './ExercisePicker';

const TYPES: { v: DayType; l: string }[] = [
  { v: 'strength', l: 'Strength' },
  { v: 'cardio', l: 'Cardio' },
  { v: 'conditioning', l: 'Conditioning' },
  { v: 'active_recovery', l: 'Recovery' },
  { v: 'rest', l: 'Rest' },
];

export default function DayEditor() {
  const { dayId = '' } = useParams();
  const toast = useUI((s) => s.toast);
  const exMap = useExerciseMap();
  const day = useLiveQuery(() => db.programDays.get(dayId), [dayId]);
  const planned = useLiveQuery(() => db.plannedExercises.where('dayId').equals(dayId).sortBy('order'), [dayId]);
  const [adding, setAdding] = useState(false);
  const [edit, setEdit] = useState<PlannedExercise>();
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 150, tolerance: 6 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );
  if (!day || !planned) return null;

  const onDragEnd = async (e: DragEndEvent) => {
    if (!e.over || e.active.id === e.over.id) return;
    const from = planned.findIndex((p) => p.id === e.active.id);
    const to = planned.findIndex((p) => p.id === e.over!.id);
    const next = arrayMove(planned, from, to);
    await db.transaction('rw', db.plannedExercises, () => Promise.all(next.map((p, i) => db.plannedExercises.update(p.id, { order: i }))));
  };

  const add = async (exerciseId: string) => {
    const ex = exMap.get(exerciseId) ?? (await db.exercises.get(exerciseId));
    const unit: Unit = ex?.defaultUnit ?? 'reps';
    const pe: PlannedExercise = {
      id: uid(),
      dayId,
      order: planned.length,
      slot: String(planned.length + 1),
      exerciseId,
      sets: 3,
      repsMin: unit === 'reps' ? 8 : unit === 'seconds' ? 30 : unit === 'minutes' ? 20 : 30,
      repsMax: unit === 'reps' ? 12 : unit === 'seconds' ? 45 : unit === 'minutes' ? 20 : 30,
      unit,
      perSide: false,
      restSec: unit === 'minutes' ? 0 : 75,
    };
    await db.plannedExercises.add(pe);
    if (day.type === 'rest' || day.type === 'active_recovery') await db.programDays.update(dayId, { type: 'strength' });
    toast(`${ex?.name ?? 'Exercise'} added`, { tone: 'success' });
  };

  return (
    <div className="pb-8">
      <PageHeader title={WEEKDAY_LABEL[day.weekday]} sub="Edit day" right={<BackButton to="/more/plan" />} />
      <div className="space-y-3 px-4">
        <Card className="space-y-4">
          <Field label="Title">
            <TextInput defaultValue={day.title} onBlur={(e) => e.target.value.trim() && db.programDays.update(dayId, { title: e.target.value.trim() })} />
          </Field>
          <div>
            <p className="mb-1.5 text-[14px] font-semibold text-muted">Type</p>
            <div className="flex flex-wrap gap-2">
              {TYPES.map((t) => (
                <Chip key={t.v} active={day.type === t.v} onClick={() => db.programDays.update(dayId, { type: t.v })}>
                  {t.l}
                </Chip>
              ))}
            </div>
          </div>
          <div>
            <p className="mb-1.5 text-[14px] font-semibold text-muted">Duration</p>
            <Stepper label="Duration in minutes" value={day.durationMin ?? 60} onChange={(v) => db.programDays.update(dayId, { durationMin: v })} step={5} min={10} max={180} suffix="min" decimals={0} />
          </div>
        </Card>

        <SectionTitle>Exercises · drag ⠿ to reorder</SectionTitle>
        <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
          <SortableContext items={planned.map((p) => p.id)} strategy={verticalListSortingStrategy}>
            <ul className="space-y-2">
              {planned.map((p) => (
                <SortableRow key={p.id} pe={p} ex={exMap.get(p.exerciseId)} swap={p.swapExerciseId ? exMap.get(p.swapExerciseId) : undefined} onOpen={() => setEdit(p)} />
              ))}
            </ul>
          </SortableContext>
        </DndContext>
        <Button variant="secondary" block size="lg" onClick={() => setAdding(true)}>
          <Plus size={20} aria-hidden /> Add exercise
        </Button>
      </div>
      <ExercisePicker open={adding} onClose={() => setAdding(false)} onPick={add} />
      {edit && <PlannedSheet pe={edit} exMap={exMap} onClose={() => setEdit(undefined)} />}
    </div>
  );
}

function SortableRow({ pe, ex, swap, onOpen }: { pe: PlannedExercise; ex?: Exercise; swap?: Exercise; onOpen: () => void }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: pe.id });
  const t = exerciseThumb(ex);
  return (
    <li ref={setNodeRef} style={{ transform: CSS.Transform.toString(transform), transition }} className={`flex items-center gap-2 rounded-card border border-line/50 bg-surface p-2 ${isDragging ? 'z-10 shadow-2xl ring-2 ring-primary' : ''}`}>
      <button type="button" className="flex h-12 w-9 shrink-0 touch-none items-center justify-center text-muted" aria-label={`Reorder ${ex?.name}`} {...attributes} {...listeners}>
        <GripVertical size={20} aria-hidden />
      </button>
      <button type="button" onClick={onOpen} className="flex min-w-0 flex-1 items-center gap-3 text-left" aria-label={`Edit ${ex?.name}`}>
        <span className="h-11 w-11 shrink-0 overflow-hidden rounded-btn bg-white">{t && <img src={t} alt="" className="h-full w-full object-cover" />}</span>
        <span className="min-w-0 flex-1">
          <span className="block truncate font-semibold">
            <span className="mr-1.5 text-primary-ink">{pe.slot}</span>
            {ex?.name ?? pe.exerciseId}
          </span>
          <span className="block truncate text-caption text-muted">
            {pe.sets} × {pe.repsMin === pe.repsMax ? pe.repsMax : `${pe.repsMin}–${pe.repsMax}`} {pe.unit === 'reps' ? '' : pe.unit} · rest {pe.restSec}s{swap ? ` · swap: ${swap.name}` : ''}
          </span>
        </span>
      </button>
    </li>
  );
}

function PlannedSheet({ pe, exMap, onClose }: { pe: PlannedExercise; exMap: Map<string, Exercise>; onClose: () => void }) {
  const toast = useUI((s) => s.toast);
  const live = useLiveQuery(() => db.plannedExercises.get(pe.id), [pe.id]) ?? pe;
  const [pickSwap, setPickSwap] = useState(false);
  const [alts, setAlts] = useState(false);
  const up = (patch: Partial<PlannedExercise>) => db.plannedExercises.update(pe.id, patch);
  const ex = exMap.get(live.exerciseId);
  const unitLabel = live.unit === 'reps' ? 'reps' : live.unit === 'seconds' ? 's' : live.unit === 'minutes' ? 'min' : 'm';
  return (
    <Sheet
      open
      onClose={onClose}
      title={ex?.name ?? 'Exercise'}
      tall
      footer={
        <Button
          variant="danger"
          block
          onClick={async () => {
            await db.plannedExercises.delete(pe.id);
            toast(`${ex?.name} removed`, { undo: () => db.plannedExercises.put(live).then(() => undefined) });
            onClose();
          }}
        >
          <Trash2 size={18} aria-hidden /> Remove from this day
        </Button>
      }
    >
      <div className="space-y-4 pb-3">
        <div className="flex gap-2">
          <Button variant="secondary" className="flex-1" onClick={() => setAlts(true)}>
            <Shuffle size={18} aria-hidden /> Replace with alternate
          </Button>
        </div>
        <Row label="Sets">
          <Stepper label="Sets" value={live.sets} onChange={(v) => up({ sets: v })} step={1} min={1} max={10} decimals={0} />
        </Row>
        <Row label={`Min ${unitLabel}`}>
          <Stepper label="Minimum target" value={live.repsMin} onChange={(v) => up({ repsMin: v, repsMax: Math.max(v, live.repsMax) })} step={live.unit === 'seconds' || live.unit === 'meters' ? 5 : 1} min={1} max={600} decimals={0} />
        </Row>
        <Row label={`Max ${unitLabel}`}>
          <Stepper label="Maximum target" value={live.repsMax} onChange={(v) => up({ repsMax: v, repsMin: Math.min(v, live.repsMin) })} step={live.unit === 'seconds' || live.unit === 'meters' ? 5 : 1} min={1} max={600} decimals={0} />
        </Row>
        <Row label="Rest">
          <Stepper label="Rest seconds" value={live.restSec} onChange={(v) => up({ restSec: v })} step={15} min={0} max={300} suffix="sec" decimals={0} />
        </Row>
        <div>
          <p className="mb-1.5 text-[14px] font-semibold text-muted">Measured in</p>
          <div className="flex flex-wrap gap-2">
            {(['reps', 'seconds', 'minutes', 'meters'] as Unit[]).map((u) => (
              <Chip key={u} active={live.unit === u} onClick={() => up({ unit: u })} className="capitalize">
                {u}
              </Chip>
            ))}
          </div>
        </div>
        <div>
          <p className="mb-1.5 text-[14px] font-semibold text-muted">Superset group</p>
          <div className="flex flex-wrap gap-2">
            {['', 'A', 'B', 'C', 'D'].map((g) => (
              <Chip key={g || 'none'} active={(live.supersetGroup ?? '') === g} onClick={() => up({ supersetGroup: g || undefined })}>
                {g || 'None'}
              </Chip>
            ))}
          </div>
        </div>
        <Field label="Slot label">
          <TextInput defaultValue={live.slot} onBlur={(e) => e.target.value.trim() && up({ slot: e.target.value.trim() })} />
        </Field>
        <Toggle checked={live.perSide} onChange={(v) => up({ perSide: v })} label="Per side" sub="Reps/time counted for each side" />
        <div>
          <p className="mb-1.5 text-[14px] font-semibold text-muted">"Station busy" swap</p>
          <button type="button" onClick={() => setPickSwap(true)} className="flex min-h-[52px] w-full items-center gap-2 rounded-btn border border-line bg-surface2 px-4 text-left">
            <Repeat size={18} className="text-muted" aria-hidden />
            <span className="flex-1">{live.swapExerciseId ? exMap.get(live.swapExerciseId)?.name : 'None, tap to choose'}</span>
          </button>
          {live.swapExerciseId && (
            <button type="button" onClick={() => up({ swapExerciseId: undefined })} className="mt-1 min-h-[44px] text-[14px] font-semibold text-muted">
              Remove swap
            </button>
          )}
        </div>
      </div>
      <ExercisePicker open={pickSwap} onClose={() => setPickSwap(false)} onPick={(id) => up({ swapExerciseId: id })} title="Choose swap" />
      <AlternatesSheet
        open={alts}
        onClose={() => setAlts(false)}
        originalId={live.exerciseId}
        swapId={live.swapExerciseId}
        currentId={live.exerciseId}
        allowToday={false}
        onPick={async (id) => {
          await makePermanentSwap(pe.id, id);
          toast(`Now using ${exMap.get(id)?.name}`, { tone: 'success' });
        }}
      />
    </Sheet>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-3">
      <span className="w-24 shrink-0 text-[15px] font-medium">{label}</span>
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  );
}
