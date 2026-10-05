#!/usr/bin/env python3
"""Audit caller-visible RC in every natural innermost loop of all 35 row programs.

Compile saved LLVM with exactly the release driver's CPU flags into optimized
LLVM and annotated assembly. Count stores tagged myl.count, with constant-one
stores labeled for initialization/release review, separate from count loads/checks. Propagate proven
saturated globals through pointer selects/phis; a saturated check is not a store.
LLVM CFG dominance finds each natural loop, including independent shallow loops
that a whole-file maximum-depth audit would miss. Parent-loop exclusive blocks
are also reported, avoiding double counting nested loops.

Assembly loop annotations corroborate location. Memory-write instructions in
blocks containing an IR count store are candidates, not a register-allocation
proof that every instruction writes a count. Runtime alloc/COW/free calls remain
separate opaque sites: this audit does not inspect C helper bodies, callee RC,
dynamic executions, or allocation headers merged into untagged wide stores.
All program loops are included, including input construction and inlined setup;
function/header identities let reviewers locate repeated kernels. This is a
static audit, not a claim that all listed conditional stores execute.

Run under scripts/build-slot.sh build. --reuse reads existing .opt.ll/.s artifacts.
--smoke-test checks synthetic Python parser/CFG cases without native compilation.
"""
import argparse
from collections import Counter
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

SPEC = importlib.util.spec_from_file_location("all35_rows", Path(__file__).with_name("measure_all35.py"))
ROWS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ROWS)
TOKEN = r'(?:"[^"\n]+"|[-A-Za-z$._0-9]+)'
REF = r'(?:%' + TOKEN + r'|@' + TOKEN + r')'


def name(value):
    return value.strip('"')


def count_tags(source):
    nodes = dict(re.findall(r'^!(\d+) = (.*)$', source, re.M))
    leaves = {key for key, value in nodes.items() if '!"myl.count"' in value}
    return leaves | {key for key, value in nodes.items()
                     if (refs := re.findall(r'!(\d+)', value)) and len(refs) >= 2 and refs[0] == refs[1] and refs[0] in leaves}


def saturated(source, lines):
    known = set(re.findall(r'^(@' + TOKEN + r') = .*\bconstant\b.*\}\s*\{\s*i32 -1,', source, re.M))
    definitions = dict(re.findall(r'^\s*(%' + TOKEN + r') = (.*)$', '\n'.join(lines), re.M))
    changed = True
    while changed:
        changed = False
        for ref, expression in definitions.items():
            if ref in known:
                continue
            values = []
            if expression.startswith('select '):
                values = re.findall(r'ptr\s+(' + REF + r')', expression)
            elif expression.startswith('phi ptr '):
                values = re.findall(r'\[\s*(' + REF + r')\s*,', expression)
            if values and all(value in known for value in values):
                known.add(ref)
                changed = True
    return known


def functions(source):
    for match in re.finditer(r'^define[^\n]*@(' + TOKEN + r')[^\n]*\{\n(.*?)^\}', source, re.M | re.S):
        blocks = {}
        current = None
        for line in match[2].splitlines():
            label = re.match(r'^(' + TOKEN + r'):', line)
            if label:
                current = name(label[1])
                blocks.setdefault(current, [])
            else:
                if current is None:
                    if not line.strip() or line.lstrip().startswith(';'):
                        continue
                    current = 'entry'
                    blocks.setdefault(current, [])
                blocks[current].append(line)
        if blocks:
            yield name(match[1]), blocks


