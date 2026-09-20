#!/usr/bin/env python3
"""The E1 development pilot harness: one command per task attempt.

E1 evaluates complete work. This harness runs the *development* half of the
frozen pack in ``pack/``: it prepares a scratch copy of a task's source
snapshot, runs one solver command, grades the result with the task's independent
behavioural acceptance check, and records the observations the plan requires.

    python3 pilot.py materialize          # copy the frozen compiler + identity
    python3 pilot.py freeze               # write pack/manifest.json (hashes)
    python3 pilot.py verify               # refuse drift in the pack or the tool
    python3 pilot.py selftest             # acceptance fails on the source and
                                          # passes on the intended answer
    python3 pilot.py run --task dev-maintenance-01 --arm plain
    python3 pilot.py run --task dev-maintenance-01 --arm focused-context \\
        --solver reference               # a non-model dry run of the harness

A run is one attempt: a fresh workspace, a fresh cache, one solver process (or a
built-in), one grading pass, and one observation JSON under ``evidence/runs/``.
A retry is a new run id; nothing is overwritten. The harness never edits the
pack, and it refuses to run when the pack, the protocol, the preregistration or
the compiler identity has drifted.

Observed through ``harness/shim.py``, which sits in front of the frozen compiler
on the solver's PATH: one ``compiler-invocation-v1`` event per compiler process
with the phase, the wall time, the exit status, the response bytes and the
diagnostics. The transcript is not the measurement.

Exit status: 0 accepted, 1 rejected (or a selftest failure), 2 setup error,
3 blocked (the solver could not start, e.g. a missing credential).
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parents[1]
HARNESS = Path(__file__).resolve().parent
sys.path.insert(0, str(HARNESS))
import events  # noqa: E402  (the event schema sits beside the harness)

PACK = HERE / 'pack'
TASKS = PACK / 'tasks'
TOOLS = PACK / 'tools'
TOOL_BIN = TOOLS / 'bin'
IDENTITY = TOOLS / 'identity.json'
MANIFEST = PACK / 'manifest.json'
PROTOCOL = HERE / 'protocol.json'
PREREGISTRATION = HERE / 'preregistration.json'
WORK = HERE / 'work'
EVIDENCE = HERE / 'evidence'
RUNS = EVIDENCE / 'runs'
ZIG_CACHE = HERE / 'zig-global-cache'
DEFAULT_COMPILER = ROOT / 'zig-out' / 'bin' / 'mylang'
IDENTITY_ENTRY = ROOT / 'examples' / 'corpus' / 'packet' / 'main.my'
PACK_VERSION = 'e1-pack-v1'
TOOLS_VERSION = 'e1-tools-v1'
OBSERVATION_VERSION = 'e1-observation-v1'
BUILTIN_SOLVERS = ('noop', 'reference')
TOOL_NAMES = ('mylang', 'qbe', 'mylang-io')


class SetupError(Exception):
    """A setup failure that stops a run before anything is observed."""


# --------------------------------------------------------------------------
# Small shared helpers
# --------------------------------------------------------------------------

def sha256_file(path: Path) -> str:
    """Lowercase SHA-256 of a file, or an empty string when it is unreadable."""
    digest = hashlib.sha256()
    try:
        with path.open('rb') as handle:
            for block in iter(lambda: handle.read(1 << 20), b''):
                digest.update(block)
    except OSError:
        return ''
    return digest.hexdigest()


def sha256_text(text: str) -> str:
    """Lowercase SHA-256 of a string, for hashing rendered documents."""
    return hashlib.sha256(text.encode()).hexdigest()


def load_json(path: Path) -> dict:
    """Read a JSON document, or answer an empty object when it is absent."""
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def write_json(path: Path, payload: dict) -> None:
    """Write one JSON document with a trailing newline, creating parents."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=1) + '\n')


def utc_now() -> str:
    """The current UTC instant in ISO-8601, for the observation's clocks."""
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def harness_environment() -> dict:
    """The base environment every compiler process the harness starts sees.

    Zig's global cache must be writable: the native backend drives zig as its
    assembler and linker, and a cache the sandbox refuses to write fails the link
    with ``host failure: NativeToolFailed``. The harness therefore always points
    ``ZIG_GLOBAL_CACHE_DIR`` at its own cache (``E1_ZIG_GLOBAL_CACHE`` overrides
    the location); probing the ambient value is not enough, because a directory
    the sandbox refuses to write still looks writable to ``os.access``. A run's
    own object cache stays under ``work/<run_id>/cache``.
    """
    env = dict(os.environ)
    override = env.get('E1_ZIG_GLOBAL_CACHE')
    cache = Path(override) if override else ZIG_CACHE
    cache.mkdir(parents=True, exist_ok=True)
    env['ZIG_GLOBAL_CACHE_DIR'] = str(cache)
    return env


