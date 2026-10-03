#!/usr/bin/env bash

RUST_REV=${RUST_REV:-1.98.0}
RA_REV=${RA_REV:-2026-09-28}
WASI_SDK_VER=${WASI_SDK_VER:-33}

ROOT=${ROOT:-/data/rust-wasm-build}
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

RUST_SRC=$ROOT/rust
RA_SRC=$ROOT/rust-analyzer
WASI_SDK=$ROOT/wasi-sdk-$WASI_SDK_VER.0-x86_64-linux
HOST=wasm32-wasip1-threads
TARGET=wasm32-wasip1
OUT=$ROOT/out

# ast-grep rules with must-match counts; the tree is reset by apply_patches first
apply_rules() {
  python3 "$REPO/scripts/apply-rules.py" "$@"
}

# git apply with an offset guard: a hunk placed at a line offset exits 0 but may land on the wrong lines
apply_patches() {
  local src=$1 pattern=$2 out
  git -C "$src" checkout -- . && git -C "$src" clean -fdq
  shopt -s nullglob
  local patches=("$REPO"/patches/$pattern)
  [ ${#patches[@]} -eq 0 ] && return 0
  out=$(git -C "$src" apply -v "${patches[@]}" 2>&1) || { echo "$out"; return 1; }
  echo "$out"
  if grep -q offset <<<"$out"; then echo "hunk applied at an offset, regenerate that patch"; return 1; fi
}
