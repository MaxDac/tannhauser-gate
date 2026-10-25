import { test, expect, Browser, Page } from "@playwright/test";
import { connected, dismissFlashes, logInAsAdmin, newPlayer } from "./helpers";

// A user becomes a GM, requests their own GDR (rejected first, then
// approved), publishes it, writes its guide, zones and periodic actions, and a
// player reads the guide.
test.describe.configure({ mode: "serial" });

async function adminPage(browser: Browser) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await context.newPage();
  await logInAsAdmin(page);
  return page;
}

async function reviewRequest(admin: Page, gdrName: string, decision: "Approve" | "Reject") {
  await admin.goto("/admin/requests");
  await connected(admin);
  const row = admin.locator("#admin-requests tr").filter({ hasText: gdrName });
  await row.getByRole("link", { name: decision, exact: true }).click();
  await expect(row).toContainText(decision === "Approve" ? "approved" : "rejected");
  await expect(row.getByRole("link", { name: decision, exact: true })).toHaveCount(0);
}

async function requestGdr(gm: Page, gdrName: string) {
  await gm.goto("/gdrs/request");
  await connected(gm);
  await gm.locator("#gdr-request-form").getByLabel("GDR name").fill(gdrName);
  await gm.locator("#gdr-request-form").getByLabel("Pitch").fill("Neon rain over a drowned city.");
  await gm.locator("#gdr-request-form").getByRole("button", { name: "Request my GDR" }).click();
  await expect(gm.locator("#request-pending")).toContainText(gdrName);
}

test("a GM requests, gets and builds their own GDR", async ({ browser }) => {
  test.setTimeout(240_000);
  const stamp = Date.now();
  const rejectedName = `Off-world ${stamp}`;
  const gdrName = `Drowned City ${stamp}`;
  const { page: gm, account } = await newPlayer(browser, "gm");
  const admin = await adminPage(browser);

  // Only GMs can request a GDR
  await gm.goto("/gdrs/request");
  await connected(gm);
  await expect(gm.locator("#not-gm")).toBeVisible();
  await expect(gm.locator("#gdr-request-form")).toHaveCount(0);

  await admin.goto("/admin/users");
  await connected(admin);
  const userRow = admin.locator("#admin-users tr").filter({ hasText: account.username });
  await userRow.getByRole("link", { name: "Make GM" }).click();
  await expect(userRow).toContainText("GM");
  await expect(userRow.getByRole("link", { name: "Revoke GM" })).toBeVisible();

  // A rejected request can be followed by a new one
  await requestGdr(gm, rejectedName);
  await reviewRequest(admin, rejectedName, "Reject");
  await gm.reload();
  await connected(gm);
  await expect(gm.locator("#request-rejected")).toContainText(rejectedName);

  await requestGdr(gm, gdrName);
  await reviewRequest(admin, gdrName, "Approve");
  await gm.goto("/gdrs");
  await connected(gm);
  await gm.locator("#my-gdr-link").click();
  await expect(gm.locator("#owned-gdr")).toContainText(gdrName);
  await expect(gm.locator("#owned-gdr")).toContainText("draft");
  await gm.locator("#open-dashboard").click();
  await expect(gm).toHaveURL(/\/g\/\d+\/gm$/);
  const gdr = new URL(gm.url()).pathname.replace(/\/gm$/, "");
  await connected(gm);

  // Publish it
  await gm.locator("#general-form").getByLabel("Status").selectOption("published");
  await gm.locator("#general-form").getByRole("button", { name: "Save", exact: true }).click();
  await expect(gm.getByText("GDR updated")).toBeVisible();
  await dismissFlashes(gm);

  // Guide: a section and a page
  await gm.locator("#gm-tab-guide").click();
  await expect(gm).toHaveURL(new RegExp(`${gdr}/gm/guide$`));
  await connected(gm);
  await gm.locator("#section-form").getByLabel("Title").fill("The basics");
  await gm.locator("#save-section").click();
  const section = gm.locator("#guide-sections [id^='guide-section-']").filter({ hasText: "The basics" });
  await expect(section).toBeVisible();
  await section.locator("[id^='new-page-']").click();
  await gm.locator("#page-form").getByLabel("Title", { exact: true }).fill("Welcome to the city");
  await gm.locator("#page-form").getByLabel("Content (Markdown)").fill("It **always** rains here.");
  await expect(gm.locator("#page-preview strong")).toHaveText("always");
  await gm.locator("#save-page").click();
  await expect(gm.locator("[id^='guide-page-row-']").filter({ hasText: "Welcome to the city" })).toBeVisible();

  // Zones: a property and a zone using it
  await gm.locator("#gm-tab-zones").click();
  await expect(gm).toHaveURL(new RegExp(`${gdr}/gm/zones$`));
  await connected(gm);
  await gm.locator("#property-form").getByLabel("Name").fill("Danger");
  await gm.locator("#save-property").click();
  await expect(gm.locator("#zone-properties-list")).toContainText("Danger");
  await gm.locator("#zone-form").getByLabel("Name").fill("The Docks");
  await gm.locator("#zone-form").getByLabel("Description").fill("Rusting cranes and smugglers.");
  await gm.locator("#save-zone").click();
  await expect(gm.locator("[id^='zone-']").filter({ hasText: "The Docks" }).first()).toBeVisible();
  await expect(gm.locator("#zones-empty")).toHaveCount(0);

  // Periodic actions: rolled against the zone danger
  await gm.locator("#gm-tab-actions").click();
  await expect(gm).toHaveURL(new RegExp(`${gdr}/gm/actions$`));
  await connected(gm);
  const actionForm = gm.locator("#periodic-action-form");
  await actionForm.getByLabel("Name").fill("Scavenge");
  await actionForm.locator("#action_zone_property").selectOption({ label: "Danger" });
  await actionForm.getByLabel("Default").fill("10");
  await gm.locator("#save-periodic-action").click();
  await expect(gm.locator("#periodic-actions [id^='periodic-action-']").filter({ hasText: "Scavenge" })).toBeVisible();

  // A player finds the published GDR and reads its guide
  const { page: player } = await newPlayer(browser, "reader");
  await player.goto("/gdrs");
  await connected(player);
  await player.locator("#gdrs article", { hasText: gdrName }).getByRole("link", { name: /Enter/ }).click();
  await expect(player).toHaveURL(new RegExp(`${gdr}$`));
  await player.locator("#nav-guide").click();
  await expect(player).toHaveURL(new RegExp(`${gdr}/guide`));
  await expect(player.locator("#guide-toc")).toContainText("The basics");
  await expect(player.locator("#guide-page-title")).toHaveText("Welcome to the city");
  await expect(player.locator("#guide-page-body strong")).toHaveText("always");
  await expect(player.locator("#guide-edit-link")).toHaveCount(0);
});
