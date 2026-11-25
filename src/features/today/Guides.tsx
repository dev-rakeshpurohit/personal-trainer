import { Dumbbell, PlusSquare, Repeat, Scale, Share } from 'lucide-react';
import { useState } from 'react';
import { Button } from '@/components/ui';
import { Sheet } from '@/components/Sheet';
import { isIOS, isStandalone } from '@/lib/platform';

const SEEN_INSTALL = 'repmate:installGuideSeen';

export function InstallGuide() {
  const [open, setOpen] = useState(() => {
    try {
      return isIOS() && !isStandalone() && !localStorage.getItem(SEEN_INSTALL);
    } catch {
      return false;
    }
  });
  const close = () => {
    try {
      localStorage.setItem(SEEN_INSTALL, '1');
    } catch {
      /* ignore */
    }
    setOpen(false);
  };
  return (
    <Sheet open={open} onClose={close} title="Add Repmate to your Home Screen" footer={<Button block size="lg" onClick={close}>Got it</Button>}>
      <ol className="space-y-4 pt-2 text-[17px]">
        <li className="flex items-center gap-3">
          <Step n={1} /> Tap <Share size={20} className="text-info" aria-label="Share" /> in Safari's toolbar
        </li>
        <li className="flex items-center gap-3">
          <Step n={2} /> Choose <span className="inline-flex items-center gap-1 font-semibold"><PlusSquare size={18} aria-hidden /> Add to Home Screen</span>
        </li>
        <li className="flex items-center gap-3">
          <Step n={3} /> Open Repmate from the new icon
        </li>
      </ol>
      <p className="mt-4 text-[15px] text-muted">As a Home Screen app it works fully offline, keeps your screen awake during workouts, and can notify you when rest is over.</p>
    </Sheet>
  );
}

const Step = ({ n }: { n: number }) => (
  <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary/20 text-[15px] font-bold text-primary-ink">{n}</span>
);

const CARDS = [
  { Icon: Dumbbell, title: 'Tap Start', body: "Today's session is on the big card. Each set is prefilled from last time. Adjust and tick ✓." },
  { Icon: Repeat, title: 'Station busy? Swap', body: 'One tap swaps to the alternative. Its history is tracked separately.' },
  { Icon: Scale, title: 'Log your weight', body: 'Weigh in most mornings. Repmate tracks the 7-day average and tells you if the plan is working.' },
];

export function CoachMarks({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [i, setI] = useState(0);
  const c = CARDS[i];
  return (
    <Sheet
      open={open}
      onClose={onClose}
      title="Quick tour"
      footer={
        <div className="flex gap-2">
          <Button variant="ghost" onClick={onClose}>
            Skip
          </Button>
          <Button block size="lg" onClick={() => (i < CARDS.length - 1 ? setI(i + 1) : onClose())}>
            {i < CARDS.length - 1 ? 'Next' : "Let's go"}
          </Button>
        </div>
      }
    >
      <div key={i} className="flex animate-pop flex-col items-center py-6 text-center">
        <div className="mb-4 flex h-16 w-16 items-center justify-center rounded-[20px] bg-primary/15 text-primary-ink">
          <c.Icon size={30} aria-hidden />
        </div>
        <h3 className="text-title">{c.title}</h3>
        <p className="mt-2 max-w-xs text-[17px] text-muted">{c.body}</p>
        <div className="mt-5 flex gap-1.5" aria-hidden>
          {CARDS.map((_, k) => (
            <span key={k} className={`h-1.5 rounded-full ${k === i ? 'w-6 bg-primary' : 'w-1.5 bg-line'}`} />
          ))}
        </div>
      </div>
    </Sheet>
  );
}
