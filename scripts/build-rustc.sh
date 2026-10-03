#!/usr/bin/env bash
set -e

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

apply_patches $RUST_SRC 'rustc-*.patch'
for rules in "$REPO"/rules/rustc-*.yml; do
  apply_rules $RUST_SRC "$rules" $REPO/files/rustc
done
apply_patches $RUST_SRC/src/llvm-project 'llvm-*.patch'
sed "s|@WASI_SDK@|$WASI_SDK|g" $REPO/config/bootstrap.toml.in > $RUST_SRC/bootstrap.toml

cd $RUST_SRC

# cc-rs and bootstrap read these per target; llvm.cflags and friends would also hit the x86 host LLVM
EMU="--target=wasm32-wasip1-threads -D_WASI_EMULATED_MMAN -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS"
export CFLAGS_wasm32_wasip1_threads="$EMU"
export CXXFLAGS_wasm32_wasip1_threads="$EMU"
export LDFLAGS_wasm32_wasip1_threads="-lwasi-emulated-mman -lwasi-emulated-signal -lwasi-emulated-process-clocks -Wl,--max-memory=2147483648 -Wl,-z,stack-size=1048576 -Wl,--stack-first"

echo "building rustc"
python3 x.py build --stage 2 compiler

mkdir -p $OUT
bin=
for f in build/$HOST/stage2/bin/rustc.wasm build/$HOST/stage2/bin/rustc; do
  [ -f $f ] && bin=$f && break
done
[ -n "$bin" ] || { echo "rustc binary not found"; ls build/$HOST/stage2/bin; exit 1; }

cp $bin $OUT/rustc.names.wasm
wasm-opt -Os --strip-debug $OUT/rustc.names.wasm -o $OUT/rustc.wasm
python3 $REPO/scripts/sizemap.py $OUT/rustc.names.wasm 60 > $OUT/sizemap-rustc.txt
python3 $REPO/scripts/sizemap.py $OUT/rustc.names.wasm 200 3 > $OUT/sizemap-rustc-d3.txt
ls -la $OUT/rustc.wasm

echo "BUILD DONE"
