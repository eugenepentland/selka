import json,subprocess
from pathlib import Path
p=Path('.tmp/memory-closeout/A02/public-constructors-validation')
r=json.loads((p/'registered.json').read_text())
argv=[r['compiler']['path'],'dump-typed',str(p/'sources/generator_arguments.my'),'test_sorted_list_set_and_dict_collect_a_generator']
x=subprocess.run(argv,capture_output=True,text=True)
(p/'dict-before.typed').write_text(x.stdout)
(p/'dict-before.json').write_text(json.dumps({'compiler':r['compiler'],'argv':argv,'status':x.returncode,'stderr':x.stderr},indent=2)+'\n')
print(x.returncode)
