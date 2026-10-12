"""Reconcile fresh command reports and exact draft block hashes, keeping refusals."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

base = Path(__file__).resolve().parent
owner = base.parent
compiler_hash = '8b1898be7ad2f95cf53bf709f9d468b3bcfbabcaab2aaa7b5aa48d0163b2a789'
reports = ['commands-support5-0.json', 'commands-support5-10.json', 'commands-support5-20.json',
           'analysis-support5-0.json', 'analysis-support5-10.json', 'followup-support5.json', 'cost-support5.json']
commands = []
for name in reports:
    report = json.loads((owner / name).read_text())
    assert report['compiler_sha256'] == compiler_hash and report['success'], name
    for row in report['results']:
        command = row['argv'][1]
        scope = 'diagnostic-core' if command == 'dump-ir' else 'source-admission' if command.startswith('check') or command in ['lint', 'coverage', 'cost'] else 'executable-emission' if command == 'build' else 'guest-execution-or-receipt'
        commands.append(dict(report=name, name=row['name'], passed=row['passed'], qualification_scope=scope))
assert len(commands) == 52 and all(row['passed'] for row in commands)

def project(block):
    found = re.search(r'^# doc: project (\S+)\s*$', block['source'], re.MULTILINE)
    return found.group(1) if found else None

evidence = {}
paths = sorted(base.glob('docs-*support5*.json'))
# Corrected project-accounting report must supersede the retained initial harness error.
paths.sort(key=lambda path: (path.name.endswith('-project.json'), path.name))
for path in paths:
    report = json.loads(path.read_text())
    assert report['compiler_sha256'] == compiler_hash
    blocks = report['selected_blocks']
    flattened = '\n\n'.join('```mylang\n' + block['source'] + '```' for block in blocks) + '\n'
    offsets = [flattened.count('\n', 0, match.start()) + 1 for match in re.finditer(r'^```mylang\n', flattened, re.MULTILINE)]
    assert len(offsets) == len(blocks)
    by_line = dict(zip(offsets, blocks))
    covered = set()
    for unit in report['doctest_report']['units']:
        if unit['kind'] == 'project':
            name = unit['label'].split('#', 1)[1]
            selected = [block for block in blocks if project(block) == name]
        else:
            selected = [by_line[int(unit['label'].rsplit(':', 1)[1])]]
        assert selected
        for block in selected:
            key = (block['path'], block['sha256'])
            covered.add(key)
            evidence[key] = dict(report=str(path.relative_to(owner)), status=unit['status'], detail=unit['detail'], project=project(block))
    assert len(covered) == len(blocks), path

pages = [base / 'ownership-C2.md', base / 'managed-memory-C2.md', base / 'reference-docs/performance.md',
         base / 'reference-docs/python-syntax.md', base / 'reference-docs/tooling/guest-tests.md']
blocks = []
for path in pages:
    source = path.read_text()
    for match in re.finditer(r'^```mylang\n(.*?)^```\s*$', source, re.MULTILINE | re.DOTALL):
        digest = hashlib.sha256(match.group(1).encode()).hexdigest()
        key = (str(path.resolve()), digest)
        assert key in evidence, ('unqualified current block', key)
        row = dict(path=str(path.relative_to(owner)), line=source.count('\n', 0, match.start()) + 1, sha256=digest, **evidence[key])
        row['passed'] = row['status'] in ['run', 'checked']
        blocks.append(row)
assert len(blocks) == 51
failures = [block for block in blocks if not block['passed']]
for block in failures:
    block['owner'] = 'A04/A07' if 'round_float' in block['detail'] else 'A01/A07'
    block['classification'] = 'audited-helper contract pending' if 'round_float' in block['detail'] else 'dictionary tuple binding compiler refusal'
result = dict(source_revision='a1f19edf255c8c0886731d8d7cce450d5f657720', compiler_sha256=compiler_hash,
              selection='explicit --experimental-zero-rc, default unchanged', command_rows=commands,
              documents=dict(blocks=len(blocks), execution_or_check_units=len(blocks)-1,
                             passing_blocks=sum(row['passed'] for row in blocks),
                             passing_units=sum(row['passed'] for row in blocks)-1,
                             statuses=dict(Counter(row['status'] for row in blocks)), evidence=blocks),
              blockers=failures, package='Support5 staged libexec still legacy RC; no package qualification',
              milestones=dict(qualified_implementation=False, zero_rc_default=False, legacy_rc_retired=False),
              notes=['Original failing reports retained; explicit copy/index migrations qualify only their matching source hashes.',
                     'Initial final project batch harness incorrectly equated blocks with units; corrected rerun covers all3blocks as2checked units.',
                     'Source check and diagnostic Core dump success do not establish executable runtime admission.',
                     'Guest test status0 alone does not establish zero unsupported tests; command matrix checks JSON counts.'])
(owner / 'support5-summary.json').write_text(json.dumps(result, indent=2) + '\n')
print(f"commands {len(commands)}/{len(commands)}; doc blocks {result['documents']['passing_blocks']}/{len(blocks)}; blockers {len(failures)}")
