"""Make an unapplied eight-page documentation patch against one immutable base."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--source-revision', required=True)
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args()
base = Path(__file__).resolve().parent
root = base.parents[3]
items = {'docs/managed-memory.md': base / 'managed-memory-C2.md',
         'docs/tooling/ownership.md': base / 'ownership-C2.md'}
for name in ['current-language.md', 'performance.md', 'python-syntax.md',
             'tooling/native-build.md', 'tooling/guest-tests.md', 'tooling/cost.md']:
    items['docs/' + name] = base / 'reference-docs' / name
patch = ''
identities = {}
for target, draft in sorted(items.items()):
    original = subprocess.check_output(['git', 'show', args.source_revision + ':' + target], text=True, cwd=root)
    if original != (root / target).read_text():
        raise ValueError('review current document changes before generating patch: ' + target)
    after = draft.read_text()
    patch += f'diff --git a/{target} b/{target}\n'
    patch += ''.join(difflib.unified_diff(original.splitlines(True), after.splitlines(True), fromfile='a/' + target, tofile='b/' + target))
    identities[target] = dict(original_sha256=hashlib.sha256(original.encode()).hexdigest(),
                             draft=str(draft.relative_to(root)), draft_sha256=hashlib.sha256(after.encode()).hexdigest())
args.output_dir.mkdir(parents=True, exist_ok=True)
output = args.output_dir / 'C2-docs.patch'
output.write_text(patch)
(args.output_dir / 'docs-identities.json').write_text(json.dumps(dict(
    source_revision=args.source_revision,
    status='UNAPPLIED; draft blocks use explicit zero-RC Support5, ordinary default qualification pending',
    files=identities, patch_sha256=hashlib.sha256(output.read_bytes()).hexdigest()), indent=2) + '\n')
