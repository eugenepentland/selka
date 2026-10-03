#!/usr/bin/env python3
"""Current retrospective source/prefix/helper binding; no guest execution."""
from pathlib import Path
import hashlib, json
from prefixes_v2 import snapshot

lane = Path(__file__).resolve().parents[2]
work = lane / '.tmp-lox-native-policy-20261003'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
frozen = json.loads((work / 'frozen-source-v2.json').read_text())
prefix = json.loads((work / 'compiler-final-v2.json').read_text())
current = snapshot()
candidate_root = str((work / 'compiler-final-v2').resolve())
assert current[candidate_root] == prefix['owned_final_prefix']
historic = json.loads((work / 'builds-complete.json').read_text())['immutable_prefixes_after']
assert all(current[p] == files for p, files in historic.items())
assert all(sha(lane / p) == h for p, h in frozen['core'].items())
assert all(sha(Path(frozen['core_copy']) / p) == h for p, h in frozen['core'].items())
source = Path(frozen['source'])
assert {str(p.relative_to(source)): sha(p) for p in source.rglob('*') if p.is_file()} == frozen['source37']
helpers = [p for p in Path(__file__).parent.glob('*.py') if p.name.endswith('v2.py')]
helpers += [work / 'record.py']
report = dict(scope='Retrospective current postflight binding; no saved native full-prefix before/after claim.',
              native_prefix_scope='native-v2.py asserts equality of full prefix snapshots in memory. completed.json retains used compiler/guest/runtime/input before/after maps, not full prefix maps or all imported helpers.',
              source_descriptor_sha256=sha(work / 'frozen-source-v2.json'),
              authoritative_core_copy=frozen['core_copy'], core878=frozen['core'], source37=frozen['source37'],
              immutable_prefixes_current=current, candidate_prefix_matches_initial_descriptor=True,
              historical_prefixes_match_saved_maps=True,
              current_helpers_sha256={str(p): sha(p) for p in sorted(helpers)},
              receipts_sha256={name: sha(work / name) for name in ['compiler-final-v2.json', 'builds-v2.json',
                  'public-v2.json', 'equivalence-v2.json', 'producer-check-final-v2/qualification.json',
                  'native-v2/completed.json', 'native-v2-ceiling.json',
                  'selected-boundaries-verified-v2/qualification.json']},
              verified_current=True)
destination = work / 'postflight-v2.json'
assert not destination.exists()
destination.write_text(json.dumps(report, indent=2) + '\n')
print('Current source878/source37, frozen prefix maps and imported helpers bound retrospectively; no guest rerun')
