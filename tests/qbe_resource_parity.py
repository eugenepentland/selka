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
    prefix=('resource File: filesystem\n\n\n'
            'result A:\n    ok: File,\n    err: i64\n\n\n'
            'result Run:\n    ok: i64,\n    err: i64\n\n\n')
    finish=('def main(fs: filesystem_cap) -> i64:\n'
            '    match work(fs):\n'
            '        case Run.ok(n):\n            return n\n'
            '        case Run.err(e):\n            return e\n')
    cases=[('normal',example,{},0,b'7\n',None),
           ('retry',example,{'COMPLETE':1},0,b'7\n',None),
           ('denied',example,{'COMPLETE':2},0,b'2\n',None),
           ('missing','def main(fs: filesystem_cap) -> i64:\n    return 7\n',{'MISSING':1},2,b'',b'CapabilityUnavailable')]
    reordered=(prefix+'class Pair:\n    first: File\n    second: File\n\n\n'
               'def work(fs: filesystem_cap) -> Run:\n'
               '    request: [1]u8 = [42u8]\n'
               '    first = acquire_resource[A](fs, request)?\n'
               '    empty: [0]u8 = []\n'
               '    second = acquire_resource[A](fs, empty)?\n'
               '    pair = Pair(first=second, second=first)\n'
               '    _ = pair\n'
               '    return Ok(9)\n\n\n'+finish)
    cases.append(('record-drop-order',reordered,{},0,b'9\n',None))
    cases.extend(oracle.io_cases(prefix,finish))
    generic=(root/'examples/generic-resources.my').read_text()
    cases.extend([('generic',generic,{},0,b'8\n',None),
                  ('generic-network',generic.replace('filesystem','network'),{},0,b'8\n',None)])
    quota=(prefix+'def work(fs: filesystem_cap, n: i64) -> Run:\n'
           '    empty: [0]u8 = []\n'
           '    first = acquire_resource[A](fs, empty)?\n'
           '    if n == 0:\n        _ = first\n        return Ok(0)\n'
           '    second = acquire_resource[A](fs, empty)?\n'
           '    return work(fs, n - 1)\n\n\n'
           'def main(fs: filesystem_cap) -> i64:\n'
           '    match work(fs, 512):\n'
           '        case Run.ok(n):\n            return n\n'
           '        case Run.err(first):\n'
           '            match work(fs, 512):\n'
           '                case Run.ok(n):\n                    return n\n'
           '                case Run.err(second):\n                    return first + second\n')
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
