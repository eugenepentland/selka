#!/usr/bin/env python3
"""Reproduce only the predecessor C/M/runner -> S2 function/site identity proof.

All inputs are local complete LLVM modules pinned by the historical receipt.
This is not full-module identity, performance qualification, or final S3-X.
Default execution is read-only and prints the deterministic receipt as JSON.
"""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re


AREA = Path(__file__).resolve().parent
TOKEN = r'("(?:[^"\\]|\\.)*"|[-A-Za-z$._0-9]+)'
FUNCTION = re.compile(r'^define [^\n]*\n.*?^\}$', re.M | re.S)
BASELINE = '92590700cb0bf5e4dc19cc1f0c836c3a41693f64'
PREDECESSOR = '9637eb9a1aa4af8ee0ecd88838ceed09b228d812'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def functions(text):
    matches = list(FUNCTION.finditer(text))
    header_count = len(re.findall(r'^define ', text, re.M))
    require(len(matches) == header_count, 'Incomplete definition extraction')
    out = {}
    for match in matches:
        body = match.group()
        # Only the definition header supplies its key. A body call cannot
        # substitute for an unrecognized dotted helper name.
        header = body.splitlines()[0]
        symbol = re.search(r'@' + TOKEN + r'\(', header)
        require(symbol is not None, 'Unrecognized definition header: ' + header)
        name = symbol[1]
        require(name not in out, 'Duplicate definition header: ' + name)
        out[name] = body
    return out, matches


def sites(text):
    pairs = re.findall(r'^@(myl\.(?:op|fn)\.\d+) = .* c"([^"]*)"', text, re.M)
    require(len(dict(pairs)) == len(pairs), 'Duplicate semantic site string')
    strings = dict(pairs)
    tables = re.findall(r'^@myl_core_sites = constant .*', text, re.M)
    require(len(tables) == 1, 'Expected one complete site table')
    table = tables[0]
    count = int(re.search(r'= constant \[(\d+) x %myl.site\]', table)[1])
    entries = re.findall(
        r'%myl.site \{ i32 (\d+), i32 (\d+), i32 (\d+), i32 (\d+), '
        r'ptr @(myl.op.\d+), ptr @(myl.fn.\d+) \}', table)
    require(len(entries) == count, 'Incomplete semantic site table extraction')
    return [tuple(map(int, e[:4])) + (strings[e[4]], strings[e[5]]) for e in entries]


def debug(text):
    scopes = dict(re.findall(
        r'^!(\d+) = distinct !DISubprogram\(name: "([^"]+)"', text, re.M))
    out = {key: ('function', value) for key, value in scopes.items()}
    for key, line, column, scope in re.findall(
            r'^!(\d+) = !DILocation\(line: (\d+), column: (\d+), scope: !(\d+)\)',
            text, re.M):
        out[key] = ('location', int(line), int(column), scopes[scope])
    return out


def normalize(function, site_table, debug_table):
    function = re.sub(r'!dbg !(\d+)', lambda m: '!dbg ' + repr(debug_table[m[1]]), function)
    function = re.sub(
        r'(@myl_core_(?:trap|err_trace)\(i32) (\d+)',
        lambda m: m[1] + ' SITE' + repr(site_table[int(m[2])]), function)
    # No opcode, call, flag, CFG edge, parameter, label, or named type is removed.
    # Only SSA values defined by instructions can be alpha-renamed.
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
            require(current not in edges, 'Duplicate basic block: ' + current)
            edges[current] = set()
        elif current:
            edges[current].update(re.findall(r'label %([A-Za-z0-9_.]+)', line))
    cyclic = set()
    for start in edges:
        pending = list(edges[start])
        seen = set()
        while pending:
            node = pending.pop()
            if node == start:
                cyclic.add(start)
                break
            if node not in seen:
                seen.add(node)
                pending.extend(edges.get(node, ()))
    return cyclic


