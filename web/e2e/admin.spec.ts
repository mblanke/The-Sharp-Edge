import { expect, test } from '@playwright/test';

test('admin shows the gf audit and exports download', async ({ page }) => {
  await page.goto('/admin');
  // the seed corpus carries known check-the-label items (Worcestershire,
  // wasabi oil) in GF-flagged recipes — the audit must surface them
  await expect(page.getByText(/Worcestershire/).first()).toBeVisible();
  await expect(page.getByText(/wasabi oil/).first()).toBeVisible();
  await expect(page.getByText(/rag-api/)).toBeVisible();

  const download = page.waitForEvent('download');
  await page.getByRole('link', { name: 'master.md' }).click();
  expect((await download).suggestedFilename()).toBe('recipes-master.md');
});

test('editor warns live when a GF recipe gains a risky ingredient', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'ipad', 'edits shared state fields; run once');
  await page.goto('/r/goulash/edit');
  await expect(page.getByTestId('gf-warning')).toHaveCount(0);
  // type a hidden-gluten ingredient into the first name field
  await page.getByLabel('Name').first().fill('soy sauce');
  await expect(page.getByTestId('gf-warning')).toBeVisible();
  // clearing it with a GF phrasing removes the warning
  await page.getByLabel('Name').first().fill('GF tamari');
  await expect(page.getByTestId('gf-warning')).toHaveCount(0);
});
