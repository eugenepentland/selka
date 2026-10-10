#!/usr/bin/env python3
"""Qualify the ten inline R fixture sources under all five native CLI modes."""
import argparse,hashlib,json,os,pathlib,re,shutil,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('--compiler',type=pathlib.Path,required=True);p.add_argument('--tag',required=True);a=p.parse_args()
assert pathlib.Path(os.readlink('/proc/self/fd/9')).name.startswith('build')
compiler=a.compiler.resolve();area=ROOT/'experiments/runtime-parity-3-20261009/R';work=ROOT/'.mylang-cache/rp3/R/fixtures'/a.tag;work.mkdir(parents=True,exist_ok=True)
shutil.copyfile(compiler,work/'compiler');compiler=work/'compiler';compiler.chmod(0o755)
source=(ROOT/'src/core/r_runtime_test.zig').read_text();chunks=re.findall(r'const \w+ =\n((?:\s*\\\\[^\n]*\n)+)',source)
expected=['13 3 13\n14 7\n4 90\ne b\n','True -55 -9223372036854775808 9223372036854775807\n','2 1 5\n','31 14 529 15\n','-10 -6\n','780 37\n','1037 37 80\n','42 42 86\n','1 suffix-1\n3 suffix-3\n5 suffix-5\n3 4\n','5 suffix-5\n4 3 child-3\n']
assert len(chunks)==len(expected)
modes={'debug':[],'optimize-debug':['--optimize-debug'],'optimize-debug-verify':['--optimize-debug','--verify-facts'],'release':['--release'],'release-verify':['--release','--verify-facts']}
receipt={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'cells':[]}
for i,chunk in enumerate(chunks):
 text='\n'.join(line.split('\\\\',1)[1] for line in chunk.splitlines() if '\\\\' in line)+'\n';path=work/f'fixture-{i}.my';path.write_text(text)
 for mode,flags in modes.items():
  binary=work/f'{i}-{mode}';command=[str(compiler),'build',str(path),'-o',str(binary),'--cache-dir',str(work/'cache'),*flags]
  built=subprocess.run(command,cwd=ROOT,capture_output=True)
  cell={'fixture':i,'mode':mode,'command':command,'build_status':built.returncode,'build_stderr':built.stderr.decode()}
  receipt['cells'].append(cell)
  if built.returncode==0:
   ran=subprocess.run([str(binary)],cwd=ROOT,capture_output=True,env=dict(os.environ,MYL_CORE_LEAKCHECK='1'))
   cell.update(status=ran.returncode,stdout=ran.stdout.decode(),stderr=ran.stderr.decode(),matches=ran.stdout.decode()==expected[i],binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
  (area/(a.tag+'-fixtures.json')).write_text(json.dumps(receipt,indent=1))
  assert built.returncode==0 and cell['status']==0 and cell['matches'],cell
  print('fixture',i,mode,'passed',flush=True)
print('qualified',len(receipt['cells']),'native fixture/mode cells, all leak checked',flush=True)
