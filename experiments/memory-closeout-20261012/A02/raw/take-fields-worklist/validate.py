from pathlib import Path
import json, subprocess, sys
root=Path.cwd();here=Path(__file__).resolve().parent;out=root/".tmp/memory-closeout/A02/take-fields-worklist"
r=json.loads((out/"registered.json").read_text());compiler=(root/r["compiler"]["path"]).resolve()
commands=[[sys.executable,here/"diagnostic.py","--compiler",compiler,"--output",out/"diagnostic"]]
for name in ("augmented","method","field_augmented","rc_semantic_publication"):
    commands.append([sys.executable,here/"matrix.py","--compiler",compiler,"--case",name,"--output",out/name])
statuses=[]
for argv in commands:
    p=subprocess.run(list(map(str,argv)),timeout=300)
    statuses.append({"argv":list(map(str,argv)),"status":p.returncode})
    (out/"validation-commands.json").write_text(json.dumps(statuses,indent=2)+"\n")
raise SystemExit(0 if all(x["status"]==0 for x in statuses) else 1)
