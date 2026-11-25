import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { BackButton } from '@/components/BackButton';
import { Button, Card, PageHeader } from '@/components/ui';
import { useUI } from '@/store/ui';

/** Dev tools (hidden): demo data for checking charts and coach cards. */
export default function Developer() {
  const toast = useUI((s) => s.toast);
  const nav = useNavigate();
  const [busy, setBusy] = useState(false);
  return (
    <div className="pb-6">
      <PageHeader title="Developer" right={<BackButton to="/more" />} />
      <div className="space-y-3 px-4">
        <Card>
          <p className="font-semibold">Demo data</p>
          <p className="mt-1 text-[15px] text-muted">Replaces all logs (sessions, sets, meals, habits, body) with 30 days of realistic fake data. Your plan and profile are kept.</p>
          <Button
            className="mt-3"
            block
            disabled={busy}
            onClick={async () => {
              setBusy(true);
              const { seedDemoData } = await import('@/data/devSeed');
              const r = await seedDemoData();
              toast(`Loaded ${r.sessions} sessions, ${r.sets} sets, ${r.weighIns} weigh-ins`, { tone: 'success' });
              setBusy(false);
              nav('/progress');
            }}
          >
            Load 30 days of demo data
          </Button>
        </Card>
      </div>
    </div>
  );
}
