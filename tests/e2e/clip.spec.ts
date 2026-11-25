import path from 'node:path';
import { test, expect } from '@playwright/test';
import { KillableServer, onboard, waitForSW, idbCount } from './helpers';

test('a clip recorded offline plays after an app restart', async ({ page, context }) => {
  const server = new KillableServer(4184);
  await server.start();
  try {
    await page.goto(server.url + '/');
    await waitForSW(page);
    await page.goto(server.url + '/onboarding');
    await onboard(page, { base: server.url });
    await server.stop();

    await page.goto(server.url + '/train/library/front-plank');
    await page.getByLabel('Record a clip for Front plank').setInputFiles(path.join(import.meta.dirname, '../fixtures/clip.mp4'));
    await expect(page.getByText(/Clip saved for Front plank/)).toBeVisible();
    expect(await idbCount(page, 'clips')).toBe(1);

    // "restart": fresh page in the same context, still offline
    await page.close();
    const p2 = await context.newPage();
    await p2.goto(server.url + '/train/library/front-plank');
    const video = p2.getByLabel('My clip: Front plank');
    await expect(video).toBeVisible();
    expect(await video.evaluate((v: HTMLVideoElement) => v.src.startsWith('blob:'))).toBe(true);
    await expect(p2.getByRole('button', { name: 'Delete my clip' })).toBeVisible();
    await expect(p2.getByRole('button', { name: 'Replace clip' })).toBeVisible();
  } finally {
    await server.stop();
  }
});
