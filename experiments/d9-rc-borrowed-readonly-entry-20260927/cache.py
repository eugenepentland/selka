from pathlib import Path
exec(Path('.tmp-borrowed-frame/controls.py').read_text().split('for side,c in C.items():')[0])
W=W/'cache-control';W.mkdir(exist_ok=True);S=W/'main.my';c=C['after'];D={'compiler':str(c),'compiler_sha256':sha(c),'emissions':[],'builds':[],'runs':[]}
def save(): (W/'results.json').write_text(json.dumps(D,indent=2)+'\n')
prefix='record Item:\n    text: bytes\n    number: int\ndef empty() -> Item:\n'
suffix='''def pick(items: list[Item], i: int) -> Item:
    if i < 0:
        return empty()
    return items[i]
def middle(items: list[Item]) -> int:
    return pick(items, -1).number
def selected(items: list[Item]) -> int:
    return middle(items)
def main() -> int:
    return selected([Item(b"a", 7)])
'''
for label,body in [('constant','    return Item(b"first", 1)\n'),('changed','    return Item(b"second", 2)\n'),('allocated','    return Item(bytes([97]), 3)\n')]:
 S.write_text(prefix+body+suffix);(W/(label+'.my')).write_text(S.read_text());maps=[]
 for warmth in ('warm','cold'):
  cmd=[R/'scripts/build-slot.sh','build',c,'emit-qbe',S,'--rc-runtime','--cache-dir='+str(W/('warm-cache' if warmth=='warm' else label+'-cold-cache'))]
  row=execute(cmd);row.update(case=label,warmth=warmth,source_sha256=sha(S));assert row['status']==0,row
  manifest=W/(label+'-'+warmth+'.json');manifest.write_text(row.pop('stdout'));row['manifest_sha256']=sha(manifest);D['emissions'].append(row);save()
  m=json.loads(manifest.read_text());maps.append({f['symbol']:f['il'] for f in m['functions']});owned={f['name']:f['il'] for f in m['functions'] if not f['symbol'].endswith(('_rc_borrow','_rc_immortal'))}
  for name in ('middle','selected'):assert ('call $myl_qbe_rc_frame_enter' in owned[name])==(label=='allocated'),(name,label)
 assert maps[0]==maps[1],label;print(label,'warm/cold identical',flush=True)
for backend in ('qbe','llvm'):
 for warmth in ('warm','cold'):
  b=W/(backend+'-'+warmth);cmd=[R/'scripts/build-slot.sh','build',c,'build',S,'--mode=ReleaseFast','--rc-runtime=stats','--backend='+backend,'--cache-dir='+str(W/('warm-cache' if warmth=='warm' else 'native-'+backend)),'-o',b]
  if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
  row=execute(cmd);row.update(backend=backend,warmth=warmth);D['builds'].append(row);save();assert row['status']==0,row
  row.update(manifest=json.loads(Path(str(b)+'.qbe-manifest.json').read_text()),binary_sha256=sha(b));assert row['manifest']['backend']==backend
  run=execute([b]);run.update(backend=backend,warmth=warmth);D['runs'].append(run);save();assert run['status']==3,run
  counts(run);save();print(backend,warmth,'balanced owned fallback',flush=True)
D['complete']=True;save()
