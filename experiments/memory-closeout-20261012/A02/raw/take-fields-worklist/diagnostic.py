from pathlib import Path
import argparse, hashlib, json, re, subprocess
p=argparse.ArgumentParser();p.add_argument("--compiler",type=Path,required=True);p.add_argument("--output",type=Path,required=True);args=p.parse_args()
args.output.mkdir(parents=True,exist_ok=False)
root=Path(__file__).resolve().parent
result={"compiler":str(args.compiler),"compiler_sha256":hashlib.sha256(args.compiler.read_bytes()).hexdigest(),"cases":{}}
for name in ("augmented","method"):
    source=root/"sources"/(name+".my")
    argv=[str(args.compiler),"dump-ir",str(source),"--experimental-zero-rc","--facts"]
    p=subprocess.run(argv,capture_output=True,text=True,timeout=90)
    (args.output/(name+".facts.txt")).write_text(p.stdout)
    # A record producer with a larger numeric ref than its executed projection
    # keeps the ordering regression concrete without requiring particular ref IDs.
    makers=set(map(int,re.findall(r"%(\d+) = record_make ",p.stdout)))
    projections=[(int(a),int(b)) for a,b in re.findall(r"%(\d+) = record_get .*? %(\d+), field",p.stdout)]
    reversed_edges=[(a,b) for a,b in projections if b in makers and a<b]
    row={"source_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),"argv":argv,"status":p.returncode,"stdout":p.stdout,"stderr":p.stderr,"producer_after_projection_storage_edges":reversed_edges}
    row["pass"]=p.returncode==0 and bool(reversed_edges) and not re.search(r"^  retain ",p.stdout,re.M)
    result["cases"][name]=row
result["pass"]=all(x["pass"] for x in result["cases"].values())
(args.output/"result.json").write_text(json.dumps(result,indent=2)+"\n")
raise SystemExit(0 if result["pass"] else 1)
