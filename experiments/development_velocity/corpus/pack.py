"""Freeze external task packs; public projection contains no oracle or private seed."""
import argparse
import hashlib
import json
import sys
from pathlib import Path
from .catalog import catalog, IDS, VERSION
from .cases import build
from .contracts import COMMON, DESCRIPTIONS


def encoded(value):return (json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False)+'\n').encode()
def sha(value):return hashlib.sha256(value).hexdigest()


def create(destination, task, seed):
    if task not in IDS or not seed.strip():raise ValueError('known task and nonempty seed required')
    destination=Path(destination).resolve()
    source=Path(__file__).resolve().parent
    repository=source.parents[2]
    if destination.is_relative_to(repository):raise ValueError('private packs must be outside repository')
    destination.mkdir(parents=True,exist_ok=False)
    public=destination/'public';private=destination/'private';public.mkdir();private.mkdir(mode=0o700)
    authoring={p.name:sha(p.read_bytes()) for p in source.glob('*.py')}
    files={'public/PROCESS.md':COMMON.encode(),'public/TASK.md':DESCRIPTIONS[task].encode(),
           'public/cases.json':encoded(build(task,'public-v1',public=True)),
           'private/cases.json':encoded(build(task,seed)),
           'private/seed.txt':seed.encode()}
    for name,data in files.items():
        path=destination/name;path.write_bytes(data)
        if name.startswith('private/'):path.chmod(0o600)
    if authoring != {p.name:sha(p.read_bytes()) for p in source.glob('*.py')}:
        raise ValueError('authoring changed while generating pack; retain incomplete directory for review')
    receipt={'version':VERSION,'task':task,'status':'draft-preparation-only','timed_launch_ready':False,
             'files':{name:sha(data) for name,data in files.items()},
             'authoring':authoring, 'python_version':sys.version,
             'prerequisites':next(x['prerequisites'] for x in catalog()['tasks'] if x['id']==task)}
    (destination/'receipt.json').write_bytes(encoded(receipt))
    return receipt


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--task',required=True,choices=IDS);parser.add_argument('--seed-file',required=True,type=Path)
    parser.add_argument('--directory',required=True,type=Path);args=parser.parse_args()
    receipt=create(args.directory,args.task,args.seed_file.read_text())
    print(json.dumps({'task':receipt['task'],'status':receipt['status'],'receipt_sha256':sha(encoded(receipt))}))

if __name__=='__main__':main()
