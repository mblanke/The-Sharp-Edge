import { expect, test } from '@playwright/test';

const API = 'http://127.0.0.1:8001/api/v1';
const AUTH = { authorization: 'Bearer e2e-token' };

// The edit mutates shared seeded state; run once (the kitchen device) and use
// a unique step text so retries/reruns stay unambiguous.
test('version switcher shows and swaps history after an edit', async ({ page, request }, testInfo) => {
  test.skip(testInfo.project.name !== 'ipad', 'runs on one project only');

  const stamp = `Rest the batter ${Date.now()} ms.`;
  const current = await (await request.get(`${API}/recipes/pancakes`)).json();
  const v = current.current_version;

  const res = await request.put(`${API}/recipes/pancakes`, {
    headers: AUTH,
    data: {
      ingredients: v.ingredients,
      steps: [...v.steps, { text: stamp }],
      notes: v.notes,
      label: 'rested batter'
    }
  });
  expect(res.ok()).toBeTruthy();

  await page.goto('/r/pancakes');
  const switcher = page.getByRole('group', { name: 'Versions' });
  await expect(switcher).toBeVisible();
  await expect(page.getByText(stamp)).toBeVisible();

  // switch to v1 — the old steps come back and the banner appears
  await switcher.getByRole('button', { name: /^v1/ }).click();
  await expect(page.getByText('viewing an older version')).toBeVisible();
  await expect(page.getByText(stamp)).toHaveCount(0);

  // and back to the newest (buttons are newest-first)
  await switcher.getByRole('button').first().click();
  await expect(page.getByText(stamp)).toBeVisible();
  await expect(page.getByText('viewing an older version')).toHaveCount(0);
});
