"""Check archived static ablation receipts; no QBE or guest execution."""
from pathlib import Path
import base64,gzip,hashlib,importlib.util,json,re,sys,tempfile
HERE=Path(__file__).resolve().parent
SHA=lambda b:hashlib.sha256(b).hexdigest()
manifest=json.loads((HERE/'archive-manifest.json').read_text())
packed=(HERE/'originals.json.gz').read_bytes();assert SHA(packed)==manifest['archive_sha256']
raw=json.loads(gzip.decompress(packed));files={k:base64.b64decode(v) for k,v in raw['files'].items()}
assert set(files)==set(manifest['files'])
for k,v in files.items():assert SHA(v)==manifest['files'][k]['sha256'] and len(v)==manifest['files'][k]['bytes']
r=json.loads(files['scratch/receipt.json']);d=json.loads(files['scratch/debug-receipt.json'])
assert r['verified_after'] and d['verified_after'] and r['before']==r['after'] and d['before']==d['after']
assert all(x['status']==0 for x in r['arms'].values()) and all(x['status']==0 for x in d['commands'])
source=files['scratch/control.ssa'].decode();assert SHA(files['scratch/control.ssa'])=='33055cc51ba3cd8b6a5c17130a0594c4421677eeffe49c021877c5d3f9eff113'
assert set(r['arms'])=={'control','all-six','loadub-four','loadl-two','s0-five','s1-one'}
with tempfile.TemporaryDirectory() as temp:
 t=Path(temp);helper=t/'static-paths.py';helper.write_bytes(files['helper/static-paths.py'])
 spec=importlib.util.spec_from_file_location('paths',helper);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 for arm,row in r['arms'].items():
  lines=source.splitlines(keepends=True)
  for edit in row['edits']:
   name,root=edit['alias'],edit['root'];at=edit['definition_line']-1;used=edit['consumer_line']-1
   assert lines[at]==edit['original_definition']==f' %{name} =l copy %{root}\n'
   assert lines[used]==edit['original_consumer']
   consumers=[i for i,line in enumerate(lines) if re.search(r'%'+name+r'(?![A-Za-z0-9_])',line) and i!=at]
   assert consumers==[used]
   match=re.fullmatch(r'(\s*%\S+ =[wl] (?:loadub|loadl) )%'+name+r'(\n)',lines[used]);assert match
   assert edit['new_consumer']==match[1]+'%'+root+match[2]
   lines[at]='';lines[used]=edit['new_consumer']
  il=files['scratch/'+arm+'.ssa'];assembly=files['scratch/'+arm+'.s']
  assert ''.join(lines).encode()==il and SHA(il)==row['IL_sha256'] and SHA(assembly)==row['assembly_sha256']
  ops=[line.strip() for line in assembly.decode().splitlines() if re.match(r'^\t[a-z]',line)]
  assert len(ops)==row['whole']['instructions'] and sum(x.startswith('call') for x in ops)==row['whole']['calls']
  frame=next(int(re.fullmatch(r'subq \$(\d+), %rsp',x)[1]) for x in ops if re.fullmatch(r'subq \$(\d+), %rsp',x))
  assert frame==row['whole']['stack']['initial_fixed_frame_bytes']
  path=t/(arm+'.s');path.write_bytes(assembly);parsed=m.assembly(path)
  assert row['dispatch_paths']=={str(op):m.path(parsed,op) for op in range(37)}
for group in [['control','loadub-four','s0-five'],['all-six','loadl-two','s1-one']]:
 assert all(files['scratch/'+a+'.s']==files['scratch/'+group[0]+'.s'] for a in group)
a=json.loads(files['scratch/analysis.json']);assert a['verified_after'] and a['slot_coalescing_bytes_delta']==a['fixed_frame_bytes_delta']==-768
assert sum(a['slot_coalescing_removed_allocations_normalized_ssa_versions_only'].values())==768
if '--current' in sys.argv:
 for receipt in [r,d]:
  for path,expected in receipt['before'].items():assert SHA(Path(path).read_bytes())==expected
 for name in ['probe.py','diagnose.py','analyze.py']:
  assert (HERE/name).read_bytes()==files['helper/'+name]
 for path,expected in a['explanatory_vendor_source_map'].items():assert SHA(Path(path).read_bytes())==expected
print(json.dumps({'verified':True,'archived_originals':len(files),'arms':6,'emission_statuses':[x['status'] for x in r['arms'].values()],'actual_pass_dump_statuses':[x['status'] for x in d['commands']],'raw_byte_identity_groups':2,'successful_dispatch_walks':6*37,'current_inputs': '--current' in sys.argv,'guest_execution':False,'performance_execution':False}))
