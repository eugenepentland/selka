#!/usr/bin/env python3
"""Typed JSON QBE native/VM parity through the normative codec bridge."""
import argparse
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]


def run(command):
    return subprocess.run(list(map(str,command)),capture_output=True,timeout=240)


def signature(result):
    return (0,result.stdout) if result.returncode==0 else (result.returncode,re.findall(rb'R_[A-Z_]+',result.stderr)[:1])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,required=True)
    parser.add_argument('--qbe',default='qbe')
    parser.add_argument('--zig',default='zig')
    args=parser.parse_args()
    original=(ROOT/'src/native_fixtures/typed_json.my').read_text()
    document='buffer Bytes:u8;buffer Words:i64;result Encoded{ok:Bytes,err:i64}result Parsed{ok:Words,err:i64}' \
        'fn work(heap:allocator)->Parsed{let bytes=try json_encode::<Encoded>(heap,42,4096);return json_parse::<Parsed>(heap,bytes,4096);}' \
        'fn main(heap:allocator)->i64{match work(heap){Parsed.ok(words)=>{return read_buffer(words,0);},Parsed.err(e)=>{return -e;}}}' 
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-json-') as directory:
        directory=Path(directory)
        source,binary=directory/'main.my',directory/'program'
        for label,text in [('roundtrip',original),('invalid-limit',original.replace(',4096)',',0)')),
                           ('byte-limit',original.replace(',4096)',',1)')),
                           ('domain-codecs',(ROOT/'src/native_fixtures/domain_json.my').read_text()),('document',document),
                           ('malformed','result Status{ok:bool,err:i64}'+original.replace('let bytes=try','let mut bytes=try').replace('    return json_decode','    acknowledge write_buffer<Status>(bytes,0,0u8); return json_decode'))]:
            source.write_text(text)
            built=run([sys.executable,ROOT/'scripts/qbe.py',source,'--compiler',args.compiler.resolve(),'--qbe',args.qbe,
                       '--zig',args.zig,'--cache-dir',directory/'cache','-o',binary])
            assert built.returncode==0,(label,built.stderr.decode())
            for budgets in [[], *[[f'--max-steps={n}'] for n in (20,50,100,200,500)], *[[f'--max-frames={n}'] for n in (1,2,3,4)]]:
                vm=run([args.compiler.resolve(),'run',source,*budgets]);native=run([binary,*budgets])
                assert signature(vm)==signature(native),(label,budgets,vm,native)
    print('Typed/domain/document JSON QBE/VM roundtrips, malformed input, limits and execution budgets passed')


if __name__=='__main__':
    main()