def run_command(argv: list[str], cwd: Path | None = None, env: dict | None = None,
                timeout: float | None = None) -> dict:
    """Run one command to completion, capturing output and wall time."""
    started = time.monotonic()
    try:
        completed = subprocess.run(argv, cwd=cwd, env=env if env is not None else harness_environment(),
                                   capture_output=True, text=True, timeout=timeout)
        return {'status': completed.returncode, 'stdout': completed.stdout,
                'stderr': completed.stderr, 'timed_out': False,
                'seconds': round(time.monotonic() - started, 3)}
    except subprocess.TimeoutExpired as expired:
        return {'status': None, 'stdout': expired.stdout or '', 'stderr': expired.stderr or '',
                'timed_out': True, 'seconds': round(time.monotonic() - started, 3)}
    except OSError as error:
        return {'status': None, 'stdout': '', 'stderr': f'{argv[0]}: {error}',
                'timed_out': False, 'seconds': round(time.monotonic() - started, 3)}


def task_ids() -> list[str]:
    """Every frozen task id, in name order."""
    return sorted(path.name for path in TASKS.iterdir() if (path / 'task.json').exists())


def task_dir(task_id: str) -> Path:
    """The pack directory of one task, refusing an unknown id."""
    path = TASKS / task_id
    if not (path / 'task.json').exists():
        raise SetupError(f'no task {task_id!r} in {TASKS}')
    return path


def load_task(task_id: str) -> dict:
    """One task's metadata plus its brief text and directory."""
    path = task_dir(task_id)
    task = load_json(path / 'task.json')
    task['brief'] = (path / 'brief.md').read_text()
    task['dir'] = str(path)
    return task


def pack_inventory() -> dict[str, str]:
    """Hash every frozen document: the tasks, the harness, the protocol, the preregistration.

    The harness is part of the instrument, so it is frozen with the pack: a run
    that used edited harness code is visible in ``pilot.py verify`` and in the
    manifest hash every observation records.
    """
    entries: dict[str, str] = {}
    for path in sorted(TASKS.rglob('*')):
        if path.is_file() and '__pycache__' not in path.parts:
            entries[path.relative_to(HERE).as_posix()] = sha256_file(path)
    for path in sorted(HARNESS.rglob('*')):
        if path.is_file() and '__pycache__' not in path.parts:
            entries[path.relative_to(HERE).as_posix()] = sha256_file(path)
    for path in (PROTOCOL, PREREGISTRATION, IDENTITY):
        if path.exists():
            entries[path.relative_to(HERE).as_posix()] = sha256_file(path)
    return entries


def tool_identity() -> dict:
    """The materialized tool identity, or an empty object when not materialized."""
    return load_json(IDENTITY)


def docs_digest() -> str:
    """A digest of the documentation the solver can read, for drift detection."""
    docs = ROOT / 'docs'
    entries = {path.relative_to(ROOT).as_posix(): sha256_file(path)
               for path in sorted(docs.rglob('*.md'))}
    entries['README.md'] = sha256_file(ROOT / 'README.md')
    return sha256_text(json.dumps(entries, sort_keys=True))


def compiler_identity(binary: Path, entry: Path, timeout: float) -> dict | None:
    """The compiler's build-time identity from ``schema-project --schema-report``."""
    if not entry.exists():
        return None
    result = run_command([str(binary), 'schema-project', str(entry), '--schema-report'],
                         timeout=timeout)
    if result['status'] != 0:
        return None
    for line in result['stdout'].splitlines():
        stripped = line.strip()
        if not stripped.startswith('{'):
            continue
        try:
            payload = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        implementation = (payload.get('source') or {}).get('implementation')
        if implementation:
            return implementation
    return None


def resolve_compiler(explicit: Path | None, timeout: float) -> dict:
    """The frozen compiler, its identity and every tool hash a run records.

    The materialized copy wins over ``zig-out/bin/mylang``. The identity file is
    authoritative: a resolved binary whose sha256 differs is a drift error, not a
    silent substitution.
    """
    identity = tool_identity()
    materialized = TOOL_BIN / 'mylang'
    if explicit is not None:
        binary = explicit if explicit.is_absolute() else (Path.cwd() / explicit).resolve()
    elif materialized.exists():
        binary = materialized
    else:
        binary = DEFAULT_COMPILER
    if not binary.exists():
        raise SetupError(f'no compiler at {binary}; run `pilot.py materialize`')
    digest = sha256_file(binary)
    recorded = ((identity.get('tools') or {}).get('mylang') or {}).get('sha256')
    if recorded and digest != recorded:
        raise SetupError(f'compiler drift: {binary} is sha256 {digest[:16]}, '
                         f'identity.json records {recorded[:16]}; re-run materialize '
                         f'or restore the frozen pack')
    compiler = {
        'path': str(binary), 'sha256': digest,
        'compiler_sha256': (identity.get('compiler_identity') or {}).get('compiler_sha256'),
        'qbe': str(binary.parent / 'qbe'),
        'materialized': binary == materialized,
    }
    if not compiler['compiler_sha256']:
        found = compiler_identity(binary, IDENTITY_ENTRY, timeout) or {}
        compiler['compiler_sha256'] = found.get('compiler_sha256')
    return compiler


# --------------------------------------------------------------------------
# materialize / freeze / verify
# --------------------------------------------------------------------------

