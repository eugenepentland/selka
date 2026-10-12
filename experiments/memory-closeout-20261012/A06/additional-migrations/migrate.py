#!/usr/bin/env python3
"""Apply only explicit copy migrations; preserve unresolved source refusals."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
spec=importlib.util.spec_from_file_location('probes',HERE.parent/'guest-migrations/probe.py')
probes=importlib.util.module_from_spec(spec);spec.loader.exec_module(probes)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--start',type=int,default=0)
    parser.add_argument('--limit',type=int,default=10)
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    baseline=json.loads((HERE/'before.json').read_text())
    report={'compiler':str(args.compiler),'compiler_sha256':hashlib.sha256(args.compiler.read_bytes()).hexdigest(),'harness_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'cases':[]}
    for old in baseline['cases'][args.start:args.start+args.limit]:
        source=ROOT/old['source'];command=[str(args.compiler),'check',str(source),'--experimental-zero-rc','--no-cache'];changes=[]
        for attempt in range(80):
            ran=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=120)
            if ran.returncode==0 or not args.apply:break
            change=probes.certain_copy(source,ran.stderr)
            if change is None:break
            changes.append(change)
        else:raise RuntimeError('migration iteration limit '+str(source))
        report['cases'].append({'source':old['source'],'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'command':command,'status':ran.returncode,'stdout':ran.stdout,'stderr':ran.stderr,'changes':changes})
        (args.output/('batch-'+str(args.start)+'.json')).write_text(json.dumps(report,indent=2)+'\n')
        print(old['source'],ran.returncode,len(changes),ran.stderr[:250].replace('\n',' '),flush=True)

if __name__=='__main__':main()
