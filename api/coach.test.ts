// @vitest-environment node
import { readFileSync } from 'node:fs';
import { POST, GET } from './coach';

const code = (() => {
  try {
    return readFileSync('.access-code.local', 'utf8').trim();
  } catch {
    return process.env.REPMATE_CODE ?? '';
  }
})();

const body = (over: Record<string, unknown> = {}) =>
  JSON.stringify({
    code,
    mode: 'new',
    want: { workout: true, diet: false },
    profile: { sex: 'male', age: 35, heightCm: 175, weightKg: 82, goalWeightKg: 75, goal: 'lean', experience: 'beginner', trainingDays: ['TUE'], sessionMin: 60, equipment: [], dietType: 'veg', intolerances: [] },
    notes: '',
    exercises: [{ id: 'push-up', name: 'Push-up', unit: 'reps' }],
    ...over,
  });
const post = (b: string, ip = '1.1.1.1') => POST(new Request('https://x/api/coach', { method: 'POST', body: b, headers: { 'x-forwarded-for': ip } }));

describe('/api/coach', () => {
  const realFetch = globalThis.fetch;
  beforeEach(() => {
    process.env.OPENROUTER_API_KEY = 'test-key';
  });
  afterEach(() => {
    globalThis.fetch = realFetch;
    delete process.env.OPENROUTER_API_KEY;
  });

  it('reports configuration', async () => {
    expect(await (await GET()).json()).toMatchObject({ ok: true });
  });

  it('rejects a wrong invite code without calling the model', async () => {
    const spy = vi.fn();
    globalThis.fetch = spy;
    const r = await post(body({ code: 'RPM-AAAA-BBBB' }));
    expect(r.status).toBe(401);
    expect(spy).not.toHaveBeenCalled();
  });

  it('rejects malformed requests', async () => {
    expect((await post('{"nope":1}')).status).toBe(400);
  });

  it.skipIf(!code)('calls OpenRouter with a server-built prompt and returns the parsed plan + cost', async () => {
    const spy = vi.fn(async (_url: string, init: RequestInit) => {
      const sent = JSON.parse(String(init.body));
      expect(sent.messages[0].content).toMatch(/ONLY exercise ids/);
      expect((init.headers as Record<string, string>).authorization).toBe('Bearer test-key');
      return new Response(JSON.stringify({ model: 'm', choices: [{ message: { content: '```json\n{"summary":"ok"}\n```' } }], usage: { cost: 0.0021 } }));
    });
    globalThis.fetch = spy as unknown as typeof fetch;
    const r = await post(body(), '2.2.2.2');
    expect(r.status).toBe(200);
    expect(await r.json()).toEqual({ plan: { summary: 'ok' }, model: 'm', costUsd: 0.0021 });
  });

  it.skipIf(!code)('rate-limits per IP', async () => {
    globalThis.fetch = (async () => new Response(JSON.stringify({ choices: [{ message: { content: '{"summary":"ok"}' } }] }))) as unknown as typeof fetch;
    const codes: number[] = [];
    for (let i = 0; i < 14; i++) codes.push((await post(body(), '3.3.3.3')).status);
    expect(codes.filter((c) => c === 429).length).toBeGreaterThan(0);
  });
});
