import { test, expect, Page } from "@playwright/test";

async function connected(page: Page) {
  await expect(page.locator(".phx-connected").first()).toBeVisible();
}

async function adminLogin(page: Page) {
  await page.goto("/users/log_in");
  await connected(page);
  await page.getByLabel("Email").fill(process.env.ADMIN_EMAIL || "admin@tannhauser.gate");
  await page.getByLabel("Password").fill(process.env.ADMIN_PASSWORD || "change-me-tannhauser-2121");
  await page.getByRole("button", { name: /log in/i }).click();
  await expect(page).toHaveURL(/\/characters$/);
}

function contrast(first: string, second: string) {
  const luminance = (color: string) => {
    const match = /^rgb\((\d+), (\d+), (\d+)\)$/.exec(color);
    if (!match) throw new Error(`Expected an opaque RGB color, got ${color}`);
    const channels = match.slice(1).map((value) => {
      const channel = Number(value) / 255;
      return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
    });
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  };
  const values = [luminance(first), luminance(second)].sort((a, b) => b - a);
  return (values[0] + 0.05) / (values[1] + 0.05);
}

test("login controls have visible keyboard focus and retain checkbox behavior", async ({ page }) => {
  await page.goto("/users/log_in");
  await connected(page);
  const email = page.locator("#login_form input[type=email]");
  await expect(email).toHaveCSS("border-color", "rgb(114, 137, 122)");
  await expect(email).toHaveCSS("background-color", "rgb(11, 16, 13)");
  const colors = await email.evaluate((input) => {
    const style = getComputedStyle(input);
    return { border: style.borderColor, background: style.backgroundColor, text: style.color };
  });
  expect(contrast(colors.border, colors.background)).toBeGreaterThanOrEqual(3);
  expect(contrast(colors.text, colors.background)).toBeGreaterThanOrEqual(4.5);
  await page.getByRole("link", { name: "Register", exact: true }).focus();
  await page.keyboard.press("Tab");
  await expect(email).toBeFocused();
  await expect(email).toHaveCSS("outline-width", "2px");
  await expect(email).toHaveCSS("outline-color", "rgb(74, 224, 138)");

  const password = page.getByLabel("Password", { exact: true });
  await page.keyboard.press("Tab");
  await expect(password).toBeFocused();
  const remember = page.getByLabel("Keep me logged in");
  await page.keyboard.press("Tab");
  await expect(remember).toBeFocused();
  await expect(remember).toHaveCSS("outline-width", "2px");
  await page.keyboard.press("Space");
  await expect(remember).toBeChecked();
  await expect(remember).toHaveCSS("background-color", "rgb(74, 224, 138)");
  await remember.evaluate((input: HTMLInputElement) => { input.disabled = true; });
  await expect(remember).toHaveCSS("background-color", "rgb(18, 26, 21)");
  await remember.evaluate((input: HTMLInputElement) => { input.disabled = false; });
  await remember.focus();
  await page.keyboard.press("Space");
  await expect(remember).not.toBeChecked();

  await email.evaluate((input: HTMLInputElement) => { input.readOnly = true; });
  await expect(email).toHaveCSS("border-style", "dashed");
  await email.evaluate((input: HTMLInputElement) => {
    input.readOnly = false;
    input.disabled = true;
  });
  await expect(email).toHaveCSS("cursor", "not-allowed");
});

test("account recovery fields retain visible labels after typing", async ({ page }) => {
  for (const route of ["/users/reset_password", "/users/confirm"]) {
    await page.goto(route);
    await connected(page);
    await page.getByLabel("Email", { exact: true }).fill("player@example.com");
    await expect(page.locator("label .console-label")).toHaveText("Email");
  }
});

test("admin artwork keeps textarea styling and accessible red validation states", async ({ page }) => {
  await adminLogin(page);
  await page.goto("/admin/stories/new");
  await connected(page);
  const artwork = page.locator("#story_map_svg");
  await expect(artwork).toHaveClass(/textarea.*console-field.*font-mono/);
  await expect(artwork).toHaveCSS("font-size", "12px");
  await page.getByLabel("Name", { exact: true }).fill("Invalid artwork");
  await artwork.fill("<script>alert(1)</script>");
  await page.getByRole("button", { name: "Save story" }).click();
  await expect(artwork).toHaveAttribute("aria-invalid", "true");
  await expect(artwork).toHaveAttribute("aria-describedby", "story_map_svg-errors");
  await expect(page.locator("#story_map_svg-errors")).toBeVisible();
  await artwork.focus();
  await expect(artwork).toHaveCSS("outline-color", "rgb(248, 113, 113)");
  await expect(artwork).toHaveCSS("border-color", "rgb(248, 113, 113)");
});

test("the compact map selector preserves story switching", async ({ page }) => {
  await adminLogin(page);
  await page.goto("/admin/stories/new");
  await connected(page);
  const name = `Selector story ${Date.now()}`;
  await page.getByLabel("Name", { exact: true }).fill(name);
  await page.getByRole("button", { name: "Save story" }).click();
  await expect(page).toHaveURL(/\/admin\/stories\/\d+\/edit$/);
  await page.goto("/map");
  await connected(page);
  const story = page.locator("#map-story");
  await expect(story).toHaveClass(/select-sm console-field/);
  await story.selectOption({ label: name });
  await expect(page).toHaveURL(/\/stories\/\d+\/map$/);
  await expect(page.locator("h1")).toHaveText(name);
});

test("forms remain within the mobile viewport", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await adminLogin(page);

  for (const route of ["/characters/new", "/admin/stories/new", "/users/settings", "/map"]) {
    await page.goto(route);
    await connected(page);
    const dimensions = await page.evaluate(() => ({
      scroll: document.documentElement.scrollWidth,
      viewport: window.innerWidth,
    }));
    expect(dimensions.scroll).toBeLessThanOrEqual(dimensions.viewport);
    for (const control of await page.locator("form .console-field").all()) {
      const bounds = await control.boundingBox();
      expect(bounds).not.toBeNull();
      expect(bounds!.x).toBeGreaterThanOrEqual(0);
      expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(dimensions.viewport);
    }
  }
});

test("favicon assets are locally served and decode at the declared sizes", async ({ page, request }) => {
  await page.goto("/users/log_in");
  await expect(page.locator("head link[rel='icon'][type='image/svg+xml']")).toHaveAttribute("sizes", "any");
  for (const [name, size] of [
    ["favicon-16.png", 16],
    ["favicon-32.png", 32],
    ["apple-touch-icon.png", 180],
  ] as const) {
    const dimensions = await page.evaluate(async (name) => {
      const image = new Image();
      image.src = `/images/${name}`;
      await image.decode();
      return [image.naturalWidth, image.naturalHeight];
    }, name);
    expect(dimensions).toEqual([size, size]);
  }
  const ico = await request.get("/favicon.ico");
  expect(ico.ok()).toBeTruthy();
  const bytes = await ico.body();
  expect(bytes.readUInt16LE(2)).toBe(1);
  expect(bytes.readUInt16LE(4)).toBe(3);
});
