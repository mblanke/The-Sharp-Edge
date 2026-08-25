import { expect, test } from '@playwright/test';

const API = 'http://127.0.0.1:8001/api/v1';
const AUTH = { authorization: 'Bearer e2e-token' };

test('cook mode walks scaled steps with per-step amounts', async ({ page }) => {
  await page.goto('/r/goulash');
  // scale 6 → 12, then enter cook mode
  const more = page.getByRole('button', { name: /More/ });
  for (let i = 0; i < 6; i++) await more.click();
  await page.getByTestId('start-cooking').click();

  await expect(page).toHaveURL(/\/r\/goulash\/cook\?yield=12$/);
  const step = page.getByTestId('cook-step');
  await expect(step).toContainText('1');

  // goulash step 1 sears the beef — the scaled amount (2 lb × 2 = 4 lb) shows inline
  await expect(step).toContainText('4 lb');

  // advance and come back
  await page.getByTestId('next-step').click();
  await expect(step).toContainText('2/');
  await page.getByRole('button', { name: /back/ }).click();
  await expect(step).toContainText('1/');

  // the drawer lists the full scaled ingredient set
  await page.getByRole('button', { name: 'Show all ingredients' }).click();
  await expect(page.getByText('Ingredients · 12 servings')).toBeVisible();
});

test('cook mode timer counts down and finish screen appears', async ({ page, request }, testInfo) => {
  test.skip(testInfo.project.name !== 'ipad', 'mutates shared seeded state; run once');

  // give stirfry's first step a 3 s timer
  const current = await (await request.get(`${API}/recipes/stirfry`)).json();
  const v = current.current_version;
  const steps = v.steps.map((s: { text: string }, i: number) =>
    i === 0 ? { ...s, timer_seconds: 3 } : s
  );
  const res = await request.put(`${API}/recipes/stirfry`, {
    headers: AUTH,
    data: { ingredients: v.ingredients, steps, notes: v.notes, label: 'timer test' }
  });
  expect(res.ok()).toBeTruthy();

  await page.goto('/r/stirfry/cook');
  const timer = page.getByTestId('step-timer');
  await expect(timer).toContainText('0:03');
  await page.getByTestId('timer-start').click();
  await expect(timer).toContainText('0:00', { timeout: 6000 });

  // ride next → … → finish
  const total = v.steps.length;
  for (let i = 0; i < total; i++) await page.getByTestId('next-step').click();
  await expect(page.getByText('Done.')).toBeVisible();
});
