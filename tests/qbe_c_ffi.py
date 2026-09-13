#!/usr/bin/env python3
"""Direct C ABI execution, linking, and external-test invalidation acceptance."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

C_SOURCE = r'''
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <math.h>
int8_t c_i8(int8_t x) { assert(x == -128); return -127; }
uint8_t c_u8(uint8_t x) { assert(x == 255); return 254; }
int16_t c_i16(int16_t x) { assert(x == -32768); return -32767; }
uint16_t c_u16(uint16_t x) { assert(x == 65535); return 65534; }
int32_t c_i32(int32_t x) { assert(x == INT32_MIN); return -2147483647; }
uint32_t c_u32(uint32_t x) { assert(x == UINT32_MAX); return UINT32_MAX-1; }
int64_t c_i64(int64_t x) { assert(x == INT64_MIN); return INT64_MIN+1; }
uint64_t c_u64(uint64_t x) { assert(x == UINT64_MAX); return UINT64_MAX-1; }
bool c_bool(bool x) { assert(x); return false; }
double c_mix(int32_t a, double b, uint64_t c, double d) {
    assert(a == -7 && b == 1.5 && c == UINT64_MAX && d == -0.0 && signbit(d));
    return 3.25;
}
double c_stack(double a,double b,double c,double d,double e,double f,double g,double h,double i,
               int64_t j,int64_t k,int64_t l,int64_t m,int64_t n,int64_t o,int64_t p) {
    return a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p;
}
static int counter;
void c_void(void) { counter++; }
int32_t c_counter(void) { return counter; }
double c_nan(void) { return NAN; }
int32_t c_version(void) { return 42; }
'''

def guest():
    declarations = []
    checks = []
    for signed in (True, False):
        for bits in (8, 16, 32, 64):
            ty = ('i' if signed else 'u') + str(bits)
            value = -(2 ** (bits - 1)) if signed else 2 ** bits - 1
            result = value + 1 if signed else value - 1
            declarations.append(f'extern fn c_{ty}(x:{ty})->{ty} effects(host);')
            checks.append(f'let expected_{ty}:{ty}={result};if c_{ty}({value}) != expected_{ty} {{return 1;}}')
    declarations += [
        'extern fn c_bool(x:bool)->bool effects(host);',
        'extern fn c_mix(a:i32,b:float,c:u64,d:float)->float effects(host);',
        'extern fn c_stack(a:float,b:float,c:float,d:float,e:float,f:float,g:float,h:float,i:float,j:i64,k:i64,l:i64,m:i64,n:i64,o:i64,p:i64)->float effects(host);',
        'extern fn c_void()->unit effects(host);',
        'extern fn c_counter()->i32 effects(host);',
        'extern fn c_nan()->float effects(host);',
        'extern fn abs(x:i32)->i32 effects(host);',
        'extern fn floor(x:float)->float effects(host);',
    ]
    checks += [
        'if c_bool(true) {return 2;}',
        'if c_mix(-7,1.5,18446744073709551615,-0.0) != 3.25 {return 3;}',
        'if c_stack(1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10,11,12,13,14,15,16) != 136.0 {return 4;}',
        'c_void(); if cast<i64>(c_counter()) != 1 {return 5;}',
        'let nan=c_nan(); if nan == nan {return 6;}',
        'if cast<i64>(abs(-7)) != 7 {return 7;}',
        'if floor(3.9) != 3.0 {return 8;}',
        'let indirect=abs; if cast<i64>(indirect(cast<i32>(-9))) != 9 {return 9;}',
    ]
    return '\n'.join(declarations) + '\nfn main()->i64{' + ''.join(checks) + 'return 42;}'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    compiler = str(Path(args.compiler).resolve())
    zig = str(Path(shutil.which(args.zig) or args.zig).resolve())
    qbe = str(Path(shutil.which(args.qbe) or args.qbe).resolve())
    with tempfile.TemporaryDirectory(prefix='mylang-c-ffi-') as tmp:
        root = Path(tmp)
        env = dict(os.environ, PATH='')
        def run(command, ok=True):
            result = subprocess.run(list(map(str, command)), cwd=root, env=env,
                                    capture_output=True, timeout=240)
            assert (result.returncode == 0) == ok, (command, result.returncode, result.stdout, result.stderr)
            return result
        tools = ['--zig', zig, '--qbe', qbe, '--cache-dir', root / 'cache']
        source = root / 'main.my'
        foreign = root / 'foreign code.c'
        source.write_text(guest())
        foreign.write_text(C_SOURCE)
        for mode in ('Debug', 'ReleaseFast'):
            result = run([compiler, 'build', source, '--run', '--link', foreign, '--mode', mode, *tools])
            assert result.stdout == b'42\n', result
        # Explicit object and archive inputs, including library search/name controls.
        obj = root / 'foreign.o'
        run([zig, 'cc', '-fPIC', '-c', foreign, '-o', obj])
        result = run([compiler, 'build', source, '--run', '--link', obj, *tools])
        assert result.stdout == b'42\n'
        shared = root / 'libforeign.so'
        run([zig, 'cc', '-shared', '-fPIC', foreign, '-o', shared])
        result = run([compiler, 'build', source, '--run', '--link', shared, *tools])
        assert result.stdout == b'42\n'
        archive = root / 'libforeign.a'
        run([zig, 'ar', 'rcs', archive, obj])
        result = run([compiler, 'build', source, '--run', '--library-path', root, '--link-library=foreign', *tools])
        assert result.stdout == b'42\n'
        run([compiler, 'build', source, '--run', *tools], ok=False)
        # Module qualification must not change the linked C symbol.
        (root / 'foreign.my').write_text('module foreign;export c_version;extern fn c_version()->i32 effects(host);')
        source.write_text('module main;import foreign;fn main()->i64{return cast<i64>(foreign::c_version());}')
        assert run([compiler, 'build', source, '--project', '--run', '--link', foreign, *tools]).stdout == b'42\n'
        # No test receipt may suppress another external call, even if IL is unchanged.
        source.write_text('module main;import foreign;export test_external;export test_pure;'
                          'fn test_external()->bool{return cast<i64>(foreign::c_version())==42;}'
                          'fn test_pure()->bool{return true;}fn main()->i64{return 0;}')
        command = [compiler, 'test', source, '--json', '--link', foreign, *tools]
        cold = json.loads(run(command).stdout)
        warm = json.loads(run(command).stdout)
        assert cold['executed'] == 2 and warm['executed'] == 1 and warm['cached'] == 1, (cold, warm)
        foreign.write_text(C_SOURCE.replace('return 42;', 'return 43;'))
        changed = json.loads(run(command, ok=False).stdout)
        assert changed['failed'] == 1 and changed['cached'] == 1, changed
        # Separate modules cannot assign conflicting C prototypes to one symbol.
        (root / 'other.my').write_text('module other;export c_version;extern fn c_version()->i64 effects(host);')
        source.write_text('module main;import foreign;import other;fn main()->i64{return 0;}')
        conflict = run([compiler, 'check-project', source], ok=False)
        assert b'E_EXTERN_CONFLICT' in conflict.stderr, conflict.stderr
    print('C FFI: scalar ABI, register/stack passing, libc, objects/archives, modules, and affected tests passed')

if __name__ == '__main__':
    main()
