#!/usr/bin/env python3
"""One untimed functional run per frozen EDA case/arm; private output directory."""
import pathlib,json,os,hashlib,subprocess,shutil
root=pathlib.Path.cwd();base=root/'experiments/lox-eda-parity-20261013/P7-runtime';work=root/'.tmp/lox-eda-parity/P7-runtime';out=base/'guest-qualification-002';out.mkdir();assert os.environ['MYLANG_ADMISSION_KIND']=='build'
coordinator=pathlib.Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012');spec_root=coordinator/'experiments/lox-eda-parity-20261013/attempts/runtime-001/specs';receipt=json.loads((base/'guest-builds-001/build-receipt.json').read_text());control=coordinator/'.tmp/lox-eda-parity/P6/native-001/eda/zero-rc'
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def tree(folder):return {str(p.relative_to(folder)):sha(p) for p in sorted(folder.rglob('*')) if p.is_file()}
inputs={};rows=[];cases=sorted(spec_root.glob('eda-*.json'));assert len(cases)==34
binaries={'installed-C1':{'path':str(control),'sha256':receipt['inputs'][str(control)]},**receipt['variants']}
for spec_path in cases:
 spec=json.loads(spec_path.read_text());name=spec_path.stem;inputs[str(spec_path)]=sha(spec_path)
 paths=[pathlib.Path(p) for p in spec['files']]
 for directory in spec['identity_dirs']:paths.extend(p for p in pathlib.Path(directory).rglob('*') if p.is_file())
 case_pins={str(p):sha(p) for p in paths};inputs.update(case_pins);golden=tree(pathlib.Path(spec['golden_dir']));directory=work/'outputs'/name;template=spec['arms']['mylang-zero-rc'];oracle=None;oracle_stderr=None
 for arm,item in binaries.items():
  assert sha(item['path'])==item['sha256'];assert all(sha(p)==h for p,h in case_pins.items())
  if directory.exists():shutil.rmtree(directory)
  argv=[item['path'],*template[1:]];argv[argv.index('--out-dir')+1]=str(directory)
  env={**os.environ,'MYL_CORE_LEAKCHECK':'1','MYLANG_JOBS':'4'};env.pop('MYLANG_COUNTERS',None)
  result=subprocess.run(argv,capture_output=True,cwd=spec['cwd'],env=env,timeout=120)
  label=name+'-'+arm;(out/(label+'.stdout')).write_bytes(result.stdout);(out/(label+'.stderr')).write_bytes(result.stderr)
  got=tree(directory) if directory.exists() else {};stdout=hashlib.sha256(result.stdout).hexdigest()
  rows.append({'case':name,'arm':arm,'argv':argv,'returncode':result.returncode,'stdout_sha256':stdout,'stderr_sha256':hashlib.sha256(result.stderr).hexdigest(),'golden_equal':got==golden,'artifacts':got});(out/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
  assert result.returncode==0 and b'leakcheck' not in result.stderr,(label,result.returncode,result.stderr)
  assert got==golden,(label,'golden mismatch')
  if oracle is None:oracle=stdout;oracle_stderr=result.stderr
  assert stdout==oracle and result.stderr==oracle_stderr,(label,'C1 stdout/stderr mismatch')
 assert all(sha(p)==h for p,h in case_pins.items())
assert all(sha(p)==h for p,h in inputs.items())
(out/'qualification.json').write_text(json.dumps({'status':'passed_untimed','cases':len(cases),'arms':list(binaries),'runs':len(rows),'inputs':inputs,'binaries':binaries,'build_receipt_sha256':sha(base/'guest-builds-001/build-receipt.json'),'harness_sha256':sha(__file__),'outer_lease':{'kind':os.environ['MYLANG_ADMISSION_KIND'],'directory':os.environ['MYLANG_ADMISSION_DIR']}},indent=2)+'\n')
print('34 EDA cases x7 arms passed golden/output/leak checks;238 untimed runs')
