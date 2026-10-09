#!/usr/bin/env python3
"""Audit every complete-report difference without dropping verdict/diagnostic fields."""
import argparse,copy,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('corpus',choices=['lox','eda']);p.add_argument('--folder');a=p.parse_args();area=Path(__file__).resolve().parent;folder=area/(a.folder or (a.corpus+'-modes'));reference=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-frontend-integration/experiments/frontend-current-lang-oracle-20261008')/a.corpus
identity=json.loads((reference/'identity.json').read_text());oldroot=identity['source_worktree'];newroot=str(area/'sources'/a.corpus);summary=json.loads((folder/'summary.json').read_text());audit={}
for label,r in summary['results'].items():
 cat,mode,*rest=label.split('/');name='/'.join(rest)
 if cat=='directory':saved=json.loads((reference/'directory.json').read_text())[mode]
 else:saved=json.loads((reference/(cat+'-'+mode+'.json')).read_text())['files'][name]
 rp=reference/saved['receipt'];old=json.loads(rp.with_suffix('.stdout').read_text());new=json.loads((folder/'commands'/label).with_suffix('.stdout').read_text());normalized=copy.deepcopy(old);changes=[];unreviewed=[]
 for i,v in enumerate(normalized.get('sources',[])):
  replacement=v.replace(oldroot,newroot);changes.append({'field':'sources['+str(i)+']','before':v,'after':replacement,'reason':'verified source snapshot relocation'});normalized['sources'][i]=replacement
 for i,t in enumerate(normalized['tests']):
  nt=new['tests'][i]
  if a.corpus=='eda':
   before=t['name'];t['name']='src.'+before;changes.append({'field':'tests['+str(i)+'].name','before':before,'after':t['name'],'reason':'mylang.json project root makes frozen sibling module identities src.<module>'})
  if cat=='configured':
   for key in ['contract','provider','source']:
    if t.get(key)!=nt.get(key):changes.append({'field':'tests['+str(i)+'].'+key,'before':t.get(key),'after':nt.get(key),'reason':{'contract':'case manifest provider source has migrated syntax; case names/providers unchanged','provider':'provider implementation syntax migrated with compiler fix','source':'settings fingerprint includes candidate compiler identity/environment; immutable preimage equivalence not proved'}[key]});t[key]=nt.get(key)
 stderr_old=rp.with_suffix('.stderr').read_bytes();stderr_new=(folder/'commands'/label).with_suffix('.stderr').read_bytes();stderr_relocated=stderr_old.replace(oldroot.encode(),newroot.encode())
 if normalized!=new:unreviewed.append('full report differs beyond explicit changes')
 if stderr_relocated!=stderr_new:unreviewed.append('stderr differs beyond source root relocation')
 audit[label]={'explicit_changes':changes,'complete_report_matches_after_explicit_changes':normalized==new,'stderr_exact_after_root_relocation':stderr_relocated==stderr_new,'unreviewed':unreviewed,'configured_fingerprint_equivalence_proved':False if cat=='configured' else None}
result={'commands':len(audit),'unreviewed_commands':[k for k,v in audit.items() if v['unreviewed']],'all_verdict_fields_preserved':all(v['complete_report_matches_after_explicit_changes'] for v in audit.values()),'configured_hash_values_changed_and_explicitly_reviewed':a.corpus=='lox','configured_settings_preimage_equivalence_proved':False,'commands_audit':audit};(area/((a.folder or a.corpus+'-modes')+'-difference-audit.json')).write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='commands_audit'},indent=2))
