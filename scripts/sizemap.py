import collections, re, subprocess, sys

path = sys.argv[1]
top = int(sys.argv[2]) if len(sys.argv) > 2 else 40
depth = int(sys.argv[3]) if len(sys.argv) > 3 else 1
b = open(path, 'rb').read()


def leb(i):
    r = s = 0
    while True:
        x = b[i]
        i += 1
        r |= (x & 0x7F) << s
        s += 7
        if x < 0x80:
            return r, i


i, nimp, sizes, names, sections = 8, 0, [], {}, collections.Counter()
while i < len(b):
    sid = b[i]
    n, j = leb(i + 1)
    end = j + n
    sections[sid] += n
    if sid == 2:
        cnt, k = leb(j)
        for _ in range(cnt):
            l, k = leb(k)
            k += l
            l, k = leb(k)
            k += l
            kind = b[k]
            k += 1
            if kind == 0:
                _, k = leb(k)
                nimp += 1
            elif kind in (1, 2):
                fl = b[k] if kind == 2 else b[k + 1]
                k += 1 if kind == 2 else 2
                _, k = leb(k)
                k = leb(k)[1] if fl & 1 else k
            elif kind == 3:
                k += 2
            elif kind == 4:
                k += 1
                _, k = leb(k)
    elif sid == 10:
        cnt, k = leb(j)
        for _ in range(cnt):
            sz, k2 = leb(k)
            sizes.append(sz + (k2 - k))
            k = k2 + sz
    elif sid == 0:
        l, k = leb(j)
        if b[k:k + l] == b'name':
            k += l
            while k < end:
                sub = b[k]
                sl, k2 = leb(k + 1)
                if sub == 1:
                    cnt, q = leb(k2)
                    for _ in range(cnt):
                        idx, q = leb(q)
                        nl, q = leb(q)
                        names[idx] = b[q:q + nl].decode('utf-8', 'replace')
                        q += nl
                k = k2 + sl
    i = end

raw = [names.get(nimp + f, f'?{f}') for f in range(len(sizes))]
dem = subprocess.run(['rustfilt'], input='\n'.join(raw), capture_output=True, text=True).stdout.split('\n')

SELF = re.compile(r'^(?:<|&|mut |\*const |\*mut |dyn )*([A-Za-z_][A-Za-z0-9_]*)::')


def key(d):
    m = SELF.match(d.strip())
    if not m:
        return '(unnamed)'
    if depth == 1:
        return m.group(1)
    return '::'.join(re.sub(r'<.*', '', d.strip().lstrip('<&')).split('::')[:depth])


total = sum(sizes)
groups = collections.Counter()
for d, s in zip(dem, sizes):
    groups[key(d)] += s
print(f'{path}: {len(sizes)} functions, code {total / 1e6:.2f} MB, named {len(names)}')
print('sections (MB):', ', '.join(f'{k}={v / 1e6:.2f}' for k, v in sections.most_common(4)))
for k, v in groups.most_common(top):
    print(f'{v / 1e6:8.3f} MB {100 * v / total:5.1f}%  {k}')
