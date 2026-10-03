#!/usr/bin/env python3
"""Compare complete selected/session manifests with the original producer.

Each command uses the same source path. The witness's whole-project GC
emission must contain COW tally calls; selected emission and retained sessions
keep their established default policy even under the counting environment.
"""
from pathlib import Path
import hashlib, json, os, subprocess
from prefixes_v2 import snapshot

lane = Path(__file__).resolve().parents[2]
scratch = lane / '.tmp-lox-native-policy-20261003'
work = scratch / 'selected-boundaries-verified-v2'
work.mkdir(exist_ok=False)
control = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
candidate = scratch / 'compiler-final-v2/bin/mylang'
historical = scratch / 'compiler-final/bin/mylang'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
frozen = json.loads((scratch / 'frozen-source-v2.json').read_text())
assert all(sha(lane / p) == h for p, h in frozen['core'].items())
prefix_before = snapshot()
text = (lane / 'test/native_variant_policy.zig').read_text().split('const source =\n', 1)[1].split('\n;', 1)[0]
source = work / 'policy_program.my'
source.write_text('\n'.join(line.split('\\\\', 1)[1] for line in text.splitlines()) + '\n')
selection = work / 'select.txt'
selection.write_text('policy_program::snapshot\n')
environment = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
environment.update(TMPDIR=str(scratch / 'tmp'), MYLANG_TIMING_CPUS='2,3,10,11')
report = dict(core_descriptor_sha256=sha(scratch / 'frozen-source-v2.json'),
              core878=frozen['core'], source37=frozen['source37'], source_sha256=sha(source),
              compilers_sha256={str(p): sha(p) for p in [control, candidate, historical]},
              immutable_prefixes_before=prefix_before, observations=[], comparisons=[],
              verified_after=False, fragment_files_sha256={}, normalization='Only replace physical fragment-store root; dereference and hash every IL/meta file, preserve all manifest metadata. Fragment reference names are BLAKE3; independent file SHA256 and full IL/meta bytes are compared.')

def save():
    (work / 'qualification.json').write_text(json.dumps(report, indent=2) + '\n')

def launch(label, producer, command, runtime, counting, flags=()):
    argv = [str(lane / 'scripts/build-slot.sh'), 'build', str(producer), command, str(source),
            '--cache-dir=' + str(work / ('cache-' + label)), *flags]
    payload = None
    if command == 'emit-project-qbe':
        argv += ['--' + runtime + '-runtime', '--select-file=' + str(selection)]
    else:
        output = work / (label + '.manifest.json')
        payload = ('lower\t' + str(selection) + '\t' + str(output) + '\nquit\n').encode()
    env = dict(environment, MYLANG_COW_COUNTING=str(counting), MYLANG_RUNTIME='rc-v5' if runtime == 'rc' else 'gc-v1')
    result = subprocess.run(argv, cwd=lane, env=env, input=payload, capture_output=True)
    stdout, stderr = work / (label + '.stdout'), work / (label + '.stderr')
    stdout.write_bytes(result.stdout)
    stderr.write_bytes(result.stderr)
    compiler_stderr = b'\n'.join(line for line in result.stderr.splitlines() if not line.startswith(b'build-slot:'))
    assert result.returncode == 0 and not compiler_stderr, (label, result.returncode, result.stderr)
    raw = result.stdout if payload is None else output.read_bytes()
    document = json.loads(raw)
    functions = document['functions']
    if document.get('store'):
        store = Path(document['store'])
        for function in functions:
            for key in ['il_digest', 'meta_digest']:
                path = store / function[key]
                assert path.is_file()
                report['fragment_files_sha256'][str(path)] = sha(path)
            function['il'] = (store / function['il_digest']).read_text()
            function['resolved_meta_file_bytes'] = (store / function['meta_digest']).read_text()
        document['store'] = '__PHYSICAL_FRAGMENT_STORE__'
    normalized = json.dumps(document, sort_keys=True).encode()
    assert functions and any('snapshot' in f['name'] for f in functions)
    row = dict(label=label, producer=str(producer), argv=argv, cwd=str(lane),
               environment={'TMPDIR': env['TMPDIR'], 'MYLANG_COW_COUNTING': str(counting), 'MYLANG_RUNTIME': env['MYLANG_RUNTIME']},
               stdin=payload.decode() if payload else None, status=result.returncode,
               stdout_sha256=sha(stdout), stderr_sha256=sha(stderr),
               manifest_sha256=hashlib.sha256(raw).hexdigest(), normalized_manifest_sha256=hashlib.sha256(normalized).hexdigest(),
               functions={f['name']: hashlib.sha256(json.dumps(f, sort_keys=True).encode()).hexdigest() for f in functions},
               cow_tally_calls=sum(f['il'].count('call $myl_native_cow_tally') for f in functions))
    if payload:
        row['manifest'] = str(output)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        assert len(replies) == 2 and all(r['status'] == 0 for r in replies)
    report['observations'].append(row)
    save()
    return normalized

