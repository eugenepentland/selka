import pathlib,json,hashlib,os
root=pathlib.Path.cwd();base=root/'experiments/lox-eda-parity-20261013/P7-stack';work=root/'.tmp/lox-eda-parity/P7-stack';out=base/'timing-001';out.mkdir();co=pathlib.Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012');q=json.loads((base/'qualification-005/receipt.json').read_text());assert q['status']=='passed_untimed';receipt=json.loads((base/'guest-builds-001/receipt.json').read_text());measure=root/'experiments/lox-eda-parity-20261013/measure.py';commands=[]
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
for case in q['cases']:
 original=co/'experiments/lox-eda-parity-20261013/attempts/runtime-001/specs'/(case+'.json');spec=json.loads(original.read_text());app='eda' if case.startswith('eda-') else 'lox';template=spec['arms']['mylang-zero-rc'];directory=work/'timing-outputs'/case
 def argv(binary):
  a=[str(binary),*template[1:]]
  if '--out-dir' in a:a[a.index('--out-dir')+1]=str(directory)
  return a
 zig=spec['arms']['zig-fast'][:]
 if '--out-dir' in zig:zig[zig.index('--out-dir')+1]=str(directory);spec['out_dir']=str(directory)
 spec['arms']={'zig-fast':zig,**{name:argv(item['path']) for name,item in receipt['variants'][app].items()}};spec['oracle']='zig-fast';spec['relative_timeout_arms']=['baseline','candidate'];spec['files']=sorted(set(spec['files'])|set(receipt['inputs'])|{str(base/'guest-builds-001/receipt.json'),str(base/'qualification-005/receipt.json'),str(base/'counter-repeats-001/receipt.json'),str(measure)});spec.pop('prior_receipt',None);spec['provenance']={'purpose':'C2 runtime-only scratch-init diagnostic; identical app LLVM/provider/native flags, separate runtime objects','old_spec_sha256':sha(original),'source_commit':'2d69c183674fd2338498e815ec60b8a88b67f099','chunk_target_seconds':60};(out/(case+'.json')).write_text(json.dumps(spec,indent=2)+'\n');commands.append({'case':case})
(out/'comparison.json').write_text(json.dumps({'status':'prepared','cpu':8,'calibration_rounds':5,'warmups':2,'pairs':9,'rss_rounds':3,'max_guest_seconds':120,'relative_factor':3,'commands':commands,'measure_sha256':sha(measure)},indent=2)+'\n')
