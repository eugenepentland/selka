"""Compare native library schema identities with independently checked public contracts."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import tempfile
from native_embedding import invoke

QUERY = r'''
import ctypes,json,sys
from concurrent.futures import ThreadPoolExecutor
library=ctypes.CDLL(sys.argv[1])
for name in ('mylang_native_schema_json_v1','mylang_native_schema_sha256_v1'):
    function=getattr(library,name);function.argtypes=[];function.restype=ctypes.c_char_p

def query(_):
    schema=library.mylang_native_schema_json_v1()
    digest=library.mylang_native_schema_sha256_v1()
    return [schema.decode() if schema else None,digest.decode() if digest else None]
with ThreadPoolExecutor(max_workers=4) as pool:
    values=list(pool.map(query,range(32)))
assert all(value==values[0] for value in values)
print(json.dumps(values[0]))
'''
BASE = '''module main;export Pair;export Color;export read;
struct Pair{x:i64,y:i64}enum Color{red,blue}
fn read(p:Pair)->i64{return p.x;}
fn main()->i64{return 1/0;}
'''


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compiler',required=True,type=Path)
    parser.add_argument('--zig',required=True)
    args=parser.parse_args()
    repository=Path(__file__).resolve().parents[1]
    cases=[
        ('base',BASE,False),
        ('body',BASE.replace('return p.x;','return p.x+1;'),False),
        ('private',BASE.replace('fn read','fn hidden()->i64{return 7;}fn read'),False),
        ('field-order',BASE.replace('x:i64,y:i64','y:i64,x:i64'),True),
        ('field-name',BASE.replace('x:i64','z:i64').replace('p.x','p.z'),True),
        ('width',BASE.replace('x:i64','x:i32').replace('return p.x;','return cast<i64>(p.x);'),True),
        ('case-order',BASE.replace('red,blue','blue,red'),True),
        ('export',BASE.replace('export read;','export read;export extra;')+'fn extra()->bool{return true;}',True),
        ('relocated',BASE,False),
    ]
    with tempfile.TemporaryDirectory(prefix='mylang-native-schema-') as directory:
        root=Path(directory)
        baseline=None
        for name,source,changed in cases:
            path=root/name;path.mkdir()
            entry=path/'main.my';entry.write_text(source)
            raw=invoke([args.compiler,'schema-project',entry]).stdout
            expected=json.dumps(json.loads(raw),ensure_ascii=False,separators=(',',':')).encode()
            expected_hash=hashlib.sha256(expected).hexdigest()
            modes=('Debug','ReleaseFast') if name=='base' else ('Debug',)
            for mode in modes:
                library=path/f'{mode}.so'
                invoke([sys.executable,repository/'scripts/native.py',entry,'--project','--library','--mode',mode,'--compiler',args.compiler,'--zig',args.zig,'-o',library])
                schema,digest=json.loads(invoke([sys.executable,'-c',QUERY,library]).stdout)
                assert schema.encode()==expected and digest==expected_hash, name
                assert hashlib.sha256(schema.encode()).hexdigest()==digest
                if baseline is None: baseline=digest
                assert (digest!=baseline)==changed, name
        entry=root/'scalar.my';entry.write_text('fn main()->i64{return 1/0;}')
        library=root/'scalar.so'
        invoke([sys.executable,repository/'scripts/native.py',entry,'--library','--compiler',args.compiler,'--zig',args.zig,'-o',library])
        assert json.loads(invoke([sys.executable,'-c',QUERY,library]).stdout)==[None,None]
    print('native schema: independent canonical hashes, field/type/case/export changes, body/private/relocation stability, both modes, concurrent queries and absent single-file schemas passed')


if __name__=='__main__':
    main()
