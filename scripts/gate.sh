#!/usr/bin/env bash
# end-to-end gate: wasm rustc compiles and links (in-process lld) a program against the official rlibs, wasm rust-analyzer reports a type error
set -e

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

WT=${WASMTIME:-wasmtime}
WTFLAGS="-W threads=y -S threads=y"
G=$ROOT/gate
rm -rf $G && mkdir -p $G/sysroot $G/tmp $G/ra/ws $G/ra/tmp $G/ra/sysroot

tar xf $OUT/sysroot.tar -C $G/sysroot

if [ -f $OUT/rustc.wasm ]; then
  echo 'fn main() { println!("Hello World!"); }' > $G/tmp/main.rs
  $WT run $WTFLAGS --env RUST_MIN_STACK=16777216 --dir $G/tmp::/ --dir $G/sysroot::/sysroot \
    $OUT/rustc.wasm /main.rs --sysroot /sysroot --target $TARGET -Copt-level=0 -Cpanic=abort -o /out.wasm
  out=$($WT run $G/tmp/out.wasm)
  [ "$out" = "Hello World!" ] || { echo "rustc gate: unexpected output '$out'"; exit 1; }
  echo "rustc gate: ok"

  mkdir -p $G/cwd/proj
  printf 'fn main() { println!("{:?} {}", std::env::current_dir().unwrap(), std::fs::read_to_string("in.txt").unwrap().trim()); }\n' > $G/cwd/proj/main.rs
  echo hi > $G/cwd/proj/in.txt
  $WT run $WTFLAGS --env PWD=/proj --dir $G/cwd::/ --dir $G/sysroot::/sysroot \
    $OUT/rustc.wasm main.rs --sysroot /sysroot --target $TARGET -Copt-level=0 -Cpanic=abort -o main.wasm
  out=$($WT run --env PWD=/proj --dir $G/cwd::/ $G/cwd/proj/main.wasm)
  [ "$out" = '"/proj" hi' ] || { echo "cwd gate: unexpected output '$out'"; exit 1; }
  echo "cwd gate: ok"
fi

tar xf $OUT/rust-src.tar -C $G/ra/sysroot
cp $OUT/toolchain.json $G/ra/toolchain.json
printf '{"sysroot_src":"/sysroot/lib/rustlib/src/rust/library","crates":[{"root_module":"/ws/main.rs","edition":"2021","deps":[]}]}\n' > $G/ra/ws/rust-project.json
ra() { $WT run $WTFLAGS --dir $G/ra::/ $OUT/rust-analyzer.wasm diagnostics /ws; }

printf 'use std::collections::HashMap;\nfn main() {\n    let mut m: HashMap<String, i32> = HashMap::new();\n    m.insert("a".to_string(), 1);\n    println!("{:?}", m.get("a"));\n}\n' > $G/ra/ws/main.rs
ra
echo "rust-analyzer gate (clean): ok"

printf 'fn main() {}\n' > $G/ra/ws/main.rs
node $REPO/scripts/lsp-gate.mjs "$(command -v $WT)" $OUT/rust-analyzer.wasm $G/ra
