import hashlib,json,pathlib,re,subprocess
import argparse
root=pathlib.Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser();parser.add_argument("--compiler",type=pathlib.Path,required=True);parser.add_argument("--output",type=pathlib.Path,required=True)
args=parser.parse_args();compiler=args.compiler.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
rows=[]
for name in ('rc_semantic_history','rc_semantic_publication','rc_box_writeback'):
 text=(root/'tests/lang'/f'{name}.my').read_text();names=re.findall(r'^public def (test_\w+)\(',text,re.M)
 source=out/f'{name}.my';source.write_text(text+'\n\ndef main(out: Stream) -> int:\n'+''.join(f'    out.print({n}())\n' for n in names)+'    return 0\n')
 for backend in ('qbe','llvm'):
  for mode in ('gc','rc'):
   cmd=[str(compiler),'build',str(source),'--run','--cache-dir',str(out/'cache')]+(['--release'] if backend=='llvm' else [])+(['--rc-runtime=stats'] if mode=='rc' else ['--gc-stress'])
   p=subprocess.run(cmd,text=True,capture_output=True,timeout=180)
   counts=[json.loads(l[len('MYLANG_RC_COUNTS '):]) for l in p.stderr.splitlines() if l.startswith('MYLANG_RC_COUNTS ')]
   row=dict(name=name,backend=backend,mode=mode,command=cmd,status=p.returncode,stdout=p.stdout,stderr=p.stderr,counts=counts,source_sha256=hashlib.sha256(source.read_bytes()).hexdigest());rows.append(row)
   (out/'results.json').write_text(json.dumps(dict(compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),runs=rows),indent=2)+'\n')
   assert p.returncode==0 and p.stdout=='True\n'*len(names),row
   if mode=='rc':
    assert len(counts)==1 and counts[0]['runtime']=='rc-v3-counting',row
    c=counts[0];assert c['heap_allocate']==c['retire'] and c['heap_allocate']+c['owner_acquire']==c['owner_release'] and c['hold_acquire']==c['hold_release'],row
   print(name,backend,mode,len(names),counts,flush=True)
