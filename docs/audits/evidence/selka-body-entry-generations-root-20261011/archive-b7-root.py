"""Retain a completed root B7 gate and reconstructable authenticated exchanges."""
import argparse
from collections import Counter
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ('root', 'work', 'cache', 'out'):
        ap.add_argument('--'+name, type=Path, required=True)
    ap.add_argument('--source-commit', required=True)
    ap.add_argument('--host', required=True)
    ap.add_argument('--body', required=True)
    ap.add_argument('--gate-log', default='b7-root-full-gate.log')
    ap.add_argument('--exit-status', type=int, required=True)
    args = ap.parse_args()
    text = (args.work/args.gate_log).read_text()
    summaries = re.findall(r'^Build Summary: (.+)$', text, re.M)
    assert len(summaries) == 1, 'no complete root gate'
    assert ('failed' in summaries[0]) == (args.exit_status != 0), 'exit status contradicts summary'
    assert 'body_check gate: 281 pure tests per mode; complete qualification passed' in text
    assert 'body entry gate: normal and release 349 operations/35 captures/15 resource attacks each; 0 failed, 0 skipped' in text
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=args.root, text=True).strip() == args.source_commit
    assert not subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=args.root, text=True)
    assert digest((args.root/'zig-out/bin/mylang').read_bytes()) == args.host
    args.out.mkdir()
    (args.out/'frames').mkdir()
    paths, blobs, report_paths = {}, {}, {}

    def retain_file(path, name):
        data = path.read_bytes()
        (args.out/name).write_bytes(gzip.compress(data, mtime=0) if name.endswith('.gz') else data)

    def frame(path, expected, archive_sha=None):
        path = Path(path)
        original = path.read_bytes()
        if archive_sha is not None:
            assert digest(original) == archive_sha
            raw = gzip.decompress(original)
        else:
            raw = original
        assert digest(raw) == expected, path
        header = raw[:64] if raw.startswith(b'SLKBCK01') and len(raw) >= 64 else b''
        payload = raw[len(header):]
        payload_sha = digest(payload)
        if payload_sha not in blobs:
            compressed = gzip.compress(payload, mtime=0)
            compressed_sha = digest(compressed)
            name = 'frames/'+compressed_sha+'.bin.gz'
            (args.out/name).write_bytes(compressed)
            blobs[payload_sha] = name, compressed_sha
        name, compressed_sha = blobs[payload_sha]
        paths[str(path)] = {'archive': name, 'archive_sha256': compressed_sha,
                            'header_hex': header.hex(), 'frame_sha256': expected,
                            'frame_bytes': len(raw), 'original_archive_sha256': archive_sha}

    def select(pattern, matches):
        candidates = []
        for path in args.cache.glob(pattern):
            data = json.loads(path.read_text())
            if matches(data):
                candidates.append((path, data))
        assert candidates, pattern
        return max(candidates, key=lambda item: item[0].stat().st_mtime_ns)

    main_reports = {}
    for lane, comparisons in (('normal', 1772), ('release', 886)):
        path, data = select('*/body-check-qualification/'+lane+'.json',
                            lambda d: d.get('host_sha256') == args.host and d.get('comparisons') == comparisons)
        assert data['packages']['body-check']['sha256'] == args.body
        assert data['workflows'] == 443 and data['failed'] == data['skipped'] == 0
        assert data['forged_reply_checks'] == 92 and data['warm_deployment_checks'] == 30 and data['live_session_checks'] == 4
        retain_file(path, 'body-check-'+lane+'.json.gz')
        report_paths['body-check-'+lane] = str(path)
        main_reports[lane] = {k: data[k] for k in ('workflows', 'comparisons', 'forged_reply_checks', 'warm_deployment_checks', 'live_session_checks')}

    entries, generations = {}, {}
    for lane in ('normal', 'release'):
        path, data = select('*/body-entry-admission/'+lane+'.json',
                            lambda d: d.get('identity', {}).get('host') == args.host)
        assert data['complete'] and data['operations'] == data['expected_operations'] == 349
        assert len(data['captures']) == 35 and len(data['resource_forged']) == 15 and len(data['generations']) == 2
        assert data['failed'] == data['skipped'] == 0 and data['identity']['packages']['body-check']['sha256'] == args.body
        retain_file(path, 'entry-'+lane+'.json.gz')
        report_paths['entry-'+lane] = str(path)
        entries[lane] = data
        for capture in data['captures']:
            for direction in ('request', 'reply'):
                frame(capture[direction+'_path'], capture[direction+'_sha256'], capture[direction+'_archive_sha256'])
        for direction in ('request', 'reply'):
            capture = data['resource_forged_capture']
            frame(capture[direction+'_path'], capture[direction+'_sha256'])
        for record in data['resource_forged']:
            frame(record['payload_path'], record['payload_sha256'])
        first, second = data['generations']
        generations[lane] = {name: first['packages'][name]['sha256'] == second['packages'][name]['sha256'] for name in first['packages']}
    assert entries['normal']['identity'] == entries['release']['identity']
    assert all(all(rows.values()) for rows in generations.values())
    request_root = Path(entries['normal']['captures'][0]['request_path']).parent.parent/'runtime-requests'
    requests = json.loads((request_root/'requests.json').read_text())
    assert requests['complete'] and len(requests['packages']) == 7
    retain_file(request_root/'requests.json', 'runtime-requests.json.gz')
    for entry in requests['packages'].values():
        frame(request_root/entry['file'], entry['sha256'])
    for path in request_root.glob('*.reply'):
        frame(path, digest(path.read_bytes()))

    path, library = select('*/body-library-admission.json', lambda d: d.get('compiler_sha256') == args.host)
    assert library['complete'] and library['operations'] == 213 and library['join_forged_checks'] == 4
    assert library['failed'] == library['skipped'] == 0
    retain_file(path, 'library-admission.json.gz')
    report_paths['library'] = str(path)
    join_root = Path(library['join_forged_records'][0]['payload_path']).parent
    for path in join_root.glob('*.bin'):
        frame(path, digest(path.read_bytes()))
    retain_file(join_root/'join_capture.my', 'join_capture.input')

    sources = entries['normal']['identity']['sources']
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w') as archive:
        for name, expected in sorted(sources.items()):
            raw = (args.root/name).read_bytes()
            assert digest(raw) == expected, name
            info = tarfile.TarInfo(name)
            info.size = len(raw)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(raw))
    (args.out/'frozen-component-sources.tar.gz').write_bytes(gzip.compress(buffer.getvalue(), mtime=0))
    guardian = [json.loads(row) for row in re.findall(r'^guardian/test: RESULT (.+)$', text, re.M)]
    assert guardian and all(row['failed'] == row['skipped'] == 0 for row in guardian)
    pure = {}
    for path in sorted((args.root/'selfhost/components/body_check').glob('*tests.my')):
        names = re.findall(r'^public func (test_[A-Za-z0-9_]+)\(', path.read_text(), re.M)
        if names:
            pure[str(path.relative_to(args.root))] = names
    assert len(pure) == 45 and sum(map(len, pure.values())) == 281
    for name in (args.gate_log, 'b7-root-debug-install.log', 'b7-root-integration-commit.log', 'b7-root-qualification-selfchecks.log'):
        retain_file(args.work/name, name+'.gz')
    fixtures = json.loads((args.root/'selfhost/tests/fixtures/body_check/manifest.json').read_text())
    summary = {'source_commit': args.source_commit, 'host': args.host, 'body': args.body,
               'full_gate_passed': args.exit_status == 0, 'exit_status': args.exit_status, 'build_summary': summaries[0],
               'guardian_verdicts': guardian, 'guardian_totals': {k: sum(row[k] for row in guardian) for k in ('passed', 'failed', 'skipped')},
               'main_reports': main_reports, 'report_paths': report_paths,
               'pure_test_roots': pure, 'pure_tests_per_mode': 281,
               'fixture_statuses': dict(Counter(row['status'] for row in fixtures.values())),
               'generation_byte_identity': generations, 'retained_frames': len(paths), 'unique_payload_archives': len(blobs),
               'source_files': len(sources), 'full_compiler_bootstrap': False,
               'performance_acceptance': False,
               'retained_native': ['catalog', 'later semantic passes', 'Core/LLVM backend', 'compiler driver']}
    (args.out/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    (args.out/'retained-paths.json').write_text(json.dumps(paths, indent=2)+'\n')
    shutil.copyfile(__file__, args.out/'archive-b7-root.py')
    shutil.copyfile(args.root/'docs/audits/evidence/selka-body-entry-generations-private-20261011/reconstruct_frame.py', args.out/'reconstruct_frame.py')
    for item in paths.values():
        archived = (args.out/item['archive']).read_bytes()
        assert digest(archived) == item['archive_sha256']
        raw = bytes.fromhex(item['header_hex']) + gzip.decompress(archived)
        assert len(raw) == item['frame_bytes'] and digest(raw) == item['frame_sha256']
    files = sorted(p for p in args.out.rglob('*') if p.is_file() and p.name != 'SHA256SUMS')
    (args.out/'SHA256SUMS').write_text(''.join(f'{digest(p.read_bytes())}  {p.relative_to(args.out)}\n' for p in files))
    print(json.dumps({k: v for k, v in summary.items() if k not in ('guardian_verdicts', 'pure_test_roots')}, indent=2))


if __name__ == '__main__':
    main()
