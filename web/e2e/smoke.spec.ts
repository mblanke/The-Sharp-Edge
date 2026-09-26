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
  // wait for the recipe itself, not just the URL — the view transition keeps the
  // home list in the DOM for a frame, and it has a GF badge on every other row
  const title = page.getByRole('heading', { name: /Goulash/ });
  await expect(title).toBeVisible();
  await expect(title.getByText('GF', { exact: true })).toBeVisible();

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

test('an unknown slug lands on the branded error page, not the framework default', async ({ page }) => {
  await page.goto('/r/no-such-recipe');
  await expect(page.getByTestId('error-page')).toBeVisible();
  await expect(page.getByText('404')).toBeVisible();
  await page.getByRole('link', { name: /all recipes/ }).click();
  await expect(page).toHaveURL(/\/$/);
});

test('a search with no hits says so and can be cleared; the query survives a reload', async ({ page }) => {
  await page.goto('/');
  const box = page.getByRole('searchbox', { name: 'Search recipes' });
  await box.fill('zzqx');
  await expect(page.getByTestId('no-results')).toBeVisible();
  await expect(page).toHaveURL(/\?q=zzqx$/);
  await page.reload();
  await expect(box).toHaveValue('zzqx');
  await expect(page.getByTestId('no-results')).toBeVisible();
  await page.getByRole('button', { name: 'Clear search', exact: true }).click();
  await expect(page.getByTestId('no-results')).toHaveCount(0);
  await expect(page.getByRole('link', { name: /Gluten-Free Hungarian Beef Goulash/ })).toBeVisible();
});

test('amounts can be read in metric or imperial, and ticks survive a reload', async ({ page }) => {
  await page.goto('/r/goulash');
  const beefRow = page.locator('li', { hasText: 'beef chuck' });
  await expect(beefRow.locator('.qty')).toHaveText(/^2 lb/);

  // the lens converts the scaled amount; the recipe itself is untouched
  await page.getByTestId('units-metric').click();
  await expect(beefRow.locator('.qty')).toHaveText(/^900 g/);
  await page.getByRole('button', { name: /More/ }).click();
  await expect(beefRow.locator('.qty')).toHaveText(/^1050 g/);
  await page.getByTestId('units-recipe').click();
  await expect(beefRow.locator('.qty')).toHaveText(/^2 ⅓ lb/);

  // tick an ingredient as it goes in; a reload keeps it
  const row = beefRow.getByTestId('ingredient-row');
  await row.click();
  await expect(row).toHaveAttribute('aria-pressed', 'true');
  await page.reload();
  await expect(page.locator('li', { hasText: 'beef chuck' }).getByTestId('ingredient-row')).toHaveAttribute('aria-pressed', 'true');
  await page.getByRole('button', { name: /clear/ }).click();
  await expect(page.locator('li', { hasText: 'beef chuck' }).getByTestId('ingredient-row')).toHaveAttribute('aria-pressed', 'false');
});

test('settings persist units and theme on this device, and home remembers what you opened', async ({ page }) => {
  await page.goto('/settings');
  await page.getByTestId('units-metric').click();
  await page.getByTestId('theme-dark').click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');

  await page.goto('/r/goulash');
  await expect(page.locator('li', { hasText: 'beef chuck' }).locator('.qty')).toHaveText(/^900 g/);
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');

  await page.goto('/');
  const recent = page.getByTestId('recent');
  await expect(recent).toBeVisible();
  await expect(recent.getByRole('link', { name: /Goulash/ })).toBeVisible();

  // ⌘K from another page lands in the search box
  await page.goto('/shopping');
  // the handler exists once the page hydrates; a press before that is lost, so
  // retry the press rather than guess a delay
  await expect(async () => {
    await page.keyboard.press('ControlOrMeta+k');
    await expect(page).toHaveURL(/\/$/, { timeout: 1000 });
  }).toPass();
  await expect(page.getByRole('searchbox', { name: 'Search recipes' })).toBeFocused();

  await page.goto('/settings');
  await page.getByTestId('theme-system').click();
  await page.getByTestId('units-recipe').click();
});
