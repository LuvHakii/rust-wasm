#!/usr/bin/env bash
set -e

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

apply_patches $RA_SRC 'rust-analyzer-*.patch'
apply_rules $RA_SRC $REPO/rules/rust-analyzer.yml $REPO/files/rust-analyzer

cd $RA_SRC

# parking_lot_core's wasm threads parker needs an unstable feature (rust-analyzer only enables the default ones)
cargo add --package rust-analyzer "parking_lot_core@0.9" --features nightly
export RUSTC_BOOTSTRAP=1

# salsa cancels in-flight queries by unwinding, and wasm32-wasip1 has no unwinding (panic=abort), so any edit that
# lands during analysis aborted the server. rules/salsa.yml stops setting the flag: the writer waits instead.
cargo fetch --target $HOST
SALSA_VER=$(grep -A1 '^name = "salsa"$' Cargo.lock | grep -m1 version | cut -d'"' -f2)
rm -rf $ROOT/salsa
cp -r "$(ls -d "${CARGO_HOME:-$HOME/.cargo}"/registry/src/*/salsa-$SALSA_VER)" $ROOT/salsa
apply_rules $ROOT/salsa $REPO/rules/salsa.yml
sed -i "s|^\[patch.'crates-io'\]|&\nsalsa = { path = \"$ROOT/salsa\" }|" Cargo.toml

# strip=debuginfo keeps the target_features section, so wasm-opt can detect features itself
export CARGO_PROFILE_RELEASE_DEBUG=false CARGO_PROFILE_RELEASE_STRIP=debuginfo CARGO_PROFILE_RELEASE_OPT_LEVEL=s \
  CARGO_PROFILE_RELEASE_LTO=true CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 CARGO_PROFILE_RELEASE_PANIC=abort

# mimalloc replaces wasi-libc's dlmalloc: -20% CPU on a cold std analysis, -32% over an edit session, +20% peak RSS, +0.1 MB.
# Its C sources need the wasi-sdk compiler.
export CC_wasm32_wasip1_threads=$WASI_SDK/bin/wasm32-wasip1-threads-clang AR_wasm32_wasip1_threads=$WASI_SDK/bin/ar

echo "building rust-analyzer"
cargo build --release --target $HOST --bin rust-analyzer --features mimalloc
mkdir -p $OUT
cp target/$HOST/release/rust-analyzer.wasm $OUT/rust-analyzer.names.wasm
wasm-opt -Os --strip-debug $OUT/rust-analyzer.names.wasm -o $OUT/rust-analyzer.wasm

echo "BUILD DONE"
