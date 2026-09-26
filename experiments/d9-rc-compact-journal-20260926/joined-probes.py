import hashlib,json,os,re,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp/compact-journal/joined-check/probes';work.mkdir(exist_ok=True)
compiler=root/'.tmp/compact-journal/joined/bin/mylang'
text=(root/'tests/lang/rc_compact_journal.my').read_text().replace('module rc_compact_journal','module positive');names=re.findall(r'public def (test_\w+)\(',text)
positive=text+'\n\ndef main() -> int:\n'+''.join('    assert '+name+'()\n' for name in names)+'    return 0\n'
(work/'greeting.txt').write_text('hello\n')
probes={
 'positive':(positive,0,None),
 'missing':('def main(fs: Filesystem) -> int:\n    with open(fs,"absent.txt","r") as file:\n        return len(file.read())\n',1,'R_FILE'),
 'file':('def main(fs: Filesystem) -> int:\n    with open(fs,"greeting.txt","r") as file:\n        text = file.read()\n        assert text == "hello\\n"\n    return 0\n',0,None),
 'bounds':('def main() -> int:\n    values = ["owned"]\n    return len(values[3])\n',1,'R_LIST_BOUNDS'),
 'iteration':('def main() -> int:\n    values = {1:10}\n    for key in values:\n        values[2] = key\n    return 0\n',1,'R_LIST_ITERATION_MUTATION'),
 'aggregate':((root/'experiments/d9-rc-aggregate-probes-20260926/trap.my').read_text(),1,'R_ASSERT'),
}
rows={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':{}}
for backend in ('qbe','llvm'):
 for name,(source,status,code) in probes.items():
  path=work/(name+'.my');path.write_text(source)
  command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'run',str(path),'--rc-runtime=stats','--cache-dir='+str(work/'cache')]+(['--release'] if backend=='llvm' else [])
  done=subprocess.run(command,cwd=work,env=dict(os.environ,TMPDIR=str(root/'.tmp')),capture_output=True,text=True,timeout=600)
  counts=[json.loads(line.split(' ',1)[1]) for line in done.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
  key=backend+'/'+name;rows['runs'][key]={'command':command,'cwd':str(work),'status':done.returncode,'stdout':done.stdout,'stderr':done.stderr,'counts':counts,'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
  (work/'results.json').write_text(json.dumps(rows,indent=2)+'\n')
  assert done.returncode==status and len(counts)==1,(key,rows['runs'][key])
  if code:assert code in done.stderr,(key,done.stderr)
  count=counts[0];assert not count['saturated'] and count['heap_allocate']==count['retire'] and count['owner_release']==count['owner_acquire']+count['heap_allocate'] and count['hold_acquire']==count['hold_release'],(key,count)
  print(key,'pass',flush=True)
