#!/usr/bin/env bash
# Pre-downloads the mdex_native precompiled NIF into rustler_precompiled's cache.
#
# rustler_precompiled downloads NIFs with Erlang's :httpc, which rejects the
# GitHub release redirect because its signed Location header is longer than
# httpc's 10 KiB limit ({:error, {:header_too_long, {:max, 10240}}}). curl has
# no such limit; rustler_precompiled finds the cached archive, verifies it
# against the checksum shipped in the package and skips the download.
# Used by CI (.github/actions/setup-elixir) and the Dockerfile.
set -euo pipefail

nif_version="${NIF_VERSION:-2.15}"
version="$(sed -nE 's/.*"mdex_native": \{:hex, :mdex_native, "([^"]+)".*/\1/p' mix.lock)"
if [ -z "$version" ]; then
  echo "mdex_native not found in mix.lock; nothing to fetch."
  exit 0
fi

target="$(uname -m)-unknown-linux-gnu"
file="libmdex_native_nif-v${version}-nif-${nif_version}-${target}.so.tar.gz"
dir="${RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH:-${XDG_CACHE_HOME:-$HOME/.cache}/rustler_precompiled/precompiled_nifs}"

mkdir -p "$dir"
if [ ! -s "$dir/$file" ]; then
  curl -fsSL --retry 3 -o "$dir/$file" \
    "https://github.com/leandrocp/mdex_native/releases/download/v${version}/${file}"
fi
echo "Cached $dir/$file"