def cmd_materialize(args: argparse.Namespace) -> int:
    """Copy the installed compiler, qbe and mylang-io into the pack, with hashes."""
    TOOL_BIN.mkdir(parents=True, exist_ok=True)
    tools = {}
    for name in TOOL_NAMES:
        source = ROOT / 'zig-out' / 'bin' / name
        if not source.exists():
            continue
        target = TOOL_BIN / name
        shutil.copy2(source, target)
        tools[name] = {'sha256': sha256_file(target), 'bytes': target.stat().st_size,
                       'source': str(source)}
    if 'mylang' not in tools:
        raise SetupError(f'no compiler at {ROOT / "zig-out" / "bin" / "mylang"}')
    identity = compiler_identity(TOOL_BIN / 'mylang', IDENTITY_ENTRY, args.timeout) or {}
    document = {
        'version': TOOLS_VERSION,
        'captured_utc': utc_now(),
        'tools': tools,
        'compiler_identity': identity,
        'identity_entry': str(IDENTITY_ENTRY.relative_to(ROOT)),
    }
    write_json(IDENTITY, document)
    print(f'materialize: froze {len(tools)} tool(s) into {TOOL_BIN.relative_to(HERE)}')
    for name, facts in tools.items():
        print(f'  {name:10s} sha256 {facts["sha256"][:16]}... {facts["bytes"]} bytes')
    print(f'  compiler_sha256 {identity.get("compiler_sha256")}')
    print('materialize: now run `pilot.py freeze` to record the pack hashes')
    return 0


def cmd_freeze(args: argparse.Namespace) -> int:
    """Write the pack manifest: one hash per frozen document, plus the task list."""
    tasks = []
    for name in task_ids():
        task = load_task(name)
        tasks.append({'id': task.get('id'), 'family': task.get('family'),
                      'cohort': task.get('cohort'), 'title': task.get('title')})
    document = {
        'version': PACK_VERSION,
        'frozen_on': datetime.date.today().isoformat(),
        'files': pack_inventory(),
        'tasks': tasks,
        'protocol': {'path': PROTOCOL.relative_to(HERE).as_posix(), 'version': load_json(PROTOCOL).get('version')},
        'preregistration': {'path': PREREGISTRATION.relative_to(HERE).as_posix(),
                            'version': load_json(PREREGISTRATION).get('version')},
    }
    write_json(MANIFEST, document)
    print(f'freeze: wrote {MANIFEST.relative_to(HERE)} '
          f'({len(document["files"])} files, {len(tasks)} tasks)')
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    """Compare the frozen manifest with the tree and the tool identity."""
    manifest = load_json(MANIFEST)
    if not manifest:
        print('verify: no pack manifest; run `pilot.py freeze` first', file=sys.stderr)
        return 2
    current = pack_inventory()
    frozen = manifest.get('files') or {}
    drift = []
    for name in sorted(set(frozen) | set(current)):
        if name not in current:
            drift.append(f'  missing: {name}')
        elif name not in frozen:
            drift.append(f'  unfrozen: {name}')
        elif frozen[name] != current[name]:
            drift.append(f'  changed: {name} ({frozen[name][:12]} -> {current[name][:12]})')
    print(f'verify: pack {manifest.get("version")} frozen {manifest.get("frozen_on")}, '
          f'{len(frozen)} files, {len(manifest.get("tasks") or [])} tasks')
    for task in manifest.get('tasks') or []:
        print(f'  {task["id"]:22s} {task.get("family", ""):26s} {task.get("cohort", "")}')
    if drift:
        print('verify: DRIFT')
        for line in drift:
            print(line)
        return 1
    identity = tool_identity()
    if identity:
        print(f'verify: tools {identity.get("version")} captured {identity.get("captured_utc")}')
        for name, facts in (identity.get('tools') or {}).items():
            print(f'  {name:10s} sha256 {facts["sha256"][:16]}...')
    else:
        print('verify: no tool identity; run `pilot.py materialize` to freeze the compiler')
    if not PROTOCOL.exists() or not PREREGISTRATION.exists():
        print('verify: protocol.json or preregistration.json is missing', file=sys.stderr)
        return 2
    print(f'verify: protocol {sha256_file(PROTOCOL)[:16]}... '
          f'preregistration {sha256_file(PREREGISTRATION)[:16]}...')
    return 0


# --------------------------------------------------------------------------
# selftest: the acceptance check discriminates
# --------------------------------------------------------------------------

def copy_answer(task: dict, tree: Path) -> list[str]:
    """Copy the intended answer over a candidate tree; answer the file names."""
    answer = Path(task['dir']) / 'answer' / 'files'
    copied = []
    for path in sorted(answer.rglob('*')):
        if path.is_file():
            relative = path.relative_to(answer)
            (tree / relative).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, tree / relative)
            copied.append(relative.as_posix())
    return copied


