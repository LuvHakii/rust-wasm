# usage: apply-rules.py <src> <rules.yml> [files-dir]
# Applies ast-grep rules to <src> after checking every rule matches exactly `metadata.expect` times, so a stale rule
# fails loudly on an upstream bump instead of silently changing nothing. files-dir is copied over <src> (new files).
import os, re, shutil, subprocess, sys, tempfile

src, rules = sys.argv[1:3]
ast_grep = os.environ.get('AST_GREP', 'npx --yes @ast-grep/cli@0.45.3').split()

for doc in open(rules).read().split('\n---\n'):
    rule_id = re.search(r'^id: (\S+)', doc, re.M).group(1)
    expect = int(re.search(r'expect: (\d+)', doc).group(1))
    with tempfile.NamedTemporaryFile('w', suffix='.yml') as f:
        f.write(doc)
        f.flush()
        out = subprocess.run([*ast_grep, 'scan', '-r', f.name, '--json=stream', '.'], cwd=src, capture_output=True, text=True, check=True).stdout
    found = len([line for line in out.split('\n') if line.startswith('{')])
    if found != expect:
        sys.exit(f'{rules}: rule {rule_id} matches {found}, expected {expect}; update it for this upstream')

subprocess.run([*ast_grep, 'scan', '-r', rules, '-U', '.'], cwd=src, check=True)
if len(sys.argv) > 3:
    shutil.copytree(sys.argv[3], src, dirs_exist_ok=True)
print(f'applied {rules}')
