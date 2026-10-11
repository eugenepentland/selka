"""Archive the coherent schema8 dictionary/set/Option qualification."""
import gzip
import hashlib
import io
import json
from pathlib import Path
import struct
import subprocess
import sys
import tarfile

root = Path('/home/epentland/.codex/worktrees/selka-compiler-probes/mylang')
work = Path('/home/epentland/ai/canopy/.selka-agent-cache/bootstrap-20261011/tmp')
lane = Path('/home/epentland/ai/canopy/.selka-agent-cache/lexer-b8')
source = lane / 'coherent-cf2-source'
prefix = lane / 'coherent-cf2-prefix'
out = root / 'docs/audits/evidence/selka-body-collections-cf2-20261011'
sys.path.insert(0, str(root / 'selfhost/tests'))
import run_body_dictionary_admission as A
import run_body_dictionary_hostile as H


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    return json.loads(path.read_text())


def retain(path, name):
    data = path.read_bytes()
    target = out / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(gzip.compress(data, mtime=0) if name.endswith('.gz') else data)


def commit(directory):
    assert not subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=directory)
    return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=directory, text=True).strip()


host = sha((prefix / 'bin/mylang').read_bytes())
assert host == 'b2351e1de5a0c927449abfc0857bb142e5183faaafb3b07bef977ec80ae4bbd7'
deployment = H.packages(prefix / 'libexec/mylang/components')
assert deployment['body-check']['sha256'] == 'c371fe99fd4be2bb4db848e92c311786394167aff5d9ad67883bbe3e9bcb08f2'
source_commit = commit(source)
harness_commit = commit(root)
selection, inventory = A.selection()
assert len(selection) == 34
assert len(H.require_inventory()['hostile_names']) == 27
out.mkdir()
reports = {}
for mode, basename in [('normal', 'cf2-admission-normal-second'), ('release', 'cf2-admission-release')]:
    report = read(lane / (basename + '.json'))
    assert report['complete'] and report['selected_admission'] == 'passed'
    assert report['operations'] == report['expected_operations'] == len(report['records']) == 246
    assert report['failed'] == report['skipped'] == report['profiles'] == 0
    assert report['fixtures'] == 34 and report['success'] == 24 and report['diagnostic'] == 10
    assert report['compiler_sha256'] == host and report['packages'] == deployment
    assert report['body_schema'] == 8 and report['native_controls'] is False
    assert report['release_facts_leaks'] == (mode == 'release')
    assert report['seed_verification']['status'] == 0
    seed = Path(bytes.fromhex(report['seed_verification']['stdout_hex']).decode().strip())
    assert sha(seed.read_bytes()) == report['qualified_seed_sha256'] == 'c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b'
    for record in report['records']:
        assert record['source_sha256'] == selection[record['name']]['source_sha256']
        for stream in ('stdout', 'stderr'):
            assert sha(bytes.fromhex(record[stream + '_hex'])) == record[stream + '_sha256']
    retain(lane / (basename + '.json'), mode + '.json.gz')
    retain(lane / (basename + '.log'), mode + '.log.gz')
    reports[mode] = {key: report[key] for key in ('operations', 'fixtures', 'success', 'diagnostic', 'failed', 'skipped')}

frames = {}
def frame(path, name, expected=None):
    raw = path.read_bytes()
    if expected is not None:
        assert sha(raw) == expected, path
    retain(path, 'frames/' + name + '.gz')
    frames[str(path)] = {'archive': 'frames/' + name + '.gz', 'sha256': sha(raw), 'bytes': len(raw)}
    return raw


replay_dir = lane / 'candidate-replay-cf2'
replay = read(replay_dir / 'requests.json')
assert replay['packages'] == deployment and replay['host_sha256'] == host
assert len(replay['cases']) == 34 and {r['source'] for r in replay['cases']} == set(selection)
assert replay['producer_engine_sha256'] == sha((source / 'selfhost/components/body_check/engine.my').read_bytes())
for case in replay['cases']:
    name = case['source']
    assert case['component_exact'] and case['shadow_exact']
    assert case['native_status'] == case['component_status'] == case['shadow_status'] == selection[name]['status']
    assert case['source_sha256'] == selection[name]['source_sha256'] == sha((replay_dir / 'sources' / name).read_bytes())
    request = frame(replay_dir / case['request'], case['request'], case['request_sha256'])
    reply = frame(replay_dir / case['reply'], case['reply'])
    H.bound_capture(request, reply)
    stem = Path(name).stem
    streams = [(replay_dir / (stem + '.' + mode + '.stderr')).read_bytes() for mode in ('reference', 'component', 'shadow')]
    assert streams[0] == streams[1] == streams[2]
    for mode in ('reference', 'component', 'shadow'):
        retain(replay_dir / (stem + '.' + mode + '.stderr'), 'stderr/' + stem + '.' + mode + '.stderr.gz')
    retain(replay_dir / 'sources' / name, 'fixtures/' + stem + '.input')
retain(replay_dir / 'requests.json', 'replay.json.gz')
retain(lane / 'candidate-replay-cf2.log', 'replay.log.gz')
retain(lane / 'replay_candidates_cf2.py', 'replay_candidates_cf2.py')
retain(replay_dir / 'sources/collection_donor.my', 'fixtures/collection_donor.my')

