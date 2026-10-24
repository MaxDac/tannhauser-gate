#!/usr/bin/env bash
# Pre-downloads binaries that mix fetches from GitHub releases.
#
# rustler_precompiled (mdex_native NIF) and the tailwind installer download
# with Erlang's :httpc, which rejects GitHub's release redirect because its
# signed Location header is longer than httpc's 10 KiB limit
# ({:error, {:header_too_long, {:max, 10240}}}). curl has no such limit.
# - The NIF goes into rustler_precompiled's cache, which still verifies it
#   against the checksum shipped in the package.
# - The tailwind CLI goes to its default path, which
#   `mix tailwind.install --if-missing` then skips.
# Run from the project root after `mix deps.get`, with config/config.exs present.
# Used by CI (.github/actions/setup-elixir) and the Dockerfile.
set -euo pipefail

fetch() {
  if [ ! -s "$2" ]; then
    mkdir -p "$(dirname "$2")"
    curl -fsSL --retry 3 -o "$2.tmp" "$1"
    mv "$2.tmp" "$2"
  fi
  echo "Cached $2"
}

arch="$(uname -m)"

mdex="$(sed -nE 's/.*"mdex_native": \{:hex, :mdex_native, "([^"]+)".*/\1/p' mix.lock)"
if [ -n "$mdex" ]; then
  nif="libmdex_native_nif-v${mdex}-nif-${NIF_VERSION:-2.15}-${arch}-unknown-linux-gnu.so.tar.gz"
  cache="${RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH:-${XDG_CACHE_HOME:-$HOME/.cache}/rustler_precompiled/precompiled_nifs}"
  fetch "https://github.com/leandrocp/mdex_native/releases/download/v${mdex}/${nif}" "$cache/$nif"
fi

tailwind="$(sed -nE '/^config :tailwind,/,/version:/ s/.*version: "([^"]+)".*/\1/p' config/config.exs)"
if [ -n "$tailwind" ]; then
  case "$arch" in
    x86_64) target=linux-x64 ;;
    aarch64 | arm64) target=linux-arm64 ;;
    *) echo "Unsupported architecture $arch for tailwind" >&2; exit 1 ;;
  esac
  fetch "https://github.com/tailwindlabs/tailwindcss/releases/download/v${tailwind}/tailwindcss-${target}" \
    "_build/tailwind-${target}"
  chmod +x "_build/tailwind-${target}"
fi