/**
 * Builds seed/library.dataset.json from hasaneyldrm/exercises-dataset (data + English instructions are MIT;
 * the animations are © Gym visual and are fetched separately by `pnpm fetch:demos`, never committed).
 *
 *   pnpm import:dataset
 *
 * Cleans names, maps the dataset's equipment and muscles onto the app's vocabulary, classifies the movement
 * pattern, and estimates difficulty and the logging unit. Exercises already covered by the curated library
 * (seed/demo-map.json) are skipped so nothing appears twice.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import demoMap from '../seed/demo-map.json' with { type: 'json' };

// Kept free of src/ imports so the script type-checks under tsconfig.node.json.
type Category = 'strength' | 'core' | 'cardio' | 'power' | 'mobility';
type Unit = 'reps' | 'seconds' | 'minutes' | 'meters';
interface Exercise {
  id: string;
  name: string;
  demoId: string;
  primaryMuscles: string[];
  secondaryMuscles?: string[];
  bodyPart: string;
  equipment: string[];
  category: Category;
  instructions: string[];
  custom: false;
  source: 'dataset';
  isBodyweight: boolean;
  defaultUnit: Unit;
  pattern?: string;
  level: number;
}
const slugify = (s: string): string =>
  s
    .toLowerCase()
    .replace(/[’']/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');

const ROOT = join(import.meta.dirname, '..');
const CACHE = join(ROOT, 'node_modules', '.cache', 'exercises-dataset.json');
const URL = 'https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/data/exercises.json';

interface Raw {
  id: string;
  name: string;
  body_part: string;
  equipment: string;
  target: string;
  secondary_muscles: string[];
  instruction_steps: { en: string[] };
  gif_url: string;
}

async function load(): Promise<Raw[]> {
  if (!existsSync(CACHE)) {
    mkdirSync(join(ROOT, 'node_modules', '.cache'), { recursive: true });
    const r = await fetch(URL);
    if (!r.ok) throw new Error(`dataset HTTP ${r.status}`);
    writeFileSync(CACHE, await r.text());
  }
  return JSON.parse(readFileSync(CACHE, 'utf8')) as Raw[];
}

const SKIP_EQUIPMENT = new Set(['assisted', 'roller', 'bosu ball', 'tire', 'hammer', 'rope']);
const EQUIPMENT: Record<string, string> = {
  'body weight': 'body only',
  dumbbell: 'dumbbell',
  barbell: 'barbell',
  'olympic barbell': 'barbell',
  'ez barbell': 'e-z curl bar',
  'trap bar': 'barbell',
  cable: 'cable',
  kettlebell: 'kettlebells',
  band: 'bands',
  'resistance band': 'bands',
  'leverage machine': 'machine',
  'sled machine': 'machine',
  'smith machine': 'machine',
  'stationary bike': 'machine',
  'elliptical machine': 'machine',
  'stepmill machine': 'machine',
  'skierg machine': 'machine',
  'upper body ergometer': 'machine',
  'medicine ball': 'medicine ball',
  'stability ball': 'exercise ball',
  'wheel roller': 'other',
  weighted: 'weight plate',
};
const TARGET: Record<string, string | undefined> = {
  abs: 'abdominals',
  abductors: 'abductors',
  adductors: 'adductors',
  biceps: 'biceps',
  calves: 'calves',
  'cardiovascular system': undefined,
  delts: 'shoulders',
  forearms: 'forearms',
  glutes: 'glutes',
  hamstrings: 'hamstrings',
  lats: 'lats',
  'levator scapulae': 'neck',
  pectorals: 'chest',
  quads: 'quadriceps',
  'serratus anterior': 'chest',
  spine: 'lower back',
  traps: 'traps',
  triceps: 'triceps',
  'upper back': 'middle back',
};
const SECONDARY: Record<string, string> = {
  shoulders: 'shoulders',
  deltoids: 'shoulders',
  'rear deltoids': 'shoulders',
  'rotator cuff': 'shoulders',
  hamstrings: 'hamstrings',
  forearms: 'forearms',
  wrists: 'forearms',
  'wrist flexors': 'forearms',
  'wrist extensors': 'forearms',
  'grip muscles': 'forearms',
  hands: 'forearms',
  triceps: 'triceps',
  biceps: 'biceps',
  brachialis: 'biceps',
  quadriceps: 'quadriceps',
  calves: 'calves',
  soleus: 'calves',
  glutes: 'glutes',
  core: 'abdominals',
  obliques: 'abdominals',
  abdominals: 'abdominals',
  'lower abs': 'abdominals',
  chest: 'chest',
  'upper chest': 'chest',
  'hip flexors': 'hip flexors',
  'lower back': 'lower back',
  rhomboids: 'middle back',
  'upper back': 'middle back',
  back: 'middle back',
  trapezius: 'traps',
  traps: 'traps',
  'latissimus dorsi': 'lats',
  lats: 'lats',
  'inner thighs': 'adductors',
  groin: 'adductors',
  sternocleidomastoid: 'neck',
};

/** Display name: fixed typos/encoding, gym-friendly words, sentence case. */
export function cleanName(raw: string): string {
  let n = raw
    .replace(/в°/g, '°')
    .replace(/\s*\(male\)/gi, '')
    .replace(/\bv\. ?(\d)/g, '(v$1)')
    .replace(/\brollerout\b/g, 'rollout')
    .replace(/\bkeens\b/g, 'knees')
    .replace(/\bpeacher\b/g, 'preacher')
    .replace(/\brevers\b/g, 'reverse')
    .replace(/\bsitted\b/g, 'seated')
    .replace(/\bflyes\b/g, 'flys')
    .replace(/_shoulder$/, ' (shoulder)')
    .replace(/^lever /, 'machine ')
    .replace(/^sled 45° /, '45° ')
    .replace(/^sled /, 'machine ')
    .replace(/^smith /, 'smith machine ')
    .replace(/^ez barbell /, 'EZ-bar ')
    .replace(/^ez bar /, 'EZ-bar ')
    .replace(/^ez-bar(bell)? /, 'EZ-bar ')
    .replace(/^olympic barbell /, 'barbell ')
    .replace(/\s+/g, ' ')
    .trim();
  n = n.replace(/\. (boxing)$/, ' ($1)');
  return n.charAt(0).toUpperCase() + n.slice(1);
}

