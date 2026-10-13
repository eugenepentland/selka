"""Run only the coordinator-released six frozen diagnostic leases."""
from pathlib import Path
import hashlib, json, os, subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PLAN = HERE / 'timing-plan-held.json'
def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(PLAN) == '267e8bac52a3c9c519e43fe38fbb19ee673525dff0b51ba7d38adfdf9f9c075b'
plan = json.loads(PLAN.read_text())
assert sha(plan['harness']['path']) == plan['harness']['sha256']
env = dict(os.environ)
env.pop('MYLANG_COUNTERS', None)
env.pop('MYL_CORE_LEAKCHECK', None)
records = []
for case in ['rds3+flat', 'cyclops-digital-pcb']:
    for lease in plan['cases'][case]['leases']:
        assert sha(lease['spec']) == lease['spec_sha256']
        assert not Path(lease['output']).exists(), 'inspect an interrupted lease before resuming'
        with (HERE / (lease['id'] + '.log')).open('w') as log:
            result = subprocess.run(lease['command'], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
        records.append({'id': lease['id'], 'command': lease['command'], 'returncode': result.returncode})
        (HERE / 'timing-admissions.json').write_text(json.dumps(records, indent=2) + '\n')
        assert result.returncode == 0, lease['id']
print('all six approved diagnostic leases returned; inspect all arm statuses and retained samples')
