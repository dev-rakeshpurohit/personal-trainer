# 09 — Training research (alternates, periodization, sustainability)

Compiled 2026-11-26 for Repmate. Machine-readable data: `seed/alternates.research.json` (every `freeDbId` validated against free-exercise-db with ≥ 2 images).

## Alternates
49 distinct exercises (31 main + 18 swaps) each have 3–6 alternates (276 total), ordered level 1 (easiest) → 5 (hardest), and every list includes a dumbbell or bodyweight option so one is always available when stations are busy. Patterns: squat, hinge, lunge, horizontal/vertical push and pull, elbow flexion/extension, lateral and rear delt, core (anti-extension, anti-rotation, flexion), carry, power, conditioning, mobility.

## 8-week periodization (refines the program's cycle)
| Week | RIR main | RIR accessory | Focus | +Acc. sets | Deload | Note |
|---|---|---|---|---|---|---|
| 1 | 3 | 3 | Learn | 0 |  | Pick loads you could lift 3 more times; own the technique and log every set as your baseline. |
| 2 | 3 | 3 | Build baseline | 0 |  | Same loads, add reps inside the range; once every set hits the top at RIR 3, add the smallest increment. |
| 3 | 2 | 2 | Accumulate | 0 |  | Move to RIR 2: same loads should now give 1-2 more reps; progress load when all sets reach the top of the range. |
| 4 | 2 | 2 | Accumulate | 0 |  | Keep double progression going; last week before accessory rotation, so note which accessories stalled. |
| 5 | 1 | 2 | Intensify + rotate | 1 |  | Main lifts may go to RIR 1; swap in new accessory variations and add 1 accessory set only if the session still fits the time. |
| 6 | 1 | 2 | Intensify | 1 |  | Chase a rep or load PR on each main lift at RIR 1; the extra accessory set is optional on busy weeks. |
| 7 | 1 | 2 | Peak | 0 |  | Last hard week: best reps on main lifts at RIR 1, drop the extra accessory set so you reach the deload fresh. |
| 8 | 3 | 3 | Deload | 0 | yes | Half the sets (round up), same weights, RIR 3; keep steps and sleep high, then restart week 1 with heavier baselines. |

- Double progression with RIR autoregulation: sets ending 1–3 reps short of failure give nearly the same hypertrophy as failure (Refalo 2023; Robinson 2024); RIR is a practical load guide (Helms 2016; Zourdos 2016).
- The week already undulates by rep range (A 8–10, B 10–12, C 6–8). With equal volume, periodization gives slightly more strength, no extra hypertrophy (Moesgaard 2022).
- Deload: reduce stress rather than stop (Bell 2023 Delphi consensus); a full week off hurt strength (Coleman 2024), so we keep weights and halve sets.
- Rotation: main lifts stay fixed for the block; accessories rotate every 4 weeks, never randomly. Planned variation helps; excessive rotation can blunt gains (Kassiano 2022); variation helps motivation (Baz-Valle 2019).

## Minimum effective dose
- ~4+ hard sets per muscle per week (6–15 reps) still produce gains; weekly volume matters more than frequency (Iversen 2021).
- More sets → more hypertrophy, with diminishing returns (Schoenfeld 2017; Pelland 2024 preprint).
- Strength and muscle can be maintained for months with 1 session/week of 1 set per exercise if intensity is kept (Spiering 2021; Bickel 2011).
- Supersets / rest-pause halve session time at similar volume (Iversen 2021; Weakley 2017).

## Express (~40 min)
{
 "targetMin": 40,
 "keepSlots": "Strength days: keep the A and B superset slots (the 4 compound lifts; on Strength C keep A, B1 and B2) and drop C and D. Wednesday: 20 min steady cardio + Dead bug and Side plank. Friday: slams + box jumps (3 sets each) + 4 bike intervals.",
 "setsPerSlot": 2,
 "restSec": {
  "main": 90,
  "accessory": 45
 },
 "rules": [
  "Warm-up shrinks to 5 min: 2-3 min easy cardio, then 1 light ramp set of the first lift (skip the mobility list).",
  "Do the kept slots as antagonist supersets (e.g. A1 squat + A2 press, B1 pull + B2 hinge): set of A1, ~45 s, set of A2, then 90 s before the next round. Paired supersets cut session time roughly in half with similar volume (Iversen 2021; Weakley 2017).",
  "2 hard working sets per slot at the week's RIR target (never below RIR 1). If you have 5 spare minutes, give the first lift of the day a 3rd set.",
  "Drop all C/D accessories first; if time remains, add ONE 2-set superset finisher (e.g. lateral raise + hammer curl) with 45 s rest.",
  "Keep the same loads as a full session; Express cuts sets, not weight. Intensity, not volume, is what maintains strength (Spiering 2021).",
  "Rest-pause option for the last set of an accessory: reach the RIR target, rest 15 s, do 2-4 more reps once. Use only on machines/cables, not on squats or deadlifts.",
  "Cooldown is 2 min of walking; stretch later at home if possible.",
  "Two Express sessions give each big muscle ~4+ hard sets per week, the minimum Iversen 2021 suggests for continued gains; three Express sessions give ~6."
 ]
}

