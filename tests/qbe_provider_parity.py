#!/usr/bin/env python3
"""Execute the existing VM provider oracle cases through QBE native callbacks."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import native_providers as external
import native_environment as environment


def run(args, env=None):
    return subprocess.run(list(map(str,args)),capture_output=True,env=env,timeout=240)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',required=True)
    parser.add_argument('--qbe',required=True)
    parser.add_argument('--zig',default='zig')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    count=0
    with tempfile.TemporaryDirectory(prefix='qbe-providers-') as directory:
        directory=Path(directory)
        external.vm_oracle(root,directory,args.zig)
        environment.vm_oracle(root,directory,args.zig)
        for family,sources,provider in [('external',external.SOURCES,'native_provider.c'),
                                        ('environment',environment.SOURCES,'native_environment.c')]:
            for index,text in enumerate(sources):
                source=directory/'input.my';source.write_text(text)
                output=directory/'program'
                built=run(['python3',root/'scripts/qbe.py',source,'--compiler',args.compiler,
                           '--qbe',args.qbe,'--zig',args.zig,'--provider',root/'tests'/provider,'-o',output])
                assert built.returncode==0,built.stderr.decode()
                if family=='external':
                    cases=[]
                    for selected,clock,random,missing,value,error,cc,rc in external.cases():
                        if selected!=index:continue
                        env=dict(os.environ,TEST_CLOCK_STATUS=str(clock),TEST_RANDOM_STATUS=str(random),TEST_MISSING=str(missing))
                        cases.append((env,value,error,f'provider-calls: {cc} {rc}\n'))
                else:
                    cases=[(environment.settings(mode,missing,index==3),value,error,f'environment-calls: {calls}\n')
                           for selected,mode,missing,value,error,calls in environment.CASES if selected==index]
                for env,value,error,trace in cases:
                    result=run([output],env)
                    if error:
                        assert result.returncode==2 and not result.stdout and error.encode() in result.stderr,(family,index,error,result)
                    else:
                        assert result.returncode==0 and result.stdout==f'{value}\n'.encode(),(family,index,result)
                    assert trace.encode() in result.stderr,(family,index,result.stderr)
                    count+=1
    print(f'QBE providers: {count} clock/random/environment VM oracle comparisons passed')


if __name__=='__main__':main()
