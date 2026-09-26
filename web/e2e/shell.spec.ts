import { expect, test } from '@playwright/test';

// The one layout is a phone app below 768px and a rail beside the content above
// it. These pin which chrome is on screen per device, and that cook mode owns
// the bottom edge on a phone (the tab bar used to sit on top of Next).

test('the right chrome for the device', async ({ page }, testInfo) => {
  await page.goto('/');
  const rail = page.getByTestId('rail');
  const tabbar = page.getByTestId('tabbar');
  const topbar = page.getByTestId('topbar');
  if (testInfo.project.name === 'iphone') {
    await expect(tabbar).toBeVisible();
    await expect(topbar).toBeVisible();
    await expect(rail).toBeHidden();
  } else {
    await expect(rail).toBeVisible();
    await expect(tabbar).toBeHidden();
    await expect(topbar).toBeHidden();
  }
  // exactly one theme toggle is reachable, whichever bar carries it
  await expect(page.getByRole('button', { name: /evening kitchen|daylight/ })).toHaveCount(1);
});

test('the current section is marked in the visible nav', async ({ page }) => {
  await page.goto('/shopping');
  const current = page.locator('nav a[aria-current="page"]:visible');
  await expect(current).toHaveCount(1);
  await expect(current).toHaveText(/List/);
});

test('cook mode owns the bottom edge and, on an iPad, shows the mise en place', async ({ page }, testInfo) => {
  await page.goto('/r/goulash/cook');
  await expect(page.getByTestId('tabbar')).toHaveCount(0);
  await expect(page.getByTestId('next-step')).toBeVisible();
  const side = page.getByTestId('cook-side');
  if (testInfo.project.name === 'ipad') {
    await expect(side).toBeVisible();
    // the step's own ingredients are lit in the full list
    await expect(side.locator('li.now').first()).toContainText('beef chuck');
  } else {
    await expect(side).toBeHidden();
  }
});

test('a phone gets a way back from a recipe; home has none', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'iphone', 'the back button lives in the phone top bar');
  await page.goto('/');
  await expect(page.getByTestId('back')).toHaveCount(0);
  await page.getByRole('link', { name: /Classic Fluffy Pancakes/ }).click();
  await expect(page).toHaveURL(/\/r\/pancakes$/);
  await page.getByTestId('back').click();
  await expect(page).toHaveURL(/\/$/);
});

test('quantities keep their contrast in evening mode', async ({ page }) => {
  await page.goto('/r/goulash');
  await page.getByRole('button', { name: /evening kitchen/ }).click();
  const qty = page.locator('li', { hasText: 'beef chuck' }).locator('.qty');
  // #8fc39e — the ink accent, never the #24402c fill; polled because the colour
  // eases over 450 ms
  await expect.poll(() => qty.evaluate((el) => getComputedStyle(el).color)).toBe('rgb(143, 195, 158)');
  // the current section in whichever nav is showing uses it too — it used to
  // be the fill, which left the active phone tab almost invisible at night
  const currentNav = page.locator('nav a[aria-current="page"]:visible').first();
  await expect
    .poll(() => currentNav.evaluate((el) => getComputedStyle(el).color))
    .not.toBe('rgb(36, 64, 44)');
  await page.getByRole('button', { name: /daylight/ }).click();
});
