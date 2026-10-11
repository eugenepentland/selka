"""Prepare portable, deduplicated private B7 proof; root qualification stays separate."""
import gzip
import hashlib
import io
import json
from pathlib import Path
import shutil
import tarfile

WORK = Path('/home/epentland/ai/canopy/.selka-agent-cache/bootstrap-20261011/tmp')
REPORTS = WORK/'b7-private-entry-generations'
SOURCE = Path('/home/epentland/ai/canopy/.selka-agent-cache/lexer-b7/source')
OUT = WORK/'b7-entry-portable-evidence'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    reports = {lane: json.loads((REPORTS/(lane+'.json')).read_text()) for lane in ('normal', 'release')}
    assert all(d['complete'] and d['operations'] == 349 and len(d['captures']) == 35 and
               len(d['resource_forged']) == 15 and len(d['generations']) == 2 and
               d['failed'] == d['skipped'] == 0 for d in reports.values())
    assert reports['normal']['identity'] == reports['release']['identity']
    OUT.mkdir(exist_ok=True)
    (OUT/'frames').mkdir(exist_ok=True)
    for name in ('composed-frontend-check.py', 'composed-frontend-check.log', 'composed-frontend-check.json.gz'):
        shutil.copyfile(WORK/'b7-entry-prepared-evidence'/name, OUT/name)
    paths = {}

    def retain_frame(path, expected, archive_sha=None):
        original = path.read_bytes()
        if archive_sha is not None:
            assert digest(original) == archive_sha
            raw = gzip.decompress(original)
        else:
            raw = original
        assert digest(raw) == expected
        # Request correlation headers differ across otherwise identical entry
        # exchanges. Preserve every header exactly, while storing common graph
        # payloads once. Reconstruction must reproduce each complete frame hash.
        header = raw[:64] if raw.startswith(b'SLKBCK01') and len(raw) >= 64 else b''
        payload = raw[len(header):]
        compressed = gzip.compress(payload, mtime=0)
        name = 'frames/'+digest(compressed)+'.bin.gz'
        target = OUT/name
        if target.exists():
            assert target.read_bytes() == compressed
        else:
            target.write_bytes(compressed)
        paths[str(path)] = {'archive': name, 'archive_sha256': digest(compressed),
                            'header_hex': header.hex(), 'frame_sha256': expected,
                            'frame_bytes': len(raw), 'original_archive_sha256': archive_sha}

    generations = {}
    for lane, report in reports.items():
        (OUT/(lane+'.json.gz')).write_bytes(gzip.compress((REPORTS/(lane+'.json')).read_bytes(), mtime=0))
        for capture in report['captures']:
            for direction in ('request', 'reply'):
                retain_frame(Path(capture[direction+'_path']), capture[direction+'_sha256'],
                             capture[direction+'_archive_sha256'])
        capture = report['resource_forged_capture']
        for direction in ('request', 'reply'):
            retain_frame(Path(capture[direction+'_path']), capture[direction+'_sha256'])
        for record in report['resource_forged']:
            retain_frame(Path(record['payload_path']), record['payload_sha256'])
        first, second = report['generations']
        generations[lane] = {name: first['packages'][name]['sha256'] == second['packages'][name]['sha256']
                             for name in first['packages']}
    invocation = Path(reports['normal']['captures'][0]['request_path']).parent.parent
    requests = invocation/'runtime-requests'
    inventory = json.loads((requests/'requests.json').read_text())
    assert inventory['complete'] and len(inventory['packages']) == 7
    (OUT/'runtime-requests.json.gz').write_bytes(gzip.compress((requests/'requests.json').read_bytes(), mtime=0))
    for entry in inventory['packages'].values():
        retain_frame(requests/entry['file'], entry['sha256'])
    for path in requests.glob('*.reply'):
        retain_frame(path, digest(path.read_bytes()))

    sources = reports['normal']['identity']['sources']
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w') as archive:
        for name, expected in sorted(sources.items()):
            raw = (SOURCE/name).read_bytes()
            assert digest(raw) == expected, name
            info = tarfile.TarInfo(name)
            info.size = len(raw)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(raw))
    (OUT/'frozen-component-sources.tar.gz').write_bytes(gzip.compress(buffer.getvalue(), mtime=0))
    (OUT/'retained-paths.json').write_text(json.dumps(paths, indent=2)+'\n')
    for record in paths.values():
        compressed = (OUT/record['archive']).read_bytes()
        assert digest(compressed) == record['archive_sha256']
        frame = bytes.fromhex(record['header_hex']) + gzip.decompress(compressed)
        assert len(frame) == record['frame_bytes'] and digest(frame) == record['frame_sha256']
    summary = {'scope': 'private B7 two-generation component proof; native catalog/backend/driver retained; not root qualification or full compiler bootstrap',
               'producer_commit': '085ae768a8958a07caf74ba181db5c1f1f2287fb',
               'native_commit': '18da27cc0', 'runner_commit': '7de60b8dc990b4cd5ac848e48623eb63ff73de08',
               'lanes': ['normal', 'release/facts/leaks'], 'operations_per_lane': 349,
               'captures_per_lane': 35, 'resource_forgeries_per_lane': 15,
               'identical_generation_artifacts': generations, 'frozen_source_files': len(sources),
               'retained_paths': len(paths), 'unique_archives': len({v['archive'] for v in paths.values()}),
               'frame_storage': 'Every complete frame reconstructs as bytes.fromhex(header_hex) + gzip.decompress(archive); all original frame hashes verified. Original gzip-container hashes are provenance only.'}
    (OUT/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    shutil.copyfile(Path(__file__), OUT/Path(__file__).name)
    shutil.copyfile(WORK/'b7-private-entry-generations.log', OUT/'private-generation.log')
    (OUT/'SHA256SUMS').write_text(''.join(digest(p.read_bytes())+'  '+str(p.relative_to(OUT))+'\n'
        for p in sorted(OUT.rglob('*')) if p.is_file() and p.name != 'SHA256SUMS'))
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
