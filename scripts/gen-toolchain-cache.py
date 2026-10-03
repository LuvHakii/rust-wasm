import json, os, subprocess, sys

src, vfs, target, out = sys.argv[1:5]
src = os.path.abspath(src)
env = {**os.environ, 'RUSTC_BOOTSTRAP': '1', '__CARGO_TEST_CHANNEL_OVERRIDE_DO_NOT_USE_THIS': 'nightly'}
manifest = f'{src}/Cargo.toml'
vfs_manifest = f'{vfs}/Cargo.toml'

COMMANDS = [
    ['rustc', '-vV'],
    ['rustc', '--version'],
    ['rustc', '--print', 'cfg', '-O', '--target', target],
    ['rustc', '-Z', 'unstable-options', '--print', 'target-spec-json', '--target', target],
    ['cargo', 'metadata', '--format-version', '1', '--no-deps', '--manifest-path', manifest, '--filter-platform', target],
    ['cargo', 'metadata', '--format-version', '1', '--manifest-path', manifest, '--filter-platform', target, '-Zunstable-options'],
]

table = {}
for argv in COMMANDS:
    stdout = subprocess.run(argv, env=env, cwd=src, capture_output=True, text=True, check=True).stdout.strip()
    if argv[:2] == ['rustc', '-vV']:
        stdout = '\n'.join(f'host: {target}' if line.startswith('host:') else line for line in stdout.split('\n'))
    key = ' '.join(a.replace(manifest, vfs_manifest) for a in argv)
    table[key] = stdout.replace(src, vfs)

json.dump(table, open(out, 'w'), separators=(',', ':'))
for key, value in table.items():
    print(f'{len(value):9d}  {key[:150]}')
