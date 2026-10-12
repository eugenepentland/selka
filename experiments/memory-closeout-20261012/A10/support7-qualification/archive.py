#!/usr/bin/env python3
"""Archive completed package commands without archiving executable caches."""
from pathlib import Path
import gzip
import hashlib
import json

ROOT=Path(__file__).resolve().parents[4]
EVIDENCE=Path(__file__).resolve().parent
WORK=ROOT/'.tmp/memory-closeout/A10/package-support7'

def digest(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def main():
    result=json.loads((WORK/'results.json').read_text())
    assert result['passed'] and result['pure_test_executions']==42
    assert len(result['rows'])==12
    raw=EVIDENCE/'raw';raw.mkdir(exist_ok=True)
    archive={}
    files=[WORK/'results.json',*sorted((WORK/'identities').iterdir())]
    for row in result['rows']:
        files.extend(sorted((WORK/row['label']).iterdir()))
    for source in files:
        assert source.is_file()
        data=source.read_bytes(); target=raw/(str(source.relative_to(WORK))+'.gz')
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(gzip.compress(data,mtime=0))
        archive[str(target.relative_to(EVIDENCE))]={'original_sha256':hashlib.sha256(data).hexdigest(),
            'compressed_sha256':digest(target),'original_bytes':len(data)}
    # Installed binaries and fresh guest binaries are distinct qualified objects.
    result['fresh_binaries']={name:digest(WORK/(name+'-release')) for name in ['test-index','cache-plan']}
    result['harness_sha256']=digest(EVIDENCE/'qualify_package.py')
    result['raw']=archive
    result['measurement_limits']='Oracle scripts print incidental durations; these correctness runs have shared build admission, not exclusive timing admission. No runtime/RSS or speedup claim.'
    result['counted_component_protocols']='A08 separately owns exact Support7 688-run counted protocol qualification; these installed components are uninstrumented.'
    result['state']='Support7 intermediate exact package qualification passed; later candidates and C2/C3 require rerun'
    (EVIDENCE/'package-results.json').write_text(json.dumps(result,indent=2)+'\n')
    print('archived',len(files),'files; 42 pure tests and both fresh/installed protocols passed')


if __name__=='__main__':main()
