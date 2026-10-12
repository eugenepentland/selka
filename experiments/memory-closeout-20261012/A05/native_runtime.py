#!/usr/bin/env python3
"""Adapt the existing durable native regression fixture to the owned ABI.

This establishes native runtime behavior only. It does not admit a source helper
or qualify resource-result lifetimes in the compiler. Compilation owns admission.
"""
# spec: NEW-CORE-DURABLE-STORAGE-1 NEW-CORE-ZERO-RC-RESOURCES-1
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[3]

def digest(data): return hashlib.sha256(data).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--zig',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--runtime-overlay',type=Path,help='Explicitly labelled scratch runtime preview; never edits production')
    a=p.parse_args(); a.zig=a.zig.resolve(); a.output=a.output.resolve(); a.output.mkdir(parents=True,exist_ok=True)
    driver=(ROOT/'src/core/driver.zig').read_text(); declaration=driver.split('pub const runtime_source =',1)[1].split('/// One build:',1)[0]
    paths=[ROOT/'src/core'/name for name in re.findall(r'@embedFile\("([^\"]+)"\)',declaration)]
    inputs={str(path.relative_to(ROOT)):(a.runtime_overlay/path.name if a.runtime_overlay and (a.runtime_overlay/path.name).exists() else path).read_bytes() for path in paths}
    runtime=b'\n'.join(inputs.values())
    (a.output/'core_rt.c').write_bytes(runtime)
    original=(ROOT/'src/core/durable_fixture.c').read_text()
    fixture=original.replace('if (owner) core_io_retain(owner);','if (owner) (void)myl_core_result_take_pointer(result, 1);')
    fixture=fixture.replace('myl_core_release(provider);','(void)provider;' if a.runtime_overlay else 'core_io_root_transferred(provider);')
    fixture=fixture.replace('myl_core_release(', 'myl_core_drop_owned(')
    (a.output/'fixture.c').write_text(fixture)
    command=[str(ROOT/'scripts/build-slot.sh'),'build',str(a.zig),'cc','-O2','-std=c11','-pthread','-DMYL_ZERO_RC',str(a.output/'fixture.c'),'-o',str(a.output/'fixture')]
    built=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=1800)
    result={'scope':'Native owned-runtime fixture only; source resource lifetimes are not qualified by this result.','runtime_overlay':str(a.runtime_overlay) if a.runtime_overlay else None,'zig_sha256':digest(a.zig.read_bytes()),'zig_version':subprocess.check_output([str(a.zig),'version'],text=True).strip(),'source_revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'runtime_sources':{name:digest(data) for name,data in inputs.items()},'runtime_sha256':digest(runtime),'original_fixture_sha256':digest(original.encode()),'owned_fixture_sha256':digest(fixture.encode()),'argv':command,'build_status':built.returncode,'build_stdout':built.stdout,'build_stderr':built.stderr,'passed':False}
    if built.returncode==0:
        symbols=subprocess.check_output(['nm',str(a.output/'fixture')],text=True)
        result['legacy_symbols']=[name for name in ('myl_core_retain','myl_core_release','myl_core_share') if name in symbols]
        ran=subprocess.run([str(a.output/'fixture'),'all'],cwd=a.output,env=dict(os.environ,MYL_CORE_LEAKCHECK='1'),capture_output=True,text=True,timeout=60)
        result.update(run_status=ran.returncode,stdout=ran.stdout,stderr=ran.stderr,binary_sha256=digest((a.output/'fixture').read_bytes()))
        result['passed']=ran.returncode==0 and not ran.stderr and not result['legacy_symbols']
    (a.output/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({key:value for key,value in result.items() if key not in ('runtime_sources','argv')},indent=2))
    return not result['passed']

if __name__=='__main__': raise SystemExit(main())
