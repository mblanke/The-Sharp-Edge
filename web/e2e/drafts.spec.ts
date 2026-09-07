import { expect, test } from '@playwright/test';

test('a list of links lands as drafts, out of the index, with the bad link reported', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'ipad', 'mutates shared seeded state; run once');
  await page.goto('/drafts');
  await page.getByLabel('Import a list of links').fill(
    'https://example.com/recipes/lemon-posset\nhttps://example.com/broken\nhttps://example.com/recipes/pan-bagnat'
  );
  await page.getByTestId('batch-import').click();
  await expect(page.getByTestId('import-failed')).toContainText('broken');
  const list = page.getByTestId('drafts-list');
  await expect(list).toContainText('Lemon Posset');
  await expect(list).toContainText('Pan Bagnat');

  // drafts stay out of the home index, but home points at the queue
  await page.goto('/');
  await expect(page.getByText('Lemon Posset')).toHaveCount(0);
  await expect(page.getByTestId('drafts-link')).toContainText(/drafts? to review/);
});
