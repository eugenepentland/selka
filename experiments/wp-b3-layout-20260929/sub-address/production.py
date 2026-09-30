import hashlib,json,os,pathlib,shutil,subprocess
root=pathlib.Path.cwd();out=root/'.tmp/sub-address/production';out.mkdir(parents=True,exist_ok=True)
parent=pathlib.Path('/home/epentland/ai/canopy/mylang-worktrees/codex-next-closeout-20260929')
profile=parent/'.tmp/lox-qbe-attribution';source=parent/'.tmp-rc-quick/lox/benchmarks/lox/ports/mylang'
owned=out/'source';owned.mkdir(exist_ok=True)
for p in source.glob('*.my'):shutil.copy2(p,owned/p.name)
comp=root/'.tmp/sub-address/compiler/bin/mylang';qb=root/'.tmp/sub-address/compiler/bin/qbe';old=parent/'.tmp/phase-b-targeted-combined/compiler/bin/qbe'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
initial={str(p):sha(p) for p in [comp,qb,old,root/'vendor/qbe/amd64/isel.c']}
rows=[]
def run(cmd,name,cwd=root):
 r=subprocess.run([str(x) for x in cmd],cwd=cwd,capture_output=True,text=True)
 (out/(name+'.stdout')).write_text(r.stdout);(out/(name+'.stderr')).write_text(r.stderr)
 rows.append({'command':[str(x) for x in cmd],'cwd':str(cwd),'status':r.returncode})
 if r.returncode:raise RuntimeError((name,r.returncode,r.stderr[-12000:]))
 return r.stdout
exe=out/'lox.qbe'
run([comp,'build','main.my','--project','--rc-runtime','--keep-symbols','--cache-dir',out/'cache','-o',exe],'build',owned)
asm=run(['objdump','-d','--no-show-raw-insn',exe],'assembly')
(out/'assembly').write_text(asm)
programs={}
for case,count in [('properties',20000),('string_equality',2000)]:
 input=profile/f'{case}.n{count}.lox';answer=run([exe,'--engine=vm',input],case)
 assert answer==f'{count}\n',(case,answer)
 programs[case]={'input_sha256':sha(input),'stdout':answer}
state=next((out/'cache/modules').glob('*/out/vm.manifest.json'))
d=json.loads(state.read_text());functions={}
for f in d['functions']:
 if f['name'] not in ['vm::load_frame','vm::run']:continue
 il=pathlib.Path(d['store'])/f['il_digest'];ownedil=out/(f['name'].replace('::','-')+'.ssa');shutil.copy2(il,ownedil)
 for mode,tool in [('control',old),('candidate',qb)]:
  run([tool,'-o',out/(f['name'].replace('::','-')+'-'+mode+'.s'),ownedil],f['name'].replace('::','-')+'-'+mode+'-qbe')
 functions[f['name']]={'symbol':f['symbol'],'il_sha256':sha(ownedil)}
assert initial=={str(p):sha(p) for p in [comp,qb,old,root/'vendor/qbe/amd64/isel.c']}
(out/'receipt.json').write_text(json.dumps({'inputs_before_after':initial,'source_hashes':{p.name:sha(p) for p in owned.glob('*.my')},'programs':programs,'functions':functions,'binary_sha256':sha(exe),'rows':rows},indent=2)+'\n')
print(json.dumps({'programs':programs,'functions':functions,'compiler':sha(comp),'qbe':sha(qb)},indent=2),flush=True)
