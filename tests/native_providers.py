"""Compare explicit C providers and VM callbacks against shared value/call expectations."""
import json
import os
from pathlib import Path
import re
import subprocess


SOURCES = [
    """result T:
    ok: i64,
    err: i64


result R:
    err: i64,
    ok: u64


class Auth:
    c: clock_cap
    r: random_cap


def work(auth: Auth) -> T:
    n = clock_now[T](auth.c)?
    word = random_u64[R](auth.r)?
    if word != 18446744073709551615u64:
        return Err(90)
    return Ok(n)


def main(r: random_cap, c: clock_cap) -> i64:
    match work(Auth(c=c, r=r)):
        case T.ok(n):
            return n
        case T.err(e):
            return e
""",
    """result T:
    ok: i64,
    err: i64


def main(c: clock_cap, r: random_cap) -> i64:
    _ = r
    if False:
        _ = clock_now[T](c)
    return 7
""",
]

SOURCES.append(SOURCES[0].replace("def work(", "def work[G](").replace("match work(", "match work[bool]("))

SOURCES.append(SOURCES[1].replace("def main(", "def skip[G](")
               + "\n\ndef main(c: clock_cap, r: random_cap) -> i64:\n    return skip[bool](c, r)\n")


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
