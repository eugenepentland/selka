#!/usr/bin/env python3
"""Compare real CLI and guarded retained help startup in private source copies.

No verification action, native build or receipt is executed. Watch/compiled-source
checks run normally in retained startup; a trace only records already-set hashes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


EXPRESSION = 'hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()'
MODULES = ('verify_cache', 'verification_snapshot', 'fuzz_campaign_store',
           'verification_process', 'verification_producers', 'verification_profiles')
OBSERVER = '''import os,sys
_seen=False
def _observe(frame,event,arg):
 global _seen
 if not _seen and event=='line' and frame.f_code.co_name=='<module>' and frame.f_code.co_filename.endswith('/scripts/verify_cache.py') and 'LOADED_CODE_SHA256' in frame.f_globals:
  _seen=True
  import json
  values={'verify_cache':frame.f_globals['LOADED_CODE_SHA256']}
  for name in ('verification_snapshot','fuzz_campaign_store','verification_process','verification_producers','verification_profiles'):
   values[name]=sys.modules[name].LOADED_CODE_SHA256
  helper=sys.modules.get('verification_code_identity')
  with open(os.environ['MYLANG_CODE_PROBE_LOG'],'a') as output:
   output.write(json.dumps({'implementation':values,'helper':getattr(helper,'LOADED_CODE_SHA256',None),'filename':frame.f_code.co_filename})+'\\n')
  sys.settrace(None)
 return _observe
sys.settrace(_observe)
'''


def prepare(root, destination, canonical):
    scripts = destination / 'scripts'
    scripts.mkdir(parents=True)
    for source in (root / 'scripts').rglob('*.py'):
        if '__pycache__' not in source.parts:
            target = scripts / source.relative_to(root / 'scripts')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
    changes = []
    if canonical:
        for path in scripts.rglob('*.py'):
            text = path.read_text()
            if EXPRESSION in text:
                text = text.replace('import marshal', 'import verification_code_identity as code_identity')
                text = text.replace(EXPRESSION, 'code_identity.loaded_code_sha256(sys._getframe().f_code)')
                path.write_text(text)
                changes.append(str(path.relative_to(destination)))
        path = scripts / 'cache_session.py'
        text = path.read_text().replace(
            'self._compiled(verification_snapshot, verification_snapshot._LOADED_CODE_OBJECT,',
            'self._compiled(code_identity, code_identity._LOADED_CODE_OBJECT,\n'
            '                           code_identity._LOADED_CODE_OBJECT.co_filename)\n'
            '            self._compiled(verification_snapshot, verification_snapshot._LOADED_CODE_OBJECT,')
        text = text.replace('if code != expected:',
                            'if code_identity.loaded_code_sha256(code) != code_identity.loaded_code_sha256(expected):')
        path.write_text(text)
    return changes


def scenario(root, scratch, name, canonical):
    destination = scratch / name
    changes = prepare(root, destination, canonical)
    observer = scratch / (name + '-observer')
    observer.mkdir()
    (observer / 'sitecustomize.py').write_text(OBSERVER)
    environment = dict(os.environ, PYTHONPATH=str(observer), PYTHONDONTWRITEBYTECODE='1',
                       PYTHONPYCACHEPREFIX='/dev/null')
    results = {}
    for mode in ('cli', 'retained'):
        log = observer / (mode + '.jsonl')
        environment['MYLANG_CODE_PROBE_LOG'] = str(log)
        command = [os.path.realpath(shutil.which('python3')), str(destination / 'scripts' /
                    ('verify_cache.py' if mode == 'cli' else 'cache_session.py'))]
        if mode == 'cli':
            command.append('--help')
            request = None
        else:
            request = json.dumps({'id': 'help', 'command': 'verify', 'args': ['--help']}) + '\n'
            request += json.dumps({'id': 'stop', 'command': 'stop'}) + '\n'
        process = subprocess.run(command, input=request, env=environment, cwd=destination,
                                 text=True, capture_output=True, timeout=60)
        observed = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        results[mode] = {'command': command, 'exit_status': process.returncode,
                         'observed': observed, 'stdout': process.stdout,
                         'stderr': process.stderr}
        if process.returncode != 0 or len(observed) != 1:
            raise RuntimeError(json.dumps(results[mode], indent=2))
        if mode == 'retained':
            completions = [json.loads(line) for line in process.stdout.splitlines()]
            if [row['status'] for row in completions] != [0, 0]:
                raise RuntimeError('retained help/stop did not complete with intact guard')
    cli, retained = [results[mode]['observed'][0]['implementation'] for mode in ('cli', 'retained')]
    equal = {module: cli[module] == retained[module] for module in MODULES}
    return {'canonical': canonical, 'private_consumer_patch_paths': changes,
            'equal_per_module': equal, 'all_equal': all(equal.values()), 'results': results,
            'source_sha256': {module: hashlib.sha256((destination / 'scripts' / (module + '.py')).read_bytes()).hexdigest()
                              for module in MODULES}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='identity-startup-') as folder:
        scratch = Path(folder)
        before = scenario(args.root, scratch, 'before', False)
        after = scenario(args.root, scratch, 'after', True)
        output = {'schema': 1, 'scope': 'real CLI --help and complete RuntimeGuard retained --help in private source copies',
                  'no_verification_actions': True, 'no_guards_suppressed': True,
                  'before': before, 'after': after}
        print(json.dumps(output, indent=2, sort_keys=True))
        return 0 if after['all_equal'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
