import { test, expect } from '@playwright/test';
import { onboard } from './helpers';

test('training day: eating every planned meal matches the seed totals (≈150 g / ≈2,000 kcal)', async ({ page }) => {
  await page.clock.install({ time: new Date(2026, 11, 1, 21, 0) }); // Tuesday
  await onboard(page);
  await page.getByRole('link', { name: 'Eat' }).click();
  for (let i = 0; i < 6; i++) await page.getByRole('button', { name: 'Eaten', exact: true }).first().click();
  const bar = page.getByRole('status', { name: 'Day totals' });
  await expect(bar).toContainText('155/150 g');
  await expect(bar).toContainText('2,005/2,000 kcal');
});

test('rest day hides the pre-gym snack (≈1,950 kcal)', async ({ page }) => {
  await page.clock.install({ time: new Date(2026, 10, 30, 8, 0) }); // Monday, gym closed
  await onboard(page);
  await page.getByRole('link', { name: 'Eat' }).click();
  await expect(page.getByText(/rest-day menu/)).toBeVisible();
  await expect(page.getByText(/1,940 kcal planned/)).toBeVisible();
  await expect(page.getByRole('article', { name: /Pre-gym/ })).toHaveCount(0);
});

test('swap a meal with custom macros, undo a skip, and log habits', async ({ page }) => {
  await page.clock.install({ time: new Date(2026, 11, 1, 12, 0) });
  await onboard(page);
  await page.getByRole('link', { name: 'Eat' }).click();
  const lunch = page.getByRole('article', { name: /Lunch/ });
  await lunch.getByRole('button', { name: 'Swap Lunch' }).click();
  await page.getByPlaceholder(/3 egg whites/).fill('Chole + 2 roti');
  await page.getByRole('button', { name: 'Save swap' }).click();
  await expect(lunch).toContainText('Swapped: Chole + 2 roti');

  const snack = page.getByRole('article', { name: /Snack/ });
  await snack.getByRole('button', { name: 'Skip Snack' }).click();
  await page.getByRole('button', { name: 'Undo', exact: true }).last().click();
  await expect(snack.getByRole('button', { name: 'Eaten', exact: true })).toBeVisible();

  await page.getByRole('button', { name: 'Add 250 ml water' }).click();
  await page.getByRole('button', { name: 'Add 500 ml water' }).click();
  await expect(page.getByText('0.75')).toBeVisible();
  await page.getByRole('checkbox', { name: /Creatine/ }).click();
  await expect(page.getByRole('checkbox', { name: /Creatine/ })).toHaveAttribute('aria-checked', 'true');
});
