#!/usr/bin/env bash
set -e

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DL=$ROOT/sysroot-dl
DIST=https://static.rust-lang.org/dist
mkdir -p $DL $OUT
cd $DL

curl -fsSLO $DIST/rust-std-$RUST_REV-$TARGET.tar.xz
curl -fsSLO $DIST/rust-src-$RUST_REV.tar.xz
tar xf rust-std-$RUST_REV-$TARGET.tar.xz
tar xf rust-src-$RUST_REV.tar.xz

STD=$DL/rust-std-$RUST_REV-$TARGET/rust-std-$TARGET/lib/rustlib/$TARGET/lib
SRC=$DL/rust-src-$RUST_REV/rust-src/lib/rustlib/src/rust/library

# rustc only reads the rlibs a crate depends on, so the test harness, proc-macro and getopts crates are dead weight here
rm -f $STD/libtest-* $STD/libproc_macro-* $STD/libgetopts-*

# programs linked against this sysroot start in $PWD, so getcwd() and relative paths follow the host's PWD
CWD=$REPO/wasi-libc-patches
"$CWD/scripts/build.sh" >/dev/null
LLD="$(rustc --print target-libdir)/../bin/rust-lld"
WASM_LD="$LLD -flavor wasm" "$CWD/scripts/merge.sh" $STD/self-contained/crt1-command.o "$CWD/dist/cwd-$TARGET.o"

rm -rf $DL/tree && mkdir -p $DL/tree/rustc/lib/rustlib/$TARGET $DL/tree/ra/lib/rustlib/src/rust
cp -r $STD $DL/tree/rustc/lib/rustlib/$TARGET/lib
cp -r $SRC $DL/tree/ra/lib/rustlib/src/rust/library

# rust-analyzer spends most of a cold start parsing std and expanding its macros: ship core, alloc and std pre-expanded
bash $REPO/scripts/setup.sh ra
mkdir -p $RA_SRC/crates/syntax/examples
cp $REPO/tools/strip.rs $RA_SRC/crates/syntax/examples/strip.rs
(cd $RA_SRC && cargo build --release -p syntax --example strip)
python3 $REPO/scripts/slim-std.py $DL/tree/ra/lib/rustlib/src/rust/library $STD $RA_SRC/target/release/examples/strip

# rust-analyzer's file loader reads every file under library/, so unused crates cost time and memory (-21% CPU, -18% RSS).
# Kept in vendor: hashbrown, cfg-if, foldhash, wasip1, rustc-demangle, libc (without hashbrown, HashMap inference breaks).
(cd $DL/tree/ra/lib/rustlib/src/rust/library && rm -rf stdarch portable-simd coretests alloctests backtrace compiler-builtins \
  windows-sys windows_link rtstartup profiler_builtins rustc-std-workspace-*
 # other vendored crates serve other targets (backtrace symbolization, hermit, sgx, uefi, wasip2): diagnostics and hover are identical without them
 cd vendor && for d in *; do
   case $d in cfg-if-*|foldhash-*|hashbrown-*|libc-*|rustc-demangle-*|wasip1-*) ;; *) rm -rf "$d" ;; esac
 done)

tar cf $OUT/sysroot.tar -C $DL/tree/rustc lib
tar cf $OUT/rust-src.tar -C $DL/tree/ra lib

# rust-analyzer cannot spawn rustc or cargo on wasm: answer its queries from this file instead
python3 $REPO/scripts/gen-toolchain-cache.py $SRC /sysroot/lib/rustlib/src/rust/library $TARGET $OUT/toolchain.json

ls -la $OUT
