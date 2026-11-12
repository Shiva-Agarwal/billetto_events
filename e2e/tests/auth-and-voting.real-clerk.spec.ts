import { test, expect } from "@playwright/test";
import { clerk, setupClerkTestingToken } from "@clerk/testing/playwright";
import { count, firstCard, vote, waitForClerk } from "./helpers";

// Runs against a real Clerk development instance (E2E_REAL_CLERK=1 + Clerk test keys in .env).
// The instance must allow email + password sign-up. Emails containing "+clerk_test" never
// receive real mail and always accept the verification code 424242.
test.skip(process.env.E2E_REAL_CLERK !== "1", "set E2E_REAL_CLERK=1 to run against real Clerk");

test("sign-up, voting, sign-out and sign-in with real Clerk", async ({ page }) => {
  const email = `billetto-e2e+clerk_test${Date.now()}@example.com`;
  const password = `E2e-${Date.now()}-pass!`;

  await setupClerkTestingToken({ page });

  // Sign up through Clerk's <SignUp/> component
  await page.goto("/sign_up");
  await page.getByLabel("Email address").fill(email);
  await page.getByLabel("Password", { exact: true }).fill(password);
  await page.getByRole("button", { name: "Continue", exact: true }).click();
  await expect(page.getByText(/verify your email/i)).toBeVisible();
  await page.keyboard.type("424242");
  await expect(page.getByTestId("current-user")).toBeVisible({ timeout: 20_000 });

  // Vote (server verified the Clerk JWT from the __session cookie)
  await page.goto("/");
  const card = firstCard(page);
  const up = await count(card, "up");
  await vote(page, card, "up");
  await expect(card.getByTestId("upvotes-count")).toHaveText(String(up + 1));

  // Sign out
  await waitForClerk(page);
  await page.getByTestId("sign-out").click();
  await expect(page.getByTestId("sign-in-link")).toBeVisible();

  // Sign in again (programmatic sign-in helper from @clerk/testing)
  await page.goto("/sign_in");
  await clerk.signIn({ page, signInParams: { strategy: "password", identifier: email, password } });
  await page.goto("/");
  await expect(page.getByTestId("current-user")).toBeVisible();
  await expect(firstCard(page).getByTestId("vote-up")).toHaveAttribute("aria-pressed", "true");
});
