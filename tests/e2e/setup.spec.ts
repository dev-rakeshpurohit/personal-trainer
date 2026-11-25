import { test, expect } from '@playwright/test';
import { onboard } from './helpers';

test('setup: switch to a dumbbells-only gym → plan adapts, never keeps unavailable exercises', async ({ page }) => {
  await page.clock.install({ time: new Date(2026, 11, 1, 8, 0) });
  await onboard(page);
  await page.goto('/more/setup');
  await page.getByRole('button', { name: /Gym equipment/ }).click();
  await page.getByRole('button', { name: 'Dumbbells', exact: true }).click();
  await page.getByRole('button', { name: 'Done' }).click();
  await page.getByRole('button', { name: /Apply changes/ }).click();
  await page.getByRole('dialog', { name: 'Apply changes' }).getByRole('button', { name: 'Apply', exact: true }).click();
  await expect(page).toHaveURL(/today/);
  await page.goto('/more/plan');
  await page.getByRole('link', { name: /Strength B/ }).click();
  const text = await page.locator('main').innerText();
  expect(text).not.toMatch(/Leg press|Seated cable row|Face pull|Cable/);
});

test('setup: start fresh keeps history', async ({ page }) => {
  await onboard(page);
  await page.goto('/more/setup');
  await page.getByRole('button', { name: /New plan, keep history/ }).click();
  await expect(page.getByRole('heading', { name: /Start fresh/ })).toBeVisible();
  await page.getByRole('button', { name: 'Get started' }).click();
  await page.getByRole('button', { name: /Get stronger/ }).click();
  for (let i = 0; i < 5; i++) await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByRole('button', { name: 'Use this plan' }).click();
  await expect(page).toHaveURL(/today/);
  await expect(page.getByText(/Fresh plan ready/)).toBeVisible();
});
