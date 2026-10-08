#!/usr/bin/env bash
# Recreates the screenshot-test database with deterministic fixtures.
# Usage: e2e/scripts/visual-db.sh   (run from anywhere; honours VISUAL_DATABASE)
set -euo pipefail
cd "$(dirname "$0")/../.."
export MIX_ENV=dev
export DEV_DATABASE="${VISUAL_DATABASE:-tannhauser_gate_visual}"
mix ecto.drop --force --quiet
mix ecto.setup
mix run priv/repo/visual_seeds.exs