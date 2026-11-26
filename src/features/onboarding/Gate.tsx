import { KeyRound, Lock } from 'lucide-react';
import { useState } from 'react';
import { Button } from '@/components/ui';
import { checkCode, markUnlocked } from '@/lib/access';

/** Invite-only gate: Repmate is shared by its owner with people who have the access code. */
export function Gate({ onUnlock }: { onUnlock: () => void }) {
  const [code, setCode] = useState('');
  const [err, setErr] = useState<string>();
  const [fails, setFails] = useState(0);
  const [until, setUntil] = useState(0);
  const [busy, setBusy] = useState(false);
  const submit = async () => {
    if (Date.now() < until) return setErr(`Too many tries. Wait ${Math.ceil((until - Date.now()) / 1000)} s.`);
    setBusy(true);
    const ok = await checkCode(code);
    setBusy(false);
    if (ok) {
      markUnlocked(code);
      onUnlock();
      return;
    }
    const n = fails + 1;
    setFails(n);
    if (n >= 5) {
      setUntil(Date.now() + 30_000);
      setFails(0);
      setErr('Too many tries. Wait 30 s and check the code with the person who shared Repmate.');
    } else setErr("That code doesn't look right. Check it and try again.");
  };
  return (
    <div className="app-shell flex flex-col bg-bg">
      <main className="flex flex-1 flex-col justify-center px-6 pt-safe">
        <div className="mx-auto mb-6 flex h-16 w-16 items-center justify-center rounded-[20px] bg-gradient-to-br from-[#FF9A3D] to-[#FF5E0E] shadow-[0_12px_40px_-10px_rgba(255,122,26,0.7)]">
          <Lock size={30} className="text-[#0B0F14]" strokeWidth={2.4} aria-hidden />
        </div>
        <h1 className="text-center text-[30px] font-bold tracking-tight">Repmate is invite-only</h1>
        <p className="mx-auto mt-2 max-w-xs text-center text-[16px] text-muted">Enter the access code you were given to set up your personal coach.</p>
        <form
          className="mt-8"
          onSubmit={(e) => {
            e.preventDefault();
            void submit();
          }}
        >
          <label className="block">
            <span className="sr-only">Access code</span>
            <span className="relative block">
              <KeyRound size={20} className="absolute left-4 top-1/2 -translate-y-1/2 text-muted" aria-hidden />
              <input
                value={code}
                onChange={(e) => {
                  setCode(e.target.value.toUpperCase());
                  setErr(undefined);
                }}
                autoCapitalize="characters"
                autoComplete="one-time-code"
                spellCheck={false}
                placeholder="RPM-XXXX-XXXX"
                aria-invalid={!!err}
                aria-describedby="gate-err"
                className={`min-h-[60px] w-full rounded-btn border bg-surface pl-12 pr-4 text-center font-mono text-[22px] tracking-[0.12em] outline-none focus:border-primary ${err ? 'border-danger' : 'border-line'}`}
              />
            </span>
          </label>
          <p id="gate-err" role="alert" className="mt-2 min-h-[22px] text-center text-[15px] text-danger">
            {err}
          </p>
          <Button type="submit" size="lg" block className="mt-2" disabled={busy || code.replace(/[^A-Z0-9]/g, '').length < 8}>
            {busy ? 'Checking…' : 'Unlock'}
          </Button>
        </form>
      </main>
      <p className="px-6 pb-[calc(16px+env(safe-area-inset-bottom))] text-center text-caption text-muted">Everything you enter stays on this phone. No account, no tracking.</p>
    </div>
  );
}
