"""Execute bounded environment-provider semantics with VM and native callbacks."""
import argparse
import json
import os
from pathlib import Path
import tempfile

from native_memory import memory
from native_providers import invoke

PREFIX = "struct E{present:bool,length:u64,bytes:[4]u8}result R{err:i64,ok:E}struct Auth{env:environment_cap}fn get(auth:Auth)->R{return environment_get<R>(auth.env,new [3]u8[75u8,0u8,255u8]);}"
SOURCES = [
    PREFIX + "fn main(env:environment_cap)->i64{match get(new Auth{env:env}){R.ok(e)=>{if !e.present{return -1;}return cast<i64>(e.length)*1000+cast<i64>(e.bytes[0])*100+cast<i64>(e.bytes[1])*10+cast<i64>(e.bytes[2])+cast<i64>(e.bytes[3])*1000000;},R.err(e)=>{return -10-e;}}}",
    PREFIX + "result W{ok:i64,err:i64}fn work(env:environment_cap)->W{let a=try get(new Auth{env:env});let b=try get(new Auth{env:env});return new W.ok(cast<i64>(a.bytes[0])*10+cast<i64>(b.bytes[0]));}fn main(env:environment_cap)->i64{match work(env){W.ok(n)=>{return n;},W.err(e)=>{return -10-e;}}}",
    PREFIX + "fn main(env:environment_cap)->i64{if false{acknowledge get(new Auth{env:env});}return 7;}",
    "struct E{bytes:[0]u8,present:bool,length:u64}result R{ok:E,err:i64}fn main(env:environment_cap)->i64{match environment_get<R>(env,new [0]u8[]){R.ok(e)=>{if e.present{return cast<i64>(e.length);}return -1;},R.err(e)=>{return -10-e;}}}",
]
CASES = [(0, mode, False, value, error, 1) for mode, value, error in (
    (0, 9755, None), (1, -1, None), (2, 0, None), (3, -14, None),
    (4, -12, None), (5, -13, None), (6, -11, None),
    (7, 0, "OutOfMemory"), (8, 0, "InvalidProvider"), (9, 2000, None),
)] + [(1, 10, False, 12, None, 2), (2, 0, False, 7, None, 0)] + [
    (3, 1, False, -1, None, 1), (3, 2, False, 0, None, 1), (3, 0, False, -14, None, 1),
] + [(index, 0, True, 0, "CapabilityUnavailable", 0) for index in range(4)]

SOURCES.append(SOURCES[0].replace("fn get(", "fn get<G:copy>(").replace("match get(", "match get::<bool>("))
CASES += [(4, *case[1:]) for case in CASES if case[0] == 0]


def settings(mode=0, missing=False, empty=False):
    env = os.environ.copy()
    env.pop("NATIVE_FAIL_ALLOCATION", None)
    env.update(TEST_ENV_MODE=str(mode), TEST_ENV_MISSING=str(int(missing)), TEST_EMPTY_NAME=str(int(empty)))
    return env


