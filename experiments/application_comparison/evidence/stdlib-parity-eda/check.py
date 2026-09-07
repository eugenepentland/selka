"""Public construction oracle comparison, never a timed participant trial."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from experiments.application_comparison.eda_oracle import generated_cases, response_bytes

exe = Path(sys.argv[1]).resolve()
executable_sha256 = hashlib.sha256(exe.read_bytes()).hexdigest()
project = ROOT / 'experiments/application_comparison/baselines/eda/my'
requests = [json.dumps(generated_cases(seed, 64), separators=(',', ':')).encode()
            for seed in (1701, 2917, 4409)]
requests += [b'{"cases":[]}', b'{"cases":[{"x":1,"\\u0078":2}]}',
             b'{"cases":[1.7976931348623158e308]}',
             b'{"cases":[1.7976931348623159e308]}', b'{"cases":[1e-999999]}',
             b'{"cases":["\\ud83d\\ude00"]}', b'{"cases":["\\ud800"]}']
checks = []
for raw in requests:
    run = subprocess.run([str(exe), '--project', str(project)], input=raw,
                         capture_output=True, timeout=120)
    expected = response_bytes(raw)
    passed = run.returncode == 0 and json.loads(run.stdout) == expected
    checks.append(dict(input_sha256=hashlib.sha256(raw).hexdigest(), input_bytes=len(raw),
                       output_sha256=hashlib.sha256(run.stdout).hexdigest(), passed=passed,
                       exit_code=run.returncode, stderr=run.stderr.decode(errors='replace')))
    assert passed, checks[-1]
report = dict(kind='untimed-baseline-migration-validation', comparative_claim=False,
              executable_sha256=executable_sha256,
              executable_unchanged=hashlib.sha256(exe.read_bytes()).hexdigest() == executable_sha256,
              local_library_sources={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                     for p in project.glob('std_*.my')},
              source_sha256=hashlib.sha256((project/'main.my').read_bytes()).hexdigest(),
              generated_boards=192, transport_probes=7, checks=checks,
              development_wall_seconds=None, agent_turns=None, tokens=None, compute_cost=None)
print(json.dumps(report, indent=2))
