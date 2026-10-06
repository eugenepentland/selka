#!/usr/bin/env python3
"""Audit the exact authorized C additions to already emitted 35-row LLVM.

Keep raw diffs. Only remove the Host grant in native main and the adjacent
io_at/host_check pair immediately before each of two native timer calls in the
source main. Prove both pairs lie outside CFG cycles. Compare every remaining
instruction after alpha-renaming SSA names and resolving site/debug IDs to
their original semantic metadata. This is not a performance qualification.
"""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[4]


def functions(text):
    return {re.search(r'@("[^"]+"|\w+)\(', f)[1]: f
            for f in re.findall(r'^define .*?^\}', text, re.M | re.S)}


def sites(text):
    strings = dict(re.findall(r'^@(myl\.(?:op|fn)\.\d+) = .* c"([^"]*)"', text, re.M))
    table = re.search(r'^@myl_core_sites = constant .*', text, re.M)[0]
    entries = re.findall(r'%myl.site \{ i32 (\d+), i32 (\d+), i32 (\d+), i32 (\d+), ptr @(myl.op.\d+), ptr @(myl.fn.\d+) \}', table)
    return [tuple(map(int, e[:4])) + (strings[e[4]], strings[e[5]]) for e in entries]


def debug(text):
    scopes = dict(re.findall(r'^!(\d+) = distinct !DISubprogram\(name: "([^"]+)"', text, re.M))
    out = {key: ('function', value) for key, value in scopes.items()}
    for key, line, column, scope in re.findall(r'^!(\d+) = !DILocation\(line: (\d+), column: (\d+), scope: !(\d+)\)', text, re.M):
        out[key] = ('location', int(line), int(column), scopes[scope])
    return out


def normalize(function, site_table, debug_table):
    function = re.sub(r'!dbg !(\d+)', lambda m: '!dbg ' + repr(debug_table[m[1]]), function)
    function = re.sub(r'(@myl_core_(?:trap|err_trace)\(i32) (\d+)',
                      lambda m: m[1] + ' SITE' + repr(site_table[int(m[2])]), function)
    # Preserve parameter names, CFG labels and any named LLVM types. Only
    # instruction-defined SSA values can vary with inserted call numbering.
    values = set(re.findall(r'^  (%[A-Za-z0-9_.]+) =', function, re.M))
    names = {}
    def alpha(match):
        if match[0] not in values:
            return match[0]
        names.setdefault(match[0], f'%SSA{len(names)}')
        return names[match[0]]
    return re.sub(r'%[A-Za-z0-9_.]+', alpha, function)


def cycle_blocks(function):
    edges = {}
    current = None
    for line in function.splitlines():
        label = re.fullmatch(r'([A-Za-z0-9_.]+):', line)
        if label:
            current = label[1]
            edges[current] = set()
        elif current:
            edges[current].update(re.findall(r'label %([A-Za-z0-9_.]+)', line))
    cyclic = set()
    for start in edges:
        pending = list(edges[start]); seen = set()
        while pending:
            node = pending.pop()
            if node == start:
                cyclic.add(start); break
            if node not in seen:
                seen.add(node); pending.extend(edges.get(node, ()))
    return cyclic


def authority(function, name):
    pairs = list(re.finditer(
        r'^  call void @myl_core_io_at\(i32 (\d+)\)\n'
        r'  call void @myl_core_host_check\(i64 %p1\), !dbg !\d+\n'
        r'(?=  %v\d+ = call i64 @runtime_bench_now\(\))', function, re.M))
    boundary = []
    if '::main"' in name:
        assert len(pairs) == 2, (name, len(pairs))
        assert function.count('call i64 @runtime_bench_now()') == 2
        cyclic = cycle_blocks(function)
        for pair in pairs:
            block = re.findall(r'^([A-Za-z0-9_.]+):$', function[:pair.start()], re.M)[-1]
            assert block not in cyclic, (name, block, cyclic)
            boundary.append(dict(site=int(pair[1]), block=block, in_cfg_cycle=False,
                                 timer_adjacency='immediately before native timer call'))
    else:
        assert not pairs, name
    assert function.count('call void @myl_core_host_check') == len(pairs), name
    assert function.count('call void @myl_core_io_at') == len(pairs), name
    for pair in reversed(pairs):
        function = function[:pair.start()] + function[pair.end():]
    grant = 0
    if name == 'main':
        function, grant = re.subn(r'^  %host1 = call i64 @myl_core_host_grant\(\)\n', '', function, flags=re.M)
        assert grant == 1 and function.count('%host1') == 1
        assert re.search(r'^  %r = call .*::main"\(ptr %args, i64 %host1, i64 1\)', function, re.M)
        function = function.replace('%host1', '1')
    assert 'myl_core_host_grant' not in function
    return function, boundary, grant


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-id', required=True)
    args = parser.parse_args()
    area = Path(__file__).resolve().parent / args.run_id
    area.mkdir()
    rows = []
    for after in sorted((ROOT / '.mylang-cache/s3/identity').glob('*.ll')):
        before = ROOT / '.mylang-cache/s3/baseline' / after.name
        old_text, new_text = before.read_text(), after.read_text()
        old_funcs, new_funcs = functions(old_text), functions(new_text)
        assert old_funcs.keys() == new_funcs.keys(), after.name
        old_sites, new_sites = sites(old_text), sites(new_text)
        old_debug, new_debug = debug(old_text), debug(new_text)
        raw = ROOT / '.mylang-cache/s3/identity' / (after.stem + '.diff')
        shutil.copy2(raw, area / raw.name)
        changed, boundaries, grants, residual = [], {}, 0, []
        for name, new_function in new_funcs.items():
            if old_funcs[name] != new_function:
                changed.append(name)
            prepared, boundary, grant = authority(new_function, name)
            if boundary:
                boundaries[name] = boundary
            grants += grant
            expected = normalize(old_funcs[name], old_sites, old_debug)
            observed = normalize(prepared, new_sites, new_debug)
            if expected != observed:
                residual.append(name)
                (area / (after.stem + '.normalized.diff')).write_text(''.join(difflib.unified_diff(
                    expected.splitlines(True), observed.splitlines(True), fromfile='baseline', tofile='C')))
        removed = {item['site'] for points in boundaries.values() for item in points}
        assert [site for i, site in enumerate(new_sites) if i not in removed] == old_sites
        assert len(removed) == 2 and grants == 1
        rows.append(dict(row=after.stem, baseline_sha256=hashlib.sha256(before.read_bytes()).hexdigest(),
                         emitted_sha256=hashlib.sha256(after.read_bytes()).hexdigest(),
                         raw_changed_functions=changed, authority_boundaries=boundaries,
                         entry_grants=grants, residual_functions=residual))
        print(after.stem + ': ' + ('residual' if residual else 'only proved Host scaffolding/numbering'), flush=True)
    assert len(rows) == 35
    summary = dict(rows=rows, qualified=not any(row['residual_functions'] for row in rows),
                   limit='Code audit only; final 40-row performance and operation counts are still required.')
    (area / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(f"35 rows; {sum(bool(row['residual_functions']) for row in rows)} residual changes")
    return int(not summary['qualified'])


if __name__ == '__main__':
    raise SystemExit(main())
