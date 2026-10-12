from pathlib import Path
import hashlib,json,re,subprocess,sys
root=Path.cwd();here=Path(__file__).resolve().parent;out=root/".tmp/memory-closeout/A02/indirect-owned-results"
r=json.loads((out/"registered.json").read_text());compiler=(root/r["compiler"]["path"]).resolve()
commands=[]
for variant in ("default","alternate"):
    command=[sys.executable,here/"matrix.py","--compiler",compiler,"--case","indirect_owned","--output",out/variant,"--expected-output",here/"expected.txt"]
    if variant=="alternate":command.extend(["--guest-arg","alternate"])
    commands.append(command)
commands.append([sys.executable,here/"matrix.py","--compiler",compiler,"--case","rc_pin_elide","--output",out/"rc_pin_elide"])
statuses=[]
for argv in commands:
    p=subprocess.run(list(map(str,argv)),timeout=300)
    statuses.append({"argv":list(map(str,argv)),"status":p.returncode})
    (out/"validation-commands.json").write_text(json.dumps(statuses,indent=2)+"\n")
argv=[str(compiler),"dump-ir",str(here/"sources/indirect_owned.my"),"--experimental-zero-rc","--facts"]
p=subprocess.run(argv,capture_output=True,text=True,timeout=90)
(out/"indirect.facts.txt").write_text(p.stdout)
checked={"argv":argv,"status":p.returncode,"stdout":p.stdout,"stderr":p.stderr,"indirect_aggregate_calls":len(re.findall(r"call_indirect record",p.stdout))}
checked["pass"]=p.returncode==0 and checked["indirect_aggregate_calls"]>=3 and not re.search(r"^  retain ",p.stdout,re.M)
(out/"diagnostic.json").write_text(json.dumps(checked,indent=2)+"\n")
raise SystemExit(0 if all(x["status"]==0 for x in statuses) and checked["pass"] else 1)
