#!/usr/bin/env python3
"""Prepare repair workspaces, retain checks, seal submissions and grade fresh cases."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
import shlex

import cases
import execution
import grading
import tasks
from storage import digest, inventory, locked, read_json, utc, verify_base, verify_tools, verify_work, write_json, work_inventory, capture_work

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def harness_identity():
    paths = [*HERE.glob('*.py'), HERE.parent / 'oracle.py', HERE.parent / 'cases.json']
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted(paths)}


def validated(root):
    manifest = read_json(root / 'manifest.json')
    if manifest['version'] != 1 or manifest['harness'] != harness_identity():
        raise ValueError('study version or coordinator harness changed')
    verify_base(root, manifest)
    verify_tools(manifest)
    if inventory(root / 'compiler') != manifest['compiler_files']:
        raise ValueError('frozen compiler implementation changed')
    return manifest


def prepare(root, language, task, compiler, zig, participant, model, kind="fixture"):
    from storage import identity
    commit = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    dirty = subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain', '--', 'src'], text=True)
    tools = {'compiler': identity(compiler), 'zig': identity(zig)}
    root.mkdir(parents=True, exist_ok=False)
    shutil.copytree(ROOT / 'src/board_trial', root / 'base')
    (root / 'base/unit_conversion.zig').write_text(tasks.UNIT_ZIG)
    shutil.copytree(ROOT / 'src', root / 'compiler')
    editable = tasks.allowed(language, task)
    context = ([str(path.relative_to(root / 'base')) for path in (root / 'base/guest').glob('*.my')]
               if language == 'guest' else ['baseline.zig', 'model.zig', 'kernel.zig', 'unit_conversion.zig'])
    tasks.copy_files(root / 'base', root / 'work', context)
    tasks.seed(root / 'work', language, task)
    (root / 'work/contract.md').write_bytes((HERE.parent / 'contract.md').read_bytes())
    prompt = (f'# Repair task: {task}\n\n{tasks.TASKS[task]}\n\n'
              f'Implementation: {language}. Edit only: {", ".join(editable)}.\n'
              'Preserve nominal types and public contracts. Do not edit the checker, host wrappers, oracle or harness.\n'
              'Use the coordinator check command after each candidate edit. Keep failed attempts.\n'
              f'Check command: `{shlex.join(["python3", str(HERE / "study.py"), "check", str(root)])}`.\n'
              'Only work/ and returned development diagnostics are participant context; do not inspect base/, compiler/, attempts/, grading/, coordinator sources or the other language.\n'
              'When finished, stop editing and tell the coordinator to seal the submission.\n'
              'There are at most five edited submissions and twenty check invocations.\n')
    (root / 'work/TASK.md').write_text(prompt)
    manifest = {'version': 1, 'created': utc(), 'status': 'open', 'commit': commit, 'source_dirty': bool(dirty),
                'language': language, 'task': task, 'participant': participant, 'model': model, 'record_kind': kind,
                'tools': tools, 'harness': harness_identity(), 'editable': editable,
                'base_files': inventory(root / 'base'), 'compiler_files': inventory(root / 'compiler'),
                'compiler_source': str(root / 'compiler/compiler.zig'),
                'instructions': {name: digest(root / 'work' / name) for name in [*set(context).difference(editable), 'TASK.md', 'contract.md']},
                'max_edits': 5, 'max_checks': 20}
    manifest['initial_candidate_sha256'] = candidate_digest(work_inventory(root / 'work'))
    write_json(root / 'manifest.json', manifest)
    (root / 'attempts').mkdir()
    return {'workspace': str(root / 'work'), 'task': task, 'language': language, 'status': 'prepared'}


def attempts(root):
    rows = []
    for directory in sorted((root / 'attempts').iterdir()):
        if not (directory / 'result.json').exists():
            raise ValueError('unfinished check must be reviewed before continuing: ' + str(directory))
        rows.append(read_json(directory / 'result.json'))
    return rows


def candidate_digest(files):
    return hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()


def check(root):
    with locked(root):
        manifest = validated(root)
        if manifest['status'] != 'open':
            raise ValueError('sealed submissions cannot receive more checks')
        files = work_inventory(root / 'work')
        fingerprint = candidate_digest(files)
        previous = attempts(root)
        if previous and manifest['record_kind'] == 'agent' and 'participant_started' not in manifest:
            raise ValueError('coordinator must begin the participant session after the seeded check')
        if not previous and fingerprint != manifest['initial_candidate_sha256']:
            raise ValueError('record the seeded baseline before editing')
        edits = sum(a['edited_submission'] for a in previous)
        edited = bool(previous and previous[-1]['candidate_sha256'] != fingerprint)
        if len(previous) >= manifest['max_checks'] or edits + edited > manifest['max_edits']:
            raise ValueError('study attempt budget exhausted; seal as budget or abandoned')
        directory = root / 'attempts' / f'{len(previous):03}'
        directory.mkdir()
        shutil.copytree(root / 'base', directory / 'source')
        scope_error = None
        try:
            verify_work(root, manifest)
        except ValueError as error:
            scope_error = str(error)
        try:
            capture_work(root / 'work', directory / 'source', files)
        except ValueError as error:
            scope_error = str(error)
        for name in set(manifest['editable']) | set(manifest['instructions']):
            target = directory / 'source' / name
            if not isinstance(files.get(name), str) and target.is_file():
                target.unlink()
        snapshot = inventory(directory / 'source')
        write_json(directory / 'snapshot.json', snapshot)
        patches = []
        reference = root / 'attempts' / f'{previous[-1]["index"]:03}' / 'source' if previous else root / 'base'
        changed = []
        earlier = previous[-1]['candidate_files'] if previous else files
        for name in sorted(set(files) | set(earlier)):
            if name in files and not isinstance(files[name], str):
                changed.append(name)
                continue
            before, after = reference / name, directory / 'source' / name
            before_bytes = before.read_bytes() if before.exists() else b''
            after_bytes = after.read_bytes() if after.exists() else b''
            if before_bytes != after_bytes:
                changed.append(name)
            patches.extend(difflib.unified_diff(before_bytes.decode(errors='replace').splitlines(True),
                                               after_bytes.decode(errors='replace').splitlines(True),
                                               fromfile='previous/' + name, tofile='candidate/' + name))
        (directory / 'patch.diff').write_text(''.join(patches))
        started = utc()
        inputs = cases.UNIT_DEVELOPMENT if manifest['task'] == 'units' else read_json(HERE.parent / 'cases.json')
        clock_start = time.monotonic()
        outcome = ({'phase': 'source-boundary', 'passed': False, 'error': scope_error} if scope_error else
                   execution.evaluate(directory, manifest, inputs))
        elapsed = time.monotonic() - clock_start
        messages = []
        for path in sorted(directory.glob('*.stderr')):
            if path.stat().st_size:
                messages.append({'step': path.stem, 'stderr': path.read_text(errors='replace')[:65536]})
        row = {'index': len(previous), 'started': started, 'finished': utc(), 'candidate_sha256': fingerprint,
               'candidate_files': files, 'edited_submission': edited, 'changed_files': changed,
               'diagnostics': messages, 'elapsed_check_seconds': elapsed, 'outcome': outcome}
        if (directory / 'mismatches.json').exists():
            row['development_mismatches'] = read_json(directory / 'mismatches.json')[:3]
        write_json(directory / 'result.json', row)
        return row


def begin(root):
    with locked(root):
        manifest = validated(root)
        rows = attempts(root)
        if manifest['status'] != 'open' or 'participant_started' in manifest or len(rows) != 1:
            raise ValueError('begin requires exactly one seeded check and no prior participant session')
        if candidate_digest(work_inventory(root / 'work')) != manifest['initial_candidate_sha256']:
            raise ValueError('participant source must still be the recorded seed')
        manifest['participant_started'] = utc()
        write_json(root / 'manifest.json', manifest)
        return {'status': 'begun', 'participant_started': manifest['participant_started']}


def seal(root, reason):
    with locked(root):
        manifest = validated(root)
        if manifest['status'] != 'open':
            raise ValueError('submission already sealed')
        rows = attempts(root)
        if not rows or candidate_digest(work_inventory(root / 'work')) != rows[-1]['candidate_sha256']:
            raise ValueError('record the current candidate before sealing it')
        manifest.update(status='sealed', sealed=utc(), finish_reason=reason, final_attempt=rows[-1]['index'])
        write_json(root / 'manifest.json', manifest)
        return {'status': 'sealed', 'final_attempt': manifest['final_attempt'], 'reason': reason}


def grade(root, peer=None):
    return grading.grade(root, validated, attempts, peer)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('prepare', 'check', 'begin', 'seal', 'grade'):
        child = commands.add_parser(name)
        child.add_argument('study', type=Path)
        if name == 'prepare':
            child.add_argument('--language', choices=['guest', 'zig'], required=True)
            child.add_argument('--task', choices=tasks.TASKS, required=True)
            child.add_argument('--compiler', type=Path, required=True)
            child.add_argument('--zig', type=Path, required=True)
            child.add_argument('--participant', required=True)
            child.add_argument('--model', required=True)
            child.add_argument('--kind', choices=['fixture', 'agent'], default='fixture')
        elif name == 'grade':
            child.add_argument('--peer', type=Path)
        elif name == 'seal':
            child.add_argument('--reason', choices=['completed', 'budget', 'abandoned'], required=True)
    args = parser.parse_args()
    root = args.study.resolve()
    if args.command == 'prepare':
        result = prepare(root, args.language, args.task, args.compiler, args.zig, args.participant, args.model, args.kind)
    elif args.command == 'check':
        result = check(root)
    elif args.command == 'begin':
        result = begin(root)
    elif args.command == 'seal':
        result = seal(root, args.reason)
    else:
        result = grade(root, args.peer.resolve() if args.peer else None)
    print(json.dumps(result, indent=2))
    if args.command == 'check' and not result['outcome']['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit('repair-study: ' + str(error))
