import { test, expect } from "@playwright/test";
import { count, firstCard, vote, waitForClerk } from "./helpers";

// Runs against the in-app fake clerk-js (no Clerk account needed).
test.skip(process.env.E2E_REAL_CLERK === "1", "real Clerk run");

test("visitor signs up, votes, signs out and signs back in", async ({ page }) => {
  const email = `e2e-${Date.now()}@example.com`;
  const password = "correct-horse-battery";

  await page.goto("/");
  const card = firstCard(page);
  await expect(card).toBeVisible();

  // Voting requires authentication
  await card.getByTestId("vote-up").click();
  await expect(page).toHaveURL(/\/sign_in/);

  // Sign up
  await page.goto("/sign_up");
  await page.getByLabel("Email address").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: "Continue" }).click();
  await expect(page.getByTestId("current-user")).toBeVisible();

  // Vote: like -> dislike -> withdraw -> like
  const up = await count(card, "up");
  const down = await count(card, "down");
  await vote(page, card, "up");
  await expect(card.getByTestId("upvotes-count")).toHaveText(String(up + 1));
  await vote(page, card, "down");
  await expect(card.getByTestId("upvotes-count")).toHaveText(String(up));
  await expect(card.getByTestId("downvotes-count")).toHaveText(String(down + 1));
  await vote(page, card, "down");
  await expect(card.getByTestId("downvotes-count")).toHaveText(String(down));
  await vote(page, card, "up");

  // Sign out
  await waitForClerk(page);
  await page.getByTestId("sign-out").click();
  await expect(page.getByTestId("sign-in-link")).toBeVisible();
  await expect(card.getByTestId("upvotes-count")).toHaveText(String(up + 1));

  // Sign in again; the vote is remembered
  await page.goto("/sign_in");
  await page.getByLabel("Email address").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: "Continue" }).click();
  await expect(page.getByTestId("current-user")).toBeVisible();
  await expect(card.getByTestId("vote-up")).toHaveAttribute("aria-pressed", "true");
});