const has = (s: string, re: RegExp) => re.test(s);

export function patternOf(name: string, target: string, bodyPart: string): string | undefined {
  const n = name.toLowerCase();
  if (has(n, /stretch|pose\b|circles|greatest|pelvic tilt|cat |upward facing dog|sphinx|spine twist|runners|toe touch|inchworm|^quads$/)) return 'mobility';
  if (has(n, /planche|maltese|\bflag\b|front lever|back lever|handstand$|elevator|skin the cat/)) return 'core anti-extension';
  if (has(n, /curl/) && has(n, /bicep|biceps|hammer|preacher|concentration|zottman|drag curl|spider|reverse curl|ez-bar|barbell curl|cable curl|high curl|waiter|close grip curl|wide grip curl|alternate curl|seated curl|inner curl|overhead curl|squatting curl|prone curl|supine curl|standing curl/)) return 'elbow flexion';
  if (target === 'calves' || has(n, /calf|calves|toe raise/)) return 'calves';
  if (has(n, /leg press|leg wide press|hack squat|thruster/)) return 'squat';
  if (has(n, /jump|hop|slam|throw|clap|plyo|burpee|bound|skater|snatch|jerk|battling|depth|chest pass|chest push|sprint|swing 360|left hook/) || (has(n, /\bclean\b/) && !has(n, /squat/))) return 'power/plyometric';
  if (bodyPart === 'cardio' || has(n, /\brun\b|walking on|treadmill|elliptical|stepmill|ergometer|stationary bike|hands bike|cross trainer|jump rope|high knee|quick feet/)) return 'conditioning/cardio';
  if (has(n, /farmer|carry|sled push|backward drag/)) return 'carry';
  if (has(n, /leg curl|inverse leg curl|glute-ham|femoral|hamstring curl/)) return 'knee flexion';
  if (has(n, /leg extension|sissy squat/)) return 'knee extension';
  if (target === 'calves' || has(n, /calf|calves|toe raise/)) return 'calves';
  if (has(n, /abduction|adduction|adductor|monster walk|side hip|hip adduction/)) return 'hip abduction/adduction';
  if (has(n, /\bfly\b|flys|crossover|cross-over variation|pec deck|seated fly|svend|chest squeeze/) && !has(n, /rear|reverse|revers|row/)) return 'chest fly';
  if (has(n, /rear delt|reverse fly|rear fly|rear lateral|face pull|pull apart|external rotation|internal rotation|shoulder rotation|one arm rotate|deltoid rear|y-raise|t-raise|scapula|rear drive|reverse flys/)) return 'rear delt/scap';
  if (has(n, /lateral raise|side lateral|upright row|lateral to front|full can|front raise|lateral bent-over|incline raise|shoulder raise|iron cross|deltoid raise|y raise|cuban|forward raise|^dumbbell raise|alternate raise|one hand raise/)) return 'lateral delt';
  if (has(n, /shrug|high pull/)) return 'traps';
  if (has(n, /wrist|gripper|hand squeeze|pinch|wrist roller|pronation|supination/)) return 'forearms';
  if (has(n, /pallof|twist|woodchop|chop|windmill|side plank|side bridge|side bend|bent side|russian|landmine 180|wipers|judo flip|seated side crunch|spine rotation/)) return 'core anti-rotation';
  if (has(n, /plank|rollout|roll-out|dead bug|pull-in|body saw|abdominal fallout|bear crawl|hollow|lever\b|l-sit|v-sit|ab rollout/)) return 'core anti-extension';
  if (has(n, /crunch|sit-?up|leg raise|knee raise|v-up|jack ?knife|tuck|hanging pike|toes to bar|flutter|scissor|heel touch|elbow-to-knee|elbow to knee|cocoon|air bike|bicycle|curl-up|dragon|leg hip raise|kick out|hug|negative crunch|leg pull in|leg-hip raise|leg tucks|captains chair|bottoms-up|butt-ups|knee touch|otis/)) return 'core flexion';
  if (has(n, /curl/) && !has(n, /leg curl|wrist|sit/)) return 'elbow flexion';
  if (has(n, /tricep|pushdown|kickback|skull|french press|jm (bench )?press|tate press|lying extension|overhead extension|bench extension|elbow press|triceps dip|bench dip|tricep dip|close-grip press|dumbbell lying elbow|diamond push|close-grip push|close grip push|narrow push/) || (target === 'triceps' && has(n, /dip|extension|press/))) return 'elbow extension';
  if (has(n, /pull[- ]?up|chin-?up|chin up|pulldown|pull-down|muscle up|muscle-up|rope climb|chin\b|front lever reps|pullover|archer pull/) && !has(n, /dip/)) return 'vertical pull';
  if (has(n, /\brow\b|rows|inverted|renegade|kayak|upper row|high row|low row|\bt-bar|\bt bar/) && !has(n, /dip/)) return 'horizontal pull';
  if (has(n, /shoulder press|military|overhead press|arnold|push press|handstand push|pike push|behind (neck|head) press|bradford|scott press|seesaw press|alternate press|bent press|w-press|two arm press|one arm press(?! on)|palms in press|side press|anti gravity press|seated press/) && !has(n, /bench|chest|floor|incline|decline|lying/)) return 'vertical push';
  if (has(n, /bench press|push-?up|push up|chest press|floor press|chest dip|\bdip\b|dips|press on exercise ball|hammer press|lying press|lying one arm press|incline press|decline press|reverse-grip press|reverse grip press|guillotine|pin presses|close-grip bench|wide bench|one arm press on|incline alternate press|palm-in press|press$|planche push/) && target !== 'triceps') return 'horizontal push';
  if (has(n, /hip thrust|glute bridge|bridge|hip raise|hip extension|donkey kick|frog|hip lift|reverse hyper|glute kickback|kickback/) && target !== 'triceps') return 'glute';
  if (has(n, /lunge|split squat|step-?up|pistol|single leg squat|one leg squat|curtsey|cossack|step-up|platform slide/)) return 'lunge/single-leg';
  if (has(n, /squat|leg press|hack|wall sit|chair|march sit/)) return 'squat';
  if (has(n, /deadlift|romanian|good morning|swing|pull through|hyperextension|back extension|superman|stiff leg|rack pull|lower back curl|seated good/)) return 'hinge';
  if (target === 'abs') return 'core flexion';
  return undefined;
}

