import { expect, test } from '@playwright/test';

test('cook-together builds one interleaved timeline for two dishes', async ({ page }) => {
  await page.goto('/cook-together?slugs=goulash,gurkensalat');

  const timeline = page.getByTestId('timeline');
  await expect(timeline).toBeVisible();

  // steps from both recipes appear in one list, each labeled by dish
  await expect(timeline.getByText('Gluten-Free Hungarian Beef Goulash').first()).toBeVisible();
  await expect(
    timeline.getByText('German Creamy Cucumber-Dill Salad (Gurkensalat)').first()
  ).toBeVisible();

  // clock labels render for every entry
  const rows = timeline.locator('li');
  expect(await rows.count()).toBeGreaterThan(4);

  // checking off a step strikes it through
  await rows.first().getByRole('button').click();
  await expect(rows.first()).toHaveCSS('opacity', '0.45');

  // deselecting a dish rebuilds the picker state (exact match = the picker chip)
  await page
    .getByRole('button', { name: 'German Creamy Cucumber-Dill Salad (Gurkensalat)', exact: true })
    .click();
  await expect(page.getByText('Pick at least two dishes')).toBeVisible();
});
