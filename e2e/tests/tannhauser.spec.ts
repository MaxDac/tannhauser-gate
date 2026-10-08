import { test, expect, Page } from "@playwright/test";
import path from "node:path";

// Runs against a dev database prepared with `mix ecto.setup` (seeds the
// Tannhauser Gate story, its rooms, forum sections and the default admin).
const ADMIN_EMAIL = process.env.ADMIN_EMAIL || "admin@tannhauser.gate";
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || "change-me-tannhauser-2121";

const stamp = Date.now();
const email = `runner${stamp}@example.com`;
const password = "more-human-than-human";
const characterName = `Deckard ${stamp}`;
const message = `Have you ever retired a human by mistake? ${stamp}`;
const topicTitle = `Origami unicorns ${stamp}`;

test.describe.configure({ mode: "serial" });

async function connected(page: Page) {
  await expect(page.locator(".phx-connected").first()).toBeVisible();
}

async function logIn(page: Page, user: string, pass: string) {
  await page.goto("/users/log_in");
  await connected(page);
  await page.getByLabel("Email").fill(user);
  await page.getByLabel("Password").fill(pass);
  await page.getByRole("button", { name: /log in/i }).click();
  await expect(page).toHaveURL(/\/characters$/);
  await dismissFlashes(page);
}

async function dismissFlashes(page: Page) {
  const flashes = page.locator("#flash-group [role=alert]:visible");
  await expect(flashes.first()).toBeVisible();
  while ((await flashes.count()) > 0) {
    await flashes.first().click();
    await page.waitForTimeout(250);
  }
}

test("registers a new user", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveURL(/\/users\/log_in$/);
  await page.getByRole("link", { name: "Register" }).click();
  await connected(page);
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: "Create an account" }).click();
  await expect(page).toHaveURL(/\/characters$/);
  await expect(page.locator("#drawer")).toContainText("City Map");
});

test("plays: character, map, room chat, forum", async ({ page }) => {
  await logIn(page, email, password);

  // Character with avatar
  await page.getByRole("link", { name: /new character/i }).click();
  await connected(page);
  await page.getByLabel("Character name").fill(characterName);
  await page
    .locator("#character-form input[type=file]")
    .setInputFiles(path.join(__dirname, "..", "fixtures", "avatar.png"));
  await expect(page.locator("#character-form").getByRole("button", { name: "Remove image" })).toBeVisible();
  await page.getByLabel("Description").fill("Trench coat, tired eyes.");
  await page.getByLabel("Background").fill("A former Warden of Precinct 9.");
  await page.getByRole("button", { name: "Save character" }).click();
  await expect(page.locator("#character-sheet")).toContainText(characterName);
  await expect(page.locator("#character-sheet")).toContainText("A former Warden of Precinct 9.");
  await expect(page.locator("#character-sheet img[src^='/uploads/']")).toBeVisible();

  // Map -> room
  await page.locator("#drawer").getByRole("link", { name: "City Map" }).click();
  await expect(page.locator("#city-map")).toBeVisible();
  await page.locator("#city-map polygon[data-location-name=\"Ozu's Noodle Counter\"]").click({ force: true });
  await expect(page).toHaveURL(/\/rooms\/\d+$/);
  await expect(page.locator("h1")).toContainText("Ozu's Noodle Counter");

  // Chat message
  await page.getByLabel("Speak as").selectOption({ label: characterName });
  await page.getByLabel("Message").fill(message);
  await page.getByRole("button", { name: "Send" }).click();
  const posted = page.locator("#messages li.chat-message").filter({ hasText: message });
  await expect(posted).toBeVisible();
  await expect(posted.locator(".chat-name")).toContainText(characterName);
  await expect(posted.locator("time")).toBeVisible();
  await expect(posted.locator("img")).toBeVisible();

  // Forum
  await page.locator("#drawer").getByRole("link", { name: "Forum" }).click();
  await page.locator("#forum-sections").getByRole("link", { name: "Out of Character" }).click();
  await connected(page);
  await page.getByLabel("Title").fill(topicTitle);
  await page.getByLabel("First post").fill("Did you make this?");
  await page.getByRole("button", { name: "Create topic" }).click();
  await expect(page.locator("#forum-posts")).toContainText("Did you make this?");
  await page.getByLabel("Your post").fill("It's too bad she won't live.");
  await page.getByRole("button", { name: "Post reply" }).click();
  const posts = page.locator("#forum-posts .forum-post");
  await expect(posts).toHaveCount(2);
  await expect(posts.nth(1)).toContainText("It's too bad she won't live.");

  // Admin denied
  await page.goto("/admin");
  await expect(page).toHaveURL(/\/characters$/);
  await expect(page.getByText("Admins only.")).toBeVisible();
  await expect(page.locator("#drawer").getByRole("link", { name: "Admin" })).toHaveCount(0);
});

test("admin can reach the control room and read conversations", async ({ page }) => {
  await logIn(page, ADMIN_EMAIL, ADMIN_PASSWORD);
  await page.locator("#drawer").getByRole("link", { name: "Admin" }).click();
  await expect(page.locator("#admin-stats")).toBeVisible();

  await page.locator("#admin-nav").getByRole("link", { name: /rooms/i }).click();
  await page
    .locator("#admin-rooms tr")
    .filter({ hasText: "Ozu's Noodle Counter" })
    .getByRole("link", { name: "Read" })
    .click();
  await expect(page.locator("#admin-messages")).toContainText(message);

  await page.locator("#admin-nav").getByRole("link", { name: /users/i }).click();
  await expect(page.locator("#admin-users")).toContainText(email);
});