## Busy week
{
 "keep": [
  "Strength A \u2013 full body",
  "Strength B \u2013 full body",
  "Strength C \u2013 heavier"
 ],
 "why": "The three full-body strength sessions train every major muscle 3x per week, which keeps weekly hard sets per muscle around 6-9 (enough to keep progressing as an intermediate-beginner; Schoenfeld 2017, Iversen 2021). Cardio and conditioning are the easiest to replace outside the gym with steps, pram walks and a short home interval, and missing them for a week costs little fitness (Spiering 2021). Space them with a rest day between if possible (e.g. Tue/Thu/Sat). If only 2 sessions are possible, keep Strength A and Strength C (both include squat or hinge, press and pull), run them as Express, and keep daily steps.",
 "ifOnlyTwo": [
  "Strength A \u2013 full body",
  "Strength C \u2013 heavier"
 ],
 "ifOnlyOne": "Do Strength A as Express: 1 session per week with 1-2 hard sets per exercise at the same load maintains strength and muscle for months (Spiering 2021; Bickel 2011)."
}

## Parent habits
- Sleep is part of the program: aim for 7+ hours, and use naps to catch up. In a calorie deficit, short sleep (5.5 h) shifted weight loss from fat to lean mass and raised hunger (Nedeltcheva 2010). After a bad night, still train but use Express and RIR 3: no PR attempts.
- Most fat-loss movement is outside the gym: walk with the pram or baby carrier, take calls standing, and aim for 7,000-10,000 steps. Non-exercise activity can differ by hundreds of kcal a day between people (Levine 2005), and mortality risk keeps falling with more daily steps up to roughly 6,000-8,000 for adults over 60 and 8,000-10,000 for younger adults (Paluch 2022).
- A missed week is not lost progress. One or two short sessions a week at the same weights keep strength and muscle for months (Spiering 2021; Bickel 2011), so on chaotic weeks aim for 'two Express sessions', not 'all or nothing'.
- Eat about 1.6 g protein per kg body weight per day, spread over 3-4 meals; extra protein above this gave no further measurable muscle gain (Morton 2018). This is the main thing that protects muscle while losing fat.
- Keep the 15-minute home circuit as the fallback when the gym is impossible: training to near failure (RIR 1-3) gives most of the muscle benefit, so short, hard sets at home still count (Refalo 2023; Robinson 2024).

## Home fallback (15 min)
Circuit, about 15 min: do the first 4 moves back-to-back with no rest, rest 60 s, repeat for 3 rounds; then 2 rounds of lunge + dead bug if time allows. Stop each set at RIR 2. This counts as a strength session in the log.
- Goblet squat (one dumbbell; bodyweight squat if none): 3 × 10-15
- Push-up (hands on a sofa or bench to make easier): 3 × 8-15
- One-arm dumbbell row (hand on a chair): 3 × 10-12 / side
- Dumbbell Romanian deadlift (or single-leg RDL): 3 × 10-12
- Dumbbell reverse lunge (bodyweight if no dumbbells): 2 × 8 / side
- Dead bug: 2 × 8 / side

