from pathlib import Path
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone

LANE = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003')
ROOT = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
WORK = LANE / '.tmp-lox-lowering'
COMPILER = WORK / 'cfg-fix-release/bin/mylang'
CONTROL = ROOT / '.tmp-lox-parity/carrier-final-sweep-build.json'
OUT = WORK / 'positive-cfg-fix-guest-replay.json'
control = json.loads(CONTROL.read_text())
source = Path(control['source'])

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def now():
    return datetime.now(timezone.utc).isoformat()

assert not OUT.exists()
assert COMPILER.exists()
source_hashes = {p.relative_to(source).as_posix(): sha(p) for p in source.rglob('*') if p.is_file()}
assert all(source_hashes[n] == h for n, h in control['source_sha256'].items())
receipt = {'control_receipt': str(CONTROL), 'control_receipt_sha256': sha(CONTROL), 'compiler': str(COMPILER),
           'compiler_sha256': sha(COMPILER), 'qbe_sha256': sha(COMPILER.with_name('qbe')),
           'source': str(source), 'source_sha256': source_hashes, 'builds': [], 'verified_after': False}
env = dict(os.environ, TMPDIR=str(WORK/'tmp'))
(WORK/'cfg-fix-guests').mkdir()
for prior in control['builds']:
    backend = prior['codegen']['backend']
    output = WORK/'cfg-fix-guests'/('final-sweep-'+backend)
    log = WORK/('positive-cfg-fix-guest-'+backend+'.log')
    argv = list(prior['argv'])
    argv[0], argv[2] = str(LANE/'scripts/build-slot.sh'), str(COMPILER)
    argv[argv.index('--cache-dir')+1] = str(WORK/('cache-cfg-fix-final-sweep-'+backend))
    argv[argv.index('-o')+1] = str(output)
    row = {'command': argv, 'cwd': str(LANE), 'TMPDIR': env['TMPDIR'], 'started_utc': now(), 'log': str(log)}
    print('Building',backend,flush=True)
    with log.open('wb') as stream:
        done = subprocess.run(argv,cwd=LANE,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=900)
    row.update(status=done.returncode, finished_utc=now(), log_sha256=sha(log))
    assert done.returncode == 0, row
    row['binary'] = str(output)
    row['binary_sha256'] = sha(output)
    row['measured_control_binary'] = prior['argv'][prior['argv'].index('-o')+1]
    row['measured_control_sha256'] = prior['binary_sha256']
    assert sha(row['measured_control_binary']) == row['measured_control_sha256']
    row['byte_identical_to_measured_control'] = row['binary_sha256'] == prior['binary_sha256']
    receipt['builds'].append(row)
    OUT.write_text(json.dumps(receipt,indent=2)+'\n')
    print(backend,row['binary_sha256'],'identical',row['byte_identical_to_measured_control'],flush=True)
assert source_hashes == {p.relative_to(source).as_posix(): sha(p) for p in source.rglob('*') if p.is_file()}
assert sha(COMPILER) == receipt['compiler_sha256']
assert sha(COMPILER.with_name('qbe')) == receipt['qbe_sha256']
assert sha(CONTROL) == receipt['control_receipt_sha256']
receipt['verified_after'] = True
receipt['all_guests_byte_identical'] = all(r['byte_identical_to_measured_control'] for r in receipt['builds'])
OUT.write_text(json.dumps(receipt,indent=2)+'\n')
print('Receipt',OUT,'verified_after=True',flush=True)
