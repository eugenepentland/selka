"""Native resource lifecycle acceptance with deterministic provider traces."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from native_memory import memory


def invoke(argv, settings=None, fail=None, timeout=90):
    env = os.environ.copy()
    for key in tuple(env):
        if key.startswith("TEST_RESOURCE_") or key == "NATIVE_FAIL_ALLOCATION":
            env.pop(key)
    env.update({"TEST_RESOURCE_" + key: str(value) for key, value in (settings or {}).items()})
    if fail is not None:
        env["NATIVE_FAIL_ALLOCATION"] = str(fail)
    return subprocess.run([str(x) for x in argv], capture_output=True, timeout=timeout, env=env)


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
        elif op in (b"D", b"W"):
            assert identity in live, trace
        elif op == b"R":
            assert identity in live, trace
            live.remove(identity)
    assert not live, trace


def vm_oracle(root, directory, zig, cases):
    template = r'''
const std=@import("std");const language=@import("language");const t=std.testing;
const E=error{OutOfMemory,Unavailable,Denied,Failed};
const Provider=@typeInfo(@FieldType(@FieldType(language.vm.Options,"resources"),"filesystem")).optional.child;
const ReadCallback=@typeInfo(@FieldType(Provider,"read")).optional.child;
const ReadResult=@typeInfo(@typeInfo(ReadCallback).pointer.child).@"fn".return_type.?;
const Event=struct{op:u8,kind:u8,handle:u64=0,permissions:u8=0,status:u8=0,length:usize=0,key:u64=0};
var events:[8192]Event=undefined;var count:usize=0;
fn record(event:Event)void{std.debug.assert(count<events.len);events[count]=event;count+=1;}
const Fake=struct{kind:u8,acquire_status:u8,complete_mode:u8,read_mode:u8,write_mode:u8,next:u64=0,live:usize=0,completions:usize=0,
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
fn read(context:*anyopaque,bytes_handle:u64,bytes:[]u8)ReadResult{
 const self:*Fake=@ptrCast(@alignCast(context));const mode=self.read_mode;const status:u8=if(mode<=4)mode else 0;
 @memset(bytes,170);var length:usize=@min(bytes.len,2);if(length!=0)bytes[0]=65;if(length>1)bytes[1]=0;
 if(mode==5)length=bytes.len+1;if(mode==6)length=0;if(mode==8)length=bytes.len;
 record(.{.op='D',.kind=self.kind,.handle=bytes_handle,.status=status,.length=bytes.len});
 try fail(status);return .{.length=length,.eof=mode!=9};
}
fn write(context:*anyopaque,handle:u64,bytes:[]const u8)E!usize{
 const self:*Fake=@ptrCast(@alignCast(context));const mode=self.write_mode;const status:u8=if(mode<=4)mode else 0;
 var key:u64=0;for(bytes)|byte|{key=key*%257+%byte;}
 record(.{.op='W',.kind=self.kind,.handle=handle,.status=status,.length=bytes.len,.key=key});
 try fail(status);return if(mode==5)bytes.len+1 else if(bytes.len!=0)1 else 0;
}
fn release(context:*anyopaque,handle:u64)void{const self:*Fake=@ptrCast(@alignCast(context));self.live-=1;record(.{.op='R',.kind=self.kind,.handle=handle});}
};
fn scenario(id:usize,source:[]const u8,acquire:u8,complete:u8,permissions:u8,missing:bool,read:u8,write:u8,io_missing:bool,expected:i64,failure:?anyerror,trap:?[]const u8)!void{
 count=0;var fakes=[_]Fake{.{.kind=0,.acquire_status=acquire,.complete_mode=complete,.read_mode=read,.write_mode=write},.{.kind=1,.acquire_status=acquire,.complete_mode=complete,.read_mode=read,.write_mode=write}};
 var c=try language.Compilation.init(t.allocator,"resources.my",source);defer c.deinit();
 var options:language.vm.Options=.{};options.resources.filesystem_permissions=permissions;options.resources.network_permissions=permissions;
 if(!missing){options.resources.filesystem=.{.context=&fakes[0],.acquire=Fake.acquire,.complete=Fake.complete,.release=Fake.release,.read=if(io_missing)null else Fake.read,.write=if(io_missing)null else Fake.write};options.resources.network=.{.context=&fakes[1],.acquire=Fake.acquire,.complete=Fake.complete,.release=Fake.release,.read=if(io_missing)null else Fake.read,.write=if(io_missing)null else Fake.write};}
 if(trap)|code|{try t.expectEqualStrings(code,(try c.executeWithOptions(t.allocator,options)).trap.code);}else if(failure)|err|{try t.expectError(err,c.executeWithOptions(t.allocator,options));}else{try t.expectEqual(expected,(try c.executeWithOptions(t.allocator,options)).value);}
 for(fakes)|fake|try t.expectEqual(@as(usize,0),fake.live);
 for(events[0..count])|event|std.debug.print("resource-oracle: {d} {c} {d} {d} {d} {d} {d} {d}\n",.{id,event.op,event.kind,event.handle,event.permissions,event.status,event.length,event.key});
}
'''
    calls = []
    included = set()
    for index, (name, source, settings, code, output, error) in enumerate(cases):
        if error == b"InvalidProvider" and settings.get("READ") != 5 and settings.get("WRITE") != 5:
            continue
        included.add(index)
        failure = "null" if error is None or code == 1 else "error." + error.decode()
        trap = json.dumps(error.decode()) if code == 1 else "null"
        calls.append(f"try scenario({index},{json.dumps(source)},{settings.get('ACQUIRE',0)},{settings.get('COMPLETE',0)},{settings.get('PERMISSIONS',7)},{str(bool(settings.get('MISSING',0))).lower()},{settings.get('READ',0)},{settings.get('WRITE',0)},{str(bool(settings.get('IO_MISSING',0))).lower()},{int(output) if output else 0},{failure},{trap});")
    path = directory / "oracle.zig"
    path.write_text(template + '\ntest "resource-oracle"{\n' + "\n".join(calls) + "\n}\n")
    result = invoke([zig, "test", "-OReleaseFast", "--test-filter", "resource-oracle", "--dep", "language", f"-Mroot={path}", f"-Mlanguage={root / 'src/compiler.zig'}"])
    assert result.returncode == 0, result.stderr
    traces = {index: [] for index in included}
    for index, event in re.findall(rb"resource-oracle: (\d+) ([^\n]+)", result.stderr):
        traces[int(index)].append(tuple(event.split()))
    return traces


def io_cases(prefix, finish):
    finish = finish.replace("return e;", "return -e;")
    declarations = "struct Chunk{eof:bool,bytes:[4]u8,length:u64}result Read{err:i64,ok:Chunk}result Written{err:i64,ok:u64}"
    byte_score = "+cast<i64>(chunk.bytes[0])+cast<i64>(chunk.bytes[1])+cast<i64>(chunk.bytes[2])+cast<i64>(chunk.bytes[3])"
    fixed = prefix + declarations + "fn work(fs:filesystem_cap)->Run{let mut file=try acquire_resource<A>(fs,new [0]u8[]);let chunk=try read_resource<Read>(file);let n=try write_resource<Written>(file,chunk.bytes);let mut score=cast<i64>(chunk.length)*1000+cast<i64>(n)" + byte_score + ";if chunk.eof{score+=10000;}return new Run.ok(score);}" + finish
    progress = "struct Progress{eof:bool,length:u64}result Read{err:i64,ok:Progress}result Written{err:i64,ok:u64}"
    array_init = "let mut bytes=new [4]u8[7u8,8u8,9u8,10u8];let saved=bytes;"
    snapshot_check = "if saved[1]!=8u8{return new Run.ok(-99);}"
    sliced = prefix + progress + "fn work(fs:filesystem_cap)->Run{let mut file=try acquire_resource<A>(fs,new [0]u8[]);" + array_init + "let mut n=0u64;let mut code=0;borrow mut bytes[1..3] as dest{match read_resource_slice<Read>(file,dest){Read.ok(p)=>{n=p.length;if !p.eof{return new Run.ok(-98);}},Read.err(e)=>{code=e;}}}let mut written=0u64;borrow bytes[0..4] as input{written=try write_resource_slice<Written>(file,input);}" + snapshot_check + "return new Run.ok(code*1000+cast<i64>(n)*10+cast<i64>(written));}" + finish
    buffer_init = "let mut bytes=try acquire_buffer<BA>(heap,4);discard try resize_buffer<BS>(bytes,4,9u8);"
    buffered = ("buffer B:u8;result BA{ok:B,err:i64}result BS{ok:bool,err:i64}" + sliced).replace(array_init, buffer_init).replace(snapshot_check, "").replace("fn work(fs:filesystem_cap)", "fn work(heap:allocator,fs:filesystem_cap)").replace("fn main(fs:filesystem_cap)", "fn main(fs:filesystem_cap,heap:allocator)").replace("match work(fs)", "match work(heap,fs)")
    result = []
    def add(name, source, settings, expected, error=None):
        result.append(("io-" + name, source, settings, 2 if error else 0, b"" if error else f"{expected}\n".encode(), error))
    add("fixed", fixed, {}, 12066)
    add("slice", sliced, {}, 21)
    add("buffer", buffered, {}, 21)
    add("network", fixed.replace("filesystem", "network"), {}, 12066)
    add("empty-fixed", fixed.replace("bytes:[4]u8", "bytes:[0]u8").replace(byte_score, ""), {}, 10000)
    add("empty-slice", sliced.replace("bytes[1..3] as dest", "bytes[1..1] as dest"), {}, 1)
    add("empty-buffer", buffered.replace("bytes[1..3] as dest", "bytes[1..1] as dest"), {}, 1)
    for mode in (1, 2, 3):
        add(f"fixed-read-{mode}", fixed, {"READ": mode}, -mode)
        add(f"slice-read-{mode}", sliced, {"READ": mode}, mode * 1000 + 1)
        add(f"buffer-read-{mode}", buffered, {"READ": mode}, mode * 1000 + 1)
        add(f"write-{mode}", sliced, {"WRITE": mode}, -mode)
    for source_name, source in (("fixed", fixed), ("slice", sliced), ("buffer", buffered)):
        add(source_name + "-read-oom", source, {"READ": 4}, 0, b"OutOfMemory")
        add(source_name + "-overread", source, {"READ": 5}, 0, b"InvalidProvider")
        add(source_name + "-bad-eof", source, {"READ": 7}, 0, b"InvalidProvider")
        add(source_name + "-eof", source, {"READ": 6}, 10001 if source_name == "fixed" else 1)
    add("fixed-full", fixed, {"READ": 8}, 14406)
    add("fixed-not-eof", fixed, {"READ": 9}, 2066)
    add("slice-not-eof", sliced, {"READ": 9}, -98)
    add("write-oom", sliced, {"WRITE": 4}, 0, b"OutOfMemory")
    add("overwrite", sliced, {"WRITE": 5}, 0, b"InvalidProvider")
    add("no-callbacks", sliced, {"IO_MISSING": 1}, -1)
    add("denied-before-missing", sliced, {"IO_MISSING": 1, "PERMISSIONS": 0}, -2)
    attenuated = fixed.replace("acquire_resource<A>(fs,", "acquire_resource<A>(restrict_resource<read,write,complete>(restrict_resource<read>(fs)),")
    add("source-attenuation", attenuated, {}, -2)
    return result


def generation_stress(root, directory, zig):
    for mode in ("-O0", "-O2"):
        executable = directory / "generations"
        built = invoke([zig, "cc", "-std=c11", mode, "-fsanitize=address,undefined",
                        "-fno-sanitize-recover=undefined", root / "tests/native_resource_generations.c",
                        "-o", executable], timeout=300)
        assert built.returncode == 0, built.stderr
        result = invoke([executable])
        assert result.returncode == 0, result.stderr
        memory(result)
        for kind in (0, 1):
            stale = invoke([executable, f"stale-{kind}"])
            assert stale.returncode == 2 and b"host failure: InvalidOwner" in stale.stderr, stale.stderr
            memory(stale)
    print("native resource generations: 6 sanitizer runs passed", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", required=True)
    parser.add_argument("--case", action="append", default=[], help="Run selected named cases")
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
    cases.extend(io_cases(prefix, finish))
    acquisitions = ",".join("try acquire_resource<A>(fs,new [0]u8[])" for _ in range(1024))
    quota = prefix + "resource Socket:network;result N{ok:Socket,err:i64}fn work(fs:filesystem_cap,net:network_cap)->Run{let held=new [1024]File[" + acquisitions + "];let other=try acquire_resource<N>(net,new [0]u8[]);let overflow=try acquire_resource<A>(fs,new [0]u8[]);discard overflow;discard other;discard held;return new Run.ok(0);}fn main(fs:filesystem_cap,net:network_cap)->i64{match work(fs,net){Run.ok(n)=>{return n;},Run.err(first)=>{match work(fs,net){Run.ok(n)=>{return n;},Run.err(second)=>{return first+second;}}}}}"
    network_quota = quota.replace("filesystem", "RESOURCE_KIND").replace("network", "filesystem").replace("RESOURCE_KIND", "network")
    mixed = prefix + "resource Socket:network;result N{ok:Socket,err:i64}struct Pair{left:File,right:Socket}fn work(fs:filesystem_cap,net:network_cap)->Run{let socket=try acquire_resource<N>(net,new [0]u8[]);let file=try acquire_resource<A>(fs,new [0]u8[]);let pair=new Pair{right:socket,left:file};discard pair;return new Run.ok(9);}fn main(fs:filesystem_cap,net:network_cap)->i64{match work(fs,net){Run.ok(n)=>{return n;},Run.err(e)=>{return e;}}}"
    cases.extend([("quota-reuse", quota, {}, 0, b"8\n", None), ("quota-network", network_quota, {}, 0, b"8\n", None), ("mixed", mixed, {}, 0, b"9\n", None)])
    generic = (root / "examples/generic-resources.my").read_text()
    generic_trap = generic.replace("return read_field(value, code);", "return 7 / (read_field(value, code) - 7);")
    assert generic_trap != generic
    cases.extend([
        ("generic-cleanup", generic, {}, 0, b"8\n", None),
        ("generic-network", generic.replace("filesystem", "network"), {}, 0, b"8\n", None),
        ("generic-denied", generic, {"ACQUIRE": 2}, 0, b"2\n", None),
        ("generic-trap", generic_trap, {}, 1, b"", b"R_DIVISION_BY_ZERO"),
    ])
    generic_retry = example.replace("fn retry(", "fn retry<G:copy>(").replace("match retry(", "match retry::<bool>(")
    generic_retry = generic_retry.replace("match acquire_resource<Open>(fs, new [1]u8 [42u8])", "match open::<bool>(fs)")
    generic_retry += "fn open<G:copy>(cap:filesystem_cap)->Open{return acquire_resource<Open>(restrict_resource<read,write,complete>(cap),new [1]u8[42u8]);}"
    cases.extend([
        ("generic-provider-retry", generic_retry, {"COMPLETE": 1}, 0, b"7\n", None),
        ("generic-provider-denied", generic_retry, {"COMPLETE": 2}, 0, b"2\n", None),
    ])
    for name, source, settings, code, output, error in io_cases(prefix, finish):
        if name in ("io-fixed", "io-network", "io-fixed-read-3", "io-fixed-write-3", "io-source-attenuation"):
            generic_io = source.replace("fn work(", "fn work<G:copy>(").replace("match work(", "match work::<bool>(")
            cases.append(("generic-" + name, generic_io, settings, code, output, error))
    generic_slices = (root / "examples/generic-provider-slices.my").read_text()
    cases.extend([
        ("generic-provider-slice", generic_slices, {}, 0, b"3\n", None),
        ("generic-provider-slice-denied", generic_slices, {"READ": 3}, 0, b"3\n", None),
    ])
    if args.case:
        selected = set(args.case)
        cases = [case for case in cases if case[0] in selected]
        if {case[0] for case in cases} != selected:
            parser.error("unknown resource case")
    comparisons = failures = 0
    with tempfile.TemporaryDirectory(prefix="mylang-native-resources-") as directory:
        directory = Path(directory)
        generation_stress(root, directory, args.zig)
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
                started = time.monotonic()
                built = invoke([args.zig, "cc", "-std=c11", mode, "-fsanitize=address,undefined",
                                "-fno-sanitize-recover=undefined", "-DMYLANG_NATIVE_PROVIDER=1",
                                "-I" + str(root / "src"), generated, root / "tests/native_resources.c", "-o", executable], timeout=300)
                assert built.returncode == 0, (name, built.stderr)
                if name in ("quota-reuse", "quota-network"):
                    print(f"native {name} C compilation {mode}: {time.monotonic() - started:.1f}s", flush=True)
                result = invoke([executable], settings)
                assert (result.returncode, result.stdout) == (code, output), (name, result.stderr)
                if error:
                    marker = b"error[" + error + b"]" if code == 1 else b"host failure: " + error
                    assert marker in result.stderr, result.stderr
                attempts, _ = memory(result)
                pending_points = [int(point) for point in re.findall(rb"resource-pending: (\d+)", result.stderr)]
                trace = events(result)
                balanced(trace)
                if name in ("quota-reuse", "quota-network"):
                    full_kind = b"0" if name == "quota-reuse" else b"1"
                    acquired = [event for event in trace if event[0] == b"A"]
                    assert len(acquired) == 2050, (name, len(acquired))
                    assert sum(event[1] == full_kind for event in acquired) == 2048, name
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
                if name == "io-fixed" and mode == "-O2":
                    user_built = directory / "user-built"
                    built = invoke([sys.executable, root / "scripts/native.py", path, "--provider",
                                    root / "tests/native_resources.c", "--mode", "ReleaseFast",
                                    "--compiler", compiler, "--zig", args.zig, "-o", user_built], timeout=240)
                    assert built.returncode == 0, built.stderr
                    executed = invoke([user_built], settings)
                    assert (executed.returncode, executed.stdout) == (code, output), executed.stderr
                    assert events(executed) == trace, executed.stderr
                comparisons += 1
                if name in ("normal", "retry", "denied", "reordered", "network", "io-fixed", "io-slice", "io-buffer", "io-empty-fixed", "io-empty-slice", "io-empty-buffer", "io-slice-read-3", "io-buffer-read-3", "mixed", "generic-cleanup", "generic-network", "generic-provider-retry", "generic-io-fixed", "generic-provider-slice"):
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
    print(f"native resources: {comparisons} outcomes, {2 * len(oracle)} VM trace comparisons, {failures} injected allocation failures")


if __name__ == "__main__":
    main()
