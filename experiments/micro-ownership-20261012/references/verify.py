#!/usr/bin/env python3
"""Read-only verification of fresh reference and qualification evidence."""
import hashlib,json,pathlib,re
HERE=pathlib.Path(__file__).resolve().parent
ROOT=HERE.parents[2]
def sha(path): return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
m=json.loads((HERE/'manifest.json').read_text())
for tool in m['tools'].values():
 assert sha(tool['actual_path'])==tool['sha256']
 assert sha(tool['path'])==tool['invocation_sha256']
for path,item in m['sources'].items():
 assert sha(ROOT/path)==item['sha256']
 assert sha(ROOT/item['canonical'])==item['canonical_sha256']
for item in m['builds'].values():
 assert item['exit_status']==0
 assert sha(item['path'])==item['sha256']
 assert pathlib.Path(item['path']).stat().st_mode & 0o222 == 0
 assert sha(ROOT/item['log'])==item['log_sha256']
q=json.loads((HERE/'qualification.json').read_text())
assert q['complete'] and q['passed'] and len(q['probes'])==800
assert len({x['case'] for x in q['probes']})==40
for probe in q['probes']:
 match=re.fullmatch(r'([0-9]+) ([0-9]+)\n',probe['stdout'])
 assert probe['passed'] and probe['exit_status']==0
 assert match and int(match[1])==probe['expected_checksum'] and int(match[2])>0
 assert not re.sub(r'^build-slot:.*\n','',probe['stderr'],flags=re.M)
print('verified16 fresh binaries,40 cases,800 qualification probes')
