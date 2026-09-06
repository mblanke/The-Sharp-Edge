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

  // the drawer lists the full scaled ingredient set, and Escape closes it
  await page.getByRole('button', { name: 'Show all ingredients' }).click();
  await expect(page.getByText('Ingredients · 12 servings')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.getByText('Ingredients · 12 servings')).toHaveCount(0);
});

test('cook mode offers to resume where you left off, and a stray tap can be undone', async ({ page }) => {
  await page.goto('/r/goulash/cook');
  const step = page.getByTestId('cook-step');
  await page.getByTestId('next-step').click();
  await page.getByTestId('next-step').click();
  await expect(step).toContainText('3/');

  // undo the last advance within its 3 s window
  await page.getByTestId('undo-step').click();
  await expect(step).toContainText('2/');

  // a fresh visit offers the saved position instead of silently restarting
  await page.goto('/r/goulash/cook');
  await expect(page.getByRole('dialog', { name: /Pick up at step/ })).toBeVisible();
  await page.getByTestId('resume-step').click();
  await expect(step).toContainText('2/');

  // ?step= (the tray's deep link) jumps straight there
  await page.goto('/r/goulash/cook?step=4');
  await expect(step).toContainText('4/');
  await expect(page.getByRole('dialog')).toHaveCount(0);
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

  // the timer belongs to the app, not the step: it follows you to other pages,
  // survives a reload, and only leaves when dismissed
  await page.goto('/');
  const tray = page.getByTestId('timer-tray');
  await expect(tray).toContainText(/stir.?fry/i);
  await expect(tray).toContainText('step 1');
  await expect(tray).toContainText('done');
  await page.reload();
  await expect(page.getByTestId('timer-tray')).toContainText('done');
  await page.getByRole('button', { name: /Dismiss/ }).click();
  await expect(page.getByTestId('timer-tray')).toHaveCount(0);

  await page.goto('/r/stirfry/cook');

  // ride next → … → finish
  const total = v.steps.length;
  for (let i = 0; i < total; i++) await page.getByTestId('next-step').click();
  await expect(page.getByText('Done.')).toBeVisible();

  // log the cook with a note → recipe page shows the last-cooked strip
  await page.getByPlaceholder(/what did you change/).fill('extra ginger');
  await page.getByTestId('log-cook').click();
  await expect(page).toHaveURL(/\/r\/stirfry$/);
  const strip = page.getByTestId('last-cooked');
  await expect(strip).toContainText('last cooked');
  await expect(strip).toContainText('extra ginger');
});