def parse_json_document(text: str) -> dict:
    """The last JSON object in a command's stdout, or an empty object.

    The acceptance checker prints one indented document, but a probe's own output
    could precede it, so this scans every ``{`` with ``raw_decode`` and keeps the
    last object that parses.
    """
    stripped = (text or '').strip()
    if not stripped:
        return {}
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        pass
    decoder = json.JSONDecoder()
    found: dict = {}
    for index, character in enumerate(stripped):
        if character != '{':
            continue
        try:
            payload, _ = decoder.raw_decode(stripped[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            found = payload
    return found


def grade(task: dict, tree: Path, compiler: dict, cache_root: Path, timeout: float) -> dict:
    """Run one task's acceptance checker against a candidate tree."""
    checker = Path(task['dir']) / 'acceptance' / 'check.py'
    argv = [sys.executable, str(checker), '--project', str(tree),
            '--frozen', str(Path(task['dir']) / 'source'), '--compiler', compiler['path'],
            '--allowed', task.get('acceptance_allowed', '*.my'), '--json',
            '--cache-dir', str(cache_root), '--timeout', str(timeout)]
    result = run_command(argv, timeout=timeout + 30)
    document = parse_json_document(result['stdout'])
    return {'passed': bool(document.get('passed')), 'exit_status': result['status'],
            'seconds': result['seconds'], 'timed_out': result['timed_out'],
            'command': ' '.join(argv), 'document': document}


def cmd_selftest(args: argparse.Namespace) -> int:
    """Show that each acceptance check fails on the source and passes on the answer."""
    compiler = resolve_compiler(args.compiler, args.timeout)
    print(f'selftest: compiler {compiler["path"]} sha256 {compiler["sha256"][:16]}...')
    failures = []
    for name in task_ids():
        task = load_task(name)
        scratch = WORK / 'selftest' / name
        if scratch.exists():
            shutil.rmtree(scratch)
        frozen_tree = scratch / 'frozen'
        answer_tree = scratch / 'answer'
        shutil.copytree(Path(task['dir']) / 'source', frozen_tree)
        shutil.copytree(Path(task['dir']) / 'source', answer_tree)
        copied = copy_answer(task, answer_tree)
        cache = scratch / 'cache'
        on_source = grade(task, frozen_tree, compiler, cache / 'source', args.timeout)
        on_answer = grade(task, answer_tree, compiler, cache / 'answer', args.timeout)
        expected = [('source rejected', on_source['passed'], False),
                    ('answer accepted', on_answer['passed'], True)]
        for label, observed, wanted in expected:
            mark = 'ok' if observed == wanted else 'UNEXPECTED'
            print(f'  {name:22s} {label:18s} passed={str(observed):5s} {mark}')
            if observed != wanted:
                failures.append(f'{name}: {label} passed={observed}, expected {wanted}')
        print(f'  {name:22s} answer files copied: {", ".join(copied) or "none"}')
    if failures:
        print('selftest: FAILED')
        for line in failures:
            print(f'  {line}')
        return 1
    print(f'selftest: {len(task_ids())} task(s) discriminate source from answer')
    return 0


# --------------------------------------------------------------------------
# run: one attempt
# --------------------------------------------------------------------------

def arm_note(protocol: dict, arm: str, task: dict) -> str:
    """The one text an arm adds to the shared prompt."""
    for candidate in protocol.get('arms') or []:
        if candidate.get('name') == arm:
            return (candidate.get('note') or '').format(
                entry=task.get('entry', 'main.my'),
                context_symbol=task.get('context_symbol', ''))
    raise SetupError(f'no arm {arm!r} in the protocol; have '
                     f'{", ".join(item.get("name", "?") for item in protocol.get("arms") or [])}')


def compose_prompt(protocol: dict, task: dict, arm: str, workspace: Path) -> str:
    """The frozen prompt: template, brief and the single arm-specific note."""
    return protocol['prompt_template'].format(
        workspace=workspace, brief=task['brief'].strip(), arm_note=arm_note(protocol, arm, task))


def write_launcher(workdir: Path, compiler: dict, log: Path, attempt: str, cache: Path) -> Path:
    """Install the counting shim as `mylang` first on the solver's PATH."""
    bin_dir = workdir / 'bin'
    bin_dir.mkdir(parents=True, exist_ok=True)
    launcher = bin_dir / 'mylang'
    launcher.write_text(
        '#!/bin/sh\n'
        f'exec {sys.executable} {HARNESS / "shim.py"} '
        f'--log {log} --real {compiler["path"]} --attempt {attempt} '
        f'--cache-dir {cache} -- "$@"\n')
    launcher.chmod(0o755)
    return launcher


def link_docs(workspace: Path) -> None:
    """Expose the repository documentation read-only inside the workspace."""
    for name, target in (('docs', ROOT / 'docs'), ('README.md', ROOT / 'README.md')):
        link = workspace / name
        if link.exists() or link.is_symlink():
            continue
        try:
            link.symlink_to(target)
        except OSError:
            pass


def solver_environment(workdir: Path, workspace: Path, compiler: dict, arm: str,
                       task: dict, prompt_file: Path) -> dict:
    """Every environment field a solver sees, recorded in the observation."""
    env = harness_environment()
    env['PATH'] = str(workdir / 'bin') + os.pathsep + env.get('PATH', '')
    env['E1_WORKSPACE'] = str(workspace)
    env['E1_ARM'] = arm
    env['E1_TASK'] = str(task.get('id'))
    env['E1_ANSWER'] = str(Path(task['dir']) / 'answer')
    env['E1_CONTEXT_SYMBOL'] = str(task.get('context_symbol', ''))
    env['E1_PROMPT_FILE'] = str(prompt_file)
    env['E1_COMPILER_SHA256'] = compiler['sha256']
    env['DSH_HOME'] = str(workdir / 'dsh-home')
    (workdir / 'tmp').mkdir(parents=True, exist_ok=True)
    env['TMPDIR'] = str(workdir / 'tmp')
    return env


def solver_argv(protocol: dict, solver: str, prompt: str) -> list[str] | None:
    """The command line for a solver name, or None for a built-in."""
    if solver in BUILTIN_SOLVERS:
        return None
    if solver.startswith('script:'):
        script = solver.split(':', 1)[1]
        template = protocol['solver_templates']['script']
        return [script if part == '{script}' else part for part in template]
    template = (protocol.get('solver_templates') or {}).get(solver)
    if template is None:
        raise SetupError(f'unknown solver {solver!r}; use one of '
                         f'{", ".join(sorted(protocol["solver_templates"]))}, noop, reference '
                         f'or script:PATH')
    return [prompt if part == '{prompt}' else part for part in template]


def profile_identity(protocol: dict, env: dict, timeout: float) -> dict:
    """Hash the composed dsh profile so two runs can be compared field by field."""
    solver = protocol.get('default_solver')
    subcommand = ((protocol.get('solver_templates') or {}).get(solver) or ['dsh'])[0]
    if subcommand != 'dsh':
        return {'available': False}
    result = run_command(['dsh', '--profile', protocol['models']['profile'], '--dump-config'],
                         env=env, timeout=timeout)
    if result['status'] != 0:
        return {'available': False, 'error': result['stderr'][-500:]}
    return {'available': True, 'sha256': sha256_text(result['stdout']),
            'bytes': len(result['stdout'])}


def run_solver(command: list[str] | None, workdir: Path, workspace: Path, env: dict,
               timeout: float) -> dict:
    """Run one solver process, or the built-in that stands in for it."""
    stdout_path = workdir / 'solver.stdout'
    stderr_path = workdir / 'solver.stderr'
    if command is None:
        return {'builtin': True, 'status': 0, 'seconds': 0.0, 'timed_out': False,
                'stdout_bytes': 0, 'stderr_bytes': 0}
    started = time.monotonic()
    with stdout_path.open('wb') as out, stderr_path.open('wb') as err:
        process = subprocess.Popen(command, cwd=workspace, env=env, stdout=out, stderr=err,
                                   start_new_session=True)
        try:
            status = process.wait(timeout=timeout)
            timed_out = False
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError, OSError):
                process.kill()
            status = process.wait()
            timed_out = True
    return {'builtin': False, 'status': status, 'seconds': round(time.monotonic() - started, 3),
            'timed_out': timed_out, 'stdout_bytes': stdout_path.stat().st_size,
            'stderr_bytes': stderr_path.stat().st_size,
            'stdout_path': str(stdout_path), 'stderr_path': str(stderr_path),
            'stderr_tail': stderr_path.read_text(errors='replace')[-2000:]}


def parse_work_report(stderr: str) -> dict:
    """The ``qbe-build-v1`` report of a build, when the command printed one."""
    for line in reversed(stderr.splitlines()):
        stripped = line.strip()
        if stripped.startswith('{') and 'qbe-build-v1' in stripped:
            try:
                payload = json.loads(stripped)
            except json.JSONDecodeError:
                continue
            compiled = payload.get('compiled_functions') or 0
            reused = payload.get('reused_functions') or 0
            total = compiled + reused
            return {
                'compiled_functions': compiled, 'reused_functions': reused,
                'functions_total': total,
                'reuse_fraction': round(reused / total, 4) if total else None,
                'frontend_seconds': payload.get('frontend_seconds'),
                'codegen_seconds': payload.get('codegen_seconds'),
                'link_seconds': payload.get('link_seconds'),
                'native_seconds': payload.get('native_seconds'),
            }
    return {}


def build_probe(compiler: dict, tree: Path, cache: Path, output: Path, timeout: float) -> dict:
    """One timed build, with the reuse counters its report carries.

    The observed compiler writes the ``qbe-build-v1`` report to stdout even
    though ``mylang check --help`` says stderr, so both streams are scanned and
    the stream that carried it is recorded.
    """
    result = run_command([compiler['path'], 'build', 'main.my', '-o', str(output), '--report',
                          f'--cache-dir={cache}'], cwd=tree, timeout=timeout)
    report = parse_work_report(result['stdout'])
    stream = 'stdout'
    if not report:
        report = parse_work_report(result['stderr'])
        stream = 'stderr' if report else ''
    return {'seconds': result['seconds'], 'status': result['status'],
            'timed_out': result['timed_out'], 'report': report, 'report_stream': stream,
            'stderr_tail': result['stderr'][-800:] if result['status'] != 0 else ''}


def cache_probes(task: dict, accepted: Path, workdir: Path, compiler: dict,
                 timeout: float) -> dict:
    """Cold, warm-unchanged and warm-after-edit builds on a copy of the tree."""
    tree = workdir / 'probe-tree'
    if tree.exists():
        shutil.rmtree(tree)
    shutil.copytree(accepted, tree, symlinks=True)
    for name in ('docs', 'README.md'):
        link = tree / name
        if link.is_symlink():
            link.unlink()
    cache = workdir / 'probe-cache'
    if cache.exists():
        shutil.rmtree(cache)
    cold = build_probe(compiler, tree, cache, workdir / 'probe-cold', timeout)
    warm = build_probe(compiler, tree, cache, workdir / 'probe-warm', timeout)
    entry = tree / task.get('entry', 'main.my')
    source = entry.read_text()
    marker = '    return 0'
    applied = marker in source
    if applied:
        entry.write_text(source.replace(marker, '    return 0 + 0', 1))
    else:
        entry.write_text(source + '\n# e1 warm-after-edit probe\n')
    changed = build_probe(compiler, tree, cache, workdir / 'probe-after-edit', timeout)
    return {'edit_applied': applied, 'cold': cold, 'warm_unchanged': warm,
            'warm_after_edit': changed}


def observation_document(run_id: str, task: dict, arm: str, solver: str, protocol: dict,
                         compiler: dict, prompt: str, prompt_sha: str, solver_result: dict,
                         events_summary: dict, grading: dict, probes: dict, profile: dict,
                         started_utc: str, timings: dict, status: str,
                         blocked_reason: str | None) -> dict:
    """The one JSON document a run leaves behind."""
    initial = grading.get('initial_source_sha256')
    accepted = bool(grading.get('passed'))
    return {
        'version': OBSERVATION_VERSION,
        'run_id': run_id,
        'status': status,
        'blocked_reason': blocked_reason,
        'task': {'id': task.get('id'), 'family': task.get('family'),
                 'cohort': task.get('cohort'), 'title': task.get('title'),
                 'brief_sha256': sha256_text(task['brief'])},
        'arm': {'name': arm, 'note_sha256': sha256_text(arm_note(protocol, arm, task))},
        'solver': {'name': solver, 'argv': solver_result.get('argv'),
                   'model_driven': solver not in BUILTIN_SOLVERS and not solver.startswith('script:'),
                   'status': solver_result.get('status'),
                   'timed_out': solver_result.get('timed_out'),
                   'stdout_bytes': solver_result.get('stdout_bytes'),
                   'stderr_bytes': solver_result.get('stderr_bytes'),
                   'stderr_tail': solver_result.get('stderr_tail', '')},
        'models': {'route': protocol['models'].get('route'),
                   'profile': protocol['models'].get('profile'),
                   'temperature': protocol['models'].get('temperature'),
                   'profile_identity': profile},
        'prompt': {'sha256': prompt_sha, 'text': prompt},
        'identities': {
            'protocol': {'path': PROTOCOL.relative_to(HERE).as_posix(),
                         'sha256': sha256_file(PROTOCOL)},
            'preregistration': {'path': PREREGISTRATION.relative_to(HERE).as_posix(),
                                'sha256': sha256_file(PREREGISTRATION)},
            'pack_manifest': {'path': MANIFEST.relative_to(HERE).as_posix(),
                              'sha256': sha256_file(MANIFEST)},
            'tool_identity': {'path': IDENTITY.relative_to(HERE).as_posix(),
                              'sha256': sha256_file(IDENTITY)},
            'compiler': compiler,
            'docs_digest': docs_digest(),
        },
        'timings': timings,
        'completion': {
            'accepted': accepted,
            'time_to_accepted_seconds': timings.get('task_to_accepted_seconds') if accepted else None,
            'unsuccessful_attempts': [] if accepted else [{'attempt': 'solver-and-grade',
                                                           'seconds': timings.get('solve_seconds'),
                                                           'passed': False}],
            'overlapping_note': 'invocation_wall_seconds is the sum over compiler processes; '
                                'solver_seconds is the enclosing wall clock, so the sum can '
                                'exceed the wall time when a solver ran processes in parallel',
        },
        'grading': grading,
        'invocations': events_summary,
        'cache_probes': probes,
        'attempts': [{'attempt': 'solver', 'seconds': timings.get('solve_seconds'),
                      'status': solver_result.get('status')},
                     {'attempt': 'acceptance', 'seconds': grading.get('seconds'),
                      'passed': accepted}],
        'tokens': {'input': None, 'output': None,
                   'note': 'not reported by the solver command; no estimate is invented'},
        'budgets': {**protocol['budgets'], 'wall_seconds_per_task':
                    task.get('budgets', {}).get('wall_seconds', protocol['budgets']['wall_seconds_per_task'])},
        'initial_source_sha256': initial,
        'started_utc': started_utc,
        'finished_utc': utc_now(),
    }


def cmd_run(args: argparse.Namespace) -> int:
    """Run one task attempt end to end and write its observation."""
    protocol = load_json(PROTOCOL)
    if not protocol:
        raise SetupError(f'no protocol at {PROTOCOL}')
    manifest = load_json(MANIFEST)
    if not manifest:
        raise SetupError('no pack manifest; run `pilot.py freeze` first')
    task = load_task(args.task)
    arm = args.arm or (protocol['arms'][0]['name'])
    solver = args.solver or protocol['default_solver']
    budget = args.timeout or task.get('budgets', {}).get('wall_seconds') \
        or protocol['budgets']['wall_seconds_per_task']
    started_utc = utc_now()
    started = time.monotonic()
    compiler = resolve_compiler(args.compiler, min(budget, 60.0))
    run_id = args.run_id or (datetime.datetime.now().strftime('%Y%m%dT%H%M%S')
                             + f'-{task["id"]}-{arm}-{solver.replace(":", "-").replace("/", "-")}')
    workdir = WORK / run_id
    workspace = workdir / 'project'
    if workdir.exists():
        raise SetupError(f'run {run_id} already exists at {workdir}; a retry is a new run id')
    prepare_started = time.monotonic()
    shutil.copytree(Path(task['dir']) / 'source', workspace)
    link_docs(workspace)
    prompt = compose_prompt(protocol, task, arm, workspace)
    prompt_file = workdir / 'prompt.txt'
    prompt_file.parent.mkdir(parents=True, exist_ok=True)
    prompt_file.write_text(prompt)
    log = workdir / 'events.jsonl'
    cache = workdir / 'cache'
    write_launcher(workdir, compiler, log, run_id, cache)
    env = solver_environment(workdir, workspace, compiler, arm, task, prompt_file)
    prepare_seconds = round(time.monotonic() - prepare_started, 3)
    initial_sha, _ = events.inventory(workspace)

    blocked_reason = None
    builtin = solver in BUILTIN_SOLVERS
    command = solver_argv(protocol, solver, prompt)
    credential = protocol['models'].get('credential_env')
    if not builtin and solver == protocol.get('default_solver') and credential \
            and not os.environ.get(credential):
        blocked_reason = (f'solver {solver!r} cannot start: {credential} is not set in the '
                          f'launching environment and the harness does not read the credential '
                          f'store; export {credential} and re-run `pilot.py run --task '
                          f'{task["id"]} --arm {arm}`')
        command = None

    profile = profile_identity(protocol, env, min(budget, 120.0))
    solve_started = time.monotonic()
    if blocked_reason:
        solver_result = {'builtin': False, 'status': None, 'seconds': 0.0, 'timed_out': False,
                         'stdout_bytes': 0, 'stderr_bytes': 0, 'argv': None}
    elif builtin:
        copied = copy_answer(task, workspace) if solver == 'reference' else []
        solver_result = {'builtin': True, 'status': 0, 'seconds': 0.0, 'timed_out': False,
                         'stdout_bytes': 0, 'stderr_bytes': 0,
                         'argv': [f'builtin:{solver}'], 'copied': copied}
    else:
        solver_result = run_solver(command, workdir, workspace, env, budget)
        solver_result['argv'] = command
    solve_seconds = round(time.monotonic() - solve_started, 3)

    grade_started = time.monotonic()
    if blocked_reason:
        grading = {'passed': False, 'seconds': 0.0, 'document': {}, 'exit_status': None}
    else:
        grading = grade(task, workspace, compiler, workdir / 'acceptance-cache',
                        protocol['budgets']['acceptance_seconds'])
    grading['initial_source_sha256'] = initial_sha
    grade_seconds = round(time.monotonic() - grade_started, 3)

    probe_started = time.monotonic()
    probes = cache_probes(task, workspace, workdir, compiler, min(budget, 120.0)) \
        if grading.get('passed') else {'skipped': 'acceptance did not pass'}
    probe_seconds = round(time.monotonic() - probe_started, 3)

    observed, coverage = events.read_events(log)
    events_summary = events.aggregate(observed, initial_sha)
    events_summary['coverage'] = coverage
    if blocked_reason:
        status = 'blocked'
    elif solver_result.get('timed_out'):
        status = 'timed-out'
    elif grading.get('passed'):
        status = 'accepted'
    else:
        status = 'rejected'
    timings = {
        'prepare_seconds': prepare_seconds,
        'solve_seconds': solve_seconds,
        'grade_seconds': grade_seconds,
        'cache_probe_seconds': probe_seconds,
        'task_to_accepted_seconds': round(prepare_seconds + solve_seconds + grade_seconds, 3)
        if grading.get('passed') else None,
        'wall_seconds': round(time.monotonic() - started, 3),
    }
    document = observation_document(run_id, task, arm, solver, protocol, compiler, prompt,
                                    sha256_text(prompt), solver_result, events_summary, grading,
                                    probes, profile, started_utc, timings, status, blocked_reason)
    document['work_directory'] = str(workdir)
    document['workspace'] = str(workspace)
    RUNS.mkdir(parents=True, exist_ok=True)
    out = args.out or (RUNS / f'{run_id}.json')
    write_json(out, document)
    print(f'run {run_id}: {status}')
    print(f'  task {task["id"]} arm {arm} solver {solver}')
    print(f'  compiler sha256 {compiler["sha256"][:16]}... '
          f'compiler_sha256 {compiler.get("compiler_sha256")}')
    print(f'  acceptance {"PASS" if grading.get("passed") else "FAIL"} '
          f'({grading.get("seconds")}s); wall {timings["wall_seconds"]}s')
    print(f'  compiler invocations {events_summary["invocations"]} '
          f'(failed {events_summary["failed_compiler_invocations"]}), '
          f'response bytes {events_summary["stdout_bytes"]}+{events_summary["stderr_bytes"]}')
    for phase, facts in sorted(events_summary['phases'].items()):
        print(f'    {phase:22s} {facts["invocations"]:3d} invocations, '
              f'{facts["failed"]:2d} failed, {facts["wall_seconds"]:.2f}s process time')
    print(f'  observation {out}')
    if args.report:
        print(json.dumps(document, indent=1))
    if blocked_reason:
        print(f'run blocked: {blocked_reason}', file=sys.stderr)
        return 3
    return 0 if grading.get('passed') else 1


# --------------------------------------------------------------------------
# protocol rendering and listing
# --------------------------------------------------------------------------

def cmd_list(args: argparse.Namespace) -> int:
    """Print every frozen task and the arms the protocol defines."""
    protocol = load_json(PROTOCOL)
    print(f'protocol {protocol.get("version")} ({protocol.get("cohort")} cohort), '
          f'default solver {protocol.get("default_solver")}')
    print('arms: ' + ', '.join(item.get('name', '?') for item in protocol.get('arms') or []))
    for name in task_ids():
        task = load_task(name)
        print(f'  {name:22s} {task.get("family", ""):26s} {task.get("title", "")}')
    return 0


def cmd_protocol_md(args: argparse.Namespace) -> int:
    """Render protocol.md from protocol.json so the two cannot drift."""
    protocol = load_json(PROTOCOL)
    lines = [
        '# E1 development protocol (frozen)',
        '',
        f'Generated from `protocol.json` ({protocol.get("version")}, frozen '
        f'{protocol.get("frozen_on")}) by `pilot.py protocol-md`. Edit the JSON, never this file; '
        'the harness hashes both and every observation records the hashes.',
        '',
        f'**Scope.** {protocol.get("scope")}',
        '',
        '## Compiler and identity',
        '',
    ]
    for key, value in protocol['compiler'].items():
        lines.append(f'* `{key}`: {value}')
    lines += ['', '## Model and profile', '']
    for key, value in protocol['models'].items():
        lines.append(f'* `{key}`: {value}')
    lines += ['', '## Prompts', '', 'Template:', '', '```text', protocol['prompt_template'], '```', '']
    for item in protocol.get('arms') or []:
        lines += [f'### Arm `{item["name"]}`', '', item['note'], '']
    lines += ['## Tools', '', 'Visible:', '']
    lines += [f'* {item}' for item in protocol.get('tools_visible') or []]
    lines += ['', 'Never visible:', '']
    lines += [f'* {item}' for item in protocol.get('tools_never_visible') or []]
    lines += ['', '## Cache policy', '']
    for key, value in protocol['cache_policy'].items():
        lines.append(f'* `{key}`: {value}')
    lines += ['', '## Budgets', '']
    for key, value in protocol['budgets'].items():
        lines.append(f'* `{key}`: {value}')
    lines += ['', '## Grading', '']
    for key, value in protocol['grading'].items():
        if isinstance(value, list):
            lines += [f'* `{key}`:'] + [f'  * {item}' for item in value]
        else:
            lines.append(f'* `{key}`: {value}')
    lines += ['', '## Invariants', ''] + [f'* {item}' for item in protocol.get('invariants') or []]
    lines += ['', '## Solver templates', '', '```json',
              json.dumps(protocol['solver_templates'], indent=1), '```', '']
    text = '\n'.join(lines)
    target = HERE / 'protocol.md'
    target.write_text(text)
    print(f'protocol-md: wrote {target.relative_to(HERE)} '
          f'(sha256 {sha256_text(text)[:16]}...)')
    return 0


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------

def parse_args(argv: list[str]) -> argparse.Namespace:
    """Command-line contract for the E1 development pilot harness."""
    parser = argparse.ArgumentParser(
        description='Run, grade and record one E1 development task attempt.',
        formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)

    materialize = sub.add_parser('materialize', help='freeze the compiler into pack/tools')
    materialize.add_argument('--timeout', type=float, default=60.0)

    sub.add_parser('freeze', help='write pack/manifest.json from the current tree')

    verify = sub.add_parser('verify', help='refuse drift in the pack or the tool identity')
    verify.add_argument('--timeout', type=float, default=60.0)

    selftest = sub.add_parser('selftest', help='acceptance fails on source, passes on answer')
    selftest.add_argument('--compiler', type=Path)
    selftest.add_argument('--timeout', type=float, default=120.0)

    run = sub.add_parser('run', help='run one task attempt end to end')
    run.add_argument('--task', required=True, help='task id from the frozen pack')
    run.add_argument('--arm', help='arm name from the protocol (default: the first arm)')
    run.add_argument('--solver', help='solver name, or script:PATH (default: the protocol)')
    run.add_argument('--run-id', help='run id (default: timestamp-task-arm-solver)')
    run.add_argument('--out', type=Path, help='observation path (default evidence/runs/<id>.json)')
    run.add_argument('--compiler', type=Path, help='compiler override (identity-checked)')
    run.add_argument('--timeout', type=float, help='solver wall budget in seconds')
    run.add_argument('--report', action='store_true', help='also print the observation')

    sub.add_parser('list', help='list the frozen tasks and arms')
    sub.add_parser('protocol-md', help='render protocol.md from protocol.json')
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Dispatch one harness subcommand."""
    args = parse_args(sys.argv[1:] if argv is None else argv)
    handlers = {'materialize': cmd_materialize, 'freeze': cmd_freeze, 'verify': cmd_verify,
                'selftest': cmd_selftest, 'run': cmd_run, 'list': cmd_list,
                'protocol-md': cmd_protocol_md}
    try:
        return handlers[args.command](args)
    except SetupError as error:
        print(f'pilot.py: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
