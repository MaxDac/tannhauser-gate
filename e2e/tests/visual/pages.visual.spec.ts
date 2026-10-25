import { test, expect, Page } from "@playwright/test";

// Screenshot tests. The database must hold only the deterministic fixtures
// from priv/repo/visual_seeds.exs (see playwright.visual.config.ts).
const ADMIN = { username: "admin", password: "change-me-tannhauser-2121" };
const GDR = "/g/1";
const PLAYER = { username: "player", password: "more-human-than-human" };

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

async function logIn(page: Page, user: { username: string; password: string }) {
  await page.goto("/users/log_in");
  await expect(page.locator(".phx-connected").first()).toBeVisible();
  await page.getByLabel("Username").fill(user.username);
  await page.getByLabel("Password").fill(user.password);
  await page.getByRole("button", { name: /log in/i }).click();
  await expect(page).toHaveURL(/\/gdrs$/);
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
    await expect(page.getByLabel("Username", { exact: true })).toBeFocused();
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

  test("GDR picker", async ({ page }) => {
    await expect(page.locator("#gdrs")).toBeVisible();
    await snap(page, "gdrs");
  });

  test("characters (drawer layout)", async ({ page }) => {
    await page.goto(`${GDR}/characters`);
    await expect(page.locator("#characters")).toBeVisible();
    await snap(page, "characters");
  });

  test("character sheet", async ({ page }) => {
    await page.goto(`${GDR}/characters`);
    await page.locator("#characters").getByRole("link", { name: /Rick Deckard/ }).first().click();
    await expect(page.locator("#character-sheet")).toBeVisible();
    await snap(page, "character-sheet");
  });

  test("new character form", async ({ page }) => {
    await visit(page, `${GDR}/characters/new`, "character-new");
  });

  test("mobile character form", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await visit(page, `${GDR}/characters/new`, "character-new-mobile");
  });

  test("map", async ({ page }) => {
    await page.goto(`${GDR}/map`);
    await expect(page.locator("#city-map")).toBeVisible();
    await snap(page, "map");
  });

  test("room chat", async ({ page }) => {
    await page.goto(`${GDR}/map`);
    await settle(page);
    await page
      .locator("#city-map polygon[data-location-name=\"Ozu's Noodle Counter\"]")
      .click({ force: true });
    await expect(page).toHaveURL(/\/g\/\d+\/rooms\/\d+$/);
    await expect(page.locator("#messages li.chat-message")).toHaveCount(3);
    await snap(page, "room-chat");
  });

  test("forum", async ({ page }) => {
    await visit(page, `${GDR}/forum`, "forum-index");
    await page.locator("#forum-sections").getByRole("link", { name: "Out of Character" }).click();
    await expect(page.locator("#forum-topics")).toContainText("Origami unicorns");
    await snap(page, "forum-section");
    await page.locator("#forum-topics").getByRole("link", { name: "Origami unicorns" }).click();
    await expect(page.locator("#forum-posts .forum-post")).toHaveCount(2);
    await snap(page, "forum-topic");
  });

  test("mailbox", async ({ page }) => {
    await visit(page, `${GDR}/mail`, "mail-inbox");
    await page.locator("#mail-inbox").getByRole("link", { name: /You've done a man's job/ }).click();
    await expect(page.locator("#mail-show")).toBeVisible();
    await snap(page, "mail-message");
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

  test("appearance editor and all eight presets", async ({ page }) => {
    await page.goto(`${GDR}/gm/theme`);
    await expect(page.locator("#theme-presets > button")).toHaveCount(8);
    await snap(page, "appearance-editor");
    const shellStyle = await page.locator("#app-shell").getAttribute("style");

    for (const preset of [
      "tannhauser", "azure", "sepia", "nocturne",
      "midnight", "ember", "crimson", "silver",
    ]) {
      await page.locator(`#theme-preset-${preset}`).click();
      await expect(page.locator("#theme-preview")).toHaveAttribute("data-theme", preset);
      await expect(page.locator(`#theme-preset-${preset}`)).toHaveAttribute("aria-pressed", "true");
      await expect(page.locator("#app-shell")).toHaveAttribute("style", shellStyle!);
      await settle(page);
      await expect(page.locator("#theme-preview")).toHaveScreenshot(`appearance-${preset}.png`);
    }
  });

  test("appearance overrides, focus and validation states", async ({ page }) => {
    await page.goto(`${GDR}/gm/theme`);
    await settle(page);
    await page.locator("#control-corners").selectOption("round");
    await expect(page.locator("#theme-preview")).toHaveAttribute("style", /--radius-field:1.2rem/);
    await page.locator("#control-density").selectOption("compact");
    await expect(page.locator("#theme-preview")).toHaveAttribute("style", /--control-height:2.25rem/);
    await page.locator("#control-effects").selectOption("soft");
    await expect(page.locator("#theme-preview")).toHaveAttribute("style", /--control-shadow:0 4px 16px/);
    await page.locator("#theme-colours summary").click();
    await page.locator("#override-primary").fill("#ccddff");
    await expect(page.locator("#theme-preview")).toHaveAttribute("style", /--color-primary:#ccddff/);
    await expect(page.locator("#preview-disabled")).toBeDisabled();
    await expect(page.locator("#preview-error")).toHaveAttribute("aria-invalid", "true");
    await page.locator("#preview-input").focus();
    await settle(page);
    await expect(page.locator("#theme-preview")).toHaveScreenshot("appearance-custom-focus.png");
  });

  test("mobile appearance editor", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`${GDR}/gm/theme`);
    await expect(page.locator("#theme-form")).toBeVisible();
    const dimensions = await page.evaluate(() => ({
      scroll: document.documentElement.scrollWidth,
      viewport: window.innerWidth,
    }));
    expect(dimensions.scroll).toBeLessThanOrEqual(dimensions.viewport);
    await snap(page, "appearance-mobile");
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
