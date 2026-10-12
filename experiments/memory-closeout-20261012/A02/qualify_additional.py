#!/usr/bin/env python3
"""Preserve original output, property failures and traps through ownership migration."""
import argparse
import json
import os
from pathlib import Path
import re
from qualification_support import (artifact_audit, call, clean_env, counter_audit,
                                   fresh_output, mode_flags, owned_clean, save, sha)

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
DEFAULT_C0 = Path('/home/epentland/ai/canopy/mylang-memory-20261012-A09/.tmp/memory-closeout/A09/C0/bin/mylang')
GUEST_EXPECTED = {'b_buffer_values': (2, 0), 'c_runner_byte_buffer': (2, 2),
                  'm_list_methods': (4, 4), 'v_dynamic_repeat': (1, 0),
                  'v_nested_lengths': (1, 0), 'v_nested_places': (1, 0)}


def scenarios(name):
    if name == 'f2_index':
        return [[], ['all', 'x'], ['next_trap'], ['fill_inside'], ['shrink_trap'],
                ['loop_shrink', 'x'], ['bump_trap'], ['same_length_trap']]
    if name == 'ce_appends':
        return [[], ['grow', '100000']]
    if name == 'rc_lists':
        return [['a', 'b']]
    if name == 'rc_mut':
        return [[], ['a', 'b']]
    if name in ('u1_growth', 'u1_hoist'):
        return [[], ['x']]
    return [[]]


def guest_test_valid(name, row):
    if row['stderr']:
        return False
    try:
        r = json.loads(row['stdout'])
        passed, failed = GUEST_EXPECTED[name]
        if row['status'] != (1 if failed else 0) or (r['passed'], r['failed'], r['unsupported']) != (passed, failed, 0):
            return False
        if name == 'm_list_methods':
            return all(s in row['stdout'] for s in ['R_LIST_VALUE', 'R_LIST_BOUNDS', 'R_SLICE_STEP', 'R_LIST_BOUNDS (index -99, length 2)'])
        if name == 'c_runner_byte_buffer':
            def named(suffix):
                return next(x for x in r['tests'] if x['name'].endswith('::' + suffix))
            if any(named(n)['property']['counts']['passed'] != 12 for n in ['test_buffer_copy_appends_alone', 'test_buffers_inside_records_lists_and_options']):
                return False
            minimal = named('test_short_buffer')['property']['failure']['minimal']['literals']['buffer']
            return minimal == 'byte_buffer(b"\\x00\\x00\\x00")' and 'returned Err(byte_buffer(b"\\x00\\x00\\x00"))' in named('test_buffer_error_result')['reason']
        return True
    except (ValueError, KeyError, StopIteration):
        return False


def contract_source(source, test_names):
    """Count normal-return contracts separately from the actual property/trap workers."""
    text = re.sub(r'^func main\(', 'func original_main(', source.read_text(), flags=re.M)
    text += '\n\nfunc main(out: Stream) -> int:\n'
    if source.stem == 'c_runner_byte_buffer':
        text += '''    if not test_buffer_copy_appends_alone(byte_buffer([])):
        return 1
    if not test_buffer_copy_appends_alone(byte_buffer([97, 98, 99])):
        return 2
    if not test_buffers_inside_records_lists_and_options(Packet(tag=7, body=byte_buffer([120])), [byte_buffer([97, 98]), byte_buffer([])], Some(byte_buffer([122]))):
        return 3
    if not test_buffers_inside_records_lists_and_options(Packet(tag=0, body=byte_buffer([])), [], None):
        return 4
    if not test_short_buffer(byte_buffer([97, 98])) or test_short_buffer(byte_buffer([97, 98, 99])):
        return 5
    match test_buffer_error_result(byte_buffer([97, 98])):
        case Ok(value):
            if not value:
                return 6
        case Err(error):
            return 7
    match test_buffer_error_result(byte_buffer([97, 98, 99])):
        case Ok(value):
            return 8
        case Err(error):
            if len(error) != 3:
                return 9
'''
    else:
        # Four intentional trap functions remain exercised by the real guest
        # runner above; fatal exits do not promise normal-return live-byte zero.
        names = test_names[:4] if source.stem == 'm_list_methods' else test_names
        for name in names:
            text += f'    if not {name}():\n        return 1\n'
    return text + '    out.print("contracts passed")\n    return 0\n'


