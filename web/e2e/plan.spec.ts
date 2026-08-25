import { expect, test } from '@playwright/test';

// Mutates shared seeded state — run on one project only.
test('plan two dinners and generate a merged shopping list', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'ipad', 'mutates shared seeded state; run once');

  await page.goto('/plan?week=2026-09-07');

  // add goulash to Monday dinner
  await page.getByRole('button', { name: '+ dinner' }).first().click();
  await page.getByRole('button', { name: /Gluten-Free Hungarian Beef Goulash/ }).click();
  await expect(page.getByRole('link', { name: 'Gluten-Free Hungarian Beef Goulash' })).toBeVisible();

  // add gurkensalat to Tuesday dinner
  await page.getByRole('button', { name: '+ dinner' }).first().click();
  await page.getByRole('button', { name: /Gurkensalat/ }).click();
  await expect(page.getByRole('link', { name: /Gurkensalat/ })).toBeVisible();

  // generate the list — merged, unchecked, mono amounts
  await page.getByTestId('generate-list').click();
  const list = page.getByTestId('shopping-list');
  await expect(list).toBeVisible();
  await expect(list.getByText('beef chuck')).toBeVisible();
  await expect(list.getByText(/salt/).first()).toBeVisible();

  // check an item — strikethrough persists through the round-trip
  const firstRow = list.locator('li').first();
  await firstRow.getByRole('button').click();
  await expect(firstRow.locator('span').first()).toHaveText('✓');

  // remove a plan entry and regenerate → list shrinks
  await page.getByRole('button', { name: /Remove Gluten-Free/ }).click();
  await expect(page.getByRole('link', { name: 'Gluten-Free Hungarian Beef Goulash' })).toHaveCount(0);
  await page.getByTestId('generate-list').click();
  await expect(list.getByText('beef chuck')).toHaveCount(0);
});
