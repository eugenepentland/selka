#!/usr/bin/env python3
"""S5 conformance against the frozen old-core references (S5-D2).

S2's conformance_checked.py unchanged, except that the old core never runs:
`Tool.old` returns its frozen report from references/conformance-v1.json (each
test's name, status and trap code, which is all conformance.py compares).
`--references FILE` replaces `--mylang`; every other conformance.py option is the same.
"""
import argparse
import fnmatch
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]


def frontend_entries(files, supplement):
    """Map documented identities and add independent pre-fix frontend verdicts."""
    mappings = supplement['name_mappings']
    additions = supplement['files']
    if files.keys() & additions.keys():
        raise ValueError('frontend additions may not replace frozen files')
    result, used = {}, set()
    original_count = 0
    for name, entry in files.items():
        tests, seen = [], set()
        for old, status, reason in entry.get('tests', []):
            current = mappings.get(old, old)
            if old in mappings:
                used.add(old)
                if old.split('::')[0] != current.split('::')[0]:
                    raise ValueError('mapped test must remain in the same file')
            if current in seen:
                raise ValueError('duplicate identity after frontend mapping')
            seen.add(current)
            tests.append([current, status, reason])
            original_count += not fnmatch.fnmatchcase(old, '*arena*')
        result[name] = {**entry, 'tests': tests}
    if used != mappings.keys():
        raise ValueError('frontend mapping names an absent frozen identity')
    additional_count = 0
    for name, entry in additions.items():
        seen = set()
        for identity, status, reason in entry['tests']:
            if identity in seen or not identity.startswith(name + '::'):
                raise ValueError('duplicate or misplaced additional identity')
            if status != 'passed' or reason or fnmatch.fnmatchcase(identity, '*arena*'):
                raise ValueError('additional frontend reference must pass without exclusions')
            seen.add(identity)
        additional_count += len(seen)
        result[name] = entry
    if (original_count, additional_count) != (supplement['original_cases_per_mode'], supplement['additional_cases_per_mode']):
        raise ValueError('frozen or additional case count differs')
    return result, original_count + additional_count


def frontend_totals(totals, expected):
    return set(totals) == {'debug', 'release'} and all(
        (row.get('match'), row.get('mismatch'), row.get('unsupported')) == (expected, 0, 0)
        for row in totals.values())


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--references", type=Path, required=True)
    parser.add_argument("--frontend-reference", type=Path)
    parser.add_argument("--frontend-journal", type=Path)
    known, rest = parser.parse_known_args()
    files = json.loads(known.references.read_text())["files"]
    checked = load("conformance_checked", "experiments/new-core-s2-20261005/wave-b/integration/conformance_checked.py")
    sweep = load("conformance", "experiments/new-core-s1-20261005/conformance.py")
    original = sweep.parse
    sweep.parse = lambda done, what: checked.checked_report(original, done, what)
    journal, totals, identities = {}, {}, {}
    if known.frontend_reference:
        if known.frontend_journal is None or known.frontend_journal.exists():
            parser.error('--frontend-reference requires a fresh --frontend-journal')
        options = argparse.ArgumentParser(add_help=False)
        options.add_argument('--set')
        options.add_argument('--modes', default='debug,release')
        options.add_argument('--core', required=True)
        options.add_argument('--pin')
        options.add_argument('--include-arena', action='store_true')
        settings, _ = options.parse_known_args(rest)
        if settings.set != 'all' or settings.modes != 'debug,release' or settings.pin or settings.include_arena:
            parser.error('frontend qualification requires --set all, both modes, no --pin or --include-arena')
        supplement = json.loads(known.frontend_reference.read_text())
        if digest(known.references) != supplement['frozen_reference_sha256']:
            raise ValueError('frozen reference bytes differ')
        for name, expected_hash in supplement['sources_sha256'].items():
            if digest(Path(sweep.LANG) / (name + '.my')) != expected_hash:
                raise ValueError('frontend reference source differs: ' + name)
        files, expected = frontend_entries(files, supplement)
        for name, entry in files.items():
            if any(not fnmatch.fnmatchcase(t[0], '*arena*') for t in entry.get('tests', [])):
                if not (Path(sweep.LANG) / (name + '.my')).is_file():
                    raise ValueError('missing referenced source: ' + name)
        guarded = [known.references, known.frontend_reference, Path(settings.core), *Path(sweep.LANG).rglob('*.my')]
        identities = {str(p): digest(p) for p in guarded}
        journal = {'expected_per_mode': expected, 'original_per_mode': supplement['original_cases_per_mode'],
                   'additional_per_mode': supplement['additional_cases_per_mode'],
                   'reference_sha256': digest(known.references), 'frontend_reference_sha256': digest(known.frontend_reference),
                   'compiler_sha256': digest(settings.core), 'name_mappings': supplement['name_mappings']}
        table = sweep.table

        def capture(*args, **kwargs):
            text, values = table(*args, **kwargs)
            totals.update(values)
            return text, values

        sweep.table = capture
    elif known.frontend_journal:
        parser.error('--frontend-journal requires --frontend-reference')

    def frozen(self, path):
        entry = files.get(sweep.short(path))
        if entry is None:
            return "old core (frozen): no reference for %s" % sweep.short(path)
        if "problem" in entry:
            return entry["problem"]
        return {"tests": [{"name": name, "status": status, "reason": trap} for name, status, trap in entry["tests"]]}

    sweep.Tool.old = frozen
    sys.argv = [sys.argv[0], *rest]
    if not known.frontend_reference:
        return sweep.main()
    status = 1
    try:
        status = sweep.main()
    finally:
        unchanged = all(digest(path) == value for path, value in identities.items())
        complete = frontend_totals(totals, journal['expected_per_mode'])
        qualified = status == 0 and unchanged and complete
        journal.update(totals=totals, source_guard=unchanged, qualified=qualified)
        known.frontend_journal.write_text(json.dumps(journal, indent=2) + '\n')
    return int(not qualified)


if __name__ == "__main__":
    raise SystemExit(main())
