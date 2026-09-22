import hashlib, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/svg-gap-audit-20260921/host'
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
arms = ('control', 'counts', 'unchecked', 'memory-output')
data = {
  'compiler': str(ROOT / '.tmp/svg-gap-audit-20260921/mylang-audit-compiler'),
  'compiler_sha256': sha(ROOT / '.tmp/svg-gap-audit-20260921/mylang-audit-compiler'),
  'adapter_sha256': sha(ROOT / 'experiments/llvm-backend/qbe_llvm.py'),
  'guest_sources': {p.name: sha(p) for p in sorted((WORK / 'guest').glob('*.my'))},
  'arms': {a: {'provider_sha256': sha(HERE / f'native_{a.replace("-", "_")}.c'),
               'binary': str(WORK / a), 'binary_sha256': sha(WORK / a)} for a in arms},
}
(HERE / 'builds.json').write_text(json.dumps(data, indent=2) + '\n')
