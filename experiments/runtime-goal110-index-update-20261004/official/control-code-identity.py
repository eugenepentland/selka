from pathlib import Path
import hashlib, json, struct, datetime
root=Path.cwd();work=root/'.mylang-cache/goal110-index-forward-rf'
control=Path('/home/epentland/ai/canopy/mylang-worktrees/goal110-g4-rf-20261004/.mylang-cache/goal110-g4-rf/runner/manifest.json')
after=work/'runner/manifest.json'
h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def elf(path):
 d=Path(path).read_bytes();assert d[:6]==b'\x7fELF\x02\x01'
 off=struct.unpack_from('<Q',d,40)[0];ent,count,idx=struct.unpack_from('<HHH',d,58)
 sh=[struct.unpack_from('<IIQQQQIIQQ',d,off+i*ent) for i in range(count)];st=sh[idx];strings=d[st[4]:st[4]+st[5]]
 out={}
 for x in sh:
  if x[2]&2:
   name=strings[x[0]:strings.index(b'\0',x[0])].decode()
   out[name]={'type':x[1],'flags':x[2],'address':x[3],'size':x[5],'alignment':x[8],'sha256':None if x[1]==8 else hashlib.sha256(d[x[4]:x[4]+x[5]]).hexdigest()}
 phoff=struct.unpack_from('<Q',d,32)[0];phent,phcount=struct.unpack_from('<HH',d,54)
 ph=[struct.unpack_from('<IIQQQQQQ',d,phoff+i*phent) for i in range(phcount)]
 return out,[{'header':list(x),'load_sha256':hashlib.sha256(d[x[2]:x[2]+x[5]]).hexdigest() if x[0]==1 else None} for x in ph]
ms={k:json.loads(p.read_text()) for k,p in [('before',control),('after',after)]}
result={'schema':'mylang-index-update-control-code-identity-v1','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'read_only':True,'source_revisions':{k:m['identity']['source_revision'] for k,m in ms.items()},'manifests':{k:{'path':str(p),'sha256':h(p)} for k,p in [('before',control),('after',after)]},'rows':[]}
for g in ['compute','collections','text']:
 for arm in ['my-llvm','my-qbe']:
  name=g+'/'+arm; row={'name':name,'artifacts':{}}
  for side,m in ms.items():
   p=Path(m['identity']['binary_paths'][name]);assert h(p)==m['binary_hashes'][name]
   s,ph=elf(p); row['artifacts'][side]={'path':str(p),'sha256':h(p),'allocated_sections':s,'program_headers':ph,'native_metadata_sha256':h(str(p)+'.qbe-manifest.json')}
  b,a=(row['artifacts'][k] for k in ['before','after'])
  row['allocated_sections_identical']=b['allocated_sections']==a['allocated_sections']
  row['different_allocated_sections']=[k for k in sorted(set(b['allocated_sections'])|set(a['allocated_sections'])) if b['allocated_sections'].get(k)!=a['allocated_sections'].get(k)]
  row['program_headers_and_load_contents_identical']=b['program_headers']==a['program_headers']
  row['program_headers_identical']=[x['header'] for x in b['program_headers']]==[x['header'] for x in a['program_headers']]
  assert row['program_headers_identical']
  db,da=(Path(row['artifacts'][k]['path']).read_bytes() for k in ['before','after'])
  row['load_byte_differences']=[]
  for index,(pb,pa) in enumerate(zip(b['program_headers'],a['program_headers'])):
   if pb['load_sha256']!=pa['load_sha256']:
    header=pb['header'];offset,size=header[2],header[5]
    differences=[offset+i for i,(x,y) in enumerate(zip(db[offset:offset+size],da[offset:offset+size])) if x!=y]
    row['load_byte_differences'].append({'program_header_index':index,'flags':header[1],'absolute_file_offsets':differences})
  row['executable_loads_identical']=all(pb==pa for pb,pa in zip(b['program_headers'],a['program_headers']) if pb['header'][0]==1 and pb['header'][1]&1)
  assert row['executable_loads_identical'] and row['allocated_sections_identical']
  assert all(x['absolute_file_offsets']==[40] for x in row['load_byte_differences'])
  row['load_difference_explanation']='ELF header e_shoff offset40 changes with nonallocated section layout; all program headers, executable LOAD contents and SHF_ALLOC sections are exact.'
  row['text_identical']=b['allocated_sections']['.text']==a['allocated_sections']['.text']
  result['rows'].append(row)
for side,m in ms.items():
 for row in result['rows']:assert h(row['artifacts'][side]['path'])==row['artifacts'][side]['sha256']
(work/'control-code-identity.json').write_text(json.dumps(result,indent=2)+'\n')
for row in result['rows']:print(row['name'],'text',row['text_identical'],'allocated',row['allocated_sections_identical'],'load',row['program_headers_and_load_contents_identical'],'different',row['different_allocated_sections'])
