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
The two runtime_bench_now calls delimit the timed caller CFG. Dominance and
reachability distinguish repeated-kernel innermost loops, parent-exclusive timed
blocks, and pre-timing setup/input construction. Splitting blocks at each clock
instruction also handles both calls sharing a block. Timed totals cover paths
that reach the stop call; paths that abort before it are reported separately.
All loops retain full detail, including loops outside the timed region. Callee,
runtime, missing-clock, and ambiguous scopes are explicitly unknown, not zero.
This is a static audit, not a claim that conditional stores always execute.

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


def walk(successors, entry, barrier=()):
    reached = set()
    pending = [entry]
    while pending:
        block = pending.pop()
        if block in reached or block not in successors:
            continue
        reached.add(block)
        if block not in barrier:
            pending.extend(successors[block])
    return reached


def cfg_analysis(successors, entry):
    reachable = walk(successors, entry)
    predecessors = {block: set() for block in successors}
    for parent, children in successors.items():
        for child in children:
            if child in predecessors:
                predecessors[child].add(parent)
    dom = {block: ({entry} if block == entry else set(reachable)) for block in reachable}
    changed = True
    while changed:
        changed = False
        for block in reachable - {entry}:
            parents = predecessors[block] & reachable
            common = set.intersection(*(dom[parent] for parent in parents)) if parents else set()
            updated = {block} | common
            if updated != dom[block]:
                dom[block] = updated
                changed = True
    return reachable, predecessors, dom


def block_successors(blocks):
    return {block: {name(target) for target in re.findall(r'\blabel %(' + TOKEN + r')', '\n'.join(lines))}
            for block, lines in blocks.items()}


def natural_loops(blocks):
    successors = block_successors(blocks)
    reachable, predecessors, dom = cfg_analysis(successors, next(iter(blocks)))
    loops = {}
    for latch in reachable:
        for header in successors[latch] & dom[latch]:
            body = {header, latch}
            pending = [] if latch == header else [latch]
            while pending:
                block = pending.pop()
                for parent in (predecessors[block] & reachable) - body:
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
        target = direct_call(line)
        if target is not None:
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


def direct_call(line):
    opcode = r'^\s*(?:%' + TOKEN + r'\s*=\s*)?(?:(?:tail|musttail|notail)\s+)?(?:call|invoke)\s'
    if not re.match(opcode, line):
        return None
    target = re.search(r'@(' + TOKEN + r')\s*\(', line)
    return name(target[1]) if target else '<indirect>'


def split_clock_cfg(blocks, clocks):
    """Use interval nodes, with one separate node per clock instruction."""
    cuts = {}
    for block, position in clocks:
        cuts.setdefault(block, set()).add(position)
    nodes, spans, markers, successors = {}, {}, {}, {}
    for block, lines in blocks.items():
        nodes[block] = []
        beginning = 0
        for position in sorted(cuts.get(block, ())):
            interval = (block, len(nodes[block]))
            nodes[block].append(interval)
            spans[interval] = (beginning, position)
            marker = (block, len(nodes[block]))
            nodes[block].append(marker)
            markers[(block, position)] = marker
            beginning = position + 1
        interval = (block, len(nodes[block]))
        nodes[block].append(interval)
        spans[interval] = (beginning, len(lines))
        for left, right in zip(nodes[block], nodes[block][1:]):
            successors[left] = {right}
    for block, children in block_successors(blocks).items():
        successors[nodes[block][-1]] = {nodes[child][0] for child in children if child in nodes}
    return successors, nodes, spans, markers


