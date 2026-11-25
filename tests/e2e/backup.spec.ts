import { test, expect, type Page } from '@playwright/test';
import { dismissIntro, onboard, unlock } from './helpers';

async function snapshot(page: Page) {
  return page.evaluate(
    () =>
      new Promise<Record<string, string[]>>((resolve) => {
        const req = indexedDB.open('repmate');
        req.onsuccess = async () => {
          const dbi = req.result;
          const out: Record<string, string[]> = {};
          const names = Array.from(dbi.objectStoreNames).filter((n) => n !== 'media' && n !== 'activeSession');
          for (const n of names) {
            out[n] = await new Promise((res) => {
              const r = dbi.transaction(n).objectStore(n).getAll();
              r.onsuccess = () => res(r.result.map((x: unknown) => JSON.stringify(x)).sort());
            });
          }
          dbi.close();
          resolve(out);
        };
      }),
  );
}

test('backup round-trip: export → erase all data → restore on "new phone" → identical DB', async ({ page }) => {
  test.setTimeout(90_000);
  // On iPhone the share sheet opens (Save to Files). Here we hide it to exercise the download fallback.
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'canShare', { value: undefined, configurable: true });
  });
  await page.clock.install({ time: new Date(2026, 11, 20, 8, 0) });
  await onboard(page);
  await page.goto('/more/dev');
  await page.getByRole('button', { name: 'Load 30 days of demo data' }).click();
  await expect(page).toHaveURL(/progress/);

  await page.goto('/more/backup');
  const dl = page.waitForEvent('download');
  await page.getByRole('button', { name: /Export backup/ }).click();
  const file = await dl;
  expect(file.suggestedFilename()).toBe('repmate-backup-2026-12-20.json');
  const path = test.info().outputPath('backup.json');
  await file.saveAs(path);
  await expect(page.getByText('Last backup: 20 Dec 2026')).toBeVisible();
  const before = await snapshot(page);
  expect(before.sets.length).toBeGreaterThan(100);

  // erase everything (like a new phone)
  await page.goto('/more/settings');
  await page.getByRole('button', { name: 'Erase all data on this phone' }).click();
  await page.getByRole('button', { name: 'Erase all data', exact: true }).click();
  await expect(page).toHaveURL(/onboarding/);
  // erasing also forgets the invite unlock, like a brand-new phone
  await unlock(page);
  await page.getByLabel('Backup file').setInputFiles(path);
  await expect(page).toHaveURL(/today/);
  await dismissIntro(page);
  const after = await snapshot(page);
  expect(after).toEqual(before);
});

test('plan editor: add an exercise, edit sets, reorder by keyboard', async ({ page }) => {
  await page.clock.install({ time: new Date(2026, 11, 1, 8, 0) });
  await onboard(page);
  await page.goto('/more/plan');
  await page.getByRole('link', { name: /Strength A/ }).click();
  await page.getByRole('button', { name: 'Add exercise' }).click();
  await page.getByPlaceholder('Search 190+ exercises').fill('face pull');
  await page.getByRole('dialog').getByRole('button', { name: /^Face pull/ }).first().click();
  await expect(page.getByRole('button', { name: /Edit Face pull/ })).toBeVisible();
  await page.getByRole('button', { name: /Edit Face pull/ }).click();
  await page.getByRole('button', { name: 'Increase Sets' }).click();
  await page.getByRole('button', { name: 'Close' }).last().click();
  await expect(page.getByRole('button', { name: /Edit Face pull/ })).toContainText('4 ×');
  // keyboard reorder: move the new last item up one
  const handle = page.getByRole('button', { name: 'Reorder Face pull' });
  await handle.focus();
  await page.keyboard.press('Space');
  await page.keyboard.press('ArrowUp');
  await page.keyboard.press('Space');
  const names = await page.getByRole('button', { name: /^Edit / }).allTextContents();
  expect(names[names.length - 2]).toContain('Face pull');
});

test('settings: switching to lb converts displayed weights', async ({ page }) => {
  await onboard(page);
  await page.goto('/more/settings');
  await page.getByRole('tab', { name: 'lb' }).click();
  await expect(page.getByRole('group', { name: 'Goal weight' }).getByRole('textbox')).toHaveValue('163');
});
