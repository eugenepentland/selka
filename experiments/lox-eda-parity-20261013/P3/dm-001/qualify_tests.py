"""Fresh focused baseline plus candidate canonical checked qualification, under one shared build admission."""
from pathlib import Path
import hashlib, json, os, subprocess

HERE = Path(__file__).resolve().parent
SCRATCH = Path('/home/epentland/ai/canopy/mylang/.tmp/lox-eda-parity/P3/dm-001')
COMPILER = Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/coordinator/common-002/install/bin/mylang')
def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert os.environ.get('MYLANG_ADMISSION_KIND') == 'build'
assert sha(COMPILER) == '9bedb835438615d79ed8f2985352877a8c844eebeb74cd95a1d276332b6b0c6a'
focused = json.loads((HERE / 'focused-candidate.json').read_text())
assert focused['passed'] == 3 and all(focused[k] == 0 for k in ['failed', 'cached', 'skipped', 'unsupported'])
pins = json.loads((HERE / 'source-pins.json').read_text())
def unchanged():
    for arm, files in pins.items():
        assert {p.name: sha(p) for p in (SCRATCH / arm / 'eda').glob('*.my')} == files
reuse = json.loads((HERE / 'baseline-reuse.json').read_text())
assert all(sha(Path(reuse['installation']) / p) == v for p, v in reuse['installation_files'].items())
focused_pins = json.loads((HERE / 'focused-source-pins.json').read_text())
assert all(sha(p) == v for files in focused_pins.values() for p, v in files.items())
records = []
for arm in ['focused-baseline', 'candidate']:
    unchanged()
    command = [str(COMPILER), 'test', str(SCRATCH / arm / 'eda' / 'p3_dm_tests.my') if arm == 'focused-baseline' else str(SCRATCH / arm / 'eda'),
               '--experimental-zero-rc', '--verify-facts', '--force', '--jobs', '4',
               '--max-steps', '1000000000', '--max-frames', '40000', '--max-memory', '2G',
               '--timeout-ms', '120000', '--cache-dir', str(SCRATCH / ('cache-suite-' + arm)), '--json']
    with (HERE / (arm + '-suite.json')).open('w') as out, (HERE / (arm + '-suite.stderr')).open('w') as err:
        result = subprocess.run(command, stdout=out, stderr=err, env={**os.environ, 'MYL_CORE_LEAKCHECK': '1'})
    unchanged()
    records.append({'arm': arm, 'command': command, 'returncode': result.returncode})
    (HERE / 'suite-commands.json').write_text(json.dumps(records, indent=2) + '\n')
    assert result.returncode == 0
    doc = json.loads((HERE / (arm + '-suite.json')).read_text())
    assert doc['passed'] == (3 if arm == 'focused-baseline' else 328) and all(doc[k] == 0 for k in ['failed', 'cached', 'skipped', 'unsupported'])
print('fresh baseline focused3/3 and candidate canonical328/328 pass; baseline canonical328 reused via pinned five-mode receipts')
