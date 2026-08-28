import { expect, test } from '@playwright/test';

/** First e2e coverage for /ask — against the e2e server's canned retrieval
 *  (a real CIA-shaped onion soup passage) and canned provider. The attribution
 *  check, citation mapping, SSE plumbing and the passage → notebook bridge all
 *  run their genuine code paths; only Atlas and the LLM are stubbed. */

test('a question streams an answer with a citation that opens its source', async ({ page }) => {
  await page.goto('/ask');
  await page.getByPlaceholder(/how does keller/i).fill('How do I make onion soup?');
  await page.getByRole('button', { name: /^ask$/i }).click();

  // streamed tokens land, then the citation chip appears on done
  await expect(page.getByText(/then simmer in stock/)).toBeVisible();
  const chip = page.getByRole('button', { name: /\[1\] The Professional Chef/ });
  await expect(chip).toBeVisible();
  await expect(chip).toContainText('p.358');

  // the chip opens the source text
  await chip.click();
  await expect(page.getByText(/5 lb thinly sliced onions|thinly sliced onions/)).toBeVisible();
});

test('a cited passage drafts into the notebook, private and review-first', async ({ page }) => {
  await page.goto('/ask');
  await page.getByPlaceholder(/how does keller/i).fill('How do I make onion soup?');
  await page.getByRole('button', { name: /^ask$/i }).click();
  await page.getByRole('button', { name: /\[1\] The Professional Chef/ }).click();

  await page.getByRole('button', { name: /draft into notebook/i }).click();

  // lands on /new with the form prefilled by the deterministic passage parser
  await expect(page).toHaveURL(/\/new/);
  await expect(page.getByLabel('Title')).toHaveValue('Onion Soup');
  // the source line carries book · page, and the draft is marked private
  await expect(page.getByLabel('Source')).toHaveValue('The Professional Chef · p.358');
  await expect(page.getByText(/private · not exported/i)).toBeVisible();
  // nothing was saved: this is a form, not a recipe
  await page.goto('/');
  await expect(page.getByText('Onion Soup')).toHaveCount(0);
});

test('asking about an absent authority shows the shelf note', async ({ page }) => {
  await page.goto('/ask');
  await page.getByPlaceholder(/how does keller/i).fill('How does Escoffier build an espagnole?');
  await page.getByRole('button', { name: /^ask$/i }).click();

  // the real attribution check runs against the canned CIA chunk
  await expect(page.getByText(/There is no Escoffier on this shelf/)).toBeVisible();
  await expect(page.getByText(/The Professional Chef/).first()).toBeVisible();
});
