import { test, expect, APIRequestContext } from "@playwright/test";
import { connected, emailPort, logIn, newAccount, register } from "./helpers";

// Runs against the second server, started with FEATURE_EMAIL_AUTH=true. Its
// emails are read from the Swoosh dev mailbox (`/dev/mailbox/json`).
test.use({ baseURL: `http://localhost:${emailPort}` });
test.describe.configure({ mode: "serial" });

const account = newAccount("mailer");
const newPassword = "all-those-moments-lost";

interface Email {
  subject: string;
  to: unknown;
  text_body: string;
}

// The link to `path` in the latest email with `subject` sent to the account.
async function emailLink(request: APIRequestContext, subject: string, path: string) {
  let link = "";
  await expect(async () => {
    const response = await request.get("/dev/mailbox/json");
    expect(response.ok()).toBeTruthy();
    const { data } = (await response.json()) as { data: Email[] };
    const email = data.find((e) => e.subject === subject && JSON.stringify(e.to).includes(account.email));
    expect(email, `email "${subject}" to ${account.email}`).toBeTruthy();
    const match = new RegExp(`${path}/[\\w-]+`).exec(email!.text_body);
    expect(match).not.toBeNull();
    link = match![0];
  }).toPass();
  return link;
}

test("account recovery fields retain visible labels after typing", async ({ page }) => {
  for (const route of ["/users/reset_password", "/users/confirm"]) {
    await page.goto(route);
    await connected(page);
    await page.getByLabel("Email", { exact: true }).fill("player@example.com");
    await expect(page.locator("label .console-label")).toHaveText("Email");
  }
});

test("registration sends a confirmation link that confirms the account", async ({ page, request }) => {
  await register(page, account);
  const link = await emailLink(request, "Confirmation instructions", "/users/confirm");
  await page.goto(link);
  await connected(page);
  await page.locator("#confirmation_form").getByRole("button", { name: "Confirm my account" }).click();
  await expect(page.getByText("User confirmed successfully.")).toBeVisible();

  // A second confirmation is not sent to confirmed accounts
  await page.goto("/users/confirm");
  await connected(page);
  await page.locator("#resend_confirmation_form").getByLabel("Email").fill(account.email);
  await page.locator("#resend_confirmation_form").getByRole("button").click();
  await expect(page.getByText(/If your email is in our system/)).toBeVisible();
});

test("a forgotten password is reset from the emailed link", async ({ page, request }) => {
  await page.goto("/users/reset_password");
  await connected(page);
  await page.locator("#reset_password_form").getByLabel("Email").fill(account.email);
  await page.locator("#reset_password_form").getByRole("button").click();
  await expect(page.getByText(/If your email is in our system/)).toBeVisible();

  const link = await emailLink(request, "Reset password instructions", "/users/reset_password");
  await page.goto(link);
  await connected(page);
  await page.getByLabel("New password", { exact: true }).fill(newPassword);
  await page.getByLabel("Confirm new password").fill(newPassword);
  await page.getByRole("button", { name: "Reset Password" }).click();
  await expect(page).toHaveURL(/\/users\/log_in$/);
  await expect(page.getByText("Password reset successfully.")).toBeVisible();

  await logIn(page, account.username, newPassword);

  // The reset link cannot be used twice
  await page.context().clearCookies();
  await page.goto(link);
  await expect(page.getByText("Reset password link is invalid or it has expired.")).toBeVisible();
});
