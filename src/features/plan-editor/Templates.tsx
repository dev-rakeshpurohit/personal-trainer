import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { BackButton } from '@/components/BackButton';
import { Sheet } from '@/components/Sheet';
import { Button, Card, PageHeader } from '@/components/ui';
import { useProfile } from '@/data/hooks';
import { useUI } from '@/store/ui';

export default function Templates() {
  const profile = useProfile();
  const toast = useUI((s) => s.toast);
  const nav = useNavigate();
  const [confirm, setConfirm] = useState<'program' | 'diet'>();
  const apply = async () => {
    const seed = await import('@/data/seed-import');
    if (confirm === 'program') await seed.importProgramTemplate({ trainingDays: profile?.trainingDays });
    if (confirm === 'diet') await seed.importDietTemplate();
    toast('Template applied. Your history is kept.', { tone: 'success' });
    setConfirm(undefined);
    nav('/today');
  };
  return (
    <div className="pb-6">
      <PageHeader title="Templates" right={<BackButton to="/more" />} />
      <div className="space-y-3 px-4">
        <Card>
          <p className="text-[17px] font-bold">Lean & Athletic · 5 days</p>
          <p className="mt-1 text-[15px] text-muted">3 full-body strength days (A/B/C), steady cardio + core, and athletic power + intervals. 8-week wave with a deload. 276 exercise alternates.</p>
          <Button className="mt-3" block onClick={() => setConfirm('program')}>
            Use this workout plan
          </Button>
        </Card>
        <Card>
          <p className="text-[17px] font-bold">Veg + eggs · 2,000 kcal / 150 g protein</p>
          <p className="mt-1 text-[15px] text-muted">Lactose-conscious, no paneer. 6 meals + an optional protein top-up, rotating snacks, habit targets.</p>
          <Button className="mt-3" block variant="secondary" onClick={() => setConfirm('diet')}>
            Use this diet plan
          </Button>
        </Card>
      </div>
      <Sheet open={!!confirm} onClose={() => setConfirm(undefined)} title="Replace your current plan?">
        <p className="text-[15px] text-muted">Your current {confirm === 'diet' ? 'diet' : 'workout'} plan will be replaced. Logs and history stay.</p>
        <div className="mt-4 space-y-2 pb-3">
          <Button block size="lg" onClick={apply}>
            Replace
          </Button>
          <Button block variant="secondary" onClick={() => setConfirm(undefined)}>
            Cancel
          </Button>
        </div>
      </Sheet>
    </div>
  );
}