def authority(function, name):
    pairs = list(re.finditer(
        r'^  call void @myl_core_io_at\(i32 (\d+)\)\n'
        r'  call void @myl_core_host_check\(i64 %p1\), !dbg !(\d+)\n'
        r'(?=  %v\d+ = call i64 @runtime_bench_now\(\))', function, re.M))
    boundary = []
    details = []
    if name.endswith('::main"'):
        require(len(pairs) == 2, 'Expected two source-main Host guard pairs: ' + name)
        require(function.count('call i64 @runtime_bench_now()') == 2,
                'Unexpected native timer call count: ' + name)
        cyclic = cycle_blocks(function)
        for pair in pairs:
            blocks = re.findall(r'^([A-Za-z0-9_.]+):$', function[:pair.start()], re.M)
            require(bool(blocks), 'Guard outside a named block: ' + name)
            block = blocks[-1]
            require(block not in cyclic, 'Guard is in a CFG cycle: ' + name + ':' + block)
            point = dict(site=int(pair[1]), block=block, in_cfg_cycle=False,
                         timer_adjacency='immediately before native timer call')
            boundary.append(point)
            details.append(dict(point, debug_id=pair[2], exact_removed_text=pair.group()))
    else:
        require(not pairs, 'Unexpected guard pair in helper: ' + name)
    require(function.count('call void @myl_core_host_check') == len(pairs),
            'Unmatched Host check in ' + name)
    require(function.count('call void @myl_core_io_at') == len(pairs),
            'Unmatched location setter in ' + name)
    for pair in reversed(pairs):
        function = function[:pair.start()] + function[pair.end():]
    grant = 0
    if name == 'main':
        function, grant = re.subn(
            r'^  %host1 = call i64 @myl_core_host_grant\(\)\n', '', function, flags=re.M)
        require(grant == 1 and function.count('%host1') == 1,
                'Native entry Host grant is not the exact single-use insertion')
        require(re.search(r'^  %r = call .*::main"\(ptr %args, i64 %host1, i64 1\)',
                          function, re.M) is not None, 'Unexpected entry Host operand use')
        function = function.replace('%host1', '1')
    require('myl_core_host_grant' not in function, 'Unaccounted Host grant: ' + name)
    return function, boundary, details, grant


def outside_functions(text, matches):
    # Inventory only. This remainder is never normalized, compared as a proof,
    # or dropped to claim complete-module equivalence.
    chunks = []
    previous = 0
    for match in matches:
        chunks.append(text[previous:match.start()])
        previous = match.end()
    chunks.append(text[previous:])
    return ''.join(chunks)