hostile_path = work / 'b8-cf2-hostile-corrected.json'
hostile = read(hostile_path)
assert hostile['complete'] and hostile['selected_admission'] == 'passed'
assert hostile['hostile'] == hostile['expected_hostile'] == len(hostile['records']) == 27
assert hostile['failed'] == hostile['skipped'] == 0 and tuple(hostile['names']) == H.NAMES
capture = hostile['capture']
assert capture['identity'] == {'host': host, 'packages': deployment}
assert capture['status'] == 0 and capture['stdout_hex'] == capture['stderr_hex'] == ''
request = frame(Path(capture['request_path']), 'hostile.request.bin', capture['request_sha256'])
reply = frame(Path(capture['reply_path']), 'hostile.reply.bin', capture['reply_sha256'])
H.bound_capture(request, reply)
assert capture['source_sha256'] == sha(H.SOURCE.read_bytes())
expected_mutations = H.mutations(reply[64:])
for record in hostile['records']:
    H.J.require_rejection((record['status'], bytes.fromhex(record['stdout_hex']), bytes.fromhex(record['stderr_hex'])))
    raw = frame(Path(record['payload_path']), 'hostile.' + record['name'] + '.bin', record['payload_sha256'])
    assert raw == expected_mutations[record['name']]
retain(hostile_path, 'hostile.json.gz')
retain(work / 'b8-cf2-hostile-corrected.log', 'hostile.log.gz')
retain(H.SOURCE, 'hostile.input')
for name in ('run_body_dictionary_admission.py', 'run_body_dictionary_hostile.py', 'body_dictionary_hostile_test.py'):
    retain(root / 'selfhost/tests' / name, 'harness/' + name)
for name in ('manifest.json', 'inventory.json'):
    retain(A.FIXTURES / name, 'fixtures/' + name)
retain(H.SOURCE.parent / 'inventory.json', 'hostile-inventory.json')

logs = ['coherent-cf2-install-second.log', 'native-set-snapshot-green-second.log', 'native-set-snapshot-commit-second.log']
for name in logs:
    retain(lane / name, name + '.gz')
assert 'Build Summary: 14/14 steps succeeded' in (lane / logs[0]).read_text()
assert '88 check(s) passed' in (lane / logs[2]).read_text()
retain(work / 'b8-hostile-correction-commit.log', 'hostile-correction-commit.log.gz')

source_files = subprocess.check_output(['git', 'ls-files', 'selfhost/components'], cwd=source, text=True).splitlines()
source_hashes = {}
buffer = io.BytesIO()
with tarfile.open(fileobj=buffer, mode='w') as archive:
    for name in sorted(source_files):
        raw = (source / name).read_bytes()
        source_hashes[name] = sha(raw)
        info = tarfile.TarInfo(name)
        info.size = len(raw)
        info.mode = 0o644
        archive.addfile(info, io.BytesIO(raw))
(out / 'component-sources.tar.gz').write_bytes(gzip.compress(buffer.getvalue(), mtime=0))
summary = {'schema': 8, 'selected_admission': 'passed', 'source_commit': source_commit,
           'native_donor': '5a18be34b5daec06c0025d3c0c904924912fb576', 'producer_donor': 'cf2e0048e',
           'harness_commit': harness_commit, 'host': host, 'packages': deployment,
           'qualified_seed_sha256': report['qualified_seed_sha256'], 'admission': reports,
           'genuine_replay_fixtures': 34, 'genuine_replay_checks': 102, 'hostile_refusals': 27,
           'root_integrated_full_gate': False, 'full_compiler_bootstrap': False, 'performance_acceptance': False,
           'extended_10_fixture_admission': 'pending on a newer producer; not qualified by these receipts',
           'frames': len(frames), 'component_source_sha256': source_hashes}
(out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
(out / 'frames.json').write_text(json.dumps(frames, indent=2) + '\n')
retain(Path(__file__), 'archive-b8-cf2.py')
(out / 'README.md').write_text('''# B8 dictionary, set and Option qualification

The immutable schema8 deployment passes all 34 selected fixtures: 246 operations in each of the normal and release lanes, plus 27 exact ComponentProtocol refusals generated from a genuine successful exchange. A separate fresh replay retains 34 request/reply pairs and exact reference/component/shadow results. The two admission reports include all commands, source identities and output bytes, generated release/fact/leak checks, and qualified seed verification.

The host is `b2351e1de5a0c927449abfc0857bb142e5183faaafb3b07bef977ec80ae4bbd7`; the body producer is `c371fe99fd4be2bb4db848e92c311786394167aff5d9ad67883bbe3e9bcb08f2`. `summary.json` binds all seven packages, native donor, producer donor, private source baseline and corrected harness commit. Component sources are retained with individual hashes. The installed build passed 14/14 steps; the native donor commit passed Guardian's 88 checks.

`frames.json` maps original paths to gzip archives, raw sizes and SHA256 values. Decompress each archive to recover the exact frame or hostile payload. Requests and replies retain their full framing, nonce and digest; the archiver verifies correlation and regenerates all 27 mutations byte for byte. The dictionary read attack targets typed `index`; the length attack changes native `i64` to `u64`. All original 27 attacks remain selected.

This is component qualification on the frozen cf2 producer. Integration into the root compiler, the newer ten-fixture extension set, full-language body checking, whole-compiler bootstrap and the 1.5× performance target remain unfinished. This archive contains no performance acceptance claim.
''')
for original, record in frames.items():
    raw = gzip.decompress((out / record['archive']).read_bytes())
    assert sha(raw) == record['sha256'] and len(raw) == record['bytes']
files = sorted(p for p in out.rglob('*') if p.is_file() and p.name != 'SHA256SUMS')
(out / 'SHA256SUMS').write_text(''.join(sha(p.read_bytes()) + '  ' + str(p.relative_to(out)) + '\n' for p in files))
print(json.dumps({'archive': str(out), 'files': len(files) + 1, 'frames': len(frames), 'admission': reports, 'hostile_refusals': 27}))
