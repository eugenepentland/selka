#!/usr/bin/env python3
"""Stage directory-wide live fixes before embedded migration; retain receipts.

Run through regenerate_language_wave1.sh, which owns build admission and flock.
Protected .selka files are absent from staging, never passed to the fix driver.
Only tracked selected .selka files are published; no compiler edits are copied back.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import migrate_embedded as embedded

# Keep mixed diagnostic fixture trees outside the broad roots. Include only
# their explicitly reviewed live provider graphs and the verification smoke input.
LIVE_ROOTS = (
    'src/stdlib', 'tests/lang', 'tests/guest', 'tests/ported',
    'tests/value_semantics', 'tests/stress', 'tests/verification/smoke.selka',
    'src/core/a02_indirect_owned_fixture.selka',
    'src/core/a02_public_constructors_fixture.selka',
    'src/core/a02_scalar_child_fixture.selka',
    'src/core/a02_scalar_child_reduced.selka',
    'src/core/a05_scalar_mut_fixture.selka',
    'src/core/a07_lifecycle_fixture.selka',
    'src/core/compact_sret_narrow.selka',
    'src/core/gap_sort_fixture.selka',
    'test/core', 'test/fixtures/domains.selka',
    'test/fixtures/application-cache/application.selka',
    'test/fixtures/environment.selka', 'test/fixtures/external-capabilities.selka',
    'test/fixtures/mutation-markers.selka', 'test/fixtures/resource-io.selka',
    'test/fixtures/resources.selka', 'tests/fixtures/interfaces',
    'tests/fixtures/module_projects', 'tests/fixtures/incremental',
    'tests/fixtures/interfaces_generic',
    'examples', 'bench', 'benchmarks', 'velocity',
)

# This host-loaded fixture has a historical non-module filename. Its only
# imports are embedded standard modules; preserve the public fixture path.
FILE_ENTRY_ALIASES = {
    'test/fixtures/external-capabilities.selka': 'external_capabilities.selka',
}

def sha(data):
    return hashlib.sha256(data).hexdigest()

def tracked_live_sources(selected, tracked, root):
    """Publish only tracked live guest sources; seed components stay manual."""
    names = set(tracked)
    return [path for path in selected
            if path.suffix == '.selka' and path.relative_to(root).as_posix() in names
            and not path.relative_to(root).as_posix().startswith('selfhost/')
            and not any(block.excluded for block in embedded.extract_sources(path))]


def protected_snapshot(root, tracked):
    """Keep whole protected files and individual excluded host block envelopes."""
    files = {}
    blocks = {}
    for name in tracked:
        path = root / name
        if not path.is_file() or path.suffix not in embedded.SUFFIXES:
            continue
        if embedded.path_exclusion(path, root):
            files[name] = sha(path.read_bytes())
            continue
        text = embedded.read_text(path)
        lines = text.splitlines(keepends=True)
        kept = []
        for block in embedded.extract_sources(path, text):
            if block.excluded:
                raw = text[block.host_span[0]:block.host_span[1]] if block.host_span else ''.join(lines[block.start:block.end])
                kept.append({'kind': block.kind, 'sha256': sha(raw.encode())})
        if kept:
            blocks[name] = kept
    return {'files': files, 'blocks': blocks}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--report-dir', type=Path, required=True)
    parser.add_argument('--root', action='append', help='repository-relative live directory, repeatable')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--directory-only', action='store_true', help='publish directory fixes and receipt, then stop for manual review')
    parser.add_argument('--timeout', type=float, default=120, help='per embedded source timeout')
    parser.add_argument('--directory-timeout', type=float, default=3600, help='per directory-wide fix timeout')
    args = parser.parse_args()
    if os.environ.get('LANGUAGE_WAVE1_ADMITTED') != '1':
        parser.error('invoke scripts/regenerate_language_wave1.sh for shared flock/build admission')
    root = embedded.ROOT
    compiler = args.compiler.resolve()
    revision = subprocess.check_output(['git', 'rev-parse', args.source_revision], cwd=root).decode().strip()
    subprocess.run(['git', 'merge-base', '--is-ancestor', revision, 'HEAD'], cwd=root, check=True)
    args.report_dir.mkdir(parents=True, exist_ok=True)
    roots = args.root or list(LIVE_ROOTS)
    for name in roots:
        path = root / name
        if Path(name).is_absolute() or '..' in Path(name).parts or embedded.path_exclusion(path):
            parser.error('live root is outside the protected selection: '+name)
    selected, exclusions = embedded.collect_paths([root / name for name in roots if (root / name).exists()])
    tracked = list(filter(None, subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')))
    selected_my = tracked_live_sources(selected, tracked, root)
    originals = {path: path.read_bytes() for path in selected_my}
    protected = protected_snapshot(root, tracked)
    report = {'source_revision': revision, 'tooling_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root).decode().strip(),
              'compiler_sha256': sha(compiler.read_bytes()), 'roots': roots, 'dry_run': args.dry_run,
              'excluded': exclusions, 'manual_seed_queue': [name for name in tracked if name.startswith('selfhost/components/') and name.endswith('.selka')], 'protected_sha256': protected, 'commands': [], 'changes': [], 'failures': []}
    # Preserve repo-relative import relationships across every live root.
    with tempfile.TemporaryDirectory(prefix='wave1-directory-', dir=os.environ.get('TMPDIR')) as temporary:
        stage = Path(temporary)
        for path, data in originals.items():
            target = stage / path.relative_to(root)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        for name in filter(None, tracked):
            path = root / name
            in_live_root = any(name == prefix or name.startswith(prefix.rstrip('/') + '/') for prefix in roots)
            if path.suffix != '.selka' and (in_live_root or path.suffix == '.json') and not embedded.path_exclusion(path) and path.is_file() and not path.is_symlink():
                target = stage / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
        for name in roots:
            target = stage / name
            if not target.exists():
                continue
            entry = target
            if name in FILE_ENTRY_ALIASES:
                entry = target.with_name(FILE_ENTRY_ALIASES[name])
                shutil.copyfile(target, entry)
            command = [str(compiler), 'fix', '--no-cache', str(entry)]
            try:
                result = subprocess.run(command, cwd=stage, capture_output=True, text=True, timeout=args.directory_timeout)
                item = {'argv': command, 'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}
            except subprocess.TimeoutExpired as error:
                item = {'argv': command, 'exit_code': None, 'error': 'timeout', 'timeout_seconds': args.directory_timeout}
            if entry != target:
                item['original_entry'] = name
                item['entry_alias'] = entry.relative_to(stage).as_posix()
                shutil.copyfile(entry, target)
                entry.unlink()
            report['commands'].append(item)
            if item['exit_code'] != 0:
                report['failures'].append({'root': name, 'reason': 'directory fix failed; review residual diagnostics; staged certain fixes retained'})
        for path, original in originals.items():
            updated = (stage / path.relative_to(root)).read_bytes()
            if updated != original:
                if path.read_bytes() != original:
                    raise RuntimeError('concurrent change: '+str(path))
                report['changes'].append({'path': str(path.relative_to(root)), 'before_sha256': sha(original), 'after_sha256': sha(updated)})
                if not args.dry_run:
                    embedded.atomic_write(path, updated, original)
    (args.report_dir / 'directory-fix.json').write_text(json.dumps(report, indent=2)+'\n')
    if args.directory_only:
        return int(bool(report['failures']))
    # Directory rounds must precede all embedded entries. Exclude .selka explicitly:
    # their project-wide metadata has already been consumed as one directory.
    command = ['python3', str(root / 'scripts/migrate_embedded.py'), '--compiler', str(compiler),
               '--timeout', str(args.timeout), '--tracked-only', '--exclude', '*.selka', '--report', str(args.report_dir.resolve() / 'embedded.json')]
    if args.dry_run:
        command.append('--dry-run')
    command.append(str(root))
    status = subprocess.run(command, cwd=root).returncode
    after_protected = protected_snapshot(root, tracked)
    changed_protected = [kind + ':' + name for kind in ('files', 'blocks')
                         for name in protected[kind] if after_protected[kind].get(name) != protected[kind][name]]
    report['protected_changes'] = changed_protected
    report['embedded_exit_code'] = status
    (args.report_dir / 'directory-fix.json').write_text(json.dumps(report, indent=2)+'\n')
    if changed_protected:
        raise RuntimeError('protected corpus changed: '+', '.join(changed_protected))
    return int(bool(status or report['failures']))

if __name__ == '__main__':
    raise SystemExit(main())