def audit_timing(source, loops):
    """Annotate full loops; aggregate only the caller's resolved timed scope."""
    all_functions = dict(functions(source))
    clocks = [(function, block, position) for function, blocks in all_functions.items()
              for block, lines in blocks.items() for position, line in enumerate(lines)
              if direct_call(line) == 'runtime_bench_now']
    report = {'status': 'unknown', 'reason': None,
              'clock_calls': [{'function': function, 'block': block, 'line_index': position,
                               'instruction': all_functions[function][block][position].strip()}
                              for function, block, position in clocks],
              'line_index_basis': 'zero-based index into the block body; interval end is exclusive',
              'count_store_scope': 'tagged_caller_stores' if count_tags(source) else 'unknown_missing_count_metadata',
              'regions': {}, 'totals': None,
              'opaque_body_scope': 'unknown: runtime, direct callee, indirect callee and untagged allocation-header stores'}
    for loop in loops:
        loop['timing_scope'] = 'unknown_clock_scope'
    if len(clocks) != 2:
        report['reason'] = f'expected exactly two runtime_bench_now calls, found {len(clocks)}'
        return report
    if clocks[0][0] != clocks[1][0]:
        report['reason'] = 'clock calls occur in different functions; interprocedural ordering is unknown'
        return report
    function = clocks[0][0]
    blocks = all_functions[function]
    successors, nodes, spans, markers = split_clock_cfg(blocks, [(block, position) for _, block, position in clocks])
    reachable, predecessors, dom = cfg_analysis(successors, nodes[next(iter(blocks))][0])
    first, second = (markers[(block, position)] for _, block, position in clocks)
    if first not in reachable or second not in reachable:
        report['reason'] = 'a clock call is unreachable from function entry'
        return report
    if first in dom[second] and second not in dom[first]:
        start, stop = first, second
    elif second in dom[first] and first not in dom[second]:
        start, stop = second, first
    else:
        report['reason'] = 'neither clock call strictly dominates the other'
        return report
    # A boundary in a repeated cycle does not delimit one timed invocation.
    after_start = set().union(*(walk(successors, child, {stop}) for child in successors[start]))
    if start in after_start or start in walk(successors, stop):
        report['reason'] = 'a timing boundary can repeat in a CFG cycle'
        return report
    ancestors_stop = walk(predecessors, stop, {start})
    timed = (after_start & ancestors_stop & reachable) - {start, stop}
    if any(start not in dom[node] for node in timed):
        report['reason'] = 'a block on a start-to-stop path is reachable without the start call'
        return report
    before = (walk(predecessors, start) & reachable) - {start}
    after = (walk(successors, stop) & reachable) - {stop}
    aborting = (after_start & reachable) - timed - {start, stop}
    covered = timed | before | after | aborting | {start, stop}
    groups = {'timed_normal_completion': timed, 'before_start_setup_or_input': before,
              'after_stop': after, 'timed_path_without_stop': aborting,
              'unclassified_caller': reachable - covered}
    tags = count_tags(source)
    immortals = saturated(source, [line for lines in blocks.values() for line in lines])

    def selected_metrics(selected):
        return combine(block_metrics(blocks[block][begin:end], tags, immortals)
                       for node in selected if node in spans
                       for block, _ in [node] for begin, end in [spans[node]])

    def intervals(selected):
        return [{'block': node[0], 'begin': spans[node][0], 'end': spans[node][1]}
                for node in sorted(selected) if node in spans and spans[node][0] != spans[node][1]]

    report.update(status='resolved_normal_completion', reason=None, function=function,
                  start={'block': start[0], 'line_index': next(position for (block, position), node in markers.items() if node == start)},
                  stop={'block': stop[0], 'line_index': next(position for (block, position), node in markers.items() if node == stop)})
    report['regions'] = {scope: {'intervals': intervals(selected), 'metrics': selected_metrics(selected)}
                         for scope, selected in groups.items()}
    caller_loops = [loop for loop in loops if loop['function'] == function]
    for loop in caller_loops:
        body_nodes = {node for block in loop['blocks'] for node in nodes[block]}
        if body_nodes <= timed:
            loop['timing_scope'] = 'timed_caller_loop'
        elif body_nodes <= before:
            loop['timing_scope'] = 'before_start_setup_or_input'
        elif body_nodes <= after:
            loop['timing_scope'] = 'after_stop'
        elif body_nodes & (timed | {start, stop}):
            loop['timing_scope'] = 'unknown_crosses_clock_boundary'
        elif body_nodes <= aborting:
            loop['timing_scope'] = 'timed_path_without_stop'
        else:
            loop['timing_scope'] = 'unknown_caller_path'

    # Preserve possible call contexts, but never assign a callee's RC to caller
    # totals. Address-taken and indirect invocations remain explicitly unknown.
    contexts = {target: set() for target in all_functions}
    for scope, selected in groups.items():
        for node in selected:
            if node not in spans:
                continue
            begin, end = spans[node]
            for line in blocks[node[0]][begin:end]:
                target = direct_call(line)
                if target in contexts:
                    contexts[target].add(scope)
    for line in source.splitlines():
        if re.match(r'^(?:define|declare)\b', line):
            continue
        direct = direct_call(line)
        references = [name(value) for value in re.findall(r'@(' + TOKEN + r')', line)]
        if direct in references:
            references.remove(direct)
        for target in set(references) & contexts.keys():
            contexts[target].add('unknown_address_taken')
    changed = True
    while changed:
        changed = False
        for parent, callee_blocks in all_functions.items():
            if parent == function or not contexts[parent]:
                continue
            for line in (line for lines in callee_blocks.values() for line in lines):
                target = direct_call(line)
                if target in contexts:
                    updated = contexts[target] | contexts[parent]
                    if updated != contexts[target]:
                        contexts[target] = updated
                        changed = True
    for loop in loops:
        if loop['function'] != function:
            loop['timing_scope'] = 'unknown_callee_scope'
            loop['possible_call_contexts'] = sorted(contexts[loop['function']]) or ['unknown_no_direct_call_context']

    def loop_nodes(selected_loops, exclusive=False):
        key = 'exclusive_blocks' if exclusive else 'blocks'
        return {node for loop in selected_loops for block in loop[key] for node in nodes[block]}

    timed_loops = [loop for loop in caller_loops if loop['timing_scope'] == 'timed_caller_loop']
    inner = [loop for loop in timed_loops if loop['innermost']]
    parents = [loop for loop in timed_loops if not loop['innermost']]
    inner_nodes = loop_nodes(inner, True) & timed
    parent_nodes = loop_nodes(parents, True) & timed
    all_loop_nodes = loop_nodes(caller_loops)
    nonloop_nodes = timed - all_loop_nodes
    unknown_nodes = timed - inner_nodes - parent_nodes - nonloop_nodes
    pre_loops = [loop for loop in caller_loops if loop['timing_scope'] == 'before_start_setup_or_input']
    timed_calls = selected_metrics(timed)['calls']
    report['totals'] = {
        'timed_innermost_loops': len(inner), 'timed_parent_loops': len(parents),
        'before_start_loops': len(pre_loops),
        'unknown_or_callee_loops': sum(loop['timing_scope'].startswith('unknown') for loop in loops),
        'timed_innermost': selected_metrics(inner_nodes),
        'timed_parent_exclusive': selected_metrics(parent_nodes),
        'timed_nonloop': selected_metrics(nonloop_nodes),
        'timed_unknown_loop_scope': selected_metrics(unknown_nodes),
        'before_start_loops_exclusive': selected_metrics(loop_nodes(pre_loops, True)),
        'timed_opaque_call_sites': sum(timed_calls.values()), 'timed_opaque_calls': timed_calls,
        'opaque_body_count_stores': None,
    }
    return report


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
    decoys = ('  br label %call.i',
              '  br i1 %condition, label %invoke.i, label %call.i',
              '  %result = phi ptr [ %made, %call.i ], [ %other, %invoke.i ]',
              '  %call.i = add i64 %invoke.i, 1',
              '  ; call i64 @commented_out()')
    assert all(direct_call(line) is None for line in decoys)
    assert not block_metrics(decoys, set(), set())['calls']
    for prefix in ('', 'tail ', 'musttail ', 'notail '):
        assert direct_call('  %result = ' + prefix + 'call i64 @worker()') == 'worker'
        assert direct_call('  ' + prefix + 'call void @worker()') == 'worker'
    assert direct_call('  %"quoted.result" = invoke i64 @"quoted.worker"() to label %call.i unwind label %invoke.i') == 'quoted.worker'
    assert direct_call('  call void %function(ptr %object)') == '<indirect>'
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
    metadata = '\n!2 = !{!"myl.count", !0}\n!3 = !{!2, !2, i64 0}\n'

    def timing(ir):
        ir_loops, _ = audit_ir(ir + metadata)
        return audit_timing(ir + metadata, ir_loops), ir_loops

    same_block = '''define i32 @main() {
entry:
  store i32 1, ptr %a, !tbaa !3
  %start = call i64 @runtime_bench_now()
  store i32 2, ptr %a, !tbaa !3
  call ptr @myl_core_list_copy(ptr %a, i64 8)
  %stop = call i64 @runtime_bench_now()
  store i32 3, ptr %a, !tbaa !3
  ret i32 0
}
'''
    scope, _ = timing(same_block)
    assert scope['status'] == 'resolved_normal_completion'
    assert scope['totals']['timed_nonloop']['count_stores'] == 1
    assert scope['regions']['before_start_setup_or_input']['metrics']['count_stores'] == 1
    assert scope['regions']['after_stop']['metrics']['count_stores'] == 1
    assert scope['totals']['timed_opaque_call_sites'] == 1
    assert scope['totals']['opaque_body_count_stores'] is None
    nested = source.replace('  br label %outer', '''  br label %construct
construct:
  store i32 1, ptr %input, !tbaa !3
  br i1 true, label %construct, label %start
start:
  %begin = call i64 @runtime_bench_now()
  br label %outer''', 1).replace('  br label %inner', '''  store i32 1, ptr %parent, !tbaa !3
  br label %inner''', 1).replace('label %exit', 'label %second').replace('exit:\n  ret i32 0', '''second:
  store i32 1, ptr %other, !tbaa !3
  call void @helper()
  br i1 true, label %second, label %stop
stop:
  %end = call i64 @runtime_bench_now()
  ret i32 0''') + '''define void @helper() {
entry:
  br label %scan
scan:
  store i32 1, ptr %callee, !tbaa !3
  br i1 true, label %scan, label %exit
exit:
  ret void
}
'''
    scope, classified = timing(nested)
    assert scope['status'] == 'resolved_normal_completion'
    assert scope['totals']['timed_innermost_loops'] == 2
    assert scope['totals']['timed_innermost']['count_stores'] == 2
    assert scope['totals']['timed_parent_exclusive']['count_stores'] == 1
    assert scope['totals']['before_start_loops'] == 1
    assert scope['totals']['before_start_loops_exclusive']['count_stores'] == 1
    callee = next(loop for loop in classified if loop['function'] == 'helper')
    assert callee['timing_scope'] == 'unknown_callee_scope'
    assert callee['possible_call_contexts'] == ['timed_normal_completion']
    assert scope['totals']['unknown_or_callee_loops'] == 1
    timed_stores = sum(scope['totals'][key]['count_stores'] for key in
                       ('timed_innermost', 'timed_parent_exclusive', 'timed_nonloop', 'timed_unknown_loop_scope'))
    assert timed_stores == scope['regions']['timed_normal_completion']['metrics']['count_stores']
    # Lexical block order need not be execution order.
    reversed_blocks = '''define void @main() {
entry:
  br label %begin
end:
  %stop = call i64 @runtime_bench_now()
  ret void
begin:
  %start = call i64 @runtime_bench_now()
  store i32 1, ptr %object, !tbaa !3
  br label %end
}
'''
    scope, _ = timing(reversed_blocks)
    assert scope['start']['block'] == 'begin' and scope['stop']['block'] == 'end'
    assert scope['totals']['timed_nonloop']['count_stores'] == 1
    assert timing(same_block.replace('runtime_bench_now', 'other_clock'))[0]['status'] == 'unknown'
    assert timing(same_block.replace('  ret i32 0', '  %extra = call i64 @runtime_bench_now()\n  ret i32 0'))[0]['totals'] is None
    ambiguous = reversed_blocks.replace('  br label %begin', '  br i1 true, label %begin, label %end', 1)
    assert timing(ambiguous)[0]['status'] == 'unknown'
    repeated_clock = reversed_blocks.replace('  ret void', '  br label %begin')
    assert timing(repeated_clock)[0]['status'] == 'unknown'
    crossing = reversed_blocks.replace('  br label %begin', '  br label %outside', 1).replace('end:', '''outside:
  br label %begin
end:''').replace('  ret void', '  br i1 true, label %outside, label %exit\nexit:\n  ret void')
    assert timing(crossing)[0]['status'] == 'unknown'
    aborting = reversed_blocks.replace('  br label %end', '''  br i1 true, label %end, label %abort
abort:
  store i32 1, ptr %failed, !tbaa !3
  unreachable''')
    scope, _ = timing(aborting)
    assert scope['totals']['timed_nonloop']['count_stores'] == 1
    assert scope['regions']['timed_path_without_stop']['metrics']['count_stores'] == 1
    different_functions = same_block.replace('  %stop = call i64 @runtime_bench_now()', '') + '''define void @other() {
entry:
  %stop = call i64 @runtime_bench_now()
  ret void
}
'''
    assert timing(different_functions)[0]['status'] == 'unknown'
    untagged_loops, _ = audit_ir(same_block)
    assert audit_timing(same_block, untagged_loops)['count_store_scope'] == 'unknown_missing_count_metadata'
    print('audit_all35 Python smoke: nested/multiple loops, timed parent stores, pre-timing construction, shared clock block instruction positions, dominance/order, repeated/ambiguous clocks, opaque callee scopes and assembly placement pass; no native compilation')


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
        print('| row | clock scope | timed inner loops | inner count stores | parent-exclusive count stores | timed nonloop count stores | pre-timing loops | pre-timing loop count stores | unknown/callee loops | timed opaque call sites |')
        print('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|')
        for row in selected:
            source = args.bin / 'llvm' / f'{ROWS.stem(row)}.ll'
            optimized = source.with_suffix('.opt.ll').read_text()
            tagged_scope = bool(count_tags(optimized))
            loops, blocks = audit_ir(optimized)
            timing = audit_timing(optimized, loops)
            assembly = audit_assembly(source.with_suffix('.s').read_text(), blocks)
            loop_scopes = {(loop['function'], loop['header']): loop['timing_scope'] for loop in loops}
            for loop in assembly:
                loop['timing_scope'] = loop_scopes.get((loop['function'], loop.get('ir_header')), 'unknown_assembly_to_ir_mapping')
            inner = [loop for loop in loops if loop['innermost']]
            total = combine(loop['exclusive'] for loop in inner)
            report['rows'][row] = {'count_tag_metadata_survives': tagged_scope,
                                   'timing': timing, 'ir_loops': loops, 'assembly_loops': assembly,
                                   'all_program_innermost_totals_including_setup': total,
                                   'count_store_blocks': {function: {block: value['count_store_ir'] for block, value in values.items() if value['count_store_ir']}
                                                          for function, values in blocks.items()}}
            timed = timing['totals']
            values = [timed['timed_innermost_loops'] if timed else 'unknown']
            values += [timed[key]['count_stores'] if timed and tagged_scope else 'unknown'
                       for key in ('timed_innermost', 'timed_parent_exclusive', 'timed_nonloop')]
            values += [timed['before_start_loops'] if timed else 'unknown',
                       timed['before_start_loops_exclusive']['count_stores'] if timed and tagged_scope else 'unknown',
                       timed['unknown_or_callee_loops'] if timed else len(loops),
                       timed['timed_opaque_call_sites'] if timed else 'unknown']
            print(f"| {row} | {timing['status']} | " + ' | '.join(map(str, values)) + ' |', flush=True)
            if timing['status'] == 'unknown':
                print(f"{row}: clock scope unknown: {timing['reason']}", flush=True)
            if not tagged_scope:
                print(f'{row}: no myl.count metadata survives; zero tagged sites is not a proof about untagged stores or opaque callees.', flush=True)
        report['valid'] = True
        print('\nScope: static caller-visible tagged count stores between the two clocks, on paths reaching the stop call. Pre-timing loops are setup/input construction; callee/runtime bodies and untagged header stores remain unknown. A count=1 initialization/release store and a saturated header check are separate JSON metrics. Full loop and assembly detail, parent-exclusive blocks, interval positions, abort paths and opaque call classes are retained.')
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
