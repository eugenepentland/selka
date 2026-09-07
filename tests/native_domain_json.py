"""Domain codec failure recovery and remaining-budget parity in compiled JSON."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def invoke(command):
    return subprocess.run([str(value) for value in command], capture_output=True, timeout=90)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--zig', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = (root / 'src/native_fixtures/domain_json.my').read_text()
    quota = source[:source.index('fn main(')] + 'fn main(heap:allocator)->i64{let values=new [257]Positive ['
    quota += ','.join('Positive.make(42)' for _ in range(257))
    quota += '];match json_encode::<Encoded>(heap,values,1048576){Encoded.err(e)=>{return e;},Encoded.ok(discard)=>{return -1;}}}'
    recursive = source.replace('return new Wire{n:n};', 'return Positive.descend(n);')
    recursive = recursive.replace('    fn value(', '    fn descend(n:i64)->Wire{if n<=0{return new Wire{n:42};}return Positive.descend(n-1);}\n    fn value(')
    recursive = recursive[:recursive.index('fn main(')] + 'fn main(heap:allocator)->i64{return checked(heap,32);}'
    cases = [(source, 42), (quota, 2), (recursive, 42)]
    comparisons = 0
    with tempfile.TemporaryDirectory(prefix='native-domain-json-', dir=root / '.zig-cache') as temporary:
        directory = Path(temporary)
        for index, (program, expected) in enumerate(cases):
            entry = directory / 'case.my'
            entry.write_text(program)
            vm_command = [args.compiler.resolve(), 'run', entry]
            vm = invoke(vm_command)
            assert vm.returncode == 0 and vm.stdout == f'{expected}\n'.encode(), vm
            limits = [f'--max-steps={n}' for n in [1, 80, 100, 200, 300, 500, 1000, 2000, 5000, 10000]]
            limits += [f'--max-frames={n}' for n in [1, 2, 3, 4, 5, 8, 16, 32, 64]]
            expected_limits = [invoke(vm_command + [limit]) for limit in limits]
            for mode in ['Debug', 'ReleaseFast']:
                executable = directory / 'native'
                built = invoke(['python3', root / 'scripts/native.py', entry, '--compiler', args.compiler.resolve(),
                                '--zig', args.zig, '--mode', mode, '-o', executable])
                assert built.returncode == 0, built.stderr
                native = invoke([executable])
                assert (native.returncode, native.stdout) == (vm.returncode, vm.stdout), (index, mode, native)
                for limit, reference in zip(limits, expected_limits):
                    native = invoke([executable, limit])
                    assert (native.returncode, native.stdout) == (reference.returncode, reference.stdout), (index, mode, limit, reference, native)
                    for code in [b'R_STEP_LIMIT', b'R_FRAME_LIMIT']:
                        assert (code in native.stderr) == (code in reference.stderr), (index, mode, limit, reference, native)
                    comparisons += 1
        allocation_checks(args, root, directory, source)
    print(f'native domain JSON: 6 recovery/quota results and {comparisons} step/frame comparisons pass')


def allocation_checks(args, root, directory, source):
    from native_embedding import TRACKER
    entry = directory / 'cleanup.my'
    entry.write_text(source)
    emitted = invoke([args.compiler.resolve(), 'emit-c', entry])
    assert emitted.returncode == 0, emitted.stderr
    (directory / 'generated.c').write_bytes(emitted.stdout)
    harness = directory / 'harness.c'
    harness.write_text(TRACKER + r"""
int main(void) {
    MylangRunResult result;
    attempts=0;
    assert(mylang_native_run_v1(NULL,&result)==0 && result.value==42 && live==0);
    size_t count=attempts;
    for(size_t i=0;i<count;++i) {
        fail_at=i;attempts=0;
        int status=mylang_native_run_v1(NULL,&result);
        assert(live==0);
        /* A failed realloc may legally fall back to a fresh allocation. */
        assert((status==0 && result.value==42) || (status==2 && !strcmp(result.code,"OutOfMemory")));
        fail_at=(size_t)-1;
        assert(mylang_native_run_v1(NULL,&result)==0 && result.value==42 && live==0);
    }
    printf("native domain JSON: %zu allocation injection positions cleaned and recovered\n",count);
    return 0;
}
""")
    for mode, optimize in [('Debug', '-O0'), ('ReleaseFast', '-O2')]:
        support = directory / 'support.o'
        built = invoke([args.zig, 'build-obj', root / 'src/native_json_bridge.zig', '-lc', '-fPIC',
                        '-O', mode, '-femit-bin=' + str(support)])
        assert built.returncode == 0, built.stderr
        executable = directory / 'cleanup'
        built = invoke([args.zig, 'cc', '-std=c11', optimize, '-fsanitize=address,undefined',
                        '-fno-sanitize-recover=undefined', harness, support, '-o', executable])
        assert built.returncode == 0, built.stderr
        checked = invoke([executable])
        assert checked.returncode == 0, checked.stderr
        print(checked.stdout.decode().strip())


if __name__ == '__main__':
    main()
