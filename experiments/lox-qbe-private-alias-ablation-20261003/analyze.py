"""Verify six-arm byte identity and explain actual pinned-QBE promotion dumps."""
from pathlib import Path
from collections import Counter
import hashlib,importlib.util,json,re,subprocess
OWN=Path(__file__).resolve().parents[2]
WORK=OWN/'.tmp-lox-private-alias-ablation-20261003'
SHA=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
BASE='3b33df52044a10cb84b908f8b1641af439e8c729'
r=json.loads((WORK/'receipt.json').read_text());d=json.loads((WORK/'debug-receipt.json').read_text())
assert r['verified_after'] and d['verified_after'] and r['before']==r['after'] and d['before']==d['after']
for p,v in r['before'].items():assert SHA(Path(p))==v
for p,v in d['before'].items():assert SHA(Path(p))==v
for arm,row in r['arms'].items():
 assert row['status']==0
 for field,hashfield in [('IL_path','IL_sha256'),('assembly_path','assembly_sha256')]:assert SHA(Path(row[field]))==row[hashfield]
for row in d['commands']:
 assert row['status']==0
 for field in ['stdout','stderr']:assert SHA(Path(row[field]))==row[field+'_sha256']
p=importlib.util.spec_from_file_location('probe',OWN/'experiments/lox-qbe-private-alias-ablation-20261003/probe.py');m=importlib.util.module_from_spec(p);p.loader.exec_module(m)
source=(WORK/'control.ssa').read_text()
for arm,names in m.ARMS.items():
 expected,edits=m.rewrite(source,names)
 assert (WORK/(arm+'.ssa')).read_text()==expected
 assert r['arms'][arm]['edits']==edits
 assert r['arms'][arm]['whole']==m.counts(WORK/(arm+'.s'))
assert SHA(WORK/'control.ssa')==r['before'][str(m.INPUT)]
groups=[['control','loadub-four','s0-five'],['all-six','loadl-two','s1-one']]
for group in groups:
 first=(WORK/(group[0]+'.s')).read_bytes()
 assert all((WORK/(a+'.s')).read_bytes()==first for a in group)
slots={}
for slot in ['s0','s1']:
 refs=[]
 for at,line in enumerate(source.splitlines(),1):
  if re.search(r'%'+slot+r'(?![A-Za-z0-9_])',line):
   mm=re.search(r' =\w+ (\w+) ',line);kind=mm[1] if mm else line.split()[0]
   refs.append({'line':at,'kind':kind,'raw':line})
 slots[slot]={'operations':dict(Counter(x['kind'] for x in refs)),'non_load_store_uses':[x for x in refs if x['kind'] not in ['loadl','storel']],'all_references':refs}
assert slots['s1']['operations']=={'alloc8':1,'storel':236,'loadl':236,'copy':1}
stages={};allocations={}
for arm in ['control','s1-one']:
 parts=re.split(r'\n> ([^\n]+):\n',(WORK/(arm+'.debug.stderr')).read_text());stages[arm]=[];allocations[arm]={}
 for i in range(1,len(parts),2):
  name,body=parts[i:i+2]
  allocs={match[1]:int(match[2]) for match in re.finditer(r'%([^\s]+) =l alloc\w* (\d+)',body)}
  allocations[arm][name]=allocs
  stages[arm].append({'stage':name,'allocation_count':len(allocs),'allocation_bytes':sum(allocs.values()),'s1_alloc_present':bool(re.search(r'%s1 =l alloc8 8',body)),'s1_assignment_copies':len(re.findall(r'%s1(?:\.\d+)? =l copy',body)),'bounds_failure_call_sites':body.count('call $myl_qbe_fail_normalized_index_bounds')})
canonical=lambda a:{re.sub(r'\.\d+$','',k):v for k,v in a.items()}
c,f=[canonical(allocations[a]['Slot coalescing']) for a in ['control','s1-one']]
assert all(c[k]==f[k] for k in c.keys()&f.keys())
removed={k:v for k,v in c.items() if k not in f};added={k:v for k,v in f.items() if k not in c}
assert not added and sum(removed.values())==768
assert r['arms']['control']['whole']['stack']['initial_fixed_frame_bytes']-sum(c.values())==1872
assert r['arms']['s1-one']['whole']['stack']['initial_fixed_frame_bytes']-sum(f.values())==1872
source_map={}
for name in ['main.c','mem.c','alias.c']:
 path=OWN/'vendor/qbe'/name;blob=subprocess.run(['git','show',BASE+':vendor/qbe/'+name],cwd=OWN,capture_output=True,check=True).stdout
 assert hashlib.sha256(blob).hexdigest()==SHA(path)
 source_map[str(path)]=SHA(path)
def opcounts(arm):
 return Counter(op for op,args in m.instructions(WORK/(arm+'.s')))
op0,op1=opcounts('control'),opcounts('s1-one')
result={'scope':r['scope'],'verified_after':True,'input_sha256':SHA(WORK/'control.ssa'),'qbe_sha256':r['before'][str(m.QBE)],'whole_assembly_byte_identity_groups':[{'arms':g,'sha256':SHA(WORK/(g[0]+'.s')),'normalization':'none; complete raw assembly bytes including header, labels, .loc, function and footer'} for g in groups],'summary':{a:{'instructions':v['whole']['instructions'],'calls':v['whole']['calls'],'stack':v['whole']['stack'],'conditional_branches':v['whole']['conditional_branches'],'unconditional_jumps':v['whole']['unconditional_jumps'],'call_site_target_deltas':v['call_site_target_deltas'],'dispatch_deltas':v['dispatch_deltas']} for a,v in r['arms'].items()},'scratch_slots':slots,'actual_pinned_QBE_pass_stages':stages,'slot_coalescing_removed_allocations_normalized_ssa_versions_only':removed,'slot_coalescing_added_allocations':added,'slot_coalescing_bytes_delta':sum(f.values())-sum(c.values()),'fixed_frame_bytes_delta':4760-5528,'same_frame_bytes_beyond_postcoalescing_allocations':1872,'assembly_opcode_deltas':{op:op1[op]-op0[op] for op in op0.keys()|op1.keys() if op0[op]!=op1[op]},'explanatory_vendor_source_map':source_map,'vendor_sources_match_selected_git_base':BASE,'source_provenance_limit':'the explanatory source files byte-match selected3b33; actual pinned99ad behavior independently observed via pass dumps; no full QBE executable rebuild provenance inferred','limitations':['no guest execution, tests, counters, timing or selection in this static diagnostic','whole-function counts are emitted instruction/call sites, not executed frequency','all24 removed calls target bounds failure and are absent on valid successful execution; dynamic call savings not established','all37 successful dispatch paths counted only from opcode0 comparison through original handler entry; operand/IP prefix and handlers symmetrically excluded','changes to frame/blocks/register allocation establish static differences; no explanation of timing-regression causality is inferred']}
(WORK/'analysis.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'byte_identity_groups':result['whole_assembly_byte_identity_groups'],'coalesced_allocation_reduction':sum(removed.values()),'frame_reduction':768,'removed_allocation_count':len(removed),'verified_after':True}))
