import { test, expect, Browser, Page } from "@playwright/test";
import {
  connected,
  createApprovedCharacter,
  createCharacter,
  dismissFlashes,
  gdrPath,
  logInAsAdmin,
  newPlayer,
} from "./helpers";

// Two players of the seeded GDR: jobs, a GM balance adjustment, a bank
// transfer, a letter, and editing then deleting a character.
test.describe.configure({ mode: "serial" });

const stamp = Date.now();
const rachael = `Rachael ${stamp}`;
const roy = `Roy ${stamp}`;
const subject = `Origami ${stamp}`;

let gdr: string;
let first: { page: Page };
let second: { page: Page };

async function gmAdjust(browser: Browser, character: string, amount: number) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const admin = await context.newPage();
  await logInAsAdmin(admin);
  await admin.goto(`${gdr}/gm/balances`);
  await connected(admin);
  const row = admin.locator("[id^='balance-']").filter({ hasText: character });
  await row.getByLabel(`Amount for ${character}`).fill(String(amount));
  await row.getByLabel(`Note for ${character}`).fill("Starting funds");
  await row.getByRole("button", { name: "Apply" }).click();
  await expect(admin.getByText("Balance updated")).toBeVisible();
  await expect(row).toContainText(`· ${amount}`);
  await context.close();
}

test.beforeAll(async ({ browser }) => {
  test.setTimeout(300_000);
  first = await newPlayer(browser, "rachael");
  second = await newPlayer(browser, "roy");
  gdr = await gdrPath(first.page);
  await createApprovedCharacter(browser, first.page, gdr, rachael);
  await createApprovedCharacter(browser, second.page, gdr, roy);
});

test("takes and quits a job", async () => {
  const page = first.page;
  await page.goto(`${gdr}/jobs`);
  await connected(page);
  const job = page.locator("[id^='job-']").first();
  const jobName = (await job.locator("p").first().textContent())!.trim();
  await job.getByRole("button", { name: "Take this job" }).click();
  await expect(page.getByText("Job taken.")).toBeVisible();
  await expect(job.getByText("Current job")).toBeVisible();
  await expect(page.locator("#quit-job")).toBeVisible();

  await page.goto(`${gdr}/bank`);
  await connected(page);
  await expect(page.locator("#bank-character")).toHaveText(rachael);
  await expect(page.locator("#bank-job")).toContainText(jobName);

  await page.goto(`${gdr}/jobs`);
  await connected(page);
  await page.locator("#quit-job").click();
  await expect(page.getByText("You quit your job.")).toBeVisible();
  await expect(page.locator("#quit-job")).toHaveCount(0);
});

test("sends money to another character", async ({ browser }) => {
  const page = first.page;
  await page.goto(`${gdr}/bank`);
  await connected(page);
  await expect(page.locator("#balance")).toHaveText(/^\s*0\b/);

  // Without funds the transfer is refused
  const form = page.locator("#transfer-form");
  await form.getByLabel("Send to").selectOption({ label: roy });
  await form.getByLabel("Amount").fill("20");
  await form.getByRole("button", { name: "Send money" }).click();
  await expect(page.getByText("Not enough funds.")).toBeVisible();
  await expect(page.locator("#no-transactions")).toBeVisible();

  await gmAdjust(browser, rachael, 50);
  await page.reload();
  await connected(page);
  await expect(page.locator("#balance")).toHaveText(/^\s*50\b/);
  await form.getByLabel("Send to").selectOption({ label: roy });
  await form.getByLabel("Amount").fill("20");
  await form.getByLabel("Note").fill("For the unicorn");
  await form.getByRole("button", { name: "Send money" }).click();
  await expect(page.getByText("Transfer sent.")).toBeVisible();
  await expect(page.locator("#balance")).toHaveText(/^\s*30\b/);
  await expect(page.locator("#transactions")).toContainText(`To ${roy}`);

  const other = second.page;
  await other.goto(`${gdr}/bank`);
  await connected(other);
  await expect(other.locator("#balance")).toHaveText(/^\s*20\b/);
  await expect(other.locator("#transactions")).toContainText(`From ${rachael}`);
  await expect(other.locator("#transactions")).toContainText("For the unicorn");
});

test("sends a letter that the recipient reads", async () => {
  const page = first.page;
  await page.goto(`${gdr}/mail`);
  await connected(page);
  await page.locator("#compose-mail").click();
  await expect(page).toHaveURL(new RegExp(`${gdr}/mail/new$`));
  const form = page.locator("#mail-form");
  await form.getByLabel("From").selectOption({ label: rachael });
  await form.getByLabel("To").selectOption({ label: roy });
  await form.getByLabel("Subject").fill(subject);
  await form.getByLabel("Message").fill("I'm not in the business. I am the business.");
  await page.locator("#send-mail").click();
  await expect(page.getByText("Message sent")).toBeVisible();
  await page.locator("#mail-tab-sent").click();
  await expect(page.locator("#mail-sent")).toContainText(subject);

  const other = second.page;
  await other.goto(`${gdr}/mail`);
  await connected(other);
  const letter = other.locator("#mail-inbox [id^='mail-message-']").filter({ hasText: subject });
  await letter.click();
  await expect(other.locator("#mail-subject")).toHaveText(subject);
  await expect(other.locator("#mail-from")).toContainText(rachael);
  await expect(other.locator("#mail-to")).toContainText(roy);
  await expect(other.locator("#mail-body")).toContainText("I am the business.");
  await expect(other.locator("#reply-message")).toBeVisible();

  other.once("dialog", (dialog) => dialog.accept());
  await other.locator("#delete-message").click();
  await expect(other.getByText("Message deleted")).toBeVisible();
  await expect(other.locator("#mail-inbox")).not.toContainText(subject);
});

test("edits and deletes a character", async () => {
  const page = second.page;
  const name = `Pris ${stamp}`;
  const sheet = await createCharacter(page, gdr, name);
  await dismissFlashes(page);

  await page.locator("#edit-character").click();
  await expect(page).toHaveURL(new RegExp(`${sheet}/edit$`));
  await connected(page);
  await page.getByLabel("Background").fill("A basic pleasure model.");
  await page.locator("#save-character").click();
  await expect(page).toHaveURL(new RegExp(`${sheet}$`));
  await expect(page.locator("#character-sheet")).toContainText("A basic pleasure model.");
  await dismissFlashes(page);

  page.once("dialog", (dialog) => dialog.accept());
  await page.locator("#delete-character").click();
  await expect(page).toHaveURL(new RegExp(`${gdr}/characters$`));
  await expect(page.getByText("Character deleted")).toBeVisible();
  await expect(page.locator("main")).not.toContainText(name);
});