function category(pattern: string | undefined, bodyPart: string): Category {
  if (pattern === 'mobility') return 'mobility';
  if (pattern === 'power/plyometric') return 'power';
  if (pattern === 'conditioning/cardio' || bodyPart === 'cardio') return 'cardio';
  if (pattern?.startsWith('core') || bodyPart === 'waist') return 'core';
  return 'strength';
}

function unitOf(name: string, pattern: string | undefined): Unit {
  const n = name.toLowerCase();
  if (pattern === 'mobility') return 'seconds';
  if (pattern === 'conditioning/cardio' && !has(n, /jump rope|high knee|quick feet|run\b(?! )|push to run|wheel run|short stride/)) return 'minutes';
  if (pattern === 'carry') return 'seconds';
  if (has(n, /plank|hold|l-sit|v-sit|isometric|wall sit|planche|front lever(?! reps)|back lever|\bflag\b|maltese|handstand$|elevator|bridge v|side bridge/) && !has(n, /push|tap|twist|reps|march|abduction|adduction|lift/)) return 'seconds';
  return 'reps';
}

function levelOf(name: string, eq: string, pattern: string | undefined): number {
  const n = name.toLowerCase();
  if (has(n, /planche|maltese|\bflag\b|muscle.?up|handstand|one arm (pull|chin)|one hand pull|archer|stalder|impossible|korean|skin the cat|front lever|back lever|dragon|elevator|swing 360|single arm push-up|one arm dip/)) return 5;
  if (pattern === 'mobility') return 1;
  if (has(n, /wall|kneeling push|incline push|assisted|knee bends|potty/)) return 1;
  if (has(n, /snatch|jerk|clean|pistol|l-sit|v-sit|toes to bar|hanging pike|deficit|clap|depth|plyo|weighted|one leg squat|single leg squat|nordic|glute-ham|overhead squat|zercher|jefferson/)) return 4;
  if (eq === 'barbell' || eq === 'e-z curl bar' || has(n, /pull-?up|chin-?up|dip|burpee|jump|hanging/)) return 3;
  return 2;
}

