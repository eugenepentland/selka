from pathlib import Path
import json,subprocess,sys
root=Path.cwd();here=Path(__file__).resolve().parent;out=root/".tmp/memory-closeout/A02/ce-record-copies-after"
r=json.loads((out/"registered.json").read_text());compiler=(root/r["compiler"]["path"]).resolve()
statuses=[]
for name in ("sibling","unchanged","phi"):
    argv=[sys.executable,here/"matrix.py","--compiler",compiler,"--case",name,"--output",out/name,"--expected-output",here/(name+".expected")]
    p=subprocess.run(list(map(str,argv)),timeout=300)
    statuses.append({"argv":list(map(str,argv)),"status":p.returncode})
    (out/"validation-commands.json").write_text(json.dumps(statuses,indent=2)+"\n")
raise SystemExit(0 if all(x["status"]==0 for x in statuses) else 1)
