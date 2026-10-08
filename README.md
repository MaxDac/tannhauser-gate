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

Tannhauser Gate is a small, self-hostable platform for running text role-playing games. Admins
write a story with its world background, customs and an interactive map. Players create
characters and play them in real-time chat rooms placed on that map. The default story is an
original setting inspired by the mood of *Blade Runner*.

## Features

- **Accounts:** email and password registration and login, built on `phx.gen.auth`. Roles are `user` and `admin`.
- **Left drawer navigation** covering Characters, City Map, Forum and Admin. The Admin entry is shown to admins only.
- **Characters:** a list of your characters. Each one opens a character sheet styled as a detective's spiral-bound notepad, with an avatar photo, name, description and background.
- **City map and chat rooms:** each story ships an SVG map with clickable polygon areas. Every area is a chat room. Messages show the speaking character's avatar, name, time and text, and arrive live through Phoenix PubSub.
- **Forum:** simple sections → topics → posts, with posts listed oldest first.
- **Admin control room:**
  - create and edit stories, their map artwork and rooms (polygon areas);
  - edit any character;
  - read and moderate every room's conversation;
  - manage forum sections;
  - promote or revoke admins.
- **Default content:** the *Tannhauser Gate* story with nine rooms in the city of Neo-Meridian, three forum sections and an admin account.

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

### Default admin account

The seeds (`mix run priv/repo/seeds.exs`, also run by `mix setup`) create an admin. They are safe to re-run.

| | Default | Override with |
| --- | --- | --- |
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

## Uploads

Character avatars are stored on local disk and served from `/uploads`. By default they go to
`priv/static/uploads`. In production, set `UPLOADS_DIR` to a persistent directory. Uploads accept
`.jpg`, `.jpeg`, `.png`, `.webp` and `.gif` files.

## Project layout

```
lib/tannhauser_gate/          domain: Accounts, Stories, Characters, Chat, Forum, Storage, Seeds
lib/tannhauser_gate_web/live/ LiveViews (characters, map, rooms, forum, admin)
assets/css/app.css            Tailwind v4 + daisyUI theme (console-green palette, notepad styles)
assets/js/app.js              LiveSocket setup (hooks are colocated in the LiveViews)
priv/static/images/logo.svg   brand mark; priv/static/favicon.svg
e2e/                          Playwright end-to-end tests
```

## License

Tannhauser Gate is free software released under the
[GNU Affero General Public License v3.0](LICENSE).

You may use, study, modify and share it, including commercially. If you distribute it, **or run a
modified version as a network service**, you must release your complete source code under the
same license. Closed-source forks and closed hosted versions are not allowed: everything stays in the open.

*Blade Runner* is a trademark of its respective owners. This project is an original, unaffiliated
work inspired by the genre. All story text, map art and branding here were written for this project.
