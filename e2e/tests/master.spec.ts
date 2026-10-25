import { test, expect, Page } from "@playwright/test";
import { connected, dismissFlashes, gdrPath, logInAsAdmin } from "./helpers";

// The master tools of the seeded GDR, used by the platform admin (who owns
// it): NPC creation, speaking as the NPC, chat log, moderation and zone events.
test.describe.configure({ mode: "serial" });

const stamp = Date.now();
const npc = `Gaff ${stamp}`;
const line = `You've done a man's job, sir. ${stamp}`;
const eventTitle = `Blackout ${stamp}`;
const ROOM = "Ozu's Noodle Counter";

let page: Page;
let gdr: string;

test.beforeAll(async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  page = await context.newPage();
  await logInAsAdmin(page);
  gdr = await gdrPath(page);
});

test.afterAll(async () => {
  await page.context().close();
});

test("the master dashboard links every tool", async () => {
  await page.goto(`${gdr}/master`);
  await connected(page);
  for (const tool of ["characters", "npcs", "moderation", "chat-log", "zones", "actions"]) {
    await expect(page.locator(`#master-${tool}`)).toBeVisible();
  }
  await page.locator("#master-npcs").click();
  await expect(page).toHaveURL(new RegExp(`${gdr}/master/npcs/new$`));
});

test("creates an NPC and speaks as it in a room", async () => {
  await page.goto(`${gdr}/master/npcs/new`);
  await connected(page);
  await page.getByLabel("Character name").fill(npc);
  await page.getByLabel("Description").fill("Origami and a cane.");
  await page.locator("#save-character").click();
  await expect(page.getByText("NPC created")).toBeVisible();
  await expect(page).toHaveURL(/\/g\/\d+\/characters\/\d+$/);
  await expect(page.locator("#character-sheet")).toContainText(npc);
  await dismissFlashes(page);

  await page.goto(`${gdr}/map`);
  await connected(page);
  await page.locator(`#city-map polygon[data-location-name="${ROOM}"]`).click({ force: true });
  await expect(page).toHaveURL(/\/g\/\d+\/rooms\/\d+$/);
  await connected(page);
  const speaker = page.getByLabel("Speak as");
  const option = speaker.locator("option", { hasText: npc });
  await speaker.selectOption((await option.getAttribute("value"))!);
  await page.getByRole("textbox", { name: "Message" }).fill(line);
  await page.getByRole("button", { name: "Send", exact: true }).click();
  const posted = page.locator("#messages li.chat-message").filter({ hasText: line });
  await expect(posted).toBeVisible();
  await expect(posted.locator(".chat-name")).toContainText(npc);
});

test("finds the message in the chat log", async () => {
  await page.goto(`${gdr}/master/chat-log`);
  await connected(page);
  await page.locator("#chat-log-filters").getByLabel("Room").selectOption({ label: ROOM });
  await page.locator("#chat-log-search").click();
  await expect(page.locator("#chat-log")).toContainText(line);
  await expect(page.locator("#chat-log-count")).not.toHaveText("0 entries");
});

test("deletes the message from the moderation queue", async () => {
  await page.goto(`${gdr}/master/moderation`);
  await connected(page);
  const entry = page.locator("#moderation-messages li").filter({ hasText: line });
  await expect(entry).toContainText(npc);
  await expect(entry).toContainText(ROOM);
  page.once("dialog", (dialog) => dialog.accept());
  await entry.getByRole("button", { name: "Delete message" }).click();
  await expect(page.getByText("Message deleted")).toBeVisible();
  await expect(page.locator("#moderation-messages li").filter({ hasText: line })).toHaveCount(0);
});

test("posts and deletes a zone event", async () => {
  await page.goto(`${gdr}/master/zones`);
  await connected(page);
  const form = page.locator("#zone-event-form");
  await page.locator("#zone-event-zone").selectOption({ label: "Undercity" });
  await form.getByLabel("Date", { exact: true }).fill("2049-10-06");
  await form.getByLabel("Title").fill(eventTitle);
  await form.getByLabel("What happened (Markdown)").fill("The grid went **dark**.");
  await page.locator("#post-zone-event").click();
  await expect(page.getByText("Zone event posted.")).toBeVisible();
  const event = page.locator("#zone-events article").filter({ hasText: eventTitle });
  await expect(event).toContainText("Undercity");
  await expect(event.locator("strong")).toHaveText("dark");

  page.once("dialog", (dialog) => dialog.accept());
  await event.getByTitle("Delete").click();
  await expect(page.getByText("Zone event deleted.")).toBeVisible();
  await expect(page.locator("#zone-events article").filter({ hasText: eventTitle })).toHaveCount(0);
});
