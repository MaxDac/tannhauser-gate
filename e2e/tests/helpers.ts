import { expect, Browser, Page } from "@playwright/test";
import path from "node:path";

// The specs run against a dev database prepared with `mix setup` (seeds the
// Tannhauser Gate, Neon Republic, Arkham Adrift and Toronto by Night GDRs,
// their rooms, jobs, forum sections, GM owners and the default admin). The
// database persists across runs, so every created record gets a unique suffix.
//
// The seeded admin must change its initial password at the first access: the
// suite changes it once to ADMIN_E2E_PASSWORD and logs in with that from then
// on, so it also works on a database where an earlier run already changed it.
export const ADMIN_USERNAME = process.env.ADMIN_USERNAME || "admin";
export const ADMIN_INITIAL_PASSWORD = process.env.ADMIN_PASSWORD || "change-me-tannhauser-2121";
export const ADMIN_PASSWORD = process.env.ADMIN_E2E_PASSWORD || `${ADMIN_INITIAL_PASSWORD}-e2e`;
export const SEEDED_GDR = "Tannhauser Gate";
export const PASSWORD = "more-human-than-human";

export const port = Number(process.env.E2E_PORT || 4000);
// A second server runs with FEATURE_EMAIL_AUTH=true (see playwright.config.ts).
export const emailPort = port + 1;

let counter = 0;
export function unique(prefix: string) {
  counter += 1;
  return `${prefix}${Date.now()}${counter}`;
}

export async function connected(page: Page) {
  // The LiveView socket can take a while to connect on a busy machine.
  await expect(page.locator(".phx-connected").first()).toBeVisible({ timeout: 30_000 });
}

export async function dismissFlashes(page: Page) {
  const flashes = page.locator("#flash-group [role=alert]:visible");
  await expect(flashes.first()).toBeVisible();
  while ((await flashes.count()) > 0) {
    await flashes.first().click();
    await page.waitForTimeout(250);
  }
}

export async function logIn(page: Page, user: string, pass: string) {
  await page.goto("/users/log_in");
  await connected(page);
  await page.getByLabel("Username").fill(user);
  await page.getByLabel("Password").fill(pass);
  await page.getByRole("button", { name: /log in/i }).click();
  await expect(page).toHaveURL(/\/gdrs$/, { timeout: 30_000 });
  await dismissFlashes(page);
}

async function submitLogIn(page: Page, user: string, pass: string) {
  await page.goto("/users/log_in");
  await connected(page);
  await page.getByLabel("Username").fill(user);
  await page.getByLabel("Password").fill(pass);
  await page.getByRole("button", { name: /log in/i }).click();
  // Every outcome (welcome, wrong password, forced change) shows a flash.
  await expect(page.locator("#flash-group [role=alert]:visible").first()).toBeVisible({ timeout: 30_000 });
}

async function changeInitialAdminPassword(page: Page) {
  await expect(page).toHaveURL(/\/users\/settings$/);
  await connected(page);
  await expect(page.locator("#must-change-password-notice")).toBeVisible();
  const form = page.locator("#password_form");
  await form.getByLabel("New password", { exact: true }).fill(ADMIN_PASSWORD);
  await form.getByLabel("Confirm new password").fill(ADMIN_PASSWORD);
  await form.getByLabel("Current password").fill(ADMIN_INITIAL_PASSWORD);
  await form.getByRole("button", { name: "Change Password" }).click();
  await expect(page.locator("#flash-group")).toContainText("Password updated successfully!");
  await expect(page.locator("#must-change-password-notice")).toHaveCount(0);
}

// Logs the seeded admin in and lands on /gdrs, changing the initial password
// first when needed.
export async function logInAsAdmin(page: Page) {
  await submitLogIn(page, ADMIN_USERNAME, ADMIN_PASSWORD);

  if (/\/users\/log_in$/.test(page.url())) {
    await submitLogIn(page, ADMIN_USERNAME, ADMIN_INITIAL_PASSWORD);
    await changeInitialAdminPassword(page);
  }

  await page.goto("/gdrs");
  await expect(page).toHaveURL(/\/gdrs$/);
  await connected(page);
}