def natural_loops(blocks):
    successors = {block: {name(target) for target in re.findall(r'\blabel %(' + TOKEN + r')', '\n'.join(lines))}
                  for block, lines in blocks.items()}
    reachable = set()
    pending = [next(iter(blocks))]
    while pending:
        block = pending.pop()
        if block in reachable or block not in blocks:
            continue
        reachable.add(block)
        pending.extend(successors[block])
    predecessors = {block: {parent for parent in reachable if block in successors[parent]} for block in reachable}
    entry = next(iter(blocks))
    dom = {block: ({entry} if block == entry else set(reachable)) for block in reachable}
    changed = True
    while changed:
        changed = False
        for block in reachable - {entry}:
            common = set.intersection(*(dom[parent] for parent in predecessors[block])) if predecessors[block] else set()
            updated = {block} | common
            if updated != dom[block]:
                dom[block] = updated
                changed = True
    loops = {}
    for latch in reachable:
        for header in successors[latch] & dom[latch]:
            body = {header, latch}
            pending = [] if latch == header else [latch]
            while pending:
                block = pending.pop()
                for parent in predecessors[block] - body:
                    body.add(parent)
                    if parent != header:
                        pending.append(parent)
            loops.setdefault(header, set()).update(body)
    return loops


def call_kind(symbol):
    if symbol.startswith('llvm.'):
        return 'intrinsic'
    if symbol.startswith('myl_core_'):
        if 'free' in symbol or 'release' in symbol:
            return 'runtime_free_or_release'
        if symbol in ('myl_core_ir_str_char', 'myl_core_args') or any(part in symbol for part in ('alloc', 'new', 'copy', 'grow', 'reserve', 'append', 'push', 'insert', 'concat', 'join', 'split', 'from_view', 'str_from', 'bytes_from', 'materialize', 'str_slice', 'bytes_slice', 'to_list', 'sort')):
            return 'runtime_alloc_or_cow_candidate'
        return 'runtime_other_opaque'
    return 'callee_opaque'


def block_metrics(lines, tags, immortals):
    result = {'count_stores': 0, 'constant_one_count_stores': 0, 'other_constant_count_stores': 0,
              'saturated_count_reads': 0, 'dynamic_count_reads': 0, 'calls': {}, 'count_store_ir': []}
    calls = Counter()
    for line in lines:
        tag = re.search(r'!tbaa !(\d+)', line)
        counted = tag is not None and tag[1] in tags
        if counted and re.search(r'\bstore\b', line):
            constant = re.search(r'\bstore(?: volatile)? i\d+ (-?[0-9]+),', line)
            result['count_stores'] += 1
            if constant:
                result['constant_one_count_stores' if constant[1] == '1' else 'other_constant_count_stores'] += 1
            result['count_store_ir'].append(line.strip())
        if counted and re.search(r'\bload\b', line):
            pointer = re.search(r'\bptr\s+(' + REF + r')', line)
            result['saturated_count_reads' if pointer and pointer[1] in immortals else 'dynamic_count_reads'] += 1
        if re.search(r'\b(?:call|invoke)\b', line):
            symbol = re.search(r'@(' + TOKEN + r')\s*\(', line)
            target = name(symbol[1]) if symbol else '<indirect>'
            category = call_kind(target)
            if category != 'intrinsic':
                calls[f'{category}:{target}'] += 1
    result['calls'] = dict(sorted(calls.items()))
    return result


def combine(metrics):
    result = {key: 0 for key in ('count_stores', 'constant_one_count_stores', 'other_constant_count_stores',
                                'saturated_count_reads', 'dynamic_count_reads')}
    calls = Counter()
    for value in metrics:
        for key in result:
            result[key] += value[key]
        calls.update(value['calls'])
    return {**result, 'calls': dict(sorted(calls.items()))}


def audit_ir(source):
    tags = count_tags(source)
    result = []
    by_block = {}
    for function, blocks in functions(source):
        immortals = saturated(source, [line for lines in blocks.values() for line in lines])
        metrics = {block: block_metrics(lines, tags, immortals) for block, lines in blocks.items()}
        by_block[function] = metrics
        loops = natural_loops(blocks)
        for header, body in loops.items():
            children = [other for other in loops.values() if other < body]
            exclusive = body - set().union(*children) if children else body
            result.append({'function': function, 'header': header,
                           'depth': 1 + sum(body < other for other in loops.values()), 'innermost': not children,
                           'blocks': sorted(body), 'exclusive_blocks': sorted(exclusive),
                           'inclusive': combine(metrics[block] for block in body),
                           'exclusive': combine(metrics[block] for block in exclusive)})
    return sorted(result, key=lambda loop: (loop['function'], loop['header'])), by_block


