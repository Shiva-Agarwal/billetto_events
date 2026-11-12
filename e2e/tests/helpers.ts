import { expect, Page, Locator } from "@playwright/test";

export const firstCard = (page: Page): Locator => page.locator("li.event-card").first();

export async function waitForClerk(page: Page) {
  await expect(page.locator("html")).toHaveAttribute("data-clerk-loaded", "true");
}

export async function vote(page: Page, card: Locator, direction: "up" | "down") {
  await waitForClerk(page);
  await card.getByTestId(`vote-${direction}`).click();
  await expect(page.getByTestId("flash")).toBeVisible();
}

export async function count(card: Locator, direction: "up" | "down") {
  return Number(await card.getByTestId(`${direction}votes-count`).innerText());
}
