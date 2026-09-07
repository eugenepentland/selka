//! Native emission, representation boundaries, and compiler allocation-failure cleanup.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "native.my", "fn twice(x: i64) -> i64 { return x * 2; } fn main() -> i64 { return 1 + twice(3); }");
    defer c.deinit();
    const first = try c.emitC(allocator);
    defer allocator.free(first);
    const second = try c.emitC(allocator);
    defer allocator.free(second);
    try t.expectEqualStrings(first, second);
    try t.expect(std.mem.indexOf(u8, first, "goto L") != null);
    try t.expect(std.mem.indexOf(u8, first, "__builtin_mul_overflow") != null);
}
// spec: PROJ-5
// spec: NATIVE-EMBED-1
test "native scalar emission is deterministic and cleans every failed allocation" {
    try scenario(t.allocator);
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
// spec: PROJ-6
test "native emission validates uncalled functions" {
    for ([_][]const u8{
        "fn unused()->i64{return false;}fn main()->i64{return 7;}",
    }) |text| {
        var c = try language.Compilation.init(t.allocator, "native.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.emitC(t.allocator));
        try t.expectEqualStrings("E_TYPE", c.diagnostics.items[c.diagnostics.items.len - 1].code);
    }
}

fn domainScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "domain.my", "domain D:i64 { fn make(x:i64)->D{return wrap<D>(x);} fn value(x:D)->i64{return " ++
        "unwrap(x);} } fn forward(x:D)->D{return x;} fn main()->i64{return " ++
        "D.value(forward(D.make(37)));}");
    defer c.deinit();
    const generated = try c.emitC(allocator);
    defer allocator.free(generated);
    try t.expectEqual(@as(i64, 37), (try c.execute(allocator)).value);
}
test "native nominal scalar domains preserve checked construction and allocation failure cleanup" {
    try domainScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), domainScenario, .{});
}
test "native domain representation elision does not bypass nominal or private checks" {
    for ([_][]const u8{
        "domain D:i64 {} fn main()->i64{discard wrap<D>(1);return 0;}",
        "domain D:i64 { private fn raw(x:i64)->D{return wrap<D>(x);} } fn main()->i64{discard D.raw(1);return 0;}",
        "domain A:i64 {fn make(x:i64)->A{return wrap<A>(x);}} domain B:i64 {} fn take(x:B)->i64{return 0;} fn main()->i64{return take(A.make(1));}",
    }) |text| {
        var c = try language.Compilation.init(t.allocator, "invalid.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.emitC(t.allocator));
        try t.expect(!std.mem.eql(u8, c.diagnostics.items[0].code, "E_NATIVE_FEATURE"));
    }
}

fn enumScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "enum.my", "enum Color{red,green,blue} fn score(x:Color)->i64{match x{Color.blue=>{return 3;}," ++
        "Color.red=>{return 1;},Color.green=>{return 2;}}} fn main()->i64{return score(new " ++
        "Color.red)*100+score(new Color.green)*10+score(new Color.blue);}");
    defer c.deinit();
    const generated = try c.emitC(allocator);
    defer allocator.free(generated);
    try t.expect(std.mem.indexOf(u8, generated, "switch (") != null);
    try t.expectEqual(@as(i64, 123), (try c.execute(allocator)).value);
}
test "native closed enum dispatch and VM tag identity survive allocation failures" {
    try enumScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), enumScenario, .{});
}
test "native enum support retains exhaustive nominal checks and rejects unsupported payloads" {
    for ([_][]const u8{
        "enum E{a,b} fn main()->i64{match new E.a { E.a=>{return 1;} }}",
        "enum A{x} enum B{x} fn main()->i64{if new A.x==new B.x{return 1;}return 0;}",
    }) |text| {
        var c = try language.Compilation.init(t.allocator, "invalid.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.emitC(t.allocator));
        try t.expect(!std.mem.eql(u8, c.diagnostics.items[0].code, "E_NATIVE_FEATURE"));
    }
}
test "native backend supports owned resource payloads" {
    for ([_][]const u8{
        "resource B:filesystem; union U{value:B} fn unsupported(x:U)->i64{discard x;return 0;} fn main()->i64{return 0;}",
        "resource B:filesystem; struct R{value:B} fn unsupported(x:R)->i64{discard x;return 0;} fn main()->i64{return 0;}",
    }) |text| {
        var c = try language.Compilation.init(t.allocator, "unsupported.my", text);
        defer c.deinit();
        const generated = try c.emitC(t.allocator);
        defer t.allocator.free(generated);
    }
}

fn variantScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "variant.my", "union E{missing,code:i8} result R{err:E,ok:i64} result S{ok:bool,err:E} fn " ++
        "convert(r:R)->S{return new S.ok(try r>0);} fn main()->i64{let a=new R.ok(1);" ++
        "acknowledge a;match convert(new R.err(new E.code(-128i8))){S.ok(discard)=>{return 0;}" ++
        ",S.err(e)=>{match e{E.missing=>{return 1;},E.code(n)=>{return cast<i64>(n);}}}}}");
    defer c.deinit();
    const generated = try c.emitC(allocator);
    defer allocator.free(generated);
    try t.expectEqual(@as(i64, -128), (try c.execute(allocator)).value);
}
test "native nested variants and result propagation clean every allocation failure" {
    try variantScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), variantScenario, .{});
}
test "native packed variants retain result handling obligations" {
    for ([_][]const u8{
        "result R{ok:i64,err:i64} fn main()->i64{let r=new R.ok(1);return 0;}",
        "result R{ok:i64,err:i64} fn main()->i64{let a=new R.ok(1);let b=a;acknowledge a;acknowledge b;return 0;}",
        "union U{a:i64,b:bool} fn main()->i64{match new U.a(1){U.a(n)=>{return n;}}}",
    }) |source| {
        var c = try language.Compilation.init(t.allocator, "invalid.my", source);
        defer c.deinit();
        try t.expectError(error.SourceError, c.emitC(t.allocator));
        try t.expect(!std.mem.eql(u8, c.diagnostics.items[0].code, "E_NATIVE_FEATURE"));
    }
}

