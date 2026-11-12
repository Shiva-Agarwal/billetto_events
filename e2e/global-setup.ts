import { clerkSetup } from "@clerk/testing/playwright";

// Obtains a Clerk Testing Token (bypasses bot protection for automated sign-ups/sign-ins).
// Requires CLERK_PUBLISHABLE_KEY and CLERK_SECRET_KEY of a *development* Clerk instance.
export default async function globalSetup() {
  await clerkSetup();
}
