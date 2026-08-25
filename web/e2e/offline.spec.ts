import { expect, test } from '@playwright/test';

// Runs in the chromium "offline" project — service workers + setOffline are
// reliable there; the webkit device projects skip this file (see config).
test('a viewed recipe cooks offline after reload', async ({ page, context }) => {
  await page.goto('/r/goulash');
  await expect(page.getByRole('heading', { name: /Goulash/ })).toBeVisible();
  // let the service worker install and cache the visit
  await page.evaluate(async () => {
    const reg = await navigator.serviceWorker.ready;
    return reg.active?.state;
  });
  // second visit lands in the runtime cache under SW control
  await page.reload();
  await expect(page.getByRole('heading', { name: /Goulash/ })).toBeVisible();

  await context.setOffline(true);
  await page.reload();
  await expect(page.getByRole('heading', { name: /Goulash/ })).toBeVisible();
  // scaling still works offline (client mirror; server reconcile silently skipped)
  const beefRow = page.locator('li', { hasText: 'beef chuck' });
  await page.getByRole('button', { name: /More/ }).click();
  await expect(beefRow.locator('.qty')).toHaveText(/2 ⅓ lb/);
  await context.setOffline(false);
});
