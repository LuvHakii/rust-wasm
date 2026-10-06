#!/usr/bin/env bash
set -e

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

mkdir -p $ROOT

if [ "$1" = "ra" ] || [ -z "$1" ]; then
  if [ ! -d $RA_SRC ]; then
    echo "cloning rust-lang/rust-analyzer @ $RA_REV"
    git clone --depth 1 --branch $RA_REV --single-branch \
      https://github.com/rust-lang/rust-analyzer.git $RA_SRC
  fi
fi

if [ ! -d $WASI_SDK ]; then
  echo "downloading wasi-sdk $WASI_SDK_VER"
  curl -fsSL "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-$WASI_SDK_VER/wasi-sdk-$WASI_SDK_VER.0-x86_64-linux.tar.gz" \
    | tar xz -C $ROOT
fi

if [ "$1" = "ra" ] || [ "$1" = "rustc" ] || [ -z "$1" ]; then
  if [ ! -d $RUST_SRC ]; then
    echo "cloning rust-lang/rust @ $RUST_REV"
    git clone --depth 1 --branch $RUST_REV --single-branch \
      https://github.com/rust-lang/rust.git $RUST_SRC
  fi
  if [ "$1" != "ra" ]; then
    git -C $RUST_SRC submodule update --init --depth 1 src/llvm-project
  fi
fi

echo "SETUP DONE"
