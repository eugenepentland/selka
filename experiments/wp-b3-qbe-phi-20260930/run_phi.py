from pathlib import Path
import subprocess, sys, json, hashlib
root=Path.cwd(); dest=root/sys.argv[1]; dest.mkdir(parents=True,exist_ok=True)
qbe=Path(sys.argv[2]).resolve()
commands=[([str(qbe),'-dPGI',str(root/'tests/qbe_phi_width.ssa')],'debug.log'),([str(qbe),'-o',str(dest/'phi.s'),str(root/'tests/qbe_phi_width.ssa')],'translate.log'),(['cc','-std=c11','-O2','-Wall','-Wextra','-Werror',str(root/'tests/qbe_phi_width.c'),str(dest/'phi.s'),'-o',str(dest/'phi')],'link.log'),([str(dest/'phi')],'execute.log')]
status=[]
for cmd,log in commands:
    with (dest/log).open('wb') as f: p=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
    status.append({'argv':cmd,'log':log,'exit':p.returncode})
    print(log,p.returncode)
    if p.returncode and log!='execute.log': break
inputs=[root/'tests/qbe_phi_width.ssa',root/'tests/qbe_phi_width.c',qbe]
inputs += [p for p in dest.iterdir() if p.is_file() and p.name!='receipt.json']
manifest={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
(dest/'receipt.json').write_text(json.dumps({'commands':status,'manifest':manifest},indent=2)+'\n')
print((dest/'execute.log').read_text() if (dest/'execute.log').exists() else '')
sys.exit(status[-1]['exit'])