def counted_program(compiler, source, flags, directory, cache, argv_sets):
    directory.mkdir()
    binary, llvm = directory / 'program', directory / 'program.ll'
    row = call([compiler, 'build', source, *flags, '--release', '--counters', '--zig', os.environ['ZIG'],
                '--cache-dir', cache, '--emit-llvm', llvm, '-o', binary], env=clean_env(), cwd=ROOT)
    if row['status'] != 0:
        return row
    row.update(artifact_audit(binary, llvm))
    row['runs'] = []
    for i, argv in enumerate(argv_sets):
        counts = directory / f'counts-{i}.json'
        env = dict(clean_env(), MYLANG_COUNTERS=str(counts), MYL_CORE_LEAKCHECK='1')
        run = call([binary, *argv], env=env, cwd=ROOT)
        run.update(counter_audit(counts))
        row['runs'].append(run)
    return row


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--baseline', type=Path, default=DEFAULT_C0)
    p.add_argument('--mode', choices=['zero', 'default'], default='zero',
                   help='default omits the prototype flag and still requires owned runtime evidence')
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--files', nargs='+', required=True)
    args = p.parse_args()
    args.compiler, args.baseline = args.compiler.resolve(), args.baseline.resolve()
    args.output = fresh_output(args.output)
    if len(args.files) != len(set(args.files)):
        raise ValueError('duplicate files')
    originals = json.loads((HERE / 'additional/originals.json').read_text())
    result = dict(compiler=str(args.compiler), compiler_sha256=sha(args.compiler), mode=args.mode,
                  baseline=str(args.baseline), baseline_sha256=sha(args.baseline), harness_sha256=sha(__file__),
                  support_sha256=sha(HERE / 'qualification_support.py'), requested_files=args.files,
                  complete=False, qualified=False, cases={})
    save(args.output / 'results.json', result)
    for name in args.files:
        old, source = originals[name], ROOT / name
        original = HERE / 'additional/originals' / name
        directory = args.output / source.stem
        directory.mkdir()
        entry = dict(original_sha256=sha(original), migrated_sha256=sha(source), lanes={})
        result['cases'][name] = entry
        assert entry['original_sha256'] == old['sha256']
        assert re.findall(r'^(?:public )?func (test_\w+)\(', source.read_text(), re.M) == old['test_names']
        for lane, compiler, input_source, flags in [
            ('original', args.baseline, original, []),
            ('owned', args.compiler, source, mode_flags(args.mode)),
        ]:
            cache = args.output / ('cache-' + lane)
            if old['test_names']:
                row = call([compiler, 'test', input_source, *flags, '--release', '--json', '--seed', '7',
                            '--property-runs', '12', '--zig', os.environ['ZIG'], '--cache-dir', cache],
                           env=dict(clean_env(), MYL_CORE_LEAKCHECK='1'), cwd=ROOT)
                row['guest_results_pass'] = guest_test_valid(source.stem, row)
                wrapper = directory / (lane + '-contracts.my')
                wrapper.write_text(contract_source(input_source, old['test_names']))
                probe = counted_program(compiler, wrapper, flags, directory / (lane + '-contracts'), cache, [[]])
                probe['source_sha256'] = sha(wrapper)
                probe['scope'] = ('all positive zero-argument contracts; four fatal list traps remain in guest command' if source.stem == 'm_list_methods'
                                  else 'explicit empty/nonempty byte-buffer property examples, False and handled Err/Ok returns; not all randomized workers' if source.stem == 'c_runner_byte_buffer'
                                  else 'all zero-argument test contracts')
                row['counted_contracts'] = probe
                row['pass'] = row['guest_results_pass'] and probe['status'] == 0
                if probe['status'] == 0:
                    run = probe['runs'][0]
                    row['pass'] &= run['status'] == 0 and run['stdout'] == 'contracts passed\n' and not run['stderr'] and run['leak_free']
                    if lane == 'owned':
                        row['pass'] &= owned_clean(run, probe)
                entry['lanes'][lane] = row
            else:
                entry['lanes'][lane] = counted_program(compiler, input_source, flags, directory / lane, cache, scenarios(source.stem))
        a, b = entry['lanes']['original'], entry['lanes']['owned']
        if old['test_names']:
            entry['pass'] = a['pass'] and b['pass']
        elif a['status'] == 0 and b['status'] == 0:
            entry['pass'] = b['symbols_clean'] and b['llvm_clean'] and len(a['runs']) == len(b['runs'])
            for x, y in zip(a['runs'], b['runs']):
                same = x['status'] == y['status'] and x['stdout'] == y['stdout'] and not x.get('timed_out', False) and not y.get('timed_out', False)
                if x['status'] == 0:
                    same &= not y['stderr'] and x['leak_free'] and owned_clean(y, b)
                else:
                    before = re.findall(r'error\[([^]]+)\]', x['stderr'])
                    after = re.findall(r'error\[([^]]+)\]', y['stderr'])
                    same &= bool(before) and before == after and re.findall(r'\{"version":.*', x['stderr']) == re.findall(r'\{"version":.*', y['stderr'])
                    same &= not y['counts_present'] or y['rc_events'] == 0
                    y['counter_scope'] = 'fatal trap: structural RC audit required; live-byte cleanup is only claimed for normal returns'
                y['same_as_original'] = same
                entry['pass'] &= same
        else:
            entry['pass'] = False
        save(args.output / 'results.json', result)
        print(name, entry['pass'], flush=True)
    assert sha(args.compiler) == result['compiler_sha256'] and sha(args.baseline) == result['baseline_sha256']
    assert all(entry['migrated_sha256'] == sha(ROOT / name) for name, entry in result['cases'].items())
    result['complete'] = True
    result['qualified'] = all(entry['pass'] for entry in result['cases'].values())
    save(args.output / 'results.json', result)
    return 0 if result['qualified'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
