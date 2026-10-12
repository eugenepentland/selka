"""Compare the owned module set with an explicit original-source directory."""
from pathlib import Path
import difflib,json,sys
out=Path(__file__).resolve().parent
r=out.parent/'eda/source/src';o=Path(sys.argv[1]);rows=[];patch=[]
for p in sorted(r.glob('*.my')):
 if not p.name.startswith(('board_layers','diagram_membership','design_model','eval_','flat_netlist','placement_')):continue
 before=(o/p.name).read_text();after=p.read_text();diff=list(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='original/'+p.name,tofile='source/'+p.name));patch.extend(diff)
 rows.append(dict(module=p.name,added=sum(x.startswith('+') and not x.startswith('+++') for x in diff),removed=sum(x.startswith('-') and not x.startswith('---') for x in diff),original_copy_count=before.count('.copy()'),prepared_copy_count=after.count('.copy()'),public_api_unchanged=[x for x in before.splitlines() if x.startswith('public ')]==[x for x in after.splitlines() if x.startswith('public ')]))
(out/'original-to-prepared.patch').write_text(''.join(patch));(out/'migration-burden.json').write_text(json.dumps(rows,indent=2)+'\n')
print(sum(x['added'] for x in rows),sum(x['removed'] for x in rows),sum(x['prepared_copy_count']-x['original_copy_count'] for x in rows),all(x['public_api_unchanged'] for x in rows))
