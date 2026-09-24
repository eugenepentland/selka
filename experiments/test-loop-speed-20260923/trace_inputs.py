#!/usr/bin/env python3
"""usage: trace_inputs.py STRACE_LOG WORKTREE [full]

Record the log with `strace -f --seccomp-bpf -y -e trace=execve,openat,chdir,clone,clone3,vfork,fork,newfstatat,statx,access,faccessat2 -o LOG zig build test`.
GITS=1 lists the git commands each step ran instead.

Attribute file accesses in an `strace -f -y` log of `zig build` to build steps.

A "step" is a process whose parent is the Zig maker (the build runner). Every
descendant's accesses are charged to the step it descends from. Prints, per
step label, the worktree-relative directories read (with counts), writes, and
the programs executed.
"""
import re, sys, collections, os

log, root = sys.argv[1], sys.argv[2].rstrip('/') + '/'
FULL = len(sys.argv) > 3
line_re = re.compile(r'^(\d+)\s+(.*)$')
call_re = re.compile(r'^(\w+)\((.*)$')
parent = {}
tgid = {}
argv = {}
pending = {}
events = collections.defaultdict(list)   # pid -> [(kind, path, flags)]

def path_of(rest, name):
    # openat(AT_FDCWD</cwd>, "path", FLAGS) or openat(3</dir>, "sub", ...)
    m = re.match(r'(?:AT_FDCWD<([^>]*)>|AT_FDCWD|\d+<([^>]*)>|-?\d+),\s*"((?:[^"\\]|\\.)*)"(.*)', rest)
    if m:
        base = m.group(1) or m.group(2) or ''
        p = m.group(3)
        full = p if p.startswith('/') else (base + '/' + p if base else p)
        return os.path.normpath(full), m.group(4)
    m = re.match(r'"((?:[^"\\]|\\.)*)"(.*)', rest)
    if m:
        return m.group(1), m.group(2)
    return None, rest

def handle(pid, call, rest, ret):
    if call in ('clone', 'clone3', 'vfork', 'fork'):
        try:
            child = int(ret)
            if child > 0:
                parent[child] = pid
                if 'CLONE_THREAD' in rest:
                    tgid[child] = tgid.get(pid, pid)
        except ValueError:
            pass
    elif call == 'execve':
        m = re.match(r'"([^"]*)", \[(.*?)\]', rest)
        if m and ret.strip().startswith('0'):
            argv[pid] = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(2))
    elif call in ('openat', 'newfstatat', 'statx', 'access', 'faccessat2', 'chdir'):
        p, tail = path_of(rest, call)
        if p is None:
            return
        ok = not ret.strip().startswith('-1')
        kind = 'read'
        if call == 'openat' and re.search(r'O_WRONLY|O_RDWR|O_CREAT', tail):
            kind = 'write'
        elif call != 'openat':
            kind = 'stat'
        events[pid].append((kind, p, ok))

MAKER = None
with open(log, errors='replace') as f:
    for line in f:
        m = line_re.match(line)
        if not m:
            continue
        pid, body = int(m.group(1)), m.group(2)
        if MAKER is None:
            MAKER = pid
        if body.startswith('<...'):
            mm = re.match(r'<\.\.\. (\w+) resumed>(.*)', body)
            if not mm or pid not in pending:
                continue
            call, rest0 = pending.pop(pid)
            full = rest0 + mm.group(2)
            r = full.rsplit(' = ', 1)
            handle(pid, call, r[0], r[1] if len(r) > 1 else '')
            continue
        mm = call_re.match(body)
        if not mm:
            continue
        call, rest = mm.group(1), mm.group(2)
        if rest.endswith('<unfinished ...>'):
            pending[pid] = (call, rest[:-len('<unfinished ...>')])
            continue
        r = rest.rsplit(' = ', 1)
        handle(pid, call, r[0], r[1] if len(r) > 1 else '')

def is_maker(pid):
    return tgid.get(pid, pid) == MAKER

def label(pid):
    a = argv.get(pid, [])
    s = ' '.join(x for x in a[:6])
    s = re.sub(r'/[^ ]*/o/[0-9a-f]{32}/', '$O/', s)
    s = s.replace(root, '')
    return s[:150]

def step_of(pid):
    chain = []
    p = pid
    while p in parent:
        pp = parent[p]
        if is_maker(pp):
            return p
        p = pp
    return None

steps = collections.defaultdict(lambda: {'read': collections.Counter(), 'write': collections.Counter(), 'exec': collections.Counter(), 'stat': collections.Counter()})
for pid, evs in events.items():
    s = step_of(pid)
    if s is None:
        continue
    key = label(s)
    for kind, p, ok in evs:
        if not ok and kind != 'stat':
            continue
        if p.startswith(root):
            rel = p[len(root):]
            if rel.startswith(('.zig-cache', 'zig-out/', '.mylang-cache')):
                continue
            d = rel if FULL else (rel if '/' not in rel else rel.split('/')[0] + '/' + (rel.split('/')[1] if rel.count('/') >= 2 else ''))
            steps[key][kind][d] += 1
    a = argv.get(pid)
    if a and pid != s:
        steps[key]['exec'][os.path.basename(a[0])] += 1

if os.environ.get('GITS'):
    seen = collections.Counter()
    for pid, a in argv.items():
        if os.path.basename(a[0]) == 'git':
            s = step_of(pid)
            seen[(label(s) if s else '?')[:60] + ' :: ' + ' '.join(a[:6])] += 1
    for k, v in sorted(seen.items()):
        print('GIT', v, k)
    sys.exit(0)

for key in sorted(steps):
    st = steps[key]
    print('=== ' + key)
    for kind in ('read', 'write', 'stat'):
        if st[kind]:
            items = sorted(st[kind].items(), key=lambda kv: -kv[1])
            print(f'  {kind}: ' + ', '.join(f'{k}({v})' for k, v in (items if FULL else items[:40])))
    if st['exec']:
        print('  exec: ' + ', '.join(f'{k}({v})' for k, v in st['exec'].most_common(15)))
