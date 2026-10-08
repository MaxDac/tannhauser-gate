import { test, expect, Page } from "@playwright/test";

// Screenshot tests. The database must hold only the deterministic fixtures
// from priv/repo/visual_seeds.exs (see playwright.visual.config.ts).
const ADMIN = { email: "admin@tannhauser.gate", password: "change-me-tannhauser-2121" };
const PLAYER = { email: "player@tannhauser.gate", password: "more-human-than-human" };

// Hide things that are never stable between runs: the LiveView progress bar,
// flash toasts, the text caret and any CSS animation or transition.
const STABILISE_CSS = `
  #flash-group, body > canvas { display: none !important; }
  *, *::before, *::after {
    animation: none !important;
    transition: none !important;
    caret-color: transparent !important;
  }
`;

async function settle(page: Page) {
  await expect(page.locator(".phx-connected").first()).toBeVisible();
  await page.addStyleTag({ content: STABILISE_CSS });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForLoadState("networkidle");
  await page.evaluate(() =>
    Promise.all(
      Array.from(document.images)
        .filter((img) => !img.complete)
        .map((img) => new Promise((resolve) => img.addEventListener("load", resolve, { once: true }))),
    ),
  );
}

async function snap(page: Page, name: string) {
  await settle(page);
  await expect(page).toHaveScreenshot(`${name}.png`, { fullPage: true });
}

async function visit(page: Page, path: string, name: string) {
  await page.goto(path);
  await snap(page, name);
}

async function logIn(page: Page, user: { email: string; password: string }) {
  await page.goto("/users/log_in");
  await expect(page.locator(".phx-connected").first()).toBeVisible();
  await page.getByLabel("Email").fill(user.email);
  await page.getByLabel("Password").fill(user.password);
  await page.getByRole("button", { name: /log in/i }).click();
  await expect(page).toHaveURL(/\/characters$/);
}

test.describe("guest", () => {
  test("login", async ({ page }) => {
    await visit(page, "/users/log_in", "login");
  });

  test("register", async ({ page }) => {
    await visit(page, "/users/register", "register");
  });

  test("login keyboard focus", async ({ page }) => {
    await page.goto("/users/log_in");
    await settle(page);
    await page.getByRole("link", { name: "Register", exact: true }).focus();
    await page.keyboard.press("Tab");
    await expect(page.getByLabel("Email", { exact: true })).toBeFocused();
    await snap(page, "login-focus");
  });

  test("mobile login", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await visit(page, "/users/log_in", "login-mobile");
  });
});

test.describe("player", () => {
  test.beforeEach(async ({ page }) => {
    await logIn(page, PLAYER);
  });

  test("characters (drawer layout)", async ({ page }) => {
    await snap(page, "characters");
  });

  test("character sheet", async ({ page }) => {
    await page.locator("#characters").getByRole("link", { name: /Rick Deckard/ }).first().click();
    await expect(page.locator("#character-sheet")).toBeVisible();
    await snap(page, "character-sheet");
  });

  test("new character form", async ({ page }) => {
    await visit(page, "/characters/new", "character-new");
  });

  test("mobile character form", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await visit(page, "/characters/new", "character-new-mobile");
  });

  test("map", async ({ page }) => {
    await page.goto("/map");
    await expect(page.locator("#city-map")).toBeVisible();
    await snap(page, "map");
  });

  test("room chat", async ({ page }) => {
    await page.goto("/map");
    await settle(page);
    await page
      .locator("#city-map polygon[data-location-name=\"Ozu's Noodle Counter\"]")
      .click({ force: true });
    await expect(page).toHaveURL(/\/rooms\/\d+$/);
    await expect(page.locator("#messages li.chat-message")).toHaveCount(3);
    await snap(page, "room-chat");
  });

  test("forum", async ({ page }) => {
    await visit(page, "/forum", "forum-index");
    await page.locator("#forum-sections").getByRole("link", { name: "Out of Character" }).click();
    await expect(page.locator("#forum-topics")).toContainText("Origami unicorns");
    await snap(page, "forum-section");
    await page.locator("#forum-topics").getByRole("link", { name: "Origami unicorns" }).click();
    await expect(page.locator("#forum-posts .forum-post")).toHaveCount(2);
    await snap(page, "forum-topic");
  });
});

test.describe("admin", () => {
  test.beforeEach(async ({ page }) => {
    await logIn(page, ADMIN);
  });

  test("dashboard", async ({ page }) => {
    await page.goto("/admin");
    await expect(page.locator("#admin-stats")).toBeVisible();
    await snap(page, "admin-dashboard");
  });

  test("stories", async ({ page }) => {
    await visit(page, "/admin/stories", "admin-stories");
  });

  test("story form", async ({ page }) => {
    await visit(page, "/admin/stories/new", "admin-story-form");
  });

  test("story artwork validation", async ({ page }) => {
    await page.goto("/admin/stories/new");
    await settle(page);
    await page.getByLabel("Name", { exact: true }).fill("Invalid artwork");
    await page.locator("#story_map_svg").fill("<script>alert(1)</script>");
    await page.getByRole("button", { name: "Save story" }).click();
    await expect(page.locator("#story_map_svg-errors")).toBeVisible();
    await page.locator("#story_map_svg").focus();
    await snap(page, "admin-story-error");
  });

  test("characters", async ({ page }) => {
    await visit(page, "/admin/characters", "admin-characters");
  });

  test("rooms and conversation", async ({ page }) => {
    await visit(page, "/admin/rooms", "admin-rooms");
    await page
      .locator("#admin-rooms tr")
      .filter({ hasText: "Ozu's Noodle Counter" })
      .getByRole("link", { name: "Read" })
      .click();
    await expect(page.locator("#admin-messages")).toContainText("Have you ever retired a human");
    await snap(page, "admin-room-conversation");
  });

  test("users", async ({ page }) => {
    await visit(page, "/admin/users", "admin-users");
  });

  test("forum sections", async ({ page }) => {
    await visit(page, "/admin/forum", "admin-forum");
  });
});
