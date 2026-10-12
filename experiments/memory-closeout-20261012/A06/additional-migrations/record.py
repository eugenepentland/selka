#!/usr/bin/env python3
"""Record reserved source identities and preserve every unresolved contract."""
from pathlib import Path
import difflib,gzip,hashlib,json,re

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]

def main():
    before=json.loads((HERE/'before.json').read_text()); latest={}
    for folder in ('after-copies','after-manual','after-followup','after-final-local','after-final-name', 'after-support5', 'after-support5-projection'):
        for path in sorted((HERE/folder).glob('batch-*.json')):
            report=json.loads(path.read_text())
            for row in report['cases']:
                latest[row['source']]=dict(row,report=str(path.relative_to(ROOT)),compiler_sha256=report['compiler_sha256'])
    rows=[]
    for old in before['cases']:
        path=ROOT/old['source'];original=gzip.decompress((ROOT/old['original_archive']).read_bytes());migrated=path.read_bytes()
        assert hashlib.sha256(original).hexdigest()==old['sha256']
        a,b=original.decode(),migrated.decode()
        for pattern in (r'(?m)^\s*assert .*$',r'(?m)^public func (\w+)'):
            assert re.findall(pattern,a)==re.findall(pattern,b),old['source']
        added=removed=0
        for tag,start,end,new_start,new_end in difflib.SequenceMatcher(a=a.splitlines(),b=b.splitlines(),autojunk=False).get_opcodes():
            if tag!='equal':added+=new_end-new_start;removed+=end-start
        digest=hashlib.sha256(migrated).hexdigest();check=latest.get(old['source'])
        rows.append({'source':old['source'],'original_sha256':old['sha256'],'migrated_sha256':digest,'original_archive':old['original_archive'],'changed':original!=migrated,'added_lines':added,'removed_lines':removed,'added_copy_sites':b.count('.copy()')-a.count('.copy()'),'assertions_preserved':True,'public_functions_preserved':True,'source_check':check,'source_check_matches_current':bool(check and check['source_sha256']==digest)})
    report={'base':before['base'],'reserved_sources':len(rows),'changed_sources':sum(row['changed'] for row in rows),'added_lines':sum(row['added_lines'] for row in rows),'removed_lines':sum(row['removed_lines'] for row in rows),'added_copy_sites':sum(row['added_copy_sites'] for row in rows),'source_admitted_current':sum(row['source_check_matches_current'] and row['source_check']['status']==0 for row in rows),'scope':'Source admission only; native behavior, counter-oracle migration and final gates remain required.','sources':rows}
    (HERE/'ledger.json').write_text(json.dumps(report,indent=2)+'\n')

if __name__=='__main__':main()
