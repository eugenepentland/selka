#!/usr/bin/env python3
"""Retain independent native case-validation reducers before any M correction."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'case-validation-red-04'
OUT.mkdir(exist_ok=False)
CORE = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-project-tests/.zig-cache/o/a8dc6a99ca5967be3ab8af417d540a00/mylang-core')
OLD = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-integration/.mylang-cache/s3/oracle/mylang')
QBE = ROOT.parent / 'immutable-3c86c/qbe'
ZIG = Path('/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig')
expected_core = 'c6944963c8749593fb6cabb5a85bf89ab7185aa94696a4032c23fd39575f2bc2'
expected_old = 'd36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79'
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
assert digest(CORE) == expected_core
assert digest(OLD) == expected_old
env = dict(os.environ)
env.update(MYLANG_ZIG=str(ZIG), MYLANG_QBE=str(QBE), XDG_CACHE_HOME=str(OUT / 'xdg'), MYLANG_FRONTEND_CACHE=str(OUT / 'frontend'), ZIG_GLOBAL_CACHE_DIR=str(OUT / 'zig-global'), ZIG_LOCAL_CACHE_DIR=str(OUT / 'zig-local'), TMPDIR=str(OUT / 'tmp'))
Path(env['TMPDIR']).mkdir()
summary = {
    'source': '68ff263b5683a3c29296e8e8557892746ba19ff2',
    'scope': 'isolated native case reducers; no source correction',
    'tools': {str(p): digest(p) for p in (CORE, OLD, QBE, ZIG)},
    'environment': {k: env[k] for k in ('MYLANG_ZIG', 'MYLANG_QBE', 'XDG_CACHE_HOME', 'MYLANG_FRONTEND_CACHE', 'ZIG_GLOBAL_CACHE_DIR', 'ZIG_LOCAL_CACHE_DIR', 'TMPDIR')},
    'cases': [],
}
source_bool = 'module app\n\npublic def test_answer() -> bool:\n    return True\n'
source_int = 'module app\n\npublic def test_zero() -> int:\n    return 0\n'
survivor = '\npublic def test_z_survivor() -> bool:\n    return True\n'
source_argument_int = "module app\n\npublic def test_argument(x: int) -> bool:\n    return True\n"
source_argument_float = "module app\n\npublic def test_argument(x: float) -> bool:\n    return True\n"
reducers = tuple((name, source_argument_int, {"app::test_argument": {"arguments": {"x": value}}}) for name,value in (("integer-leading-zero","00"),("integer-plus","+0"),("integer-negative-zero","-0"),("integer-underscores","1_0"))) + tuple((name, source_argument_float, {"app::test_argument": {"arguments": {"x": value}}}) for name,value in (("float-leading-zero","00.0"),("float-plus","+0.0"),("float-negative-zero","-0.0"),("float-underscores","1_0.0"),("float-nan","nan"),("float-negative-nan","-nan")))
for name, source, cases in reducers:
    directory = OUT / name
    directory.mkdir()
    path = directory / 'app.my'
    fixture = directory / 'explicit.json'
    path.write_text(source + survivor)
    fixture.write_text(json.dumps(cases, indent=2) + '\n')
    row = {'name': name, 'source': str(path), 'source_sha256': digest(path), 'cases': str(fixture), 'cases_sha256': digest(fixture), 'commands': []}
    for arm, compiler, state in (('core', CORE, 'cold'), ('core', CORE, 'warm'), ('old', OLD, 'cold')):
        command = [str(compiler), 'test', str(path), '--cases', str(fixture), '--cache-dir', str(directory / (arm + '-cache')), '--json', '--jobs', '1', '--zig', str(ZIG)]
        started = time.monotonic()
        result = subprocess.run(command, env=env, cwd=directory, capture_output=True, timeout=120)
        duration = time.monotonic() - started
        stdout = directory / (arm + '-' + state + '.stdout')
        stderr = directory / (arm + '-' + state + '.stderr')
        stdout.write_bytes(result.stdout)
        stderr.write_bytes(result.stderr)
        entry = {'argv': command, 'cwd': str(directory), 'compiler_sha256': digest(compiler), 'status': result.returncode, 'seconds': duration, 'stdout': str(stdout), 'stderr': str(stderr), 'stdout_sha256': digest(stdout), 'stderr_sha256': digest(stderr)}
        try:
            entry['report'] = json.loads(result.stdout)
        except (ValueError, UnicodeError):
            pass
        row['commands'].append(entry)
        (OUT / 'summary.json').write_text(json.dumps(summary | {'cases': summary['cases'] + [row]}, indent=2) + '\n')
        print(json.dumps({'name': name, 'arm': arm, 'state': state, 'status': result.returncode, 'report': entry.get('report'), 'stderr_prefix': result.stderr[:300].decode(errors='replace')}, ensure_ascii=False), flush=True)
    summary['cases'].append(row)
summary['complete'] = True
summary['all_tools_unchanged'] = summary['tools'] == {str(p): digest(p) for p in (CORE, OLD, QBE, ZIG)}
(OUT / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(OUT / 'summary.json', flush=True)
