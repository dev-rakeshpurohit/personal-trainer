import { Bell } from 'lucide-react';
import { useState } from 'react';
import { BackButton } from '@/components/BackButton';
import { Field, TextInput, Toggle } from '@/components/Field';
import { Segmented } from '@/components/Segmented';
import { Sheet } from '@/components/Sheet';
import { Stepper } from '@/components/Stepper';
import { Button, Card, PageHeader, SectionTitle } from '@/components/ui';
import { db } from '@/data/db';
import { useProfile } from '@/data/hooks';
import type { Profile } from '@/domain/types';
import { fromUserUnits, toUserUnits } from '@/domain/units';
import { notificationsSupported, requestNotificationPermission } from '@/lib/notify';
import { applyTheme } from '@/lib/theme';
import { useUI } from '@/store/ui';

export default function Settings() {
  const profile = useProfile();
  const toast = useUI((s) => s.toast);
  const [reset, setReset] = useState(false);
  if (!profile) return null;
  const up = (patch: Partial<Profile>) => db.profile.update('me', patch);
  const units = profile.units;

  return (
    <div className="pb-8">
      <PageHeader title="Settings" right={<BackButton to="/more" />} />
      <div className="space-y-2 px-4">
        <SectionTitle>Profile</SectionTitle>
        <Card className="space-y-4">
          <Field label="Name">
            <TextInput defaultValue={profile.name} onBlur={(e) => e.target.value.trim() && up({ name: e.target.value.trim() })} />
          </Field>
          <div>
            <span className="mb-1.5 block text-[14px] font-semibold text-muted">Goal weight</span>
            <Stepper label="Goal weight" value={toUserUnits(profile.goalWeightKg, units)} onChange={(v) => up({ goalWeightKg: fromUserUnits(v, units) })} step={0.5} suffix={units} decimals={1} />
          </div>
          <Field label="Target date">
            <TextInput type="date" defaultValue={profile.targetDate ?? ''} onChange={(e) => up({ targetDate: e.target.value || undefined })} />
          </Field>
        </Card>

        <SectionTitle>Display</SectionTitle>
        <Card className="space-y-4">
          <div>
            <span className="mb-1.5 block text-[14px] font-semibold text-muted">Units</span>
            <Segmented label="Units" value={units} onChange={(v) => up({ units: v })} options={[{ value: 'kg', label: 'kg' }, { value: 'lb', label: 'lb' }]} />
          </div>
          <div>
            <span className="mb-1.5 block text-[14px] font-semibold text-muted">Theme</span>
            <Segmented
              label="Theme"
              value={profile.theme}
              onChange={(v) => {
                applyTheme(v);
                void up({ theme: v });
              }}
              options={[
                { value: 'dark', label: 'Dark' },
                { value: 'light', label: 'Light' },
                { value: 'system', label: 'System' },
              ]}
            />
          </div>
          <div>
            <span className="mb-1.5 block text-[14px] font-semibold text-muted">Week starts on</span>
            <Segmented label="Week start" value={profile.weekStart ?? 'mon'} onChange={(v) => up({ weekStart: v })} options={[{ value: 'mon', label: 'Monday' }, { value: 'sun', label: 'Sunday' }]} />
          </div>
        </Card>

        <SectionTitle>Rest timer</SectionTitle>
        <Card className="!py-1">
          <Toggle checked={profile.restTimer.sound} onChange={(v) => up({ restTimer: { ...profile.restTimer, sound: v } })} label="Chime" sub="Plays when rest is over (works with the screen on)" />
          <Toggle checked={profile.restTimer.vibrate} onChange={(v) => up({ restTimer: { ...profile.restTimer, vibrate: v } })} label="Vibrate" sub="Android only; iPhone gets a colour flash" />
          <Toggle
            checked={profile.restTimer.notify}
            onChange={async (v) => {
              if (v) {
                const r = await requestNotificationPermission();
                if (r !== 'granted') {
                  toast(r === 'unsupported' ? 'On iPhone, notifications need the Home Screen app (iOS 16.4+).' : 'Notifications were not allowed.');
                  return;
                }
              }
              await up({ restTimer: { ...profile.restTimer, notify: v } });
            }}
            label="Notification"
            sub={notificationsSupported() ? 'Alert when rest ends while the app is in the background' : 'Needs the Home Screen app on iPhone'}
          />
        </Card>

        <SectionTitle>Weight steps (progression)</SectionTitle>
        <Card className="space-y-3">
          {(['dumbbell', 'barbell', 'machine'] as const).map((k) => (
            <div key={k} className="flex items-center gap-3">
              <span className="w-24 font-medium capitalize">{k}</span>
              <div className="flex-1">
                <Stepper label={`${k} increment`} value={profile.stepKg[k]} onChange={(v) => up({ stepKg: { ...profile.stepKg, [k]: v } })} step={0.5} min={0.5} max={20} suffix="kg" decimals={1} />
              </div>
            </div>
          ))}
          <p className="text-caption text-muted">When you hit the top of the rep range on every set, Repmate suggests adding this much.</p>
        </Card>

        <SectionTitle>Reminders</SectionTitle>
        <Card>
          <p className="flex items-start gap-2 text-[15px] text-muted">
            <Bell size={18} className="mt-0.5 shrink-0" aria-hidden />
            Web apps can't schedule reminders reliably in the background (no server, iOS suspends them). Repmate nudges you in-app instead: Today shows your next meal, weigh-in and the session at {profile.sessionTime}.
          </p>
        </Card>

        <SectionTitle>Danger zone</SectionTitle>
        <Button variant="danger" block onClick={() => setReset(true)}>
          Erase all data on this phone
        </Button>
      </div>
      <Sheet open={reset} onClose={() => setReset(false)} title="Erase everything?">
        <p className="text-[15px] text-muted">This deletes your profile, plan, logs, clips and photos from this phone. Export a backup first if you might want them.</p>
        <div className="mt-4 space-y-2 pb-3">
          <Button
            variant="danger"
            block
            size="lg"
            onClick={async () => {
              await db.delete();
              try {
                localStorage.clear();
              } catch {
                /* ignore */
              }
              window.location.assign('/');
            }}
          >
            Erase all data
          </Button>
          <Button variant="secondary" block onClick={() => setReset(false)}>
            Cancel
          </Button>
        </div>
      </Sheet>
    </div>
  );
}
