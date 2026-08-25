import { expect, test } from '@playwright/test';

test('home lists the notebook recipes', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('link', { name: /Gluten-Free Hungarian Beef Goulash/ })).toBeVisible();
  await expect(page.getByRole('link', { name: /Classic Fluffy Pancakes/ })).toBeVisible();
});

test('goulash scales 6 → 14 with copper flash and server parity', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('link', { name: /Gluten-Free Hungarian Beef Goulash/ }).click();
  await expect(page).toHaveURL(/\/r\/goulash$/);
  await expect(page.getByText('GF', { exact: true })).toBeVisible();

  // 2 lb beef chuck at base 6
  const beefRow = page.locator('li', { hasText: 'beef chuck' });
  await expect(beefRow.locator('.qty')).toHaveText(/^2 lb/);

  // step the scaler 6 → 14
  const more = page.getByRole('button', { name: /More/ });
  for (let i = 0; i < 8; i++) await more.click();

  // client mirror renders instantly; server reconciliation must agree (4 ⅔ lb)
  await expect(beefRow.locator('.qty')).toHaveText(/4 ⅔ lb/);
  await expect(page.locator('.qty.flash').first()).toBeVisible();

  // reset to base
  await page.getByRole('button', { name: /base 6/ }).click();
  await expect(beefRow.locator('.qty')).toHaveText(/^2 lb/);
});

test('to-taste rows stay em dash at any scale', async ({ page }) => {
  await page.goto('/r/mango-salsa');
  const pepper = page.locator('li', { hasText: 'black pepper' }).first();
  await expect(pepper.locator('.qty')).toHaveText('—');
  await page.getByRole('button', { name: /More/ }).click();
  await expect(pepper.locator('.qty')).toHaveText('—');
});

test('home search finds recipes by ingredient', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('searchbox', { name: 'Search recipes' }).fill('paprika');
  // goulash has paprika; pancakes don't
  await expect(page.getByRole('link', { name: /Gluten-Free Hungarian Beef Goulash/ })).toBeVisible();
  await expect(page.getByRole('link', { name: /Classic Fluffy Pancakes/ })).toHaveCount(0);
});
