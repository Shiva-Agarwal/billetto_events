import { defineConfig, devices } from "@playwright/test";
import * as dotenv from "dotenv";
import * as path from "path";

dotenv.config({ path: path.resolve(__dirname, "../.env") });

const PORT = Number(process.env.E2E_PORT || 3100);
const realClerk = process.env.E2E_REAL_CLERK === "1";

// Boots the Rails app (development env, fake Billetto data, jobs inline so vote counts update
// immediately). Clerk is the in-app fake unless E2E_REAL_CLERK=1 (then .env Clerk test keys are used).
const serverEnv = [
  "FAKE_BILLETTO=true",
  `FAKE_CLERK=${realClerk ? "false" : "true"}`,
  "ACTIVE_JOB_ADAPTER=inline",
  `CLERK_AUTHORIZED_PARTIES=http://localhost:${PORT}`
].join(" ");

export default defineConfig({
  testDir: "./tests",
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: [["list"], ["html", { open: "never" }]],
  globalSetup: realClerk ? "./global-setup.ts" : undefined,
  use: {
    baseURL: `http://localhost:${PORT}`,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure"
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: `cd .. && ${serverEnv} bin/rails db:prepare && ${serverEnv} bin/rails db:seed && ${serverEnv} bin/rails server -p ${PORT} -P tmp/pids/e2e_server.pid`,
    url: `http://localhost:${PORT}/up`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    stdout: "pipe"
  }
});
