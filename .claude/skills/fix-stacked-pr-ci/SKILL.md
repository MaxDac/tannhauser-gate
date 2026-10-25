---
name: fix-stacked-pr-ci
description: Diagnose and fix failing CI on a tannhauser-gate pull request that is part of a native GitHub PR stack, then rebase the layers above it. Use when a PR's checks fail (credo, dialyzer, format, mix test, Playwright e2e, Playwright screenshots) or when asked to "fix CI and rebase the stack".
---

# Fix CI on a stacked PR, then restack

Do these steps in order. Do not skip the local checks.

## 0. Environment (Windows)

Prepend this to every PowerShell command:

```powershell
$env:Path="C:\Program Files\Elixir\bin;C:\Program Files\Erlang OTP\bin;$env:Path"
```

- Postgres runs locally with user/password postgres/postgres.
- For tests, set `$env:MIX_ENV="test"`.
- Hide noisy output with `| Select-String -NotMatch "\[debug\]|symlink" | Select -Last 40`.

## 1. Read the stack and the failing checks

```powershell
gh pr checks <PR>
gh api 'repos/MaxDac/tannhauser-gate/stacks?pull_request=<PR>' --jq '.[0] | {number, prs: [.pull_requests[] | {number, head: .head.ref, sha: .head.sha}]}'
gh run view <RUN_ID> --job <JOB_ID> --log-failed | Select-String "error|warning|✘|Snapshot|failed" | Select -First 40
```

- The stack's `pull_requests` list runs bottom to top.
- Fix a failure in the **lowest** PR whose own diff introduced it, i.e. the layer that owns the file. Use `git log --oneline -- <file>` to find it.
- If another session or agent owns that layer, message it instead of editing its branch.

## 2. Known failures and their fixes

| CI job | Symptom | Fix |
|---|---|---|
| credo | `Nested modules could be aliased at the top of the invoking module` (AliasUsage) | Add the module to the file's existing `alias` group, e.g. `alias TannhauserGate.Seeds.{Helpers, MapArtwork}`, and call it by its short name. |
| credo | `Struct %Foo{} found in @spec` (SpecWithStruct) | Do **not** put `%Foo{}` in specs. Add `@type t :: %__MODULE__{}` to the schema module and use `Foo.t()`. |
| dialyzer | `Unknown type: Foo.t/0` | The module has no `t/0`. Add `@type t :: %__MODULE__{}` to it. This also fixes the credo row above, so fix both together. |
| format | Diff output | Run `mix format`. |
| mix test | Failing test | Run `mix test <file>` or `mix test --failed`, fix, and re-run. |
| Playwright screenshots | `toHaveScreenshot(x.png) failed` or `A snapshot doesn't exist ... writing actual` after an **intentional** UI change | Regenerate the baselines on Linux (step 3). Never generate them on Windows: the pixels differ. |
| Playwright screenshots / e2e | Selector or geometry assertion fails after a layout change | Update the spec under `e2e/tests/` to match the new DOM, using stable element IDs. |
| any job after a rebase | `lock mismatch: the dependency is out of date` | The parent layer changed `mix.lock`. Run `mix deps.get`. |

Check every fix locally before pushing. Credo **and** Dialyzer must both pass, because a fix for one can break the other:

```powershell
mix credo --strict
mix dialyzer
mix precommit   # must pass and keep coverage >= 95%
```

## 3. Regenerate screenshot baselines (only for intentional UI changes)

```powershell
gh workflow run update-screenshots.yml --ref <branch> -f update_mode=changed
gh run list --workflow update-screenshots.yml --branch <branch> --limit 1
gh run watch <RUN_ID> --exit-status
git pull --ff-only
```

- The workflow commits the new PNGs to the branch as `github-actions[bot]` and re-runs CI.
- Afterwards, run `git pull --ff-only` locally before making any other commit.
- Use `update_mode=all` if a subtle change stayed within tolerance.
- Screenshots of an upper layer include the lower layers' UI. After rebasing an upper layer, its baselines may need regenerating too.

## 4. Commit and push the fixed layer

```powershell
git add -A
git commit -m "<message>"
git push   # use --force-with-lease only after a rebase, see step 5
```

## 5. Rebase the layers above (restack)

The rule: the stack metadata stays as it is. Never unstack or recreate the stack to rebase it. Each upper branch is rebased onto its new parent, in order from the bottom of the stack to the top.

For each upper layer, in its own worktree:

```powershell
git fetch origin
$oldParent = "<SHA of the parent head this layer was previously based on>"
$remoteTip = git rev-parse origin/<this-branch>
git rebase --onto origin/<parent-branch> $oldParent
mix deps.get
mix precommit
git push --force-with-lease="refs/heads/<this-branch>:$remoteTip" origin HEAD
```

- `$oldParent` must be the **old** parent commit, not the new one. Otherwise the rebase replays the parent's commits a second time. Find it with `git log --oneline origin/<this-branch>`: it is the last commit that is not this layer's own.
- If the lease push fails, someone else pushed. Fetch and start again; never plain `--force`.
- If another session or agent owns an upper layer, send it the new parent head SHA and let it rebase its own branch.
- Afterwards, verify the stack:

```powershell
gh api 'repos/MaxDac/tannhauser-gate/stacks/<STACK>' --jq '[.pull_requests[] | {number, head: .head.sha}]'
gh pr view <each PR> --json baseRefName,headRefOid
gh pr checks <each PR>
```

Every PR's base must be the head branch of the PR below it, and the bottom PR's base must be `main`.
