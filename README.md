<p align="center">
  <img src="priv/static/images/logo.svg" alt="Tannhauser Gate" width="140">
</p>

<h1 align="center">Tannhauser Gate</h1>

<p align="center">
  A console-green, noir play-by-chat role-playing website built with Elixir, Phoenix LiveView and PostgreSQL.
</p>

---

Neo-Meridian, 2121. The acid rain never stops, the advertising never sleeps, and somewhere past
the orbital relay called the *Tannhauser Gate* the Echoes are coming home.

Tannhauser Gate is a small, self-hostable platform for running many text role-playing games
(GDRs). Each GDR is run by a game master (GM) with its own rules, world background, theme,
character sheet, map, forum, bank and jobs. Players pick a GDR after login, create one
character in it, and play in real-time chat rooms placed on its map. *Tannhauser Gate* is also
the name of the default GDR, an original setting inspired by the mood of *Blade Runner*.

## Features

- **Accounts:** email and password registration and login, built on `phx.gen.auth`. Users have two flags: `admin` and `gm` (game master).
- **GDR selection** (`/gdrs`): after login, players choose a published GDR to enter. Each GDR lives under `/g/:id/...`.
- **Requesting a GDR:** a GM files a request (`/gdrs/request`). An admin approves or rejects it (`/admin/requests`). Approval creates a draft GDR owned by the GM. Each GM runs at most one GDR.
- **GM dashboard** (`/g/:id/gm`, only the GDR's GM and admins):
  - name, summary, world background, rules, customs, status (draft or published);
  - theme preset plus optional custom colours (hex only);
  - attributes, skills and powers, each with a name, description and min/max range;
  - jobs and their pay, the currency name and the pay interval;
  - character balances (adjustments are recorded in the ledger);
  - map artwork and rooms;
  - forum sections.
- **Characters:** one character per user per GDR. The character sheet, styled as a detective's spiral-bound notepad, shows the avatar, name, description, background and the GDR's attributes, skills and powers.
- **Bank and jobs:** characters pick a job and receive its pay automatically every pay interval. They can send money to other characters of the same GDR. Every movement is stored in a transaction ledger.
- **Left drawer navigation:** inside a GDR it covers Home, Characters, Map, Forum, Bank, Jobs and, for its GM, the dashboard.
- **City map and chat rooms:** each GDR has an SVG map with clickable polygon areas. Every area is a chat room. Messages show the speaking character's avatar, name, time and text, and arrive live through Phoenix PubSub. GM artwork is rendered as an inert SVG image, so it can't run scripts.
- **Forum:** one forum per GDR: sections → topics → posts, with posts listed oldest first.
- **Admin control room:**
  - create and edit GDRs, their map artwork and rooms (polygon areas);
  - review GDR requests;
  - edit any character;
  - read and moderate every room's conversation;
  - moderate forum sections;
  - grant or revoke the admin and GM flags.
- **Default content:** the *Tannhauser Gate* GDR with nine rooms in the city of Neo-Meridian, attributes, skills, powers, jobs, three forum sections and an admin account.

## Stack

- [Phoenix 1.8](https://www.phoenixframework.org/) and Phoenix LiveView 1.2, generated from the latest `phx.new` skeleton
- Ecto 3 with PostgreSQL (`postgrex`)
- [Tailwind CSS v4](https://tailwindcss.com/) (CSS-first config, no `tailwind.config.js`) and [daisyUI 5](https://daisyui.com/)
- esbuild with colocated LiveView hooks, and heroicons
- Bandit HTTP server

## Theme

The UI uses a console / "Matrix" green palette tuned for long reading sessions. It is a custom
dark daisyUI theme called `tannhauser`. The primary phosphor green (#4ae08a) is deliberately softer
than pure #00ff00. It sits on a green-tinted near-black (`base-100`, #0b100d) instead of pure black,
and body text uses green-grey tones rather than saturated green. All text colours meet WCAG AA, and
most exceed AAA (phosphor is 11.3:1, body text 13.1:1). Red is reserved for errors and destructive
actions.

The theme, extra design tokens (`phosphor`, `mint`, `night`, `ink`, `fog-*`, fonts) and the
notepad, map and polaroid styles are all in [`assets/css/app.css`](assets/css/app.css).
UI components use daisyUI classes (`btn`, `input`, `select`, `drawer`, `alert`, ...).

`tannhauser` is the theme of the default GDR. The platform pages (GDR selection, account,
admin) use a neutral `platform` theme. GMs choose a preset for their GDR (`tannhauser`,
`ember`, `azure` or `crimson`) and can override its main colours with hex values. The
design tokens follow the active daisyUI theme, so the custom components restyle with it.

Shared form controls add scoped `console-field`, `console-check`, and `console-action` styles:
inset dark surfaces, readable borders, restrained green focus rings, and distinct error,
disabled, and read-only states. Labels stay visible, and field errors are associated through
`aria-describedby` without changing LiveView's validation timing. Reduced-motion preferences
disable control transitions. The theme remains flat for unrelated components.

`<.input class="...">` and `<.button class="...">` **replace** their default classes. Include
the complete control styling when overriding, for example
`class="w-full textarea console-field font-mono text-xs"` for a code textarea.

### Favicons

The existing `priv/static/favicon.svg` is the source for the browser icons. The root layout
prefers that scalable icon and also declares 16px/32px PNG fallbacks, a multi-size ICO
(16px/32px/48px), and a 180px Apple touch icon. All assets are served locally.

Regenerate them using the existing Playwright 1.64.0 dependency and its pinned Chromium:

```bash
cd e2e
npm ci
npx playwright install chromium
npm run generate:favicons
```

The generator renders each size directly from the unchanged SVG and packages the smaller
PNGs into the ICO; no extra image libraries or application dependencies are needed.

## Running locally (WSL / Linux)

The project is developed and tested inside WSL (Ubuntu), but any Linux or macOS machine works.

### 1. Prerequisites

```bash
# Build tools and PostgreSQL
sudo apt update
sudo apt install -y build-essential git curl unzip postgresql inotify-tools
sudo service postgresql start
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"

# Erlang/OTP, Elixir and Node (with mise, asdf works the same way)
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc && source ~/.bashrc
mise use -g erlang@29 elixir@1.20 node@22
```

Elixir 1.17 or newer is required (CI runs Elixir 1.20 / OTP 29 and PostgreSQL 18). Tailwind and esbuild binaries are downloaded by `mix setup`, so Node is only needed for the Playwright tests.

### 2. Set up and run

```bash
git clone https://github.com/MaxDac/tannhauser-gate.git
cd tannhauser-gate
mix setup          # deps, database, migrations, seeds, assets
mix phx.server     # http://localhost:4000
```

To work from a Windows checkout, run the same commands from the `/mnt/c/...` path inside WSL.
For faster file watching, clone the repo into the Linux filesystem instead (for example `~/code`).

### Database configuration

The dev and test environments read these optional variables:

| Variable | Default |
| --- | --- |
| `PGUSER` / `PGPASSWORD` | `postgres` / `postgres` |
| `PGHOST` | `localhost` |
| `DEV_DATABASE` | `tannhauser_gate_dev` |
| `PORT` | `4000` |

### Email authentication feature flag

Email delivery and verification are behind `FEATURE_EMAIL_AUTH` (`true` or `1` enables it; the default is off,
see `TannhauserGate.Features`). While it is off, users register with a username, an email and a password. No
email is sent, the email stays unverified and login is by username. Password reset, the confirmation pages and
the "forgot password" link are disabled. Turning it on restores the confirmation, reset and email-change flows,
and login accepts the username or the email. See the "Enable email" GitHub issue for the re-enable steps.

### Default admin account

The seeds (`mix run priv/repo/seeds.exs`, also run by `mix setup`) create an admin. They are safe to re-run.

| | Default | Override with |
| --- | --- | --- |
| Username | `admin` | `ADMIN_USERNAME` |
| Email | `admin@tannhauser.gate` | `ADMIN_EMAIL` |
| Password | `change-me-tannhauser-2121` | `ADMIN_PASSWORD` |

**Change the password before deploying anywhere public.** Admins can promote other users from
**Admin → Users**.

## Tests

### Unit and LiveView tests (ExUnit)

```bash
mix test
```

These cover the contexts, authorization, the seeds, and every LiveView, including avatar uploads and admin access control.

### End-to-end tests (Playwright)

The E2E suite lives in [`e2e/`](e2e). It boots `mix phx.server` against the seeded dev database and
drives Chromium through the full journey:

1. register;
2. create a character with an avatar;
3. open a room from the map;
4. send a chat message;
5. open a forum topic and reply;
6. check that a regular user is denied admin access;
7. check that the admin can read the conversation.

```bash
mix ecto.reset                     # fresh, seeded dev database
cd e2e
npm install
npx playwright install --with-deps chromium
npx playwright test
```

Set `E2E_PORT` to use a port other than 4000, and `DEV_DATABASE` to point at another dev database. Locally, if a server is already running on that port, the suite reuses it, so pick a free port when another server is running. For example:

```bash
DEV_DATABASE=tannhauser_gate_e2e_dev E2E_PORT=4210 npx playwright test
```

### Screenshot tests (Playwright)

[`e2e/tests/visual`](e2e/tests/visual) takes full-page screenshots of the key pages and compares
them with the committed baselines in `e2e/tests/visual/__screenshots__/`. Covered pages: login,
register, characters (drawer layout), character sheet and form, map, room chat, forum, and admin.

The screenshots stay deterministic because:

- they run against a separate `tannhauser_gate_visual` database filled with fixed fixtures
  ([`priv/repo/visual_seeds.exs`](priv/repo/visual_seeds.exs)), and every timestamp is pinned to 2121-11-03;
- CI runs them in the pinned `mcr.microsoft.com/playwright:v1.64.0-noble` container, which matches
  `@playwright/test` 1.64.0 exactly, so fonts and rendering never drift. Bump both together;
- the viewport, scale, locale (`en-GB`), time zone (UTC) and colour scheme are fixed. Animations,
  transitions, the caret, flash toasts and the LiveView progress bar are disabled or hidden.

```bash
e2e/scripts/visual-db.sh           # recreate the fixture database
cd e2e
VISUAL_PORT=4220 npm run test:visual   # default port 4002
```

**Updating baselines.** The baselines are Linux-only and must come from CI's container. After an
intentional UI change, open **Actions → Update screenshots → Run workflow** and pick your PR branch.
The workflow regenerates the PNGs, commits them to the branch and re-runs CI. Review the image diff
in the PR. Locally, `npm run test:visual:update` is useful for iterating, but don't commit
the PNGs it writes. When a check fails, the diffs are uploaded as the
`playwright-screenshots-report` artifact. Its `test-results-visual/**/*-actual.png` files are also
valid baselines. They were rendered in the same container, so you can copy them into
`__screenshots__/` (dropping the `-actual` suffix) if the update workflow isn't available.

## Quality gates

Every pull request to `main` must pass these CI jobs. They are enforced by the
[`main` ruleset](.github/rulesets/main.json):

| Check | Command |
| --- | --- |
| `compile` | `mix compile --warnings-as-errors` |
| `format` | `mix format --check-formatted` |
| `credo` | `mix credo --strict` |
| `dialyzer` | `mix dialyzer` (PLTs in `priv/plts`, cached in CI) |
| `mix test` | `mix test` |
| `Playwright e2e` | `cd e2e && npx playwright test` |
| `Playwright screenshots` | `cd e2e && npm run test:visual` |

The branch must also be up to date with `main`, and review conversations must be resolved. Repository
admins can bypass the ruleset. To change the ruleset, edit the JSON and re-apply it:

```bash
gh api -X PUT repos/MaxDac/tannhauser-gate/rulesets/<id> --input .github/rulesets/main.json
```

## Uploads

Character avatars are stored on local disk and served from `/uploads`. By default they go to
`priv/static/uploads`. In production, set `UPLOADS_DIR` to a persistent directory. Uploads accept
`.jpg`, `.jpeg`, `.png`, `.webp` and `.gif` files.

## Fly.io development deployment

The deployment target is <https://tannhauser-gate.fly.dev>, with a separate legacy
Postgres cluster named `tannhauser-gate-db`. Both use one shared CPU and 256MB RAM
in Amsterdam (`ams`). The database runs Postgres 17.2 with 1GB encrypted storage.
The app has a separate 1GB encrypted `uploads` volume mounted at `/data` and sets
`UPLOADS_DIR=/data/uploads`, so avatars survive restarts and deployments. Volumes
have automatic daily snapshots retained for five days; a single volume is not
high availability or a substitute for an independent backup.

This development deployment uses `MIX_ENV=prod`: debug routes and the local
mailbox are not published. The root-owned container entrypoint prepares the
mounted uploads directory, then drops to `nobody` before starting the release.
The release files remain root-owned and are not writable by the application.

GitHub Actions deploys pushes to `main` and manual runs on `main` only after
**all seven existing quality gates** pass, including Dialyzer, E2E, and screenshots.
Pull requests and manual runs on other branches never deploy. Deployments are
serialized and are not cancelled by a newer `main` run; PR checks retain their
auto-cancel behavior. Docker builds run on the GitHub runner rather than a paid
remote builder. Deployment uses `--ha=false` and never creates a spare app Machine.

| Platform | Secret | Purpose |
| --- | --- | --- |
| GitHub repository `MaxDac/tannhauser-gate` | `FLY_API_TOKEN` | Deploy token scoped only to `tannhauser-gate`, expiring after 720 hours |
| Fly app `tannhauser-gate` | `DATABASE_URL` | Attachment to database `tannhauser_gate` with a dedicated non-superuser role |
| Fly app `tannhauser-gate` | `SECRET_KEY_BASE` | Persistent session signing/encryption key |

Create or renew the deploy token with
`fly tokens create deploy -a tannhauser-gate --expiry 720h`, capturing its output
privately and passing it through stdin to
`gh secret set FLY_API_TOKEN --repo MaxDac/tannhauser-gate`. Do not run token
generation on its own where the credential will be printed. Import runtime
secrets through stdin with `fly secrets import --stage -a tannhauser-gate`.
Never put credentials in files, logs, build arguments, workflow artifacts, or
commits. Verify only metadata with `gh secret list --repo MaxDac/tannhauser-gate`
and `fly secrets list -a tannhauser-gate`. Renew the token before it expires and
preserve `SECRET_KEY_BASE` between deployments.

Deployment runs `bin/migrate` on a temporary 256MB Machine and fails if migrations
fail. The attached role has `CREATE` only on its own database to install the
trusted `citext` extension; it is not a superuser. Database resets and seeds do
not run automatically. In particular, deployment never creates an admin with
the published development password. Bootstrap content/admin access separately
with a strong private password before using the site; the local setup commands
above are not production provisioning commands.

The app stops when idle and wakes on incoming requests, with no minimum-running
Machine. Cold starts and deployment downtime are expected, and open LiveView
connections may keep it running. Postgres stays running. IPv6 database access is
enabled and the app uses a two-connection pool. Public traffic is forced to HTTPS;
Fly's internal HTTP probe uses `GET /health`, which checks database connectivity
and returns `{"status":"ok"}` or HTTP 503 with `{"status":"unavailable"}`.

**Email delivery is disabled until a real provider and sender are configured.**
The production mail adapter reports a delivery error without logging message
contents. Confirmation and password-reset emails cannot be delivered; existing
authentication requirements are unchanged. The site does not expose a mailbox
or publish email links in logs.

**Minimum resources do not mean guaranteed free billing.** Legacy allowances,
if active, are shared across all apps in the organization. This additional app,
database, and uploads volume may exceed them, and migration Machines, snapshots,
network usage, and stopped Machine root filesystems follow Fly's billing rules.
Do not increase memory, add replicas, or allocate a paid dedicated IPv4 address
without reviewing costs. The app uses shared IPv4 and free IPv6 ingress.

For an authorized local deployment, use
`fly deploy --app tannhauser-gate --config fly.toml --local-only --ha=false --no-public-ips --yes`
after provisioning the shared ingress addresses and uploads volume. Image
rollbacks do not undo migrations or restore uploaded files; do not run destructive
down migrations automatically.

## Project layout

```
lib/tannhauser_gate/          domain: Accounts, Stories, Characters, Chat, Forum, Storage, Seeds
lib/tannhauser_gate_web/live/ LiveViews (characters, map, rooms, forum, admin)
assets/css/app.css            Tailwind v4 + daisyUI theme (console-green palette, notepad styles)
assets/js/app.js              LiveSocket setup (hooks are colocated in the LiveViews)
priv/static/images/logo.svg   brand mark; priv/static/favicon.svg
e2e/                          Playwright end-to-end and screenshot tests
priv/repo/visual_seeds.exs    deterministic fixtures for the screenshot tests
.github/rulesets/main.json    branch ruleset for main (required checks)
```

## License

Tannhauser Gate is free software released under the
[GNU Affero General Public License v3.0](LICENSE).

You may use, study, modify and share it, including commercially. If you distribute it, **or run a
modified version as a network service**, you must release your complete source code under the
same license. Closed-source forks and closed hosted versions are not allowed: everything stays in the open.

*Blade Runner* is a trademark of its respective owners. This project is an original, unaffiliated
work inspired by the genre. All story text, map art and branding here were written for this project.
