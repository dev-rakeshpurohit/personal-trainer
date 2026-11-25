import { useUI } from '@/store/ui';
import { Button } from '@/components/ui';

/** Shows "New version" only when no workout is in progress. */
export function UpdatePrompt({ blocked }: { blocked: boolean }) {
  const { needRefresh, updateSW, setNeedRefresh } = useUI();
  if (!needRefresh || blocked) return null;
  return (
    <div className="fixed inset-x-0 top-0 z-50 px-4 pt-[calc(env(safe-area-inset-top)+8px)]">
      <div className="mx-auto flex max-w-md animate-pop items-center justify-between gap-3 rounded-card border border-info/40 bg-surface2 px-4 py-3 shadow-2xl">
        <span className="text-[15px] font-medium">New version available</span>
        <div className="flex gap-1">
          <Button variant="ghost" onClick={() => setNeedRefresh(false)}>
            Later
          </Button>
          <Button onClick={() => void updateSW?.(true)}>Reload</Button>
        </div>
      </div>
    </div>
  );
}
