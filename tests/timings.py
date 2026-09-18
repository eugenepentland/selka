"""Structured timing protocol checks; durations have no performance thresholds."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def records(result, tool, names):
    timings = [json.loads(line) for line in result.stderr.splitlines() if line.startswith(b'{')]
    timings = [item for item in timings if item.get('kind') == 'timing']
    assert timings, result
    assert {item['name'] for item in timings} == set(names), timings
    for item in timings:
        assert item['version'] == 'phase-timings-v1', item
        assert item['tool'] == tool, item
        assert type(item['duration_ns']) is int and item['duration_ns'] >= 0, item
        assert type(item['inclusive']) is bool, item
        assert item['exit_code'] == result.returncode, item
        assert all(type(value) is int and value >= 0 for value in item['counts'].values()), item
    assert timings[-1]['name'] == 'total' and timings[-1]['inclusive'], timings
    # Recorder intervals are disjoint; total is a parent, never an additive phase.
    assert sum(item['duration_ns'] for item in timings[:-1]) <= timings[-1]['duration_ns'], timings
    return timings[-1]['counts']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--runner', required=True, type=Path)
    args = parser.parse_args()
    compiler, runner = str(args.compiler.resolve()), str(args.runner.resolve())
    with tempfile.TemporaryDirectory(prefix='phase-timings-') as tmp:
        root = Path(tmp)
        single = root / 'single.my'
        single.write_text('def main() -> i64:\n    return 7\n')
        def command(*argv, data=b''):
            return subprocess.run(argv, input=data, capture_output=True, timeout=30)
        baseline = command(compiler, 'run', str(single), '--print-result')
        measured = command(compiler, 'run', str(single), '--print-result', '--timings=json')
        # `run` adopts the guest exit status, so this fixture exits 7.
        assert baseline.returncode == measured.returncode == 7
        assert baseline.stdout == measured.stdout == b'7\n' and not baseline.stderr
        counts = records(measured, 'compiler', ['source_load', 'frontend', 'bytecode_lowering', 'native_emission', 'native_execution', 'total'])
        assert counts['source_bytes'] == single.stat().st_size and counts['modules'] == 1
        assert counts['ast_nodes'] and counts['typed_nodes']
        legacy = command(compiler, 'run', str(single), '--print-result', '--timings')
        assert legacy.returncode == baseline.returncode and legacy.stdout == baseline.stdout
        assert legacy.stderr.startswith(b'timings: native_ns='), legacy
        checked = command(compiler, 'check', str(single), '--timings=json')
        assert checked.returncode == 0 and not checked.stdout
        records(checked, 'compiler', ['source_load', 'frontend', 'total'])
        for flags in [('--timings=json', '--timings=json'), ('--timings=json', '--timings'), ('--timings=text',)]:
            assert command(compiler, 'run', str(single), *flags).returncode == 2
        missing = command(compiler, 'check', str(root / 'missing.my'), '--timings=json', '--diagnostics=json')
        assert missing.returncode == 2
        records(missing, 'compiler', ['source_load', 'total'])
        single.write_text('def main() -> i64:\n    return missing\n')
        failed = command(compiler, 'check', str(single), '--timings=json', '--diagnostics=json')
        assert failed.returncode == 1 and not failed.stdout
        records(failed, 'compiler', ['source_load', 'frontend', 'total'])
        assert any(json.loads(line).get('kind') == 'diagnostic' for line in failed.stderr.splitlines())
        single.write_text('def main() -> i64:\n    x = 0\n    return 7 // x\n')
        trapped = command(compiler, 'run', str(single), '--timings=json', '--diagnostics=json')
        assert trapped.returncode == 1 and not trapped.stdout
        records(trapped, 'compiler', ['source_load', 'frontend', 'bytecode_lowering', 'native_emission', 'native_execution', 'total'])
        project = root / 'main.my'
        project.write_text('module main\n\n\ndef main() -> i64:\n    return 7\n')
        check_phases = [
            'dependency_key_preparation', 'symbolic_templates', 'ordinary_body_replay',
            'fresh_body_check', 'entry_adaptation', 'effect_origin_passes',
            'domain_codec_validation', 'warning_derivation', 'retention_store_io',
        ]
        for mode, phases in [('check-project', []), ('run-project', ['bytecode_lowering', 'native_emission', 'native_execution']), ('index-project', []), ('emit-project-qbe', ['bytecode_lowering', 'native_emission'])]:
            normal = command(compiler, mode, str(project))
            # --no-cache keeps this protocol check on the instrumented fresh
            # path instead of letting a stored whole-project verdict skip it.
            timed = command(compiler, mode, str(project), '--timings=json', '--no-cache')
            expected_rc = 7 if mode == 'run-project' else 0
            assert timed.returncode == normal.returncode == expected_rc, (mode, timed)
            assert timed.stdout == normal.stdout, (mode, timed)
            expected = ['source_load_parse', 'syntax_parse', 'declarations_interfaces', 'source_merge']
            expected += check_phases
            expected += phases + ['total']
            records(timed, 'compiler', expected)
        (root / 'io.my').write_text('module io\n\n\n\n\n\npublic host def length() -> i64 effects(host)\npublic host def byte(index: i64) -> u8 effects(host)\npublic host def put(value: u8) -> i64 effects(host)\n')
        project.write_text('module main\nimport io\n\n\ndef main() -> i64:\n    i = 0\n    while i < io.length():\n        _ = io.put(io.byte(i))\n        i += 1\n    return 0\n')
        payload = b'\x00\xff\xc0\x80{broken}'
        normal = command(runner, '--project', str(root), data=payload)
        timed = command(runner, '--project', str(root), '--timings=json', data=payload)
        assert normal.returncode == timed.returncode == 0 and normal.stdout == timed.stdout == payload
        assert not normal.stderr
        counts = records(timed, 'byte_io', ['compilation_inclusive', 'stdin_read', 'vm_execution', 'stdout_write', 'total'])
        assert counts['input_bytes'] == counts['output_bytes'] == len(payload)
        assert counts['modules'] == 2
        assert command(runner, '--project', str(root), '--timings=json', '--timings=json').returncode != 0
        project.write_text('module main\nimport io\n\n\ndef main() -> i64:\n    _ = io.put(65u8)\n    return 1\n')
        failed = command(runner, '--project', str(root), '--timings=json')
        assert failed.returncode == 1 and not failed.stdout
        records(failed, 'byte_io', ['compilation_inclusive', 'stdin_read', 'vm_execution', 'total'])
        project.write_text('module main\n\n\ndef main() -> i64:\n    return missing\n')
        failed = command(runner, '--project', str(root), '--timings=json')
        assert failed.returncode == 1 and not failed.stdout
        records(failed, 'byte_io', ['compilation_inclusive', 'total'])
    print('phase timings: opt-in JSONL, counts, failures, legacy compatibility and raw stdout passed')


if __name__ == '__main__':
    main()