## Sources
- Iversen VM, Norum M, Schoenfeld BJ, Fimland MS (2021). No Time to Lift? Designing Time-Efficient Training Programs for Strength and Hypertrophy: A Narrative Review. Sports Med 51:2079-2095. https://pubmed.ncbi.nlm.nih.gov/34125411/
- Spiering BA, Mujika I, Sharp MA, Foulis SA (2021). Maintaining Physical Performance: The Minimal Dose of Exercise Needed to Preserve Endurance and Strength Over Time. J Strength Cond Res 35(5):1449-1458. https://pubmed.ncbi.nlm.nih.gov/33629972
- Bickel CS, Cross JM, Bamman MM (2011). Exercise dosing to retain resistance training adaptations in young and older adults. Med Sci Sports Exerc 43(7):1177-1187.
- Schoenfeld BJ, Ogborn D, Krieger JW (2017). Dose-response relationship between weekly resistance training volume and increases in muscle mass: a systematic review and meta-analysis. J Sports Sci 35(11):1073-1082.
- Schoenfeld BJ, Ogborn D, Krieger JW (2016). Effects of Resistance Training Frequency on Measures of Muscle Hypertrophy: A Systematic Review and Meta-Analysis. Sports Med 46(11):1689-1697.
- Ralston GW, Kilgore L, Wyatt FB, Baker JS (2017). The Effect of Weekly Set Volume on Strength Gain: A Meta-Analysis. Sports Med 47:2585-2601. https://pubmed.ncbi.nlm.nih.gov/28755103/
- Pelland JC, Remmert JF, Robinson ZP, Hinson SR, Zourdos MC (2024 preprint). The Resistance Training Dose-Response: Meta-Regressions Exploring the Effects of Weekly Volume and Frequency on Muscle Hypertrophy and Strength Gain. SportRxiv. https://sportrxiv.org/index.php/server/preprint/view/460
- Refalo MC, Helms ER, Trexler ET, Hamilton DL, Fyfe JJ (2023). Influence of Resistance Training Proximity-to-Failure on Skeletal Muscle Hypertrophy: A Systematic Review with Meta-analysis. Sports Med 53(3):649-665. https://pubmed.ncbi.nlm.nih.gov/36334240/
- Robinson ZP, Pelland JC, Remmert JF, et al. (2024). Exploring the Dose-Response Relationship Between Estimated Resistance Training Proximity to Failure, Strength Gain, and Muscle Hypertrophy: A Series of Meta-Regressions. Sports Med.
- Helms ER, Cronin J, Storey A, Zourdos MC (2016). Application of the Repetitions in Reserve-Based Rating of Perceived Exertion Scale for Resistance Training. Strength Cond J 38(4):42-49. https://openrepository.aut.ac.nz/items/92cefeac-7c32-44f1-bfbc-f48f4a5dd8cf
- Zourdos MC, Klemp A, Dolan C, et al. (2016). Novel Resistance Training-Specific Rating of Perceived Exertion Scale Measuring Repetitions in Reserve. J Strength Cond Res 30(1):267-275.
- Moesgaard L, Beck MM, Christiansen L, Aagaard P, Lundbye-Jensen J (2022). Effects of Periodization on Strength and Muscle Hypertrophy in Volume-Equated Resistance Training Programs: A Systematic Review and Meta-analysis. Sports Med 52:1647-1666. https://pubmed.ncbi.nlm.nih.gov/35044672/
- Kassiano W, Nunes JP, Costa B, Ribeiro AS, Schoenfeld BJ, Cyrino ES (2022). Does Varying Resistance Exercises Promote Superior Muscle Hypertrophy and Strength Gains? A Systematic Review. J Strength Cond Res 36(6):1753-1762. https://pubmed.ncbi.nlm.nih.gov/35438660/
- Baz-Valle E, Schoenfeld BJ, Torres-Unda J, Santos-Concejero J, Balsalobre-Fernandez C (2019). The effects of exercise variation in muscle thickness, maximal strength and motivation in resistance trained men. PLoS One 14(12):e0226989. https://pubmed.ncbi.nlm.nih.gov/31881066/
- Bell L, Strafford BW, Coleman M, Androulakis Korakakis P, Nolan D (2023). Integrating Deloading into Strength and Physique Sports Training Programmes: An International Delphi Consensus Approach. Sports Med Open 9:87. https://pmc.ncbi.nlm.nih.gov/articles/PMC10511399/
- Coleman M, Burke R, Augustin F, et al. (2024). Gaining more from doing less? The effects of a one-week deload period during supervised resistance training on muscular adaptations. PeerJ 12:e16777. https://pubmed.ncbi.nlm.nih.gov/38274324/
- Weakley JJS, Till K, Read DB, et al. (2017). The effects of traditional, superset, and tri-set resistance training structures on perceived intensity and physiological responses. Eur J Appl Physiol 117(9):1877-1889. https://pmc.ncbi.nlm.nih.gov/articles/PMC5556132/
- Nedeltcheva AV, Kilkus JM, Imperial J, Schoeller DA, Penev PD (2010). Insufficient sleep undermines dietary efforts to reduce adiposity. Ann Intern Med 153(7):435-441. https://pubmed.ncbi.nlm.nih.gov/20921542/
- Levine JA, Lanningham-Foster LM, McCrady SK, et al. (2005). Interindividual variation in posture allocation: possible role in human obesity. Science 307:584-586. https://pubmed.ncbi.nlm.nih.gov/15681386/
- Paluch AE, Bajpai S, Bassett DR, et al. (2022). Daily steps and all-cause mortality: a meta-analysis of 15 international cohorts. Lancet Public Health 7(3):e219-e228. https://pubmed.ncbi.nlm.nih.gov/35247352/
- Morton RW, Murphy KT, McKellar SR, et al. (2018). A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength in healthy adults. Br J Sports Med 52(6):376-384.
- free-exercise-db (yuhonas). Public-domain exercise dataset used for all freeDbId values. https://github.com/yuhonas/free-exercise-db

Note: Bickel 2011, Morton 2018, Schoenfeld 2016 and Robinson 2024 were cited from memory; the others were confirmed by web search during the research.