for runtime in ['rc', 'gc']:
    for command in ['emit-project-qbe', 'native-test-compile']:
        for counting in [0, 1]:
            label = '-'.join([runtime, command, str(counting)])
            expected = launch(label + '-control', control, command, runtime, counting)
            for mode, flags in [('default', []), ('explicit-original', ['--native-variants=original'])]:
                actual = launch(label + '-' + mode, candidate, command, runtime, counting, flags)
                report['comparisons'].append(dict(label=label + '-' + mode, full_il_and_metadata_equal=actual == expected))
                assert actual == expected, label + '-' + mode
            if command == 'emit-project-qbe':
                drop = ['--drop-step-checks', '--drop-frame-checks', '--drop-debug']
                drop_expected = launch(label + '-control-drop', control, command, runtime, counting, drop)
                actual = launch(label + '-candidate-drop', candidate, command, runtime, counting, drop)
                report['comparisons'].append(dict(label=label + '-drop', full_il_and_metadata_equal=actual == drop_expected == expected))
                assert actual == drop_expected == expected, label + '-drop'
            old = launch(label + '-historical-v1', historical, command, runtime, counting)
            report['comparisons'].append(dict(label=label + '-historical-v1',
                                             historical_only=True, full_il_and_metadata_equal=old == expected))

# A full emission has the original full-policy counting behavior. Its real
# tally witness proves that the selected/session equality cases are sensitive.
argv = [str(lane / 'scripts/build-slot.sh'), 'build', str(candidate), 'emit-project-qbe', str(source),
        '--gc-runtime', '--no-cache']
env = dict(environment, MYLANG_COW_COUNTING='1')
result = subprocess.run(argv, cwd=lane, env=env, capture_output=True)
(work / 'whole-project-counting.stdout').write_bytes(result.stdout)
(work / 'whole-project-counting.stderr').write_bytes(result.stderr)
compiler_stderr = b'\n'.join(line for line in result.stderr.splitlines() if not line.startswith(b'build-slot:'))
assert result.returncode == 0 and not compiler_stderr
whole = json.loads(result.stdout)
calls = sum(f['il'].count('call $myl_native_cow_tally') for f in whole['functions'])
assert calls > 0
report['whole_project_counting_witness'] = dict(argv=argv, status=0, cow_tally_calls=calls,
    environment={'MYLANG_COW_COUNTING': '1'}, stdout_sha256=sha(work / 'whole-project-counting.stdout'),
    stderr_sha256=sha(work / 'whole-project-counting.stderr'))
assert all(sha(lane / p) == h for p, h in frozen['core'].items())
assert report['compilers_sha256'] == {str(p): sha(p) for p in [control, candidate, historical]}
assert sha(source) == report['source_sha256']
assert all(sha(p) == h for p, h in report['fragment_files_sha256'].items())
report['immutable_prefixes_after'] = snapshot()
assert prefix_before == report['immutable_prefixes_after']
report['verified_after'] = True
save()
print('Selected/session complete IL+metadata matches d14, counting+drop defaults preserved; V1 retained separately')
