# rust-analyzer spends most of a cold start parsing std and expanding its macros (about 60% natively).
# Expand core, alloc and std once for the target and split the result back into module files (bodies kept):
# same hover docs, completion items and go-to-definition targets.
import glob, os, re, shutil, subprocess, sys

library, std_lib, strip_bin = sys.argv[1:4]
target = 'wasm32-wasip1'
names = ['alloc', 'cfg_if', 'hashbrown', 'std_detect', 'wasip1', 'rustc_demangle', 'unwind', 'panic_unwind', 'panic_abort', 'libc', 'miniz_oxide', 'object', 'addr2line', 'gimli', 'memchr', 'core', 'compiler_builtins']
externs = []
for n in names:
    found = sorted(glob.glob(f'{std_lib}/lib{n}-*.rmeta')) or sorted(glob.glob(f'{std_lib}/lib{n}-*.rlib'))
    if found:
        externs += ['--extern', f'{n}={found[0]}']
env = {**os.environ, 'STD_ENV_ARCH': 'wasm32', 'RUSTC_BOOTSTRAP': '1'}

crates = ['core', 'alloc', 'std']

# expand everything first: std includes core's .md docs, which the replacement below deletes
for crate in crates:
    cmd = ['rustc', '--target', target, '--edition', '2024', '--crate-type', 'lib', '--crate-name', crate, *externs, '-Zunpretty=expanded', f'{library}/{crate}/src/lib.rs']
    r = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f'expanding {crate} failed:\n' + '\n'.join(r.stderr.split('\n')[:20]))
    # the expansion prints pattern types (`u32 is 0..=9`, `*const T is !null`), which rust-analyzer's parser rejects
    text = re.sub(r'\b((?:u8|u16|u32|u64|u128|usize|i8|i16|i32|i64|i128|isize|char))\s+is\s+(?:const\s|\.\.|-?[0-9])[^>;,)\n]*', r'\1', r.stdout)
    text = re.sub(r'\s+is\s+!null\b', '', text)
    # and inner attributes inside expression blocks
    text = text.replace('#![allow(unused_unsafe)]', '')
    open(f'{library}/{crate}.expanded.rs', 'w').write(text)

for crate in crates:
    src = f'{library}/{crate}/src'
    expanded = f'{library}/{crate}.expanded.rs'
    shutil.rmtree(src)
    out = subprocess.run([strip_bin, expanded, src], capture_output=True, text=True, check=True).stdout.strip()
    print(f'{crate}: {out}')
    os.remove(expanded)
