import { z } from 'zod';

const weekday = z.enum(['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']);
const unit = z.enum(['reps', 'seconds', 'minutes', 'meters']);
const dayType = z.enum(['strength', 'cardio', 'conditioning', 'rest', 'active_recovery']);

const seedExercise = z.object({
  slot: z.string(),
  name: z.string(),
  freeDbId: z.string().nullable().optional(),
  youtubeQuery: z.string().optional(),
  cue: z.string().optional(),
  target: z.object({ sets: z.number().int().positive(), repsMin: z.number(), repsMax: z.number(), unit, perSide: z.boolean() }),
  restSec: z.number().min(0),
  supersetGroup: z.string().optional(),
  swap: z
    .object({ name: z.string(), freeDbId: z.string().nullable().optional(), youtubeQuery: z.string().optional(), reason: z.string().optional() })
    .optional(),
});

export const seedProgramSchema = z.object({
  id: z.string(),
  name: z.string(),
  warmup: z.object({
    durationMin: z.number().optional(),
    items: z.array(z.object({ name: z.string(), minutes: z.number().optional(), reps: z.string().optional(), freeDbId: z.string().nullable().optional(), youtubeQuery: z.string().optional() })),
  }),
  cooldown: z.string(),
  rules: z.array(z.string()),
  progression: z.object({
    model: z.literal('double_progression'),
    dumbbellIncrementKg: z.number(),
    barIncrementKg: z.number(),
    cycle: z.array(z.object({ weeks: z.array(z.number()), rir: z.number(), deload: z.boolean().optional(), note: z.string().optional() })),
  }),
  days: z.array(
    z.object({
      weekday,
      type: dayType,
      title: z.string(),
      durationMin: z.number().optional(),
      notes: z.string().optional(),
      exercises: z.array(seedExercise).optional(),
    }),
  ),
});
export type SeedProgram = z.infer<typeof seedProgramSchema>;

export const seedDietSchema = z.object({
  id: z.string(),
  name: z.string(),
  kcalTarget: z.number(),
  proteinTargetG: z.number(),
  constraints: z.array(z.string()).optional(),
  trainingDay: z.array(
    z.object({
      time: z.string(),
      meal: z.string(),
      items: z.array(z.string()),
      rotate: z.array(z.string()).optional(),
      proteinG: z.number(),
      kcal: z.number(),
      optional: z.boolean().optional(),
      skipOnRestDay: z.boolean().optional(),
    }),
  ),
  habits: z.array(z.object({ id: z.string(), label: z.string(), target: z.number().optional(), unit: z.string().optional() })),
  adjustmentRules: z.array(z.object({ if: z.string(), then: z.string() })).optional(),
  annualChecks: z.array(z.string()).optional(),
});
export type SeedDiet = z.infer<typeof seedDietSchema>;

export const mediaIndexSchema = z.array(
  z.object({ id: z.string(), name: z.string(), instructions: z.array(z.string()), primaryMuscles: z.array(z.string()), equipment: z.array(z.string()), category: z.string() }),
);
export type MediaIndex = z.infer<typeof mediaIndexSchema>;

export const backupSchema = z.object({
  app: z.literal('repmate'),
  schemaVersion: z.number().int().min(1),
  exportedAt: z.string(),
  tables: z.record(z.string(), z.array(z.record(z.string(), z.unknown()))),
  media: z.enum(['omitted', 'included-in-zip']),
});
export type Backup = z.infer<typeof backupSchema>;

export const researchSchema = z.object({
  patterns: z.record(z.string(), z.string()),
  alternates: z.record(
    z.string(),
    z.array(z.object({ name: z.string(), freeDbId: z.string(), equipment: z.string(), level: z.number(), why: z.string().optional(), unit: unit })),
  ),
  periodization: z.object({
    weeks: z.array(
      z.object({ week: z.number(), rirMain: z.number(), rirAccessory: z.number(), focus: z.string(), note: z.string(), setsDelta: z.number().optional(), deload: z.boolean() }),
    ),
  }),
  homeFallback: z.array(z.object({ name: z.string(), freeDbId: z.string(), sets: z.number(), reps: z.string() })),
  parentTips: z.array(z.string()),
});
export type Research = z.infer<typeof researchSchema>;
