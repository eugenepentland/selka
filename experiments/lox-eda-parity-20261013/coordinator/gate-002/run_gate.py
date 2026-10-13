import hashlib,json,os,subprocess,time
from pathlib import Path
root=Path.cwd();evidence=root/'.tmp/lox-eda-parity/coordinator/gate-002'
common=root/'experiments/lox-eda-parity-20261013/coordinator/common-003'
inputs=json.loads((common/'inputs.json').read_text());receipt=json.loads((common/'build-receipt.json').read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert all(sha(root/name)==digest for name,digest in inputs['source_files'].items()),'C3 compiler sources differ'
route=inputs['qualified_component_inputs'];pin=next(x['path'] for x in route if x['path'].endswith('.json'));archive=next(x['path'] for x in route if x['path'].endswith('.tar'))
command=['python3','-B','scripts/verify_cache.py','--zig',os.environ['ZIG'],'--','-j'+os.environ['MYLANG_DEV_JOBS'],'--maxrss',os.environ['MYLANG_DEV_MAXRSS'],'-Dcomponent-owned-compiler-pin='+pin,'-Dcomponent-seed-source='+archive]
record={'gate_commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'compiler_source_commit':receipt['source_commit'],'compiler_sha256':receipt['compiler_sha256'],'compiler_source_manifest_matches':True,'common_receipt_sha256':sha(common/'build-receipt.json'),'command':command,'note':'Run directly; verification coordinator owns admission. Admission-inclusive elapsed is not a compiler benchmark.'}
(evidence/'command.json').write_text(json.dumps(record,indent=2)+'\n')
started=time.monotonic()
with (evidence/'gate.log').open('x') as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
record.update(returncode=r.returncode,elapsed_seconds_including_admission=time.monotonic()-started,compiler_source_manifest_matches_after=all(sha(root/name)==digest for name,digest in inputs['source_files'].items()))
(evidence/'status.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({k:record[k] for k in ['returncode','elapsed_seconds_including_admission','compiler_source_manifest_matches_after']}),flush=True)
raise SystemExit(r.returncode)