async function main() {
  const raw = await load();
  // Curated exercise ids are exactly the keys of the demo map (a unit test keeps them in sync).
  const curatedIds = new Set(Object.keys(demoMap.map));
  const covered = new Set(Object.values(demoMap.map).filter(Boolean) as string[]);
  const out: Exercise[] = [];
  const seenNames = new Set<string>();
  const skipped: Record<string, number> = {};
  const skip = (why: string) => (skipped[why] = (skipped[why] ?? 0) + 1);

  // Prefer the plain version over POV duplicates.
  const sorted = [...raw].sort((a, b) => Number(/pov\)/.test(a.name)) - Number(/pov\)/.test(b.name)) || a.id.localeCompare(b.id));
  for (const r of sorted) {
    if (/\(female\)/i.test(r.name)) { skip('female duplicate'); continue; }
    if (SKIP_EQUIPMENT.has(r.equipment)) { skip(`equipment ${r.equipment}`); continue; }
    if (covered.has(r.id)) { skip('already curated'); continue; }
    if (r.body_part === 'neck') { skip('neck'); continue; }
    let name = cleanName(r.name);
    const base = name.replace(/\s*\((side|back) pov\)/i, '');
    if (base !== name) {
      if (seenNames.has(base.toLowerCase())) { skip('pov duplicate'); continue; }
      name = base;
    }
    if (seenNames.has(name.toLowerCase())) { skip('same name'); continue; }
    const id = slugify(name);
    if (curatedIds.has(id) || out.some((e) => e.id === id)) { skip('same id'); continue; }
    seenNames.add(name.toLowerCase());

    const eq = EQUIPMENT[r.equipment] ?? 'other';
    const pattern = patternOf(name, r.target, r.body_part);
    const cat = category(pattern, r.body_part);
    const unit = unitOf(name, pattern);
    const prim = TARGET[r.target];
    const secondary = [...new Set(r.secondary_muscles.map((m) => SECONDARY[m.toLowerCase()]).filter((m): m is string => !!m && m !== prim))];
    const equipment = r.equipment === 'trap bar' ? ['barbell'] : [eq];
    out.push({
      id,
      name: r.equipment === 'trap bar' && !/trap/i.test(name) ? `Trap bar ${name.toLowerCase()}` : name,
      demoId: r.id,
      primaryMuscles: prim ? [prim] : [],
      secondaryMuscles: secondary.length ? secondary : undefined,
      bodyPart: r.body_part,
      equipment,
      category: cat,
      instructions: (r.instruction_steps?.en ?? []).map((s) => s.trim()).filter(Boolean),
      custom: false,
      source: 'dataset',
      isBodyweight: (eq === 'body only' || eq === 'bands' || eq === 'exercise ball') && cat !== 'cardio' ? true : cat === 'cardio' || cat === 'mobility',
      defaultUnit: unit,
      pattern,
      level: levelOf(name, eq, pattern),
    });
  }
  out.sort((a, b) => a.name.localeCompare(b.name));
  // Extra metadata for the curated exercises that share a dataset demo: helper muscles, body part and
  // instructions that match the animation they now show.
  const curatedMeta: Record<string, { secondaryMuscles?: string[]; bodyPart: string; instructions: string[] }> = {};
  for (const r of raw) {
    if (!covered.has(r.id)) continue;
    const prim = TARGET[r.target];
    const secondary = [...new Set(r.secondary_muscles.map((m) => SECONDARY[m.toLowerCase()]).filter((m): m is string => !!m && m !== prim))];
    curatedMeta[r.id] = { secondaryMuscles: secondary.length ? secondary : undefined, bodyPart: r.body_part, instructions: (r.instruction_steps?.en ?? []).map((x) => x.trim()).filter(Boolean) };
  }
  const files: Record<string, string> = {};
  for (const r of raw) if (out.some((e) => e.demoId === r.id)) files[r.id] = r.gif_url;
  writeFileSync(
    join(ROOT, 'seed', 'library.dataset.json'),
    JSON.stringify({ _source: 'hasaneyldrm/exercises-dataset (data and instructions MIT). Animations © Gym visual, fetched separately.', version: 1, exercises: out, files }) + '\n',
  );
  writeFileSync(join(ROOT, 'seed', 'library.curated-meta.json'), JSON.stringify({ _source: 'hasaneyldrm/exercises-dataset (MIT): metadata for curated exercises, keyed by demo id.', meta: curatedMeta }) + '\n');
  const byPattern: Record<string, number> = {};
  for (const e of out) byPattern[e.pattern ?? '(none)'] = (byPattern[e.pattern ?? '(none)'] ?? 0) + 1;
  console.log(`dataset: ${out.length} exercises added`, { skipped, byPattern });
}

if (process.argv[1]?.endsWith('import-dataset.ts')) await main();
