"""Native resource lifecycle acceptance with deterministic provider traces."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


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
    result = invoke([zig, "test", "-OReleaseFast", "--test-filter", "resource-oracle", "--dep", "language", f"-Mroot={path}", f"-Mlanguage={root / 'src/compiler.zig'}"], timeout=1800)
    assert result.returncode == 0, result.stderr
    traces = {index: [] for index in included}
    for index, event in re.findall(rb"resource-oracle: (\d+) ([^\n]+)", result.stderr):
        traces[int(index)].append(tuple(event.split()))
    return traces


def recorded(reference, root, directory, zig, cases):
    """Recorded interpreter release order for the cases that have one, keyed by name."""
    names = [case[0] for case in cases]

    def produce():
        traces = vm_oracle(root, directory, zig, cases)
        return {names[index]: [[part.decode() for part in event] for event in events]
                for index, events in traces.items()}

    data = reference.remember(['resource-release-order'], produce)
    return {name: [tuple(part.encode() for part in event) for event in events] for name, events in data.items()}


def io_cases(prefix, finish):
    finish = finish.replace("return e\n", "return -e\n")
    declarations = ("class Chunk:\n    eof: bool\n    bytes: [4]u8\n    length: u64\n\n\n"
                    "result Read:\n    err: i64,\n    ok: Chunk\n\n\n"
                    "result Written:\n    err: i64,\n    ok: u64\n\n\n")
    byte_score = " + i64(chunk.bytes[0]) + i64(chunk.bytes[1]) + i64(chunk.bytes[2]) + i64(chunk.bytes[3])"
    fixed = (prefix + declarations + "def work(fs: filesystem_cap) -> Run:\n"
             "    empty: [0]u8 = []\n"
             "    file = acquire_resource[A](fs, empty)?\n"
             "    chunk = read_resource[Read](file)?\n"
             "    n = write_resource[Written](file, chunk.bytes)?\n"
             "    score = i64(chunk.length) * 1000 + i64(n)" + byte_score + "\n"
             "    if chunk.eof:\n        score += 10000\n"
             "    return Ok(score)\n\n\n" + finish)
    result = []

    def add(name, source, settings, expected, error=None):
        result.append(("io-" + name, source, settings, 2 if error else 0, b"" if error else f"{expected}\n".encode(), error))
    add("fixed", fixed, {}, 12066)
    add("network", fixed.replace("filesystem", "network"), {}, 12066)
    add("empty-fixed", fixed.replace("bytes: [4]u8", "bytes: [0]u8").replace(byte_score, ""), {}, 10000)
    for mode in (1, 2, 3):
        add(f"fixed-read-{mode}", fixed, {"READ": mode}, -mode)
        add(f"write-{mode}", fixed, {"WRITE": mode}, -mode)
    add("fixed-read-oom", fixed, {"READ": 4}, 0, b"OutOfMemory")
    add("fixed-overread", fixed, {"READ": 5}, 0, b"InvalidProvider")
    add("fixed-bad-eof", fixed, {"READ": 7}, 0, b"InvalidProvider")
    add("fixed-eof", fixed, {"READ": 6}, 10001)
    add("fixed-full", fixed, {"READ": 8}, 14406)
    add("fixed-not-eof", fixed, {"READ": 9}, 2066)
    add("write-oom", fixed, {"WRITE": 4}, 0, b"OutOfMemory")
    add("overwrite", fixed, {"WRITE": 5}, 0, b"InvalidProvider")
    add("no-callbacks", fixed, {"IO_MISSING": 1}, -1)
    add("denied-before-missing", fixed, {"IO_MISSING": 1, "PERMISSIONS": 0}, -2)
    attenuated = fixed.replace("acquire_resource[A](fs,", "acquire_resource[A](restrict_resource[read, write, complete](restrict_resource[read](fs)),")
    add("source-attenuation", attenuated, {}, -2)
    return result
