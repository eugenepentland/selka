"""Normative ordinary JSON parser parity through the native support-object ABI."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def invoke(args):
    return subprocess.run([str(a) for a in args], capture_output=True, timeout=90)


def source(payload, limit=4096):
    values = ','.join(str(byte) + 'u8' for byte in payload)
    return ('buffer Bytes:u8;buffer Doc:i64;result Input{ok:Bytes,err:i64}result Parsed{ok:Doc,err:i64}'
            'result Status{ok:bool,err:i64}fn parse(heap:allocator)->Parsed{'
            f'let input=new [{len(payload)}]u8 [{values}];'
            'let mut bytes=try acquire_buffer<Input>(heap,len(input));'
            'borrow input[0..len(input)] as text{let mut i=0u64;while i<len_slice(text){'
            'discard try append_buffer<Status>(bytes,read_slice(text,i));i+=1u64;}}'
            f'return json_parse::<Parsed>(heap,bytes,{limit});' + '}'
            'fn main(heap:allocator)->i64{match parse(heap){Parsed.err(e)=>{return -e;},'
            'Parsed.ok(doc)=>{borrow doc[0..len_buffer(doc)] as view{return read_slice(view,6);}}}}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--zig', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    cases = [(b'{"answer":42}', 4096, 1), (b'[true,null,"x"]', 4096, 2),
             (b'"\\ud83d\\ude00"', 4096, 3), (b'-9223372036854775808', 4096, 4),
             (b'{"x":1,"\\u0078":2}', 4096, -1), (b'"\xc0\x80"', 4096, -1),
             (b'9223372036854775808', 4096, -1), (b'1e9999', 4096, -1),
             (b'[] trailing', 4096, -1), (b'"\\ud800"', 4096, -1),
             (b'[1,2,3]', 2, -2), (b'null', 0, -4)]
    with tempfile.TemporaryDirectory(prefix='native-json-', dir=root / '.zig-cache') as temporary:
        directory = Path(temporary)
        for index, (payload, limit, expected) in enumerate(cases):
            entry = directory / 'case.my'
            entry.write_text(source(payload, limit))
            vm = invoke([args.compiler.resolve(), 'run', entry])
            assert vm.returncode == 0 and vm.stdout == f'{expected}\n'.encode(), vm
            for mode in ['Debug', 'ReleaseFast']:
                executable = directory / 'native'
                built = invoke(['python3', root / 'scripts/native.py', entry, '--compiler', args.compiler.resolve(),
                    '--zig', args.zig, '--mode', mode, '-o', executable])
                assert built.returncode == 0, (index, built.stderr)
                native = invoke([executable])
                assert (native.returncode, native.stdout) == (vm.returncode, vm.stdout), (index, mode, native)
                for budget in [1, 40, 200]:
                    vm_limited = invoke([args.compiler.resolve(), 'run', entry, f'--max-steps={budget}'])
                    native_limited = invoke([executable, f'--max-steps={budget}'])
                    assert native_limited.returncode == vm_limited.returncode, (index, mode, budget, vm_limited, native_limited)
                    assert native_limited.stdout == vm_limited.stdout, (index, mode, budget)
        typed_checks(args, root, directory)
    print('native JSON: 24 value/error comparisons and 72 shared step-budget comparisons pass')


def typed_checks(args, root, directory):
    fixtures = [((root / 'src/native_fixtures/typed_json.my').read_text(), 42)]
    for payload, expected in [
        (b'{"version":"typed-json-v1","type":"i64","value":"42"}', 42),
        (b'{"version":"typed-json-v1","type":"u64","value":"42"}', -1),
        (b'{"version":"typed-json-v1","type":"i64","value":42}', -1),
        (b'{"version":"typed-json-v1","type":"i64","value":"9223372036854775808"}', -1),
        (b'{"version":"typed-json-v1","type":"i64","value":"1","extra":true}', -1),
    ]:
        program = source(payload).replace('result Parsed{ok:Doc,err:i64}', 'result Parsed{ok:i64,err:i64}')
        program = program.replace('json_parse::<Parsed>', 'json_decode::<Parsed>')
        program = program.replace('Parsed.ok(doc)=>{borrow doc[0..len_buffer(doc)] as view{return read_slice(view,6);}}',
                                  'Parsed.ok(value)=>{return value;}')
        fixtures.append((program, expected))
    for index, (program, expected) in enumerate(fixtures):
        entry = directory / 'typed.my'
        entry.write_text(program)
        vm = invoke([args.compiler.resolve(), 'run', entry])
        assert vm.returncode == 0 and vm.stdout == f'{expected}\n'.encode(), vm
        for mode in ['Debug', 'ReleaseFast']:
            executable = directory / 'typed-native'
            built = invoke(['python3', root / 'scripts/native.py', entry, '--compiler', args.compiler.resolve(),
                '--zig', args.zig, '--mode', mode, '-o', executable])
            assert built.returncode == 0, (index, built.stderr)
            native = invoke([executable])
            assert native.returncode == 0 and native.stdout == vm.stdout, (index, native)
            for budget in [100, 500, 1000, 5000]:
                vm_limited = invoke([args.compiler.resolve(), 'run', entry, f'--max-steps={budget}'])
                native_limited = invoke([executable, f'--max-steps={budget}'])
                assert (native_limited.returncode, native_limited.stdout) == (vm_limited.returncode, vm_limited.stdout), (index, mode, budget, native_limited, vm_limited)
    print('native typed JSON: 12 value/error and 48 step-budget comparisons across scalar and composite codecs pass')


if __name__ == '__main__':
    main()
