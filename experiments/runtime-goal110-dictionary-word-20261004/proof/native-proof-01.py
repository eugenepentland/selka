from pathlib import Path
import datetime, hashlib, json, shutil, subprocess, sys
root=Path.cwd();work=root/'.mylang-cache/goal110-dict-word';out=work/'native-proof';out.mkdir(exist_ok=True)
h=lambda path:hashlib.sha256(Path(path).read_bytes()).hexdigest()
compiler=Path(shutil.which('cc')).resolve()
sources={str(p.relative_to(root)):h(p) for p in sorted((root/'src').glob('native*')) if p.suffix in {'.c','.h'}}
for p in [root/'scripts/test_native_memory.py',root/'tests/native_dictionary_word_test.c',root/'SPEC.md']:sources[str(p.relative_to(root))]=h(p)
receipt={'schema':'mylang-dictionary-word-native-proof-v1','started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'base_revision':'1a3980631e79bc65f048acd063d7250800f01901','source_state':'uncommitted guarded scalar-word read candidate','sources':sources,'compiler':{'path':str(compiler),'sha256':h(compiler)},'driver':{'path':str(Path(__file__).resolve()),'sha256':h(__file__)},'invocations':[]}
(out/'before.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps({'compiler':receipt['compiler'],'driver':receipt['driver']}),flush=True)
sys.path.insert(0,str(root/'scripts'));import test_native_memory as t
original=subprocess.run

def captured(command,**kwargs):
 executable=Path(command[0]);assert executable.is_absolute()
 row={'command':list(map(str,command)),'executable':str(executable),'sha256_before':h(executable)}
 done=original(command,capture_output=True,check=False)
 row.update(exit_status=done.returncode,stdout=done.stdout.decode(),stderr=done.stderr.decode(),sha256_after=h(executable));assert row['sha256_before']==row['sha256_after']
 receipt['invocations'].append(row)
 (out/'running.json').write_text(json.dumps(receipt,indent=2)+'\n')
 sys.stdout.write(row['stdout']);sys.stderr.write(row['stderr']);sys.stdout.flush();sys.stderr.flush()
 assert done.returncode==0,(command,done.returncode)
 return done

subprocess.run=captured
flags=['-std=c11','-O2','-Wall','-Wextra','-Werror','-fsanitize=undefined,address','-ffunction-sections','-fdata-sections','-Wl,--gc-sections']
suite,paths=next((suite,paths) for suite,paths in t.SUITES if suite=='native_dictionary_word')
for policy in ['ordinary','counted']:
 directory=out/policy;directory.mkdir(exist_ok=True)
 t.run_suite(root,[str(compiler)]+flags+(['-DMYL_NATIVE_RC_COUNTING=1'] if policy=='counted' else []),directory,suite,list(paths))
for path,digest in sources.items():assert h(root/path)==digest
assert h(compiler)==receipt['compiler']['sha256']
receipt.update(status='pass',finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),timing=False)
(out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('native word differentials passed ordinary+counted; seven GC/RC state/collision/fallback/refusal cases each',flush=True)