def audit_assembly(source, by_block):
    function = block = label = None
    loop = None
    loops = {}
    for line in source.splitlines():
        begin = re.search(r'\.type\s+(' + TOKEN + r'),\s*@function', line)
        if begin:
            function = name(begin[1])
            block = label = loop = None
        actual_label = re.match(r'^(\.LBB\d+_\d+):', line)
        comment_block = re.match(r'^\s*# %bb\.\d+:', line)
        if actual_label or comment_block:
            label = actual_label[1] if actual_label else None
            refs = re.findall(r'# %(' + TOKEN + r')', line)
            block = name(refs[-1]) if refs and not refs[-1].startswith('bb.') else None
            loop = None
        header = re.search(r'This(?: Inner)? Loop Header: Depth=(\d+)', line)
        member = re.search(r'in Loop: Header=(BB\d+_\d+) Depth=(\d+)', line)
        if header and label:
            loop = (function, label)
            entry = loops.setdefault(loop, {'function': function, 'header': label,
                                           'count_store_block_memory_write_candidates': [], 'calls': {}})
            entry.update(ir_header=block, depth=int(header[1]), innermost='Inner Loop Header' in line)
        elif member:
            loop = (function, '.L' + member[1])
            loops.setdefault(loop, {'function': function, 'header': loop[1], 'ir_header': None,
                                    'depth': int(member[2]), 'innermost': None,
                                    'count_store_block_memory_write_candidates': [], 'calls': {}})
        if loop not in loops:
            continue
        entry = loops[loop]
        metric = by_block.get(function, {}).get(block, {})
        instruction = re.match(r'^\s*(movl|incl|decl|addl|subl|andl|orl|xorl)\s+(.+)', line)
        if metric.get('count_store_ir') and instruction and instruction[2].rstrip().endswith(')'):
            entry['count_store_block_memory_write_candidates'].append({'ir_block': block, 'instruction': line.strip()})
        call = re.match(r'^\s*(?:call\w*|jmp\w*)\s+([^\s#]+)', line)
        if call:
            target = call[1].removesuffix('@PLT')
            if target.startswith('.L'):
                continue
            category = call_kind(target)
            key = f'{category}:{target}'
            entry['calls'][key] = entry['calls'].get(key, 0) + 1
    return sorted(loops.values(), key=lambda loop: (loop['function'] or '', loop['header']))


def compile_artifacts(args, selected):
    for row in selected:
        source = args.bin / 'llvm' / f'{ROWS.stem(row)}.ll'
        if not source.is_file():
            raise ValueError(f'LLVM missing: {source}; measure_all35.py --build saves it')
        for option, suffix in ((('-S', '-emit-llvm'), '.opt.ll'), (('-S',), '.s')):
            output = source.with_suffix(suffix)
            output.unlink(missing_ok=True)
            command = [args.zig, 'cc', '-O3', *ROWS.CPU_FLAGS, '-Wno-override-module', *option, str(source), '-o', str(output)]
            done = subprocess.run(command, capture_output=True, text=True)
            if done.returncode or not output.is_file():
                raise ValueError(f'audit compile status={done.returncode}: {command}\n{done.stdout}{done.stderr}')


