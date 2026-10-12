import json,subprocess,hashlib
from pathlib import Path
root=Path('/home/epentland/ai/canopy/mylang-memory-20261012-A09/.tmp/memory-closeout/A09/provider-repro');root.mkdir()
compiler='/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support4-install/bin/mylang'
cases={
 'set_add':'func main() -> int:\n    mut values: set[str] = set()\n    values.add("x")\n    return len(values)\n',
 'dict_set':'func main() -> int:\n    mut values: dict[str, int] = {}\n    values["x"] = 1\n    return len(values)\n',
 'unit_call':'func ignore():\n    pass\nfunc main() -> int:\n    ignore()\n    return 0\n',
 'list_append':'func main() -> int:\n    mut values: int[] = []\n    values.append(1)\n    return len(values)\n',
 'record_set':'record Holder:\n    items: set[str]\nfunc main() -> int:\n    mut value = Holder(items=set())\n    value.items.add("x")\n    return len(value.items)\n',
}
results={}
for name,source in cases.items():
 path=root/(name+'.my');path.write_text(source);argv=[compiler,'dump-ir',str(path),'--experimental-zero-rc'];r=subprocess.run(argv,capture_output=True,text=True);(root/(name+'.stdout')).write_text(r.stdout);(root/(name+'.stderr')).write_text(r.stderr);results[name]={'argv':argv,'status':r.returncode,'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'panic':r.stderr.splitlines()[:1]};print(name,r.returncode,results[name]['panic'],flush=True)
(root/'results.json').write_text(json.dumps(results,indent=2)+'\n')
