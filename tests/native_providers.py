"""Compare explicit C providers and VM callbacks against shared value/call expectations."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from native_memory import memory

SOURCES = [
    "result T{ok:i64,err:i64}result R{err:i64,ok:u64}buffer B:i64;result A{ok:B,err:i64}struct Auth{c:clock_cap,r:random_cap}fn work(auth:Auth,heap:allocator)->T{arena heap as scratch{let b=try acquire_buffer<A>(scratch,2);let n=try clock_now<T>(auth.c);let word=try random_u64<R>(auth.r);discard b;if word!=18446744073709551615u64{return new T.err(90);}return new T.ok(n);}}fn main(r:random_cap,heap:allocator,c:clock_cap)->i64{match work(new Auth{c:c,r:r},heap){T.ok(n)=>{return n;},T.err(e)=>{return e;}}}",
    "result T{ok:i64,err:i64}fn main(c:clock_cap,r:random_cap)->i64{discard r;if false{acknowledge clock_now<T>(c);}return 7;}",
]

SOURCES.append(SOURCES[0].replace("fn work(", "fn work<G:copy>(").replace("match work(", "match work::<bool>(").replace("arena heap as scratch{", "{").replace("acquire_buffer<A>(scratch,", "acquire_buffer<A>(heap,"))

SOURCES.append(SOURCES[1].replace("fn main(", "fn skip<G:copy>(") + "fn main(c:clock_cap,r:random_cap)->i64{return skip::<bool>(c,r);}")


def cases():
    result = [(0, 0, 0, 0, -(1 << 63), None, 1, 1), (1, 0, 0, 0, 7, None, 0, 0)]
    for status in (1, 2, 3, 4):
        error = "OutOfMemory" if status == 4 else None
        result += [(0, status, 0, 0, status, error, 1, 0), (0, 0, status, 0, status, error, 1, 1)]
    for source in (0, 1):
        for missing in (1, 2, 3):
            result.append((source, 0, 0, missing, 0, "CapabilityUnavailable", 0, 0))
    result += [(2, *case[1:]) for case in result if case[0] == 0]
    result += [(3, *case[1:]) for case in result if case[0] == 1]
    return result


def invoke(argv, env=None):
    return subprocess.run([str(a) for a in argv], capture_output=True, timeout=180, env=env)


def vm_oracle(root, temp, zig):
    declarations = "\n".join(f"const source{i} = {json.dumps(source)};" for i, source in enumerate(SOURCES))
    calls = []
    for source, clock, random, missing, expected, error, cc, rc in cases():
        failure = "null" if error is None else f"error.{error}"
        calls.append(f"try scenario(source{source}, {clock}, {random}, {missing}, {expected}, {failure}, {cc}, {rc});")
    template = r'''
const std=@import("std");const language=@import("language");const t=std.testing;
const E=error{OutOfMemory,Unavailable,Denied,Failed};
const Fake=struct{clock_status:u8,random_status:u8,clocks:usize=0,randoms:usize=0,
fn fail(status:u8) E!void {return switch(status){0=>{},1=>error.Unavailable,2=>error.Denied,3=>error.Failed,else=>error.OutOfMemory};}
fn clock(context:*anyopaque) E!i64{const self:*Fake=@ptrCast(@alignCast(context));self.clocks+=1;try fail(self.clock_status);return std.math.minInt(i64);}
fn random(context:*anyopaque) E!u64{const self:*Fake=@ptrCast(@alignCast(context));self.randoms+=1;try fail(self.random_status);return std.math.maxInt(u64);}
};
fn scenario(source:[]const u8,cs:u8,rs:u8,missing:u8,expected:i64,failure:?anyerror,cc:usize,rc:usize)!void{
 var fake:Fake=.{.clock_status=cs,.random_status=rs};
 var c=try language.Compilation.init(t.allocator,"providers.my",source);defer c.deinit();
 var options:language.vm.Options=.{};
 if(missing&1==0)options.external.clock=.{.context=&fake,.read=Fake.clock};
 if(missing&2==0)options.external.random=.{.context=&fake,.read=Fake.random};
 if(failure)|err|{try t.expectError(err,c.executeWithOptions(t.allocator,options));}
 else{try t.expectEqual(expected,(try c.executeWithOptions(t.allocator,options)).value);}
 try t.expectEqual(cc,fake.clocks);try t.expectEqual(rc,fake.randoms);
}
'''
    oracle = temp / "oracle.zig"
    oracle.write_text(template + declarations + '\ntest "provider-oracle"{\n' + "\n".join(calls) + "\n}\n")
    result = invoke([zig, "test", "-OReleaseFast", "--test-filter", "provider-oracle", "--dep", "language", f"-Mroot={oracle}", f"-Mlanguage={root / 'src/compiler.zig'}"])
    assert result.returncode == 0, result.stderr.decode(errors="replace")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix="mylang-providers-") as directory:
        temp = Path(directory)
        vm_oracle(root, temp, args.zig)
        source, c_file, executable = temp / "source.my", temp / "program.c", temp / "program"
        comparisons = 0
        failures = 0
        for index, text in enumerate(SOURCES):
            source.write_text(text)
            emitted = invoke([compiler, "emit-c", source])
            assert emitted.returncode == 0, emitted.stderr
            c_file.write_bytes((root / "tests/native_memory.h").read_bytes() + b"\n" + emitted.stdout)
            for mode in ("-O0", "-O2"):
                built = invoke([args.zig, "cc", "-std=c11", mode, "-fsanitize=address,undefined", "-fno-sanitize-recover=undefined", "-DMYLANG_NATIVE_PROVIDER=1", "-I", root / "src", c_file, root / "tests/native_provider.c", "-o", executable])
                assert built.returncode == 0, built.stderr
                for case in cases():
                    selected, clock, random, missing, expected, error, cc, rc = case
                    if selected != index:
                        continue
                    env = os.environ.copy()
                    env.update(TEST_CLOCK_STATUS=str(clock), TEST_RANDOM_STATUS=str(random), TEST_MISSING=str(missing))
                    result = invoke([executable], env)
                    memory(result)
                    if error:
                        assert result.returncode == 2 and result.stdout == b"" and error.encode() in result.stderr, (case, result.stderr)
                    else:
                        assert result.returncode == 0 and result.stdout == f"{expected}\n".encode(), (case, result.stderr, result.stdout)
                    assert f"provider-calls: {cc} {rc}\n".encode() in result.stderr, (case, result.stderr)
                    comparisons += 1
                if index in (0, 2):
                    env = os.environ.copy()
                    env.update(TEST_CLOCK_STATUS="0", TEST_RANDOM_STATUS="0", TEST_MISSING="0")
                    env.pop("NATIVE_FAIL_ALLOCATION", None)
                    baseline = invoke([executable], env)
                    attempts, _ = memory(baseline)
                    for point in range(1, attempts + 1):
                        env["NATIVE_FAIL_ALLOCATION"] = str(point)
                        failed = invoke([executable], env)
                        memory(failed)
                        assert failed.returncode == 2 and b"OutOfMemory" in failed.stderr, (point, failed.stderr)
                        failures += 1
            absent = invoke([args.zig, "cc", "-std=c11", c_file, "-o", executable])
            assert absent.returncode == 0, absent.stderr
            denied = invoke([executable])
            assert denied.returncode == 2 and b"CapabilityUnavailable" in denied.stderr and denied.stdout == b"", denied
        source.write_text(SOURCES[1])
        built = invoke(["python3", root / "scripts/native.py", source, "--compiler", compiler, "--zig", args.zig, "--provider", root / "tests/native_provider.c", "-o", executable])
        assert built.returncode == 0, built.stderr
        result = invoke([executable])
        assert result.returncode == 0 and result.stdout == b"7\n" and b"provider-calls: 0 0" in result.stderr, result
        print(f"native providers: {comparisons} VM-checked value/error/call-count comparisons, {failures} injected allocation failures, missing grants and explicit builder adapter passed")


if __name__ == "__main__":
    main()
