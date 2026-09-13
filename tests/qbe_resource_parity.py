#!/usr/bin/env python3
"""Execute resource-provider semantics and exact VM event order through QBE."""
import argparse
from pathlib import Path
import tempfile
import native_resources as oracle


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',required=True)
    parser.add_argument('--qbe',required=True)
    parser.add_argument('--zig',default='zig')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    example=(root/'examples/resources.my').read_text()
    prefix='resource File:filesystem;result A{ok:File,err:i64}result Run{ok:i64,err:i64}'
    finish='fn main(fs:filesystem_cap)->i64{match work(fs){Run.ok(n)=>{return n;},Run.err(e)=>{return e;}}}'
    cases=[('normal',example,{},0,b'7\n',None),
           ('retry',example,{'COMPLETE':1},0,b'7\n',None),
           ('denied',example,{'COMPLETE':2},0,b'2\n',None),
           ('missing','fn main(fs:filesystem_cap)->i64{return 7;}',{'MISSING':1},2,b'',b'CapabilityUnavailable')]
    reordered=prefix+'struct Pair{first:File,second:File}fn work(fs:filesystem_cap)->Run{let first=acquire_resource[A](fs,new [1]u8[42u8])?;let second=acquire_resource[A](fs,new [0]u8[])?;let pair=new Pair{first:second,second:first};_ = pair;return new Run.ok(9);}'+finish
    cases.append(('record-drop-order',reordered,{},0,b'9\n',None))
    cases.extend(oracle.io_cases(prefix,finish))
    generic=(root/'examples/generic-resources.my').read_text()
    cases.extend([('generic',generic,{},0,b'8\n',None),
                  ('generic-network',generic.replace('filesystem','network'),{},0,b'8\n',None)])
    quota=prefix+'fn work(fs:filesystem_cap,n:i64)->Run{let first=acquire_resource[A](fs,new [0]u8[])?;if n==0{_ = first;return new Run.ok(0);}let second=acquire_resource[A](fs,new [0]u8[])?;return work(fs,n-1);}fn main(fs:filesystem_cap)->i64{match work(fs,512){Run.ok(n)=>{return n;},Run.err(first)=>{match work(fs,512){Run.ok(n)=>{return n;},Run.err(second)=>{return first+second;}}}}}'
    cases.append(('quota-reuse',quota,{},0,b'8\n',None))
    with tempfile.TemporaryDirectory(prefix='qbe-resources-') as directory:
        directory=Path(directory)
        traces=oracle.vm_oracle(root,directory,args.zig,cases)
        previous=None
        for i,(name,text,settings,code,output,error) in enumerate(cases):
            source=directory/'case.my';source.write_text(text)
            executable=directory/'program'
            if text!=previous:
                built=oracle.invoke(['python3',root/'scripts/qbe.py',source,'--compiler',args.compiler,
                                     '--qbe',args.qbe,'--zig',args.zig,'--provider',root/'tests/native_resources.c','-o',executable],timeout=240)
                assert built.returncode==0,(name,built.stderr.decode())
                previous=text
            result=oracle.invoke([executable],settings)
            assert (result.returncode,result.stdout)==(code,output),(name,result)
            if error:assert error in result.stderr,(name,result.stderr)
            events=oracle.events(result);oracle.balanced(events)
            if i in traces:assert events==traces[i],(name,events,traces[i])
    print(f'QBE resources: {len(cases)} lifecycle/I/O comparisons and VM release-order checks passed')


if __name__=='__main__':main()
