#!/usr/bin/env python3
"""Compare raw closeout reports to the first batch on identical migrated inputs."""
import hashlib,json,pathlib,sys
base=pathlib.Path(__file__).resolve().parent
previous=base.parents[1]/'frontend-followthrough-20261009/external'
corpus=sys.argv[1]
oldfolder=previous/f'{corpus}-modes-successor'
newfolder=base/f'{corpus}-modes'
oldsummary=json.loads((oldfolder/'summary.json').read_text());newsummary=json.loads((newfolder/'summary.json').read_text())
labels=sorted(set(oldsummary['results'])|set(newsummary['results']))
rows=[]
for label in labels:
 oldpath=(oldfolder/'commands'/label).with_suffix('.stdout');newpath=(newfolder/'commands'/label).with_suffix('.stdout')
 old=json.loads(oldpath.read_text());new=json.loads(newpath.read_text());oldtests={t['name']:t for t in old['tests']};newtests={t['name']:t for t in new['tests']}
 changes=[]
 for name in sorted(oldtests.keys()|newtests.keys()):
  a=oldtests.get(name,{});b=newtests.get(name,{})
  for key in sorted(a.keys()|b.keys()):
   if (key in a)!=(key in b) or a.get(key)!=b.get(key):changes.append({'test':name,'field':key,'before':a.get(key),'after':b.get(key)})
 fields={field:all(oldtests[n].get(field)==newtests[n].get(field) for n in oldtests.keys()&newtests.keys()) and oldtests.keys()==newtests.keys() for field in ['contract','provider','source','status']}
 top={k:{'before':old.get(k),'after':new.get(k)} for k in old.keys()|new.keys() if k!='tests' and old.get(k)!=new.get(k)}
 rows.append({'label':label,'membership_equal':oldtests.keys()==newtests.keys(),'fields_equal':fields,'case_changes':changes,'top_level_changes':top,'raw_reports_equal':old==new,'stdout_bytes_equal':oldpath.read_bytes()==newpath.read_bytes(),'stderr_equal':oldpath.with_suffix('.stderr').read_bytes()==newpath.with_suffix('.stderr').read_bytes(),'old_report_sha256':hashlib.sha256(oldpath.read_bytes()).hexdigest(),'new_report_sha256':hashlib.sha256(newpath.read_bytes()).hexdigest()})
oldid=json.loads((oldfolder/'input-identities.json').read_text());newid=json.loads((newfolder/'input-identities.json').read_text())
result={'corpus':corpus,'baseline':str(oldfolder),'baseline_compiler_sha256':oldsummary['compiler_sha256'],'final_compiler_sha256':newsummary['compiler_sha256'],'migrated_source_inventories_equal':oldid['migrated']==newid['migrated'],'commands':len(rows),'all_membership_equal':all(r['membership_equal'] for r in rows),'all_contract_hashes_equal':all(r['fields_equal']['contract'] for r in rows),'all_provider_hashes_equal':all(r['fields_equal']['provider'] for r in rows),'all_verdicts_equal':all(r['fields_equal']['status'] for r in rows),'raw_report_equal_commands':sum(r['raw_reports_equal'] for r in rows),'stdout_byte_equal_commands':sum(r['stdout_bytes_equal'] for r in rows),'source_fingerprint_changed_commands':[r['label'] for r in rows if not r['fields_equal']['source']],'other_changed_case_fields':sorted({d['field'] for r in rows for d in r['case_changes'] if d['field']!='source'}),'configured_source_fingerprint_preimage_equivalence_proved':False,'rows':rows}
(base/f'{corpus}-first-batch-comparison.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='rows'},indent=2))
