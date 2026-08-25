import { expect, test } from '@playwright/test';

// Mutates shared seeded state — run on one project only.
test('plan two dinners and push the week to the shared list', async ({ page }, testInfo) => {
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

  // push the week into the running list — lands on /shopping, the list iOS shares
  await page.getByTestId('generate-list').click();
  await expect(page).toHaveURL(/\/shopping$/);
  await expect(page.getByText(/beef chuck/).first()).toBeVisible();

  // back on the plan, removing an entry works
  await page.goto('/plan?week=2026-09-07');
  await page.getByRole('button', { name: /Remove Gluten-Free/ }).click();
  await expect(page.getByRole('link', { name: 'Gluten-Free Hungarian Beef Goulash' })).toHaveCount(0);
});