test "native layout boxes values beyond the 127 bit slot" {
    var source: std.Io.Writer.Allocating = .init(t.allocator);
    defer source.deinit();
    try source.writer.writeAll("union U0{value:u64} ");
    for (1..64) |i| try source.writer.print("union U{d}{{value:U{d}}} ", .{ i, i - 1 });
    try source.writer.writeAll("fn unused(x:U63)->i64{discard x;return 0;} fn main()->i64{return 7;}");
    var c = try language.Compilation.init(t.allocator, "too-wide.my", source.written());
    defer c.deinit();
    const generated = try c.emitC(t.allocator);
    defer t.allocator.free(generated);
    try t.expectEqual(@as(i64, 7), (try c.execute(t.allocator)).value);
}

fn aggregateScenario(allocator: std.mem.Allocator) !void {
    const source = "struct R{a:[2]i64,b:i64} result Outcome{ok:R,err:R} fn " ++
        "work(x:Outcome)->Outcome{return new Outcome.ok(try x);} fn main()->i64{let old=new " ++
        "R{b:3,a:new [2]i64[4,5]};let changed=update(old){a:replace(old.a,0,9)};match " ++
        "work(new Outcome.err(changed)){Outcome.ok(discard)=>{return 0;}," ++
        "Outcome.err(r)=>{return r.a[0]+old.a[0];}}}";
    var c = try language.Compilation.init(allocator, "aggregate.my", source);
    defer c.deinit();
    const generated = try c.emitC(allocator);
    defer allocator.free(generated);
    try t.expectEqual(@as(i64, 13), (try c.execute(allocator)).value);
}
test "native aggregates and boxed result propagation clean every allocation failure" {
    try aggregateScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), aggregateScenario, .{});
}

