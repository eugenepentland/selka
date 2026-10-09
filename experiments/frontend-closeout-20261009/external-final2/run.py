#!/usr/bin/env python3
"""Sequential corrected-candidate qualification; run inside one build slot."""
import pathlib,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[3];base=pathlib.Path(__file__).resolve().parent
compiler=root/'experiments/frontend-closeout-20261009/artifacts/mylang-qualified'
previous=root/'experiments/frontend-followthrough-20261009/external'
ranges=root/'experiments/frontend-closeout-20261009/range'
def run(label,args):
 print(label,flush=True)
 with (base/(label+'.log')).open('wb') as log:
  result=subprocess.run(['/usr/bin/time','-v',*map(str,args)],cwd=root,stdout=log,stderr=subprocess.STDOUT)
 if result.returncode:raise SystemExit(f'{label}: exit {result.returncode}')
run('range-native',['python3',ranges/'llvm_compare.py','native-final2',compiler])
run('range-endpoints',['python3',ranges/'llvm_compare.py','native-endpoints-final2',compiler,ranges/'fixtures/range_endpoint_probe.my'])
run('native-build',['python3',base/'build_native.py',compiler])
for corpus in ['lox','eda']:
 args=['python3',previous/'qualify_modes.py',corpus,'--compiler',compiler,'--output',base/(corpus+'-modes'),'--jobs','3']
 if corpus=='eda':args+=['--preserve-property-seed','8679566789041942096']
 run(corpus+'-modes',args)
 run(corpus+'-first-batch',['python3',base/'compare_first_batch.py',corpus])
 run(corpus+'-native',['python3',previous/'tools/frontend_external_oracle.py',corpus,'--source',previous/'sources'/corpus,'--binary',base/'artifacts'/(corpus+'-release'),'--output',base/(corpus+'-native'),'--jobs','3','--against',previous/(corpus+'-native-final')/'answers.json'])
print('Qualification commands complete',flush=True)