export interface Account {
  username: string;
  email: string;
  password: string;
}

export function newAccount(prefix = "runner"): Account {
  const username = unique(prefix);
  return { username, email: `${username}@example.com`, password: PASSWORD };
}

export async function register(page: Page, account: Account) {
  await page.goto("/users/register");
  await connected(page);
  await page.getByLabel("Username").fill(account.username);
  await page.getByLabel("Email").fill(account.email);
  await page.getByLabel("Password").fill(account.password);
  await page.getByLabel("I accept the terms and disclaimer").check();
  await page.getByRole("button", { name: "Create an account" }).click();
  await expect(page).toHaveURL(/\/gdrs$/, { timeout: 30_000 });
}

// A page logged in as a fresh account, in its own browser context.
export async function newPlayer(browser: Browser, prefix = "runner") {
  const context = await browser.newContext();
  const page = await context.newPage();
  const account = newAccount(prefix);
  await register(page, account);
  return { context, page, account };
}

// Resolves the `/g/<id>` path of a GDR from its card in the directory, so the
// specs do not depend on database ids.
export async function gdrPath(page: Page, name = SEEDED_GDR) {
  await page.goto("/gdrs");
  await connected(page);
  const href = await page
    .locator("#gdrs article", { hasText: name })
    .first()
    .getByRole("link", { name: /Enter/ })
    .getAttribute("href");
  expect(href).toMatch(/^\/g\/\d+$/);
  return href!;
}

// Creates a character in the seeded GDR through the creation wizard
// (identity, origins, one step per sheet category, review) and returns the
// path of its sheet.
export async function createCharacter(page: Page, gdr: string, name: string, withAvatar = false) {
  await page.goto(`${gdr}/characters/new`);
  await connected(page);
  await page.getByLabel("Character name").fill(name);
  if (withAvatar) {
    await page
      .locator("#character-form input[type=file]")
      .setInputFiles(path.join(__dirname, "..", "fixtures", "avatar.png"));
    await expect(page.locator("#character-form").getByRole("button", { name: "Remove image" })).toBeVisible();
  }
  await page.getByLabel("Description").fill("Trench coat, tired eyes.");
  await page.getByLabel("Background").fill("A former Warden of Precinct 9.");
  await page.locator("#wizard-next").click();
  await expect(page.locator("#origins-step")).toBeVisible();
  await page.locator("#origins-step label").first().click();
  for (const step of ["attribute", "skill", "power"]) {
    await page.locator("#wizard-next").click();
    await expect(page.locator(`#sheet-${step}`)).toBeVisible();
  }
  await page.locator("#wizard-next").click();
  await expect(page.locator("#review-step")).toContainText(name);
  await page.locator("#save-character").click();
  await expect(page.locator("#character-sheet")).toContainText(name);
  await expect(page).toHaveURL(/\/g\/\d+\/characters\/\d+$/);
  return new URL(page.url()).pathname;
}

// A master (here the platform admin) approves the character from the master
// character dashboard, so it can play.
export async function approveCharacter(browser: Browser, gdr: string, name: string) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const admin = await context.newPage();
  await logInAsAdmin(admin);
  await admin.goto(`${gdr}/master/characters`);
  await connected(admin);
  const card = admin.locator("#approval-queue li").filter({ hasText: name });
  await card.getByRole("button", { name: "Approve" }).click();
  await expect(admin.locator("#approval-queue li").filter({ hasText: name })).toHaveCount(0);
  await context.close();
}

// Creates a character, submits it and has it approved.
export async function createApprovedCharacter(browser: Browser, page: Page, gdr: string, name: string) {
  const sheet = await createCharacter(page, gdr, name);
  await dismissFlashes(page);
  await page.locator("#submit-for-approval").click();
  await expect(page.locator("#character-approval-status")).toContainText("Awaiting approval");
  await dismissFlashes(page);
  await approveCharacter(browser, gdr, name);
  return sheet;
}
