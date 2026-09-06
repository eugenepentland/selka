"""Native resource lifecycle acceptance with deterministic provider traces."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from native_memory import memory


def invoke(argv, settings=None, fail=None):
    env = os.environ.copy()
    for key in tuple(env):
        if key.startswith("TEST_RESOURCE_") or key == "NATIVE_FAIL_ALLOCATION":
            env.pop(key)
    env.update({"TEST_RESOURCE_" + key: str(value) for key, value in (settings or {}).items()})
    if fail is not None:
        env["NATIVE_FAIL_ALLOCATION"] = str(fail)
    return subprocess.run([str(x) for x in argv], capture_output=True, timeout=90, env=env)


def events(result):
    assert b"resource-live: 0 0" in result.stderr, result.stderr
    return [tuple(line.split()) for line in re.findall(rb"resource-event: ([^\n]+)", result.stderr)]


def balanced(trace):
    live = set()
    for op, kind, handle, permissions, status, length, key in trace:
        identity = kind, handle
        if op == b"A" and status == b"0":
            assert identity not in live, trace
            live.add(identity)
        elif op == b"C":
            assert identity in live, trace
            if status == b"0":
                live.remove(identity)
        elif op == b"R":
            assert identity in live, trace
            live.remove(identity)
    assert not live, trace


def vm_oracle(root, directory, zig, cases):
    template = r'''
const std=@import("std");const language=@import("language");const t=std.testing;
const E=error{OutOfMemory,Unavailable,Denied,Failed};
const Event=struct{op:u8,kind:u8,handle:u64=0,permissions:u8=0,status:u8=0,length:usize=0,key:u64=0};
var events:[256]Event=undefined;var count:usize=0;
fn record(event:Event)void{std.debug.assert(count<events.len);events[count]=event;count+=1;}
const Fake=struct{kind:u8,acquire_status:u8,complete_mode:u8,next:u64=0,live:usize=0,completions:usize=0,
fn fail(status:u8)E!void{return switch(status){0=>{},1=>error.Unavailable,2=>error.Denied,3=>error.Failed,else=>error.OutOfMemory};}
fn acquire(context:*anyopaque,bytes:[]const u8,permissions:u8)E!u64{
 const self:*Fake=@ptrCast(@alignCast(context));var key:u64=0;for(bytes)|byte|{key=key*%257+%byte;}
 var handle:u64=0;if(self.acquire_status==0){self.next+=1;handle=self.next;self.live+=1;}
 record(.{.op='A',.kind=self.kind,.handle=handle,.permissions=permissions,.status=self.acquire_status,.length=bytes.len,.key=key});
 try fail(self.acquire_status);return handle;
}
fn complete(context:*anyopaque,handle:u64)E!void{
 const self:*Fake=@ptrCast(@alignCast(context));self.completions+=1;
 const status:u8=if(self.complete_mode==1 and self.completions==1)3 else if(self.complete_mode==2)2 else if(self.complete_mode==3)4 else 0;
 record(.{.op='C',.kind=self.kind,.handle=handle,.status=status});try fail(status);self.live-=1;
}
fn release(context:*anyopaque,handle:u64)void{const self:*Fake=@ptrCast(@alignCast(context));self.live-=1;record(.{.op='R',.kind=self.kind,.handle=handle});}
};
fn scenario(id:usize,source:[]const u8,acquire:u8,complete:u8,permissions:u8,missing:bool,expected:i64,failure:?anyerror)!void{
 count=0;var fakes=[_]Fake{.{.kind=0,.acquire_status=acquire,.complete_mode=complete},.{.kind=1,.acquire_status=acquire,.complete_mode=complete}};
 var c=try language.Compilation.init(t.allocator,"resources.my",source);defer c.deinit();
 var options:language.vm.Options=.{};options.resources.filesystem_permissions=permissions;options.resources.network_permissions=permissions;
 if(!missing){options.resources.filesystem=.{.context=&fakes[0],.acquire=Fake.acquire,.complete=Fake.complete,.release=Fake.release};options.resources.network=.{.context=&fakes[1],.acquire=Fake.acquire,.complete=Fake.complete,.release=Fake.release};}
 if(failure)|err|{try t.expectError(err,c.executeWithOptions(t.allocator,options));}else{try t.expectEqual(expected,(try c.executeWithOptions(t.allocator,options)).value);}
 for(fakes)|fake|try t.expectEqual(@as(usize,0),fake.live);
 for(events[0..count])|event|std.debug.print("resource-oracle: {d} {c} {d} {d} {d} {d} {d} {d}\n",.{id,event.op,event.kind,event.handle,event.permissions,event.status,event.length,event.key});
}
'''
    calls = []
    included = set()
    for index, (name, source, settings, code, output, error) in enumerate(cases):
        if error == b"InvalidProvider":
            continue
        included.add(index)
        failure = "null" if error is None else "error." + error.decode()
        calls.append(f"try scenario({index},{json.dumps(source)},{settings.get('ACQUIRE',0)},{settings.get('COMPLETE',0)},{settings.get('PERMISSIONS',7)},{str(bool(settings.get('MISSING',0))).lower()},{int(output) if output else 0},{failure});")
    path = directory / "oracle.zig"
    path.write_text(template + '\ntest "resource-oracle"{\n' + "\n".join(calls) + "\n}\n")
    result = invoke([zig, "test", "-OReleaseFast", "--test-filter", "resource-oracle", "--dep", "language", f"-Mroot={path}", f"-Mlanguage={root / 'src/compiler.zig'}"])
    assert result.returncode == 0, result.stderr
    traces = {index: [] for index in included}
    for index, event in re.findall(rb"resource-oracle: (\d+) ([^\n]+)", result.stderr):
        traces[int(index)].append(tuple(event.split()))
    return traces


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    compiler = args.compiler.resolve()
    example = (root / "examples/resources.my").read_text()
    prefix = "resource File:filesystem;result A{ok:File,err:i64}result Run{ok:i64,err:i64}"
    finish = "fn main(fs:filesystem_cap)->i64{match work(fs){Run.ok(n)=>{return n;},Run.err(e)=>{return e;}}}"
    reordered = prefix + "struct Pair{first:File,second:File}fn work(fs:filesystem_cap)->Run{let first=try acquire_resource<A>(fs,new [3]u8[42u8,0u8,255u8]);let second=try acquire_resource<A>(fs,new [0]u8[]);let pair=new Pair{first:second,second:first};discard pair;return new Run.ok(9);}" + finish
    skipped = "fn main(fs:filesystem_cap)->i64{return 7;}"
    cases = [
        ("normal", example, {}, 0, b"7\n", None),
        ("retry", example, {"COMPLETE": 1}, 0, b"7\n", None),
        ("denied", example, {"COMPLETE": 2}, 0, b"2\n", None),
        ("complete-oom", example, {"COMPLETE": 3}, 2, b"", b"OutOfMemory"),
        ("complete-invalid", example, {"COMPLETE": 4}, 2, b"", b"InvalidProvider"),
        ("attenuated", example, {"PERMISSIONS": 0}, 0, b"2\n", None),
        ("invalid-permissions", example, {"PERMISSIONS": 8}, 2, b"", b"InvalidCapability"),
        ("missing", skipped, {"MISSING": 1}, 2, b"", b"CapabilityUnavailable"),
        ("skipped", skipped, {"ACQUIRE": 4}, 0, b"7\n", None),
        ("network", example.replace("filesystem", "network"), {}, 0, b"7\n", None),
        ("reordered", reordered, {}, 0, b"9\n", None),
    ]
    for status in (1, 2, 3, 4, 99):
        cases.append((f"acquire-{status}", example, {"ACQUIRE": status},
                      0 if status < 4 else 2, f"{status}\n".encode() if status < 4 else b"",
                      b"OutOfMemory" if status == 4 else b"InvalidProvider" if status == 99 else None))
    comparisons = failures = 0
    with tempfile.TemporaryDirectory(prefix="mylang-native-resources-") as directory:
        directory = Path(directory)
        oracle = vm_oracle(root, directory, args.zig, cases)
        for case_index, (name, source, settings, code, output, error) in enumerate(cases):
            path = directory / "case.my"
            path.write_text(source)
            emitted = invoke([compiler, "emit-c", path])
            assert emitted.returncode == 0, (name, emitted.stderr)
            generated = directory / "case.c"
            body = emitted.stdout
            marker = b"pending_resource_kind = kind + 1; pending_resource_index = index;"
            assert body.count(marker) == 1
            body = body.replace(marker, marker + b' fprintf(stderr, "resource-pending: %zu\\n", test_attempts + 1);')
            generated.write_bytes((root / "tests/native_memory.h").read_bytes() + b"\n" + body)
            for mode in ("-O0", "-O2"):
                executable = directory / "case"
                built = invoke([args.zig, "cc", "-std=c11", mode, "-fsanitize=address,undefined",
                                "-fno-sanitize-recover=undefined", "-DMYLANG_NATIVE_PROVIDER=1",
                                "-I" + str(root / "src"), generated, root / "tests/native_resources.c", "-o", executable])
                assert built.returncode == 0, (name, built.stderr)
                result = invoke([executable], settings)
                assert (result.returncode, result.stdout) == (code, output), (name, result.stderr)
                if error:
                    assert b"host failure: " + error in result.stderr, result.stderr
                attempts, _ = memory(result)
                pending_points = [int(point) for point in re.findall(rb"resource-pending: (\d+)", result.stderr)]
                trace = events(result)
                balanced(trace)
                if case_index in oracle:
                    assert trace == oracle[case_index], (name, trace, oracle[case_index])
                if name == "reordered":
                    assert [event[2] for event in trace if event[0] == b"R"] == [b"1", b"2"], trace
                    assert trace[0][5:] == (b"3", str(42 * 257 * 257 + 255).encode()), trace
                if name in ("invalid-permissions", "missing", "skipped"):
                    assert trace == [], trace
                if name == "attenuated":
                    assert [event[0] for event in trace] == [b"A", b"R"], trace
                    assert trace[0][3] == b"0", trace
                comparisons += 1
                if name in ("normal", "retry", "denied", "reordered", "network"):
                    for point in range(1, attempts + 1):
                        failed = invoke([executable], settings, point)
                        assert failed.returncode == 2 and b"host failure: OutOfMemory" in failed.stderr, (name, point, failed.stderr)
                        memory(failed)
                        failed_trace = events(failed)
                        balanced(failed_trace)
                        if name == "reordered":
                            released = [event[2] for event in failed_trace if event[0] == b"R"]
                            assert released in ([], [b"1"], [b"2", b"1"], [b"1", b"2"]), (point, failed_trace)
                            if point == pending_points[1]:
                                assert released == [b"2", b"1"], (point, failed_trace)
                        failures += 1
    print(f"native resource lifecycle: {comparisons} native status/ownership comparisons, {failures} injected allocation failures; VM baseline traces match for representable provider outcomes; byte I/O remains pending")


if __name__ == "__main__":
    main()
