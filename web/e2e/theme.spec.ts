import { expect, test } from '@playwright/test';

test('evening kitchen mode toggles and persists', async ({ page }) => {
  await page.goto('/');
  const html = page.locator('html');
  await expect(html).not.toHaveAttribute('data-theme', 'dark');

  await page.getByRole('button', { name: /evening kitchen/ }).click();
  await expect(html).toHaveAttribute('data-theme', 'dark');

  // survives a reload via localStorage
  await page.reload();
  await expect(html).toHaveAttribute('data-theme', 'dark');

  await page.getByRole('button', { name: /daylight/ }).click();
  await expect(html).not.toHaveAttribute('data-theme', 'dark');
});

test('recipe rows use dotted leaders with mono amounts', async ({ page }) => {
  await page.goto('/r/goulash');
  const beefRow = page.locator('li', { hasText: 'beef chuck' });
  await expect(beefRow.locator('.leader-dots')).toBeVisible();
  await expect(beefRow.locator('.qty')).toHaveText(/^2 lb/);
});
