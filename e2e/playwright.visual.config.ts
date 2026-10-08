import { defineConfig, devices } from "@playwright/test";

// Visual regression (screenshot) tests.
//
// Baselines are Linux-only and must be generated inside the pinned Playwright
// container (same image as CI) so fonts and rendering match. See the
// "Screenshot tests" section of the README.
const port = Number(process.env.VISUAL_PORT || 4002);
const database = process.env.VISUAL_DATABASE || "tannhauser_gate_visual";

export default defineConfig({
  testDir: "./tests/visual",
  outputDir: "./test-results-visual",
  snapshotPathTemplate: "{testDir}/__screenshots__/{testFilePath}/{arg}{ext}",
  timeout: 60_000,
  fullyParallel: false,
  workers: 1,
  retries: 0,
  forbidOnly: !!process.env.CI,
  reporter: process.env.CI
    ? [["github"], ["list"], ["html", { open: "never", outputFolder: "playwright-report-visual" }]]
    : [["list"], ["html", { open: "never", outputFolder: "playwright-report-visual" }]],
  expect: {
    timeout: 10_000,
    toHaveScreenshot: {
      animations: "disabled",
      caret: "hide",
      scale: "css",
      maxDiffPixelRatio: 0.01,
    },
  },
  use: {
    ...devices["Desktop Chrome"],
    baseURL: `http://localhost:${port}`,
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 1,
    locale: "en-GB",
    timezoneId: "UTC",
    colorScheme: "dark",
    reducedMotion: "reduce",
    trace: "retain-on-failure",
  },
  projects: [{ name: "visual" }],
  webServer: {
    command: "mix phx.server",
    cwd: "..",
    url: `http://localhost:${port}/users/log_in`,
    reuseExistingServer: false,
    timeout: 180_000,
    env: { MIX_ENV: "dev", NO_WATCHERS: "1", PORT: String(port), DEV_DATABASE: database },
  },
});
