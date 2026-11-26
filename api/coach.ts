/**
 * POST /api/coach — the only server code in Repmate. Turns a person's details into a workout + diet plan
 * with an LLM via OpenRouter. The API key stays here (Vercel env OPENROUTER_API_KEY), never in the app.
 *
 * Guard rails: invite code required (same salted hash as the app gate), the prompt is built server-side
 * from validated fields, output tokens are capped, and each instance rate-limits per IP.
 */
import { createHash } from 'node:crypto';
import { ACCESS_HASH, ACCESS_SALT } from '../src/config/access.js';
import { buildPrompt, coachRequestSchema, extractJson, type CoachResponse } from '../src/domain/aiPlan.js';

const MODEL = process.env.OPENROUTER_MODEL || 'anthropic/claude-haiku-5.5';
const LIMIT_PER_HOUR = 12;
const hits = new Map<string, number[]>();

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });

const normalise = (c: string) =>
  c
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '')
    .replace(/^RPM(.{4})(.{4})$/, 'RPM-$1-$2');
export const codeOk = (code: string) => createHash('sha256').update(ACCESS_SALT + normalise(code)).digest('hex') === ACCESS_HASH;

function limited(ip: string): boolean {
  const now = Date.now();
  const list = (hits.get(ip) ?? []).filter((t) => now - t < 3600_000);
  if (list.length >= LIMIT_PER_HOUR) return true;
  list.push(now);
  hits.set(ip, list);
  return false;
}

export async function POST(req: Request): Promise<Response> {
  const key = process.env.OPENROUTER_API_KEY;
  if (!key) return json(503, { error: 'The AI coach is not configured on this server.' });
  const text = await req.text();
  if (text.length > 200_000) return json(413, { error: 'Request too large.' });
  let body;
  try {
    body = coachRequestSchema.parse(JSON.parse(text));
  } catch {
    return json(400, { error: 'Invalid request.' });
  }
  if (!codeOk(body.code)) return json(401, { error: 'Invite code not recognised.' });
  const ip = (req.headers.get('x-forwarded-for') ?? 'unknown').split(',')[0].trim();
  if (limited(ip)) return json(429, { error: 'The coach needs a breather. Try again in a little while.' });

  const { system, user } = buildPrompt(body);
  let r: Response;
  try {
    r = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        authorization: `Bearer ${key}`,
        'content-type': 'application/json',
        'x-title': 'Repmate',
      },
      body: JSON.stringify({
        model: MODEL,
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
        temperature: 0.4,
        // The plan itself is ~4-6k tokens; keep the model's private reasoning small so it can't eat the budget.
        max_tokens: 12000,
        reasoning: { max_tokens: 2000, exclude: true },
        response_format: { type: 'json_object' },
        usage: { include: true },
      }),
      signal: AbortSignal.timeout(110_000),
    });
  } catch {
    return json(504, { error: 'The coach took too long. Please try again.' });
  }
  if (!r.ok) {
    const detail = (await r.text()).slice(0, 200);
    console.error('openrouter', r.status, detail);
    return json(502, { error: r.status === 402 ? 'AI credits are used up. Top up the OpenRouter key.' : 'The coach is unavailable right now. Please try again.' });
  }
  const data = (await r.json()) as { choices?: { message?: { content?: string }; finish_reason?: string }[]; usage?: { cost?: number }; model?: string };
  const content = data.choices?.[0]?.message?.content ?? '';
  if (data.choices?.[0]?.finish_reason === 'length') return json(502, { error: 'The plan came out too long. Try asking for fewer changes at once.' });
  try {
    const plan = extractJson(content);
    const out: CoachResponse = { plan, model: data.model ?? MODEL, costUsd: data.usage?.cost };
    return json(200, out);
  } catch (e) {
    return json(502, { error: (e as Error).message });
  }
}

export async function GET(): Promise<Response> {
  return json(200, { ok: !!process.env.OPENROUTER_API_KEY, model: MODEL });
}