def run(write_raw_diffs):
    manifest_path = AREA / 'authority/provenance.json'
    manifest = json.loads(manifest_path.read_text())
    require(manifest['baseline_source_commit'] == BASELINE, 'Unexpected baseline authority')
    require(manifest['predecessor_source_commit'] == PREDECESSOR, 'Unexpected C authority')
    receipt_path = AREA / manifest['historical_receipt']
    contract_path = AREA / manifest['source_contract']
    require(sha(receipt_path.read_bytes()) == manifest['historical_receipt_sha256'],
            'Historical receipt SHA mismatch')
    require(sha(contract_path.read_bytes()) == manifest['source_contract_sha256'],
            'Source contract SHA mismatch')
    contract = json.loads(contract_path.read_text())
    require(contract['source_commit'] == PREDECESSOR, 'Source contract commit mismatch')
    historical = json.loads(receipt_path.read_text())
    recorded = {row['row']: row for row in historical['rows']}
    require(len(recorded) == len(historical['rows']) == 35, 'Historical row collision/count')
    rows = manifest['rows']
    require(len({row['row'] for row in rows}) == len(rows) == 35, 'Manifest row collision/count')
    require(set(recorded) == {row['row'] for row in rows}, 'Manifest/historical rows differ')
    expected_files = {row['row'] + '.ll' for row in rows}
    for side in ('before', 'after'):
        require({p.name for p in (AREA / side).iterdir()} == expected_files,
                'Incomplete or extra local LLVM inputs: ' + side)
    results = []
    total_functions = total_pairs = total_grants = 0
    for row in rows:
        name = row['row']
        old_data = (AREA / 'before' / (name + '.ll')).read_bytes()
        new_data = (AREA / 'after' / (name + '.ll')).read_bytes()
        old_sha, new_sha = sha(old_data), sha(new_data)
        record = recorded[name]
        require(old_sha == row['before_sha256'] == record['baseline_sha256'],
                'Complete baseline LLVM SHA mismatch: ' + name)
        require(new_sha == row['after_sha256'] == record['emitted_sha256'],
                'Complete C LLVM SHA mismatch: ' + name)
        old_text, new_text = old_data.decode(), new_data.decode()
        raw = ''.join(difflib.unified_diff(
            old_text.splitlines(True), new_text.splitlines(True),
            fromfile='before/' + name + '.ll', tofile='after/' + name + '.ll'))
        raw_path = AREA / 'raw-diffs' / (name + '.diff')
        if write_raw_diffs:
            with raw_path.open('x') as stream:
                stream.write(raw)
        require(raw_path.read_text() == raw, 'Full raw module diff mismatch: ' + name)
        left, old_matches = functions(old_text)
        right, new_matches = functions(new_text)
        require(left.keys() == right.keys(), 'Actual function names differ: ' + name)
        old_sites, new_sites = sites(old_text), sites(new_text)
        old_debug, new_debug = debug(old_text), debug(new_text)
        boundaries, boundary_details, removed, residual, changed = {}, {}, set(), [], []
        grants = 0
        for symbol, body in right.items():
            if left[symbol] != body:
                changed.append(symbol)
            prepared, points, details, grant = authority(body, symbol)
            grants += grant
            total_pairs += len(points)
            if points:
                boundaries[symbol] = points
                for detail in details:
                    detail['semantic_site'] = new_sites[detail['site']]
                    detail['semantic_debug'] = new_debug[detail.pop('debug_id')]
                boundary_details[symbol] = details
                removed.update(point['site'] for point in points)
            expected = normalize(left[symbol], old_sites, old_debug)
            observed = normalize(prepared, new_sites, new_debug)
            if expected != observed:
                residual.append(dict(function=symbol, diff=''.join(difflib.unified_diff(
                    expected.splitlines(True), observed.splitlines(True),
                    fromfile='baseline function', tofile='C function'))))
        require(boundaries == record['authority_boundaries'],
                'Exact boundary authority differs from historical receipt: ' + name)
        require(len(removed) == 2 and grants == record['entry_grants'] == 1,
                'Unexpected Host removal count: ' + name)
        require([site for index, site in enumerate(new_sites) if index not in removed] == old_sites,
                'Residual complete semantic site table change: ' + name)
        require(len(new_sites) == len(old_sites) + 2, 'Unexpected site table length: ' + name)
        total_functions += len(left)
        total_grants += grants
        old_remainder = outside_functions(old_text, old_matches)
        new_remainder = outside_functions(new_text, new_matches)
        results.append(dict(
            row=name, before_sha256=old_sha, after_sha256=new_sha,
            complete_input_sha_matches_historical_receipt=True,
            definitions_before=len(left), definitions_after=len(right),
            definition_names=list(left), raw_changed_functions=changed,
            timer_guard_pairs=sum(map(len, boundaries.values())),
            authority_boundaries=boundary_details, entry_grants=grants,
            complete_semantic_site_table_equal_after_two_guard_sites=True,
            baseline_site_count=len(old_sites), predecessor_site_count=len(new_sites),
            residual_functions=residual,
            raw_module_diff='raw-diffs/' + name + '.diff', raw_module_diff_sha256=sha(raw.encode()),
            outside_function_scope=dict(status='not_qualified',
                before_sha256=sha(old_remainder.encode()), after_sha256=sha(new_remainder.encode()),
                before_bytes=len(old_remainder.encode()), after_bytes=len(new_remainder.encode()))))
    require(total_functions == 343, 'Unexpected complete definition count')
    require(total_pairs == 70 and total_grants == 35, 'Unexpected total authorized edits')
    residual_count = sum(len(row['residual_functions']) for row in results)
    return dict(
        schema='s3-predecessor-function-identity-retrospective-v1',
        scope='Only predecessor C/M/runner 9637eb9a1 -> S2 92590700 function/site identity',
        baseline_source_commit=BASELINE, predecessor_source_commit=PREDECESSOR,
        proof_script_sha256=sha(Path(__file__).read_bytes()),
        provenance_manifest_sha256=sha(manifest_path.read_bytes()),
        complete_modules=35, actual_definitions=total_functions,
        exact_timer_guard_pairs=total_pairs, exact_native_entry_grants=total_grants,
        complete_semantic_site_tables_checked=35, residual_function_count=residual_count,
        qualified_within_function_and_site_scope=residual_count == 0,
        full_module_identity_qualified=False,
        outside_function_scope='Not qualified: declarations, globals, attributes, and other module-level content remain in complete raw LLVM and diffs without equivalence claims.',
        final_s3_x_qualified=False,
        limitations=[
            'Static retained-input proof only; no builds, compiler tests, runtime tests, performance, or final S3-X gates run.',
            'Historical SHA receipt pins complete inputs; this does not independently rebuild source commits.',
            'Only instruction-defined SSA alpha-renaming and semantic site/debug ID resolution accompany the exact 70 guard-pair and 35 entry-grant removals.',
            'Every header is parsed separately with dotted/quoted names and duplicate rejection; no helper-body overwrite or wholesale function removal.'],
        rows=results)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write-raw-diffs', action='store_true',
                        help='Initial capture only; create each raw diff exclusively, refusing overwrite')
    parser.add_argument('--output', type=Path,
                        help='Optional fresh JSON output path; existing files are never overwritten')
    args = parser.parse_args()
    if args.output is not None:
        require(not args.output.exists(), 'Refusing existing output: ' + str(args.output))
    summary = run(args.write_raw_diffs)
    rendered = json.dumps(summary, indent=2) + '\n'
    if args.output is None:
        print(rendered, end='')
    else:
        with args.output.open('x') as stream:
            stream.write(rendered)
        print(f"35 modules; {summary['actual_definitions']} definitions; "
              f"70 guard pairs; 35 entry grants; {summary['residual_function_count']} residuals; "
              'outside-function module content unqualified')
    return int(not summary['qualified_within_function_and_site_scope'])


if __name__ == '__main__':
    raise SystemExit(main())
