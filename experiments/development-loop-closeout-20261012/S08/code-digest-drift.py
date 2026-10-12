#!/usr/bin/env python3
"""Read-only subprocess reproduction of reference-sensitive code marshal bytes."""
import hashlib
import json
import marshal
import os
from pathlib import Path
import subprocess
import sys

SOURCE = 'a = "some constant"\ndef f(x):\n    return x + 1\n'


def child():
    code = compile(SOURCE, 'same.py', 'exec')
    equal_code = compile(SOURCE, 'same.py', 'exec')
    before = marshal.dumps(code)
    stored_loaded_hash = hashlib.sha256(before).hexdigest()
    aliases = [code.co_consts[0]] * 100
    after = marshal.dumps(code)
    equal_after_aliasing = code == equal_code
    unchanged_peer = marshal.dumps(equal_code)
    del aliases
    restored = marshal.dumps(code)
    result = {'python_version': sys.version, 'marshal_version': marshal.version,
              'source_sha256': hashlib.sha256(SOURCE.encode()).hexdigest(),
              'filename_equal': code.co_filename == equal_code.co_filename,
              'code_equal_after_aliasing': equal_after_aliasing,
              'before_sha256': stored_loaded_hash,
              'after_aliasing_sha256': hashlib.sha256(after).hexdigest(),
              'equal_peer_sha256': hashlib.sha256(unchanged_peer).hexdigest(),
              'after_release_sha256': hashlib.sha256(restored).hexdigest(),
              'stored_hash_stays_fixed': stored_loaded_hash == hashlib.sha256(before).hexdigest(),
              'byte_lengths': [len(before), len(after)],
              'first_differing_bytes': [{'offset': i, 'before': x, 'after': y}
                                      for i, (x, y) in enumerate(zip(before, after)) if x != y][:16]}
    print(json.dumps(result, sort_keys=True))
    return 0 if equal_after_aliasing and before != after and restored == before and unchanged_peer == before else 1


def main():
    if sys.argv[1:] == ['--child']:
        return child()
    results = []
    for seed in ('0', '1'):
        environment = dict(os.environ, PYTHONHASHSEED=seed,
                           PYTHONDONTWRITEBYTECODE='1', PYTHONPYCACHEPREFIX='/dev/null')
        command = [sys.executable, str(Path(__file__).resolve()), '--child']
        process = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=10)
        if process.returncode:
            raise RuntimeError(process.stderr or process.stdout)
        results.append({'command': command, 'hash_seed': seed, 'exit_status': process.returncode,
                        'result': json.loads(process.stdout)})
    print(json.dumps({'schema': 1, 'production_files_changed': False, 'subprocesses': results},
                     indent=2, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
