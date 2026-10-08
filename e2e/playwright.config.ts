import { defineConfig, devices } from "@playwright/test";

const port = Number(process.env.E2E_PORT || 4000);

export default defineConfig({
  testDir: "./tests",
  timeout: 60_000,
  expect: { timeout: 10_000 },
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
  webServer: {
    command: "mix phx.server",
    cwd: "..",
    url: `http://localhost:${port}/users/log_in`,
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
    env: { MIX_ENV: "dev", NO_WATCHERS: "1", PORT: String(port) },
  },
});