def smoke():
    source = '''@myl.str.0 = private constant {i32, i32} {i32 -1, i32 1}
define i32 @main() {
entry:
  br label %outer
outer:
  %s = select i1 true, ptr @myl.str.0, ptr @myl.str.0
  %rc.0 = load i32, ptr %s, !tbaa !3
  br label %inner
inner:
  %rc.1 = load i32, ptr %object, !tbaa !3
  %rn.2 = add i32 %rc.1, 1
  store i32 %rn.2, ptr %object, !tbaa !3
  call ptr @myl_core_list_copy(ptr %object, i64 8)
  br i1 true, label %inner, label %after
after:
  br i1 true, label %outer, label %exit
exit:
  ret i32 0
}
!2 = !{!"myl.count", !0}
!3 = !{!2, !2, i64 0}
'''
    loops, blocks = audit_ir(source)
    inner = next(loop for loop in loops if loop['innermost'])
    outer = next(loop for loop in loops if not loop['innermost'])
    assert inner['depth'] == 2 and inner['exclusive']['count_stores'] == 1
    assert outer['exclusive']['count_stores'] == 0 and outer['exclusive']['saturated_count_reads'] == 1
    assert len(audit_ir(source.replace('entry:', 'b0:'))[0]) == 2
    separate = '''define void @independent() {
b0:
  br label %scan
scan:
  %rc.9 = load i32, ptr @myl.str.0, !tbaa !3
  br i1 true, label %scan, label %exit
exit:
  ret void
}
'''
    assert sum(loop['innermost'] for loop in audit_ir(source + separate)[0]) == 2
    assert len(audit_ir(source.replace('!"myl.count"', '!"other"'))[0]) == 2
    assembly = ''' .type main,@function
main:
.LBB0_1: # %outer
  # =>This Loop Header: Depth=1
  movl (%rdi), %eax
.LBB0_2: # %inner
  # =>This Inner Loop Header: Depth=2
  movl %eax, (%rdi,%rcx,4)
  callq myl_core_list_copy@PLT
'''
    assembled = audit_assembly(assembly, blocks)
    assert len(assembled) == 2 and len(assembled[1]['count_store_block_memory_write_candidates']) == 1
    print('audit_all35 Python smoke: nested CFG loops, exclusive ownership stores, saturated select/read and assembly placement pass; no native compilation')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--bin', type=Path, default=ROWS.DEFAULT_BIN)
    parser.add_argument('--rows', default=','.join(ROWS.UNITS))
    parser.add_argument('--zig', default='zig')
    parser.add_argument('--reuse', action='store_true')
    parser.add_argument('--json', type=Path)
    parser.add_argument('--smoke-test', action='store_true')
    args = parser.parse_args(argv)
    if args.smoke_test:
        smoke()
        return 0
    report = {'valid': False, 'rows': {}, 'scope': __doc__, 'error': None}
    output = None
    try:
        selected = ROWS.row_names(args.rows)
        args.bin = ROWS.inside(args.bin)
        output = ROWS.inside(args.json if args.json else args.bin / 'count-audit.json')
        if not args.reuse:
            compile_artifacts(args, selected)
        print('| row | innermost loops | count stores | header count=1 stores | saturated count reads | dynamic count reads | opaque call sites |')
        print('|---|---:|---:|---:|---:|---:|---:|')
        for row in selected:
            source = args.bin / 'llvm' / f'{ROWS.stem(row)}.ll'
            optimized = source.with_suffix('.opt.ll').read_text()
            tagged_scope = bool(count_tags(optimized))
            loops, blocks = audit_ir(optimized)
            assembly = audit_assembly(source.with_suffix('.s').read_text(), blocks)
            inner = [loop for loop in loops if loop['innermost']]
            total = combine(loop['exclusive'] for loop in inner)
            report['rows'][row] = {'count_tag_metadata_survives': tagged_scope,
                                   'ir_loops': loops, 'assembly_loops': assembly, 'innermost_totals': total,
                                   'count_store_blocks': {function: {block: value['count_store_ir'] for block, value in values.items() if value['count_store_ir']}
                                                          for function, values in blocks.items()}}
            print(f"| {row} | {len(inner)} | {total['count_stores']} | {total['constant_one_count_stores']} | {total['saturated_count_reads']} | {total['dynamic_count_reads']} | {sum(total['calls'].values())} |", flush=True)
            if not tagged_scope:
                print(f'{row}: no myl.count metadata survives; zero tagged sites is not a proof about untagged stores or opaque callees.', flush=True)
        report['valid'] = True
        print('\nScope: static tagged stores in natural loops of the program, including setup; runtime/callee bodies are opaque. Assembly writes are corroborating candidates. See JSON for every header, parent-exclusive block and call class.')
        return 0
    except (OSError, ValueError, ROWS.InvalidMeasurement) as error:
        report['error'] = str(error)
        print(f'audit INVALID: {error}', file=sys.stderr)
        return 1
    finally:
        if output is not None:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
