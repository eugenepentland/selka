#!/usr/bin/env python3
"""Run a pinned Lox measurement with command logs and source identity checks."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_sources(manifest):
    result = {}
    for name, source in manifest['candidate_sources'].items():
        root = Path(source['path'])
        current = {p.name: sha(p) for p in sorted(root.glob('*.my'))}
        if current != source['hashes']:
            raise ValueError(f'source identity changed: {name}')
        result[name] = current
    return result


def main():
    argv = sys.argv[1:]
    if '--work' not in argv or '--out' not in argv:
        raise SystemExit('usage: run.py PHASE --work WORK --out OUT [audit.py options]')
    work = Path(argv[argv.index('--work') + 1]).resolve()
    out = Path(argv[argv.index('--out') + 1]).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    record_path = out.with_suffix('.command.json')
    log_path = out.with_suffix('.log')
    if out.exists() or record_path.exists() or log_path.exists():
        raise ValueError(f'refusing to overwrite measurement: {out}')
    repo = Path(__file__).resolve().parents[2]
    manifest_path = work / 'binaries.json'
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    source_hashes = check_sources(manifest)
    command = [sys.executable, str(repo / 'experiments/lox-performance-audit-20261002/audit.py'), *argv]
    record = {'argv': command, 'cwd': str(repo),
              'manifest_sha256': hashlib.sha256(manifest_bytes).hexdigest(),
              'source_hashes_before': source_hashes,
              'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    record_path.write_text(json.dumps(record, indent=2) + '\n')
    env = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    with log_path.open('w') as log:
        result = subprocess.run(command, cwd=repo, env=env, stdout=log, stderr=subprocess.STDOUT)
    record.update(status=result.returncode,
                  finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  log_sha256=sha(log_path))
    record['source_hashes_after'] = check_sources(manifest)
    if manifest_path.read_bytes() != manifest_bytes:
        raise ValueError('binary manifest changed during measurement')
    record['sources_verified_after'] = True
    record_path.write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'receipt': str(out), 'status': result.returncode,
                      'sources_verified_after': True}), flush=True)
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
