#!/usr/bin/env python3
"""Replay saved G4 correctness and identities; execute no benchmark guests."""
import gzip
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent / 'goal110-g4-rf-20261004'
CACHE = WORK / '.mylang-cache/goal110-g4-rf'
ARCHIVE = ROOT / 'experiments/runtime-goal110-g4-rf-20261004'
SOURCE = '6cf7bdce11bc205862bf75b9d9ce72e46caad0a2'
PREFIX = ROOT / 'benchmarks/runtime/candidates/goal110-g4-6cf7bdce-rf-20261004'
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import goal110
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
from registry import checksum
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    data = Path(path).read_bytes()
    return json.loads(gzip.decompress(data) if str(path).endswith('.gz') else data)


def saved(name):
    path = ARCHIVE / (name + '.gz')
    assert path.is_file(), path
    raw = gzip.decompress(path.read_bytes())
    assert raw == (CACHE / name).read_bytes(), name
    return path, json.loads(raw)


def binding(name, kind, path):
    return dict(name=name, kind=kind, status='pass', path=str(path), sha256=sha(path))


def main():
    manifest_path = CACHE / 'runner/manifest.json'
    manifest = read(manifest_path)
    identity = manifest['identity']
    receipt = identity['compiler_build_receipt']
    host = read(receipt['path'])
    assert sha(receipt['path']) == receipt['sha256'] and host == receipt['receipt']
    assert host['status'] == 'complete' and host['exit_status'] == 0
    assert host['compiler_optimize'] == 'ReleaseFast'
    assert host['source_revision'] == identity['source_revision'] == SOURCE
    assert host['sources_before'] == host['sources_after']
    assert sha(host['compiler_path']) == host['compiler_sha256']
    for name, digest in host['sources_after'].items():
        assert sha(WORK / name) == digest, name
    for name, digest in identity['installed_assets'].items():
        assert sha(name) == digest, name
    for name, digest in manifest['binary_hashes'].items():
        assert sha(identity['binary_paths'].get(name, manifest_path.parent / name)) == digest, name
    frozen = read(ROOT.parent / 'runtime-parity-harness-20261003/.mylang-cache/runtime-candidate-730a86e6-releasefast/runner/manifest.json')
    references = [key for key in manifest['binary_hashes'] if '/' in key and '/my-' not in key]
    assert len(references) == 16
    for key in references:
        assert manifest['binary_hashes'][key] == frozen['binary_hashes'][key], key

    checks = []
    sessions = []
    for letter in ('a', 'b'):
        path, report = saved('confirmation-' + letter + '.json')
        assert report['status'] == 'subset' and report['rounds'] == 15 and report['warmup_rounds'] == 3
        assert report['identity'] == report['identity_after'] == identity
        assert report['binary_hashes'] == report['binary_hashes_after'] == manifest['binary_hashes']
        seen = set()
        for row in report['qualification']:
            key = tuple(row[k] for k in ('case', 'size', 'iterations', 'seed', 'arm'))
            assert key not in seen
            seen.add(key)
            assert row['checksum'] == checksum(*key[:4]) and row['exit_status'] == 0
        assert len(seen) == 720 and len(report['samples']) == 1080
        sessions.append(report)
        checks.append(binding('fresh G4 session ' + letter.upper() + ' qualification', 'qualification', path))
    execution = goal110.execution_identity(sessions[1])
    assert execution == goal110.execution_identity(sessions[0])
    identity_hash = goal110.content_hash(execution)

    path, held = saved('holdouts.json')
    assert holdouts.verify(held) == 516
    assert held['manifest_sha256'] == sha(manifest_path)
    assert held['identity'] == identity
    assert held['binary_hashes'] == manifest['binary_hashes']
    checks.append(binding('fresh RF nearby-input holdouts, 516 outcomes', 'holdout', path))

    path, text = saved('text-checks.json')
    assert text['status'] == 'passed'
    text_counts = [0, 0, 0]
    errors = {'--max-steps=1': 'R_NO_STEP_ACCOUNTING', '--max-frames=1': 'R_NO_FRAME_ACCOUNTING',
              'MYLANG_MEMORY_LIMIT=1': 'R_MEMORY_BUDGET'}
    for row in text['checks']:
        if 'input' in row:
            case, size, iterations, seed = row['input']
            assert row['checksum'] == checksum(case, int(size), int(iterations), int(seed))
            text_counts[0] += 1
        elif 'binary' in row:
            assert sha(row['binary']) == row['sha256']
            assert sha(row['binary'] + '.qbe-manifest.json') == row['manifest_sha256']
            text_counts[2] += 1
        else:
            assert row['error'] == errors[row['control']]
            text_counts[1] += 1
    assert text_counts == [192, 6, 2]
    checks.append(binding('RF text oracles, recorded refusals and artifact identities', 'holdout', path))

    path, semantic = saved('integrated-semantics.json')
    assert semantic['source_revision'] == SOURCE and semantic['status'] == 'passed'
    assert semantic['focused_command_exit_status'] == 0
    assert semantic['focused_tests'] == dict(passed=42, failed=0, skipped=0)
    assert sha(CACHE / 'focused-units.log') == semantic['focused_log_sha256']
    assert len(semantic['append_outcomes']) == semantic['native_append_exact_pairs'] == 11
    for row in semantic['append_outcomes']:
        assert row['ordinary'] == row['fast']
        outcome = row['fast']
        if outcome['failed']:
            code = 'R_MEMORY_BUDGET' if row['max_memory'] is not None else 'R_OVERFLOW'
            assert outcome['trap']['code'] == code and outcome['status'] != 0
        else:
            count, seed = row['count'], row['seed']
            expected = 0 if count <= 0 else count + seed % 1009 + (seed + (count - 1) * 13) % 1009
            assert outcome['value'] == expected and outcome['status'] == expected % 256
            assert outcome['stdout'] == outcome['stderr'] == outcome['trap']['code'] == ''
    checks.append(binding('final-source focused append, mutation, readiness and producer-join checks', 'holdout', path))

    path, reuse = saved('native-reuse.json')
    assert reuse['source_revision'] == SOURCE
    assert reuse['status'] == 'source_matched_native_correctness_reuse'
    assert sha(reuse['prior_native_receipt']) == reuse['prior_native_receipt_sha256']
    assert sha(reuse['prior_native_log']) == reuse['prior_native_log_sha256']
    prior = read(reuse['prior_native_receipt'])
    assert prior['status'] == 'passed' and prior['exit_status'] == 0
    assert prior['suites'] == reuse['suites'] and prior['flags'] == reuse['flags']
    assert prior['compiler'] == reuse['C_compiler_identity_verified']
    assert sha(prior['compiler']['path']) == prior['compiler']['sha256']
    assert prior['mixed_width_outcomes'] == reuse['mixed_width_join_outcomes'] == 684
    files = reuse['source_files_sha256']
    assert len(files) == 114
    requests = ''.join(reuse['prior_native_source_revision'] + ':' + name + '\n' for name in files)
    objects = subprocess.run(['git', 'cat-file', '--batch'], cwd=ROOT, input=requests.encode(),
                             stdout=subprocess.PIPE, check=True).stdout
    offset = 0
    for name, digest in files.items():
        end = objects.index(b'\n', offset)
        _, kind, count = objects[offset:end].split()
        assert kind == b'blob'
        start, size = end + 1, int(count)
        assert hashlib.sha256(objects[start:start + size]).hexdigest() == digest, name
        assert sha(WORK / name) == sha(ROOT / name) == digest, name
        offset = start + size + 1
    assert offset == len(objects)
    for archive_name, original in (('reused-native-checks-receipt.json.gz', reuse['prior_native_receipt']),
                                   ('reused-native-checks.log.gz', reuse['prior_native_log'])):
        assert gzip.decompress((ARCHIVE / archive_name).read_bytes()) == Path(original).read_bytes()
    checks.append(binding('source-matched reused optimized C sanitizer suites, 114 source bindings', 'holdout', path))

    review = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  source_revision=SOURCE, execution_identity_sha256=identity_hash,
                  source_bindings=len(host['sources_after']), asset_bindings=len(identity['installed_assets']),
                  guest_bindings=len(identity['binary_paths']), frozen_reference_bindings=len(references),
                  qualification_outcomes=1440, holdout_outcomes=516, text_oracles=192,
                  text_recorded_refusals=6, text_live_identities=2, focused_tests=42, native_exact_pairs=11,
                  reused_native_source_bindings=114, reused_native_suites=5, reused_mixed_width_join_outcomes=684,
                  script_sha256=sha(__file__), checks=checks,
                  limitations=['Saved evidence replay and current file identities; no new guest executions.',
                               'Text helper asserted exit/output protocol, but saved rows retain checksums or refusal codes rather than full process streams.',
                               'Focused tests use Debug test tools on the final source; RF installed runtime artifacts were separately revalidated.',
                               'Five optimized C sanitizer suites are source-matched reused checks from448, not new executions on RF guest artifacts.',
                               'No fresh full repository correctness gate or full-suite timing claimed.'])
    review_path = Path(str(PREFIX) + '-correctness-review.json')
    checks_path = Path(str(PREFIX) + '-checks.json')
    for output in (review_path, checks_path):
        assert not output.exists(), output
    review_path.write_text(json.dumps(review, indent=2) + '\n')
    receipt = dict(schema='mylang-runtime-goal110-checks-v1', status='pass',
                   reviewed_utc=review['reviewed_utc'], execution_identity_sha256=identity_hash,
                   coverage=sessions[1]['coverage'], checks=checks,
                   review_receipt=dict(path=str(review_path), sha256=sha(review_path)),
                   limitations=review['limitations'])
    checks_path.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({k: v for k, v in review.items() if k not in ('checks', 'limitations')}))


if __name__ == '__main__':
    main()