fn referenceScenario(allocator: std.mem.Allocator) !void {
    const source = "fn middle(a:i64,x:&mut []i64,b:i64)->&mut []i64 from x{borrow mut x[a..b] as " ++
        "selected{return selected;}} fn main()->i64{let mut a=new [3]i64[2,3,5];let old=a;" ++
        "borrow mut a[0..3] as all{borrow mut middle(1,all,3) as " ++
        "selected{write_slice(selected,0,9);}}return old[1]+a[1];}";
    var c = try language.Compilation.init(allocator, "reference.my", source);
    defer c.deinit();
    const generated = try c.emitC(allocator);
    defer allocator.free(generated);
    try t.expectEqual(@as(i64, 12), (try c.execute(allocator)).value);
}
test "native reference arguments returned slices and snapshots clean every compiler allocation failure" {
    try referenceScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), referenceScenario, .{});
}
// spec: PROJ-7
test "native reference support retains static lifetime and exclusivity checks" {
    for ([_][]const u8{
        "fn main()->i64{let mut x=1;borrow mut x as r{return x;}}",
        "fn main()->i64{let x=1;borrow x as r{write_ref(r,2);}return x;}",
        "fn bad(x:&i64)->&i64 from x{let local=1;borrow local as r{return r;}} fn main()->i64{return 0;}",
    }) |source| {
        var c = try language.Compilation.init(t.allocator, "invalid.my", source);
        defer c.deinit();
        try t.expectError(error.SourceError, c.emitC(t.allocator));
        try t.expect(!std.mem.eql(u8, c.diagnostics.items[c.diagnostics.items.len - 1].code, "E_NATIVE_FEATURE"));
    }
}

fn bufferScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "buffers.my", "buffer B:i64;result A{ok:B,err:i64}result S{ok:bool,err:i64}" ++
        "fn main(heap:allocator)->i64{match acquire_buffer<A>(heap,2){A.ok(acquired)=>{let mut b=acquired;" ++
        "acknowledge append_buffer<S>(b,7);return read_buffer(b,0);},A.err(e)=>{return e;}}}");
    defer compilation.deinit();
    const output = try compilation.emitC(allocator);
    defer allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "push_value(acquire_buffer(") != null);
    try t.expect(std.mem.indexOf(u8, output, "int status = buffer_append(") != null);
}
// spec: NATIVE-BUFFER-1
test "native buffer emission supports allocator entry and owned results with allocation cleanup" {
    try bufferScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), bufferScenario, .{});
}

fn arenaScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "arenas.my", "result S{ok:bool,err:i64} fn main(heap:allocator)->i64{arena heap as scratch{acknowledge reset_arena<S>(scratch);}return 7;}");
    defer compilation.deinit();
    const output = try compilation.emitC(allocator);
    defer allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "begin_region(1);") != null);
    try t.expect(std.mem.indexOf(u8, output, "int status = reset_arena();") != null);
}
// spec: NATIVE-ARENA-1
test "native arena emission supports lexical scopes and reset with allocation cleanup" {
    try arenaScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), arenaScenario, .{});
}

fn poolScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "pools.my", "pool P(Id):i64;result A{ok:P,err:i64}result I{ok:Id,err:i64}" ++
        "fn main(heap:allocator)->i64{match acquire_pool<A>(heap,2){A.ok(acquired)=>{let mut p=acquired;" ++
        "acknowledge insert_pool<I>(p,7);return cast<i64>(len_pool(p));},A.err(e)=>{return e;}}}");
    defer compilation.deinit();
    const output = try compilation.emitC(allocator);
    defer allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "push_value(acquire_pool(") != null);
    try t.expect(std.mem.indexOf(u8, output, "int status = pool_insert(") != null);
}
// spec: NATIVE-POOL-1
test "native pool emission supports owned registries and handles with allocation cleanup" {
    try poolScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), poolScenario, .{});
}

