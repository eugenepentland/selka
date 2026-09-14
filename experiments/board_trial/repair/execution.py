"""Evaluate immutable submissions; expected answers never enter board executables."""
import json
from pathlib import Path
import shutil

from storage import command, digest, write_json


def verdict(directory, cases, language, program):
    requests = [{key: case[key] for key in ('name', 'input', 'unavailable')} for case in cases]
    write_json(directory / 'requests.json', requests)
    record = command(directory, 'run', [program, '--project', directory / 'source/guest', directory / 'requests.json'])
    if record['status'] != 'passed':
        return {'phase': 'execution', 'passed': False}
    try:
        rows = json.loads((directory / 'run.stdout').read_bytes())
        if len(rows) != len(cases):
            raise ValueError('wrong observation count')
        mismatches = []
        key = 'guest' if language == 'guest' else 'baseline'
        for row, case in zip(rows, cases, strict=True):
            actual = dict(row[key]['outcome'], calls=row[key]['calls'])
            if row['name'] != case['name'] or actual != case['expected']:
                mismatches.append({'name': case['name'], 'actual': actual, 'expected': case['expected']})
        write_json(directory / 'mismatches.json', mismatches)
        return {'phase': 'behavior', 'passed': not mismatches, 'cases': len(cases), 'mismatches': len(mismatches)}
    except (ValueError, KeyError, TypeError) as error:
        return {'phase': 'protocol', 'passed': False, 'error': str(error)}


def board(directory, manifest, cases):
    source = directory / 'source'
    compiler = manifest['tools']['compiler']['path']
    if manifest['language'] == 'guest':
        checked = command(directory, 'check', [compiler, 'check-project', source / 'guest/main.my', '--diagnostics=json'])
        if checked['status'] != 'passed':
            return {'phase': 'guest-check', 'passed': False, 'failure_kind': checked['status']}
    program = directory / 'board-trial'
    # The host wrapper bounds its own address space before running guest code,
    # so the frozen compiler snapshot supplies that module alongside `mylang`.
    src = Path(manifest['compiler_source']).parent
    budget = src / 'memory_budget.zig'
    # The host wrapper builds its guest natively, so it links the native build
    # driver module graph: `host_native` over `qbe_build`, its generated asset
    # module, and a `host_tools` whose paths are only a runtime fallback (the
    # environment names the real tools), so a placeholder module compiles.
    host_tools = directory / 'host_tools.zig'
    host_tools.write_text('pub const qbe: []const u8 = "qbe";\npub const zig: []const u8 = "zig";\n')
    compiled = command(directory, 'compile', [manifest['tools']['zig']['path'], 'build-exe',
                       '--dep', 'mylang', '--dep', 'memory_budget', '--dep', 'host_native',
                       '-Mroot=' + str(source / 'runner.zig'),
                       '-Mmylang=' + manifest['compiler_source'],
                       '-Mmemory_budget=' + str(budget),
                       '--dep', 'qbe_build', '--dep', 'host_tools',
                       '-Mhost_native=' + str(src / 'host_native.zig'),
                       '--dep', 'qbe_build_assets', '--dep', 'memory_budget',
                       '-Mqbe_build=' + str(src / 'qbe_build.zig'),
                       '-Mqbe_build_assets=' + manifest['assets_source'],
                       '-Mhost_tools=' + str(host_tools),
                       '-femit-bin=' + str(program)], timeout=120)
    if compiled['status'] != 'passed':
        return {'phase': 'zig-compile', 'passed': False, 'failure_kind': compiled['status']}
    result = verdict(directory, cases, manifest['language'], program)
    result['program_sha256'] = digest(program)
    return result


def unit_main(value):
    return ('module unit_main\nimport units\n\n\ndef main() -> i64:\n'
            '    return units.Micrometres.number('
            f'units.Millimetres.toMicro(units.Millimetres.make({value})))\n')


def guest_units(directory, manifest, inputs):
    source = directory / 'source/guest'
    staging = directory / 'unit-source'
    staging.mkdir()
    shutil.copyfile(source / 'units.my', staging / 'units.my')
    entry = staging / 'unit_main.my'
    entry.write_text(unit_main(inputs[0]))
    checked = command(directory, 'check', [manifest['tools']['compiler']['path'], 'check-project', entry, '--diagnostics=json'])
    if checked['status'] != 'passed':
        return {'phase': 'guest-check', 'passed': False, 'failure_kind': checked['status']}
    for index, value in enumerate(inputs):
        entry.write_text(unit_main(value))
        phase = f'unit-{index:03}'
        result = command(directory, phase, [manifest['tools']['compiler']['path'], 'run-project', entry, '--print-result', '--diagnostics=json'])
        if result['status'] != 'passed':
            return {'phase': 'execution', 'passed': False, 'input_index': index}
        if (directory / (phase + '.stdout')).read_text().strip() != str(value * 1000):
            return {'phase': 'behavior', 'passed': False, 'input_index': index}
    return {'phase': 'behavior', 'passed': True, 'cases': len(inputs)}


def zig_units(directory, manifest, inputs):
    source = directory / 'source'
    staging = directory / 'unit-source'
    staging.mkdir()
    shutil.copyfile(source / 'unit_conversion.zig', staging / 'unit_conversion.zig')
    entry = staging / 'unit_test.zig'
    checks = '\n'.join('try std.testing.expectEqual(@as(i64, ' + str(value * 1000) +
                       '), @backingInt(units.toMicro(@fromBackingInt(' + str(value) + '))));' for value in inputs)
    entry.write_text('const std=@import("std");const units=@import("unit_conversion.zig");test "conversion"{\n' + checks + '\n}')
    program = directory / 'unit-test'
    compiled = command(directory, 'compile', [manifest['tools']['zig']['path'], 'test', str(entry),
                        '--test-no-exec', '-femit-bin=' + str(program)], timeout=120)
    if compiled['status'] != 'passed':
        return {'phase': 'zig-compile', 'passed': False, 'failure_kind': compiled['status']}
    result = command(directory, 'run', [program])
    return {'phase': 'behavior', 'passed': result['status'] == 'passed', 'cases': len(inputs)}


def evaluate(directory, manifest, inputs):
    write_json(directory / 'inputs.json', inputs)
    if manifest['task'] != 'units':
        return board(directory, manifest, inputs)
    if manifest['language'] == 'guest':
        return guest_units(directory, manifest, inputs)
    return zig_units(directory, manifest, inputs)
