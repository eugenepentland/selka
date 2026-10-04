"""Read-only lexical diagnostic of frozen actual IL; not an admission proof."""
import collections
import csv
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
SOURCE = next((ROOT / '.mylang-cache/goal110-scalar-slots-guests/llvm-dump').glob('myl_f_b5*.ssa'))
definitions = collections.defaultdict(list)
uses = collections.defaultdict(list)
block, position = '', 0
for line_number, line in enumerate(SOURCE.read_text().splitlines(), 1):
    text = line.strip()
    if text.startswith('@'):
        block, position = text, 0
        continue
    if not text or text.startswith(('#', 'dbg', 'type', 'export', '}')):
        continue
    definition = re.match(r'(%[\w.]+)\s*=([^ ]+)\s+(.*)', text)
    name = definition[1][1:] if definition else None
    body = definition[3] if definition else text
    row = {'line': line_number, 'block': block, 'position': position, 'text': text,
           'dest': name, 'type': definition[2] if definition else None, 'body': body}
    position += 1
    if name:
        definitions[name].append(row)
    for reference in re.findall(r'%([\w.]+)', body):
        uses[reference].append(row)

baseline = {row['temporary'] for row in csv.DictReader(
    (EVIDENCE / 'actual-compute-admissions.tsv').open(), delimiter='\t') if row['admitted'] == 'true'}
roots = [name for name, rows in definitions.items() if len(rows) == 1 and rows[0]['type'] == 'l'
         and rows[0]['block'] == '@entry' and re.fullmatch(r'alloc(?:8|16) 8', rows[0]['body'])]
records = []
for root in roots:
    aliases, pending, copies, refusals = {root}, [root], [], []
    while pending:
        name = pending.pop()
        defining = definitions[name][0]
        for row in uses[name]:
            same_block_after = row['block'] == defining['block'] and row['position'] > defining['position']
            allowed_position = same_block_after if name != root else (
                row['block'] != defining['block'] or same_block_after)
            copy = re.fullmatch(r'copy %([\w.]+)', row['body'])
            if copy and row['dest'] and row['type'] == 'l' and len(definitions[row['dest']]) == 1:
                if allowed_position:
                    copies.append({'source': name, **row})
                    if row['dest'] not in aliases:
                        aliases.add(row['dest'])
                        pending.append(row['dest'])
                    continue
            address = re.fullmatch(r'loadl %([\w.]+)', row['body']) or re.fullmatch(
                r'storel (?:[^%]*|%[\w.]+), %([\w.]+)', row['body'])
            stored_pointer = row['body'].startswith('storel %' + name + ',')
            if address and address[1] == name and allowed_position and not stored_pointer:
                continue
            refusals.append({'subject': name, **row})
    records.append({'root': root, 'allocation': definitions[root], 'baseline_admitted': root in baseline,
                    'transitive_alias_count': len(aliases) - 1, 'copies': copies, 'refusals': refusals})

new_candidates = [row['root'] for row in records if not row['baseline_admitted'] and not row['refusals']]
report = {'kind': 'preliminary-lexical-diagnostic-not-admission-proof',
          'input': str(SOURCE), 'input_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
          'runner_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          'baseline_admitted_count': len(baseline), 'entry_exact8_scalar_count': len(roots),
          'additional_same_block_word_only_alias_candidates': new_candidates, 'records': records,
          'limits': 'Simple lexical diagnostic of this frozen generated IL. Production admission remains the Zig proof.'}
(EVIDENCE / 'actual-copy-use-diagnostic.json').write_text(json.dumps(report, indent=2) + '\n')
print('baseline admitted', len(baseline), '; additional local word-only alias candidates', new_candidates)
for row in records:
    if row['root'] in ('s0', 's1', 's2', 's3'):
        print(row['root'], 'copy aliases', row['transitive_alias_count'], 'refusals', len(row['refusals']))
        for refusal in row['refusals']:
            print(' ', refusal['line'], refusal['text'], refusal['block'])