fn providerScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "providers.my", "result T{ok:i64,err:i64}fn main(c:clock_cap)->i64{match clock_now<T>(c){T.ok(n)=>{return n;},T.err(e)=>{return e;}}}");
    defer c.deinit();
    const output = try c.emitC(allocator);
    defer allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "grant_external(0);") != null);
    try t.expect(std.mem.indexOf(u8, output, "int status = external_read(0,") != null);
}
// spec: NATIVE-PROVIDER-1
test "native clock emission preserves explicit grants and allocation cleanup" {
    try providerScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), providerScenario, .{});
}

fn environmentScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "environment.my", "struct E{present:bool,length:u64,bytes:[4]u8}result R{err:i64,ok:E}" ++
        "fn main(env:environment_cap)->i64{match environment_get<R>(env,new [1]u8[75u8]){R.ok(e)=>{return cast<i64>(e.length);},R.err(e)=>{return e;}}}");
    defer c.deinit();
    const output = try c.emitC(allocator);
    defer allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "grant_external(2);") != null);
    try t.expect(std.mem.indexOf(u8, output, "push_value(environment_lookup(4, 1, 0, 2, 1, 0))") != null);
}
// spec: NATIVE-ENVIRONMENT-1
test "native environment emission preserves named fields and allocation cleanup" {
    try environmentScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), environmentScenario, .{});
}

fn resourceScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "resources.my", "resource File:filesystem;result A{ok:File,err:i64}struct E{resource:File,code:i64}result F{err:E,ok:bool}" ++
        "fn main(fs:filesystem_cap)->i64{match acquire_resource<A>(fs,new [0]u8[]){A.ok(f)=>{acknowledge complete_resource<F>(f);return 7;},A.err(e)=>{return e;}}}");
    defer c.deinit();
    const generated = try c.emitC(allocator);
    defer allocator.free(generated);
}
// spec: NATIVE-RESOURCE-1
test "native resource lifecycle emission cleans failed compiler allocations" {
    try resourceScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), resourceScenario, .{});
}

fn resourceIoScenario(allocator: std.mem.Allocator) !void {
    const source = "resource File:filesystem;result A{ok:File,err:i64}struct Chunk{bytes:[4]u8,length:u64,eof:bool}" ++
        "result R{ok:Chunk,err:i64}struct Progress{eof:bool,length:u64}result S{err:i64,ok:Progress}result W{ok:u64,err:i64}" ++
        "fn main(fs:filesystem_cap)->i64{match acquire_resource<A>(fs,new [0]u8[]){A.ok(owner)=>{let mut file=owner;" ++
        "acknowledge read_resource<R>(file);let mut bytes=new [4]u8[1u8,2u8,3u8,4u8];borrow mut bytes[0..4] as d{" ++
        "acknowledge read_resource_slice<S>(file,d);}borrow bytes[0..4] as input{acknowledge write_resource_slice<W>(file,input);}" ++
        "acknowledge write_resource<W>(file,new [0]u8[]);return 7;},A.err(e)=>{return e;}}}";
    var c = try language.Compilation.init(allocator, "resource-io.my", source);
    defer c.deinit();
    const generated = try c.emitC(allocator);
    defer allocator.free(generated);
}
// spec: NATIVE-RESOURCE-IO-1
test "native resource array and slice IO emission cleans failed compiler allocations" {
    try resourceIoScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), resourceIoScenario, .{});
}

