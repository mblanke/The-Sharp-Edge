import { expect, test } from '@playwright/test';

// An iPad with a keyboard attached: `?` lists every shortcut, `g` + letter
// jumps between sections, and neither fires while typing in a field.

test('? opens the shortcut sheet and Escape closes it', async ({ page }) => {
  await page.goto('/plan');
  await page.keyboard.press('Shift+?');
  const sheet = page.getByRole('dialog', { name: 'Keyboard' });
  await expect(sheet).toBeVisible();
  await expect(sheet.getByText('find a recipe')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(sheet).toHaveCount(0);
});

test('g then a letter jumps to a section', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('searchbox', { name: 'Search recipes' })).toBeVisible();
  await page.locator('body').click({ position: { x: 5, y: 400 } });
  await page.keyboard.press('g');
  await page.keyboard.press('s');
  await expect(page).toHaveURL(/\/shopping$/);
  await page.keyboard.press('g');
  await page.keyboard.press('p');
  await expect(page).toHaveURL(/\/plan$/);
});

test('shortcuts never fire while typing', async ({ page }) => {
  await page.goto('/');
  const box = page.getByRole('searchbox', { name: 'Search recipes' });
  await box.fill('');
  await box.pressSequentially('gs?');
  await expect(box).toHaveValue('gs?');
  await expect(page).toHaveURL(/\/(\?q=gs%3F)?$/);
  await expect(page.getByRole('dialog', { name: 'Keyboard' })).toHaveCount(0);
});
