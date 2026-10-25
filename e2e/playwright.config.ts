import { defineConfig, devices } from "@playwright/test";

const port = Number(process.env.E2E_PORT || 4000);

export default defineConfig({
  testDir: "./tests",
  // Screenshot tests have their own config: playwright.visual.config.ts
  testIgnore: ["visual/**"],
  timeout: 60_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["github"], ["list"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: `http://localhost:${port}`,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: [
    {
      command: "mix phx.server",
      cwd: "..",
      url: `http://localhost:${port}/users/log_in`,
      reuseExistingServer: !process.env.CI,
      timeout: 180_000,
      env: { MIX_ENV: "dev", NO_WATCHERS: "1", PORT: String(port) },
    },
    // The email flows (confirmation, password reset) are behind a feature
    // flag: email-auth.spec.ts runs against this second server, with the flag
    // on, and reads the emails from its dev mailbox.
    {
      command: "mix phx.server",
      cwd: "..",
      url: `http://localhost:${port + 1}/users/log_in`,
      reuseExistingServer: !process.env.CI,
      timeout: 180_000,
      env: { MIX_ENV: "dev", NO_WATCHERS: "1", PORT: String(port + 1), FEATURE_EMAIL_AUTH: "true" },
    },
  ],
});