fn exportedScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "native.my", "struct R{a:[2]i64}union U{empty,value:R}domain D:i64{}fn echo(x:u64)->u64{return x;}" ++
        "fn envelope(r:R)->U{return new U.value(r);}fn main()->i64{return 0;}");
    defer c.deinit();
    try c.emit();
    var sink: @import("diagnostic.zig").Sink = .{ .allocator = allocator };
    defer sink.deinit();
    const generated = try @import("native.zig").generateWithInterface(allocator, c.code.?, c.src, &sink, .{ .roots = &.{ c.code.?.functions[0].id, c.code.?.functions[1].id }, .schema = "{\"fixture\":true}" });
    defer allocator.free(generated);
}
// spec: NATIVE-CALL-1
// spec: NATIVE-WIRE-1
// spec: NATIVE-SCHEMA-1
// spec: NATIVE-BINDINGS-1
test "native public value emission releases storage at every allocation failure" {
    try exportedScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), exportedScenario, .{});
}

fn codecDispatchScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "codec.my", "result R{ok:D,err:i64}domain D:i64{codec i64{decode:dec,encode:enc}" ++
        "fn dec(x:i64)->R{if x<0{return new R.err(x);}return new R.ok(wrap<D>(x));}" ++
        "fn enc(x:D)->i64{return unwrap(x);}}fn main()->i64{return 0;}");
    defer c.deinit();
    const generated = try c.emitC(allocator);
    defer allocator.free(generated);
}
// spec: NATIVE-CODEC-1
// spec: NATIVE-CODEC-WIRE-1
test "native declared codec dispatcher emission cleans every allocation failure" {
    try codecDispatchScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), codecDispatchScenario, .{});
}
// spec: NATIVE-HOST-1
test "native host declarations emit checked copied data descriptors and direct calls" {
    var compilation = try language.Compilation.init(t.allocator, "host.my", "struct Point{x:i64,y:u8}host fn echo(point:Point)->Point effects(host);" ++
        "fn main()->i64{return echo(new Point{x:3,y:4u8}).x;}");
    defer compilation.deinit();
    const generated = try compilation.emitC(t.allocator);
    defer t.allocator.free(generated);
    try t.expect(std.mem.indexOf(u8, generated, "host_invoke(0)") != null);
    try t.expect(std.mem.indexOf(u8, generated, "HostCapabilityDenied") != null);
}
const HostEcho = struct {
    fn invoke(call: *language.host_functions.Call) language.host_functions.CallbackError!language.vm.Value {
        return call.arguments[0].retain();
    }
};
// spec: NATIVE-HOST-2
test "native host composite parity fixture has an independent VM result" {
    var compilation = try language.Compilation.init(t.allocator, "composite.my", @embedFile("native_fixtures/composite.my"));
    defer compilation.deinit();
    try compilation.emit();
    var registry = try language.vm_host.Registry.init(t.allocator, compilation.code.?);
    defer registry.deinit();
    const contract = try registry.contract("echo");
    try registry.register("echo", .{ .signature = contract, .invoke = HostEcho.invoke }, contract.effects);
    const result = try language.vm.runWithHost(t.allocator, compilation.code.?, .{}, &registry, .{});
    try t.expectEqual(@as(i64, 42), result.value);
    const generated = try compilation.emitC(t.allocator);
    defer t.allocator.free(generated);
}
// spec: NATIVE-JSON-3
test "native checkFunction accepts compiled domain JSON codecs" {
    var compilation = try language.Compilation.init(t.allocator, "domain-json.my", "buffer Bytes:u8;result Encoded{ok:Bytes,err:i64}result R{ok:D,err:i64}" ++
        "domain D:i64{codec i64{decode:dec,encode:enc}fn dec(n:i64)->R{return new R.ok(wrap<D>(n));}fn enc(v:D)->i64{return unwrap(v);}}" ++
        "fn main(heap:allocator)->i64{match D.dec(1){R.err(e)=>{return e;},R.ok(v)=>{acknowledge json_encode::<Encoded>(heap,v,100);return 0;}}}");
    defer compilation.deinit();
    const output = try compilation.emitC(t.allocator);
    defer t.allocator.free(output);
    try t.expect(output.len > 0);
}