def vm_oracle(root, temp, zig):
    template = r'''
const std=@import("std");const language=@import("language");const t=std.testing;
const E=error{OutOfMemory,Unavailable,Denied,Failed,NoCapacity};
const Fake=struct{mode:u8,empty:bool,calls:usize=0,
fn get(context:*anyopaque,name:[]const u8,output:[]u8) E!?usize {
 const self:*Fake=@ptrCast(@alignCast(context));self.calls+=1;
 if(self.empty){if(name.len!=0)return error.Failed;}else if(!std.mem.eql(u8,name,&.{75,0,255}))return error.Failed;
 if(self.mode==9)return 2;
 @memset(output,170);
 switch(self.mode){
 1=>return null,2=>return 0,3=>return error.NoCapacity,4=>return error.Denied,
 5=>return error.Failed,6=>return error.Unavailable,7=>return error.OutOfMemory,
 8=>return output.len+1,
 10=>{if(output.len==0)return error.NoCapacity;output[0]=@intCast(self.calls);return 1;},
 else=>{if(output.len<3)return error.NoCapacity;output[0]=65;output[1]=0;output[2]=255;return 3;},
 }
}
};
fn scenario(source:[]const u8,mode:u8,missing:bool,empty:bool,expected:i64,failure:?anyerror,calls:usize)!void{
 var fake:Fake=.{.mode=mode,.empty=empty};var options:language.vm.Options=.{};
 if(!missing)options.environment=.{.context=&fake,.get=Fake.get};
 var c=try language.Compilation.init(t.allocator,"environment.my",source);defer c.deinit();
 if(failure)|err|{try t.expectError(err,c.executeWithOptions(t.allocator,options));}
 else{try t.expectEqual(expected,(try c.executeWithOptions(t.allocator,options)).value);}
 try t.expectEqual(calls,fake.calls);
}
'''
    definitions = "\n".join(f"const source{i}={json.dumps(source)};" for i, source in enumerate(SOURCES))
    calls = []
    for index, mode, missing, value, error, count in CASES:
        failure = "null" if error is None else f"error.{error}"
        calls.append(f"try scenario(source{index},{mode},{str(missing).lower()},{str(index == 3).lower()},{value},{failure},{count});")
    oracle = temp / "oracle.zig"
    oracle.write_text(template + definitions + '\ntest "environment-oracle"{\n' + "\n".join(calls) + "\n}\n")
    result = invoke([zig, "test", "-OReleaseFast", "--test-filter", "environment-oracle", "--dep", "language", f"-Mroot={oracle}", f"-Mlanguage={root / 'src/compiler.zig'}"])
    assert result.returncode == 0, result.stderr.decode(errors="replace")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix="mylang-native-environment-") as directory:
        temp = Path(directory)
        vm_oracle(root, temp, args.zig)
        source, c_file, executable = temp / "source.my", temp / "program.c", temp / "program"
        comparisons = failures = 0
        for index, text in enumerate(SOURCES):
            source.write_text(text)
            emitted = invoke([compiler, "emit-c", source])
            assert emitted.returncode == 0, emitted.stderr
            c_file.write_bytes((root / "tests/native_memory.h").read_bytes() + b"\n" + emitted.stdout)
            for optimize in ("-O0", "-O2"):
                built = invoke([args.zig, "cc", "-std=c11", optimize, "-fsanitize=address,undefined", "-fno-sanitize-recover=undefined", "-DMYLANG_NATIVE_PROVIDER=1", "-I", root / "src", c_file, root / "tests/native_environment.c", "-o", executable])
                assert built.returncode == 0, built.stderr
                for selected, mode, missing, expected, error, calls in CASES:
                    if selected != index:
                        continue
                    result = invoke([executable], settings(mode, missing, index == 3))
                    memory(result)
                    if error:
                        assert result.returncode == 2 and result.stdout == b"" and error.encode() in result.stderr, (index, mode, result.stderr)
                    else:
                        assert result.returncode == 0 and result.stdout == f"{expected}\n".encode(), (index, mode, result.stderr, result.stdout)
                    assert f"environment-calls: {calls}\n".encode() in result.stderr, (index, mode, result.stderr)
                    comparisons += 1
                if index in (0, 1, 4):
                    env = settings(10 if index == 1 else 0)
                    baseline = invoke([executable], env)
                    attempts, _ = memory(baseline)
                    for point in range(1, attempts + 1):
                        env["NATIVE_FAIL_ALLOCATION"] = str(point)
                        failed = invoke([executable], env)
                        memory(failed)
                        assert failed.returncode == 2 and b"OutOfMemory" in failed.stderr, (index, point, failed.stderr)
                        failures += 1
        source.write_text(SOURCES[0])
        built = invoke(["python3", root / "scripts/native.py", source, "--compiler", compiler, "--zig", args.zig, "--provider", root / "tests/native_environment.c", "-o", executable])
        assert built.returncode == 0, built.stderr
        result = invoke([executable], settings())
        assert result.returncode == 0 and result.stdout == b"9755\n", result
        built = invoke(["python3", root / "scripts/native.py", source, "--compiler", compiler, "--zig", args.zig, "-o", executable])
        assert built.returncode == 0, built.stderr
        denied = invoke([executable], settings())
        assert denied.returncode == 2 and b"CapabilityUnavailable" in denied.stderr, denied
        old_adapter = temp / "old-adapter.c"
        old_adapter.write_text('#include "native_providers.h"\nMylangNativeProviders mylang_native_providers_v1(void){return (MylangNativeProviders){0};}\n')
        incompatible = invoke(["python3", root / "scripts/native.py", source, "--compiler", compiler, "--zig", args.zig, "--provider", old_adapter, "-o", temp / "incompatible"])
        assert incompatible.returncode == 2 and b"mylang_native_providers_v4" in incompatible.stderr, incompatible.stderr
        print(f"native environment: {comparisons} VM-checked value/error/call comparisons, {failures} allocation failures, bounded bytes, snapshots, missing grants and builder/ABI rejection passed")


if __name__ == "__main__":
    main()
