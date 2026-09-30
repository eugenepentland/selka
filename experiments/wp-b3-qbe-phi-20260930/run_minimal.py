from pathlib import Path
import subprocess, hashlib, json,sys
root=Path.cwd();dest=root/sys.argv[1];dest.mkdir(parents=True,exist_ok=True);qbe=Path(sys.argv[2]).resolve();source=root/'experiments/wp-b3-qbe-phi-20260930/original-reduction/minimal.ssa';driver=root/'experiments/wp-b3-qbe-phi-20260930/original-reduction/minimal.c'
commands=[([str(qbe),'-dPGI',str(source)],'debug.log'),([str(qbe),'-o',str(dest/'minimal.s'),str(source)],'translate.log'),(['cc','-std=c11','-O2','-Wall','-Wextra','-Werror',str(driver),str(dest/'minimal.s'),'-o',str(dest/'minimal')],'link.log'),([str(dest/'minimal')],'execute.log')]
status=[]
for cmd,log in commands:
    with (dest/log).open('wb') as f:p=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
    status.append({'argv':cmd,'log':log,'exit':p.returncode})
    print(log,p.returncode)
    if p.returncode:break
inputs=[source,driver,qbe]+[p for p in dest.iterdir() if p.is_file() and p.name!='receipt.json']
(dest/'receipt.json').write_text(json.dumps({'commands':status,'manifest':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}},indent=2)+'\n')
print((dest/'execute.log').read_text() if (dest/'execute.log').exists() else '')
sys.exit(status[-1]['exit'])
