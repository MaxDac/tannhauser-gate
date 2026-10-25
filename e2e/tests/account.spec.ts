import { test, expect } from "@playwright/test";
import { connected, dismissFlashes, logIn, newAccount, register } from "./helpers";

test.describe.configure({ mode: "serial" });

const account = newAccount("settler");
const newPassword = "time-to-die-in-the-rain";

test("changes email and password from the settings and logs out", async ({ page }) => {
  await register(page, account);
  await dismissFlashes(page);

  await page.locator("#nav-settings").click();
  await expect(page).toHaveURL(/\/users\/settings$/);
  await connected(page);

  // Email (applied immediately while email features are disabled)
  const newEmail = `moved-${account.email}`;
  await page.locator("#email_form").getByLabel("Email").fill(newEmail);
  await page.locator("#current_password_for_email").fill(account.password);
  await page.locator("#email_form").getByRole("button", { name: "Change Email" }).click();
  await expect(page.getByText("Email updated.")).toBeVisible();
  await expect(page.locator("#email_form").getByLabel("Email")).toHaveValue(newEmail);

  // A wrong current password is rejected
  await page.locator("#password_form").getByLabel("New password", { exact: true }).fill(newPassword);
  await page.locator("#password_form").getByLabel("Confirm new password").fill(newPassword);
  await page.locator("#current_password_for_password").fill("not-my-password");
  await page.locator("#password_form").getByRole("button", { name: "Change Password" }).click();
  await expect(page.locator("#password_form")).toContainText("is not valid");

  await page.locator("#current_password_for_password").fill(account.password);
  await page.locator("#password_form").getByRole("button", { name: "Change Password" }).click();
  await expect(page).toHaveURL(/\/users\/settings$/);
  await expect(page.getByText("Password updated successfully!")).toBeVisible();

  await page.locator("#nav-log-out").click();
  await expect(page).toHaveURL(/\/users\/log_in$/);
  await page.goto("/gdrs");
  await expect(page).toHaveURL(/\/users\/log_in$/);
});

test("logs in only with the new password", async ({ page }) => {
  await page.goto("/users/log_in");
  await connected(page);
  await page.getByLabel("Username").fill(account.username);
  await page.getByLabel("Password").fill(account.password);
  await page.getByRole("button", { name: /log in/i }).click();
  await expect(page).toHaveURL(/\/users\/log_in$/);
  await expect(page.getByText("Invalid username or password")).toBeVisible();

  await logIn(page, account.username, newPassword);
});
