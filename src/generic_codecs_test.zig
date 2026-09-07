//! Generic callers may use concrete domain codecs without accessing private representation.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const domain = "struct Wire{n:i64}result Decoded{ok:Positive,err:i64}domain Positive:i64{" ++
    "codec Wire{decode:from_wire,encode:to_wire}private fn raw(x:i64)->Positive{return wrap<Positive>(x);}" ++
    "fn from_wire(x:Wire)->Decoded{if x.n<=0{return new Decoded.err(-1);}return new Decoded.ok(Positive.raw(x.n));}" ++
    "fn to_wire(x:Positive)->Wire{return new Wire{n:unwrap(x)};}}";
const helpers = "fn round<T:copy>(ignored:T,n:i64)->i64{discard ignored;match codec_decode<Positive>(new Wire{n:n}){" ++
    "Decoded.ok(x)=>{return codec_encode<Positive>(x).n;},Decoded.err(e)=>{return e;}}}";
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "generic-codecs.my", domain ++ helpers ++ "fn main()->i64{return round::<bool>(false,7)+round::<i64>(2,0);}");
    defer compilation.deinit();
    const result = compilation.execute(allocator) catch |err| {
        if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqual(@as(i64, 6), result.value);
}
// spec: GENERIC-CODEC-1
test "generic codecs execute concrete domain factories and accessors under allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn reject(body: []const u8, expected: []const u8) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{ domain, body, "fn main()->i64{return 0;}" });
    defer t.allocator.free(text);
    var compilation = try language.Compilation.init(t.allocator, "bad-generic-codecs.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(expected, compilation.diagnostics.items[0].code);
}
test "generic codecs preserve domain privacy arity input types and result obligations before calls" {
    try reject("fn f<T:copy>(n:i64)->Positive{return wrap<Positive>(n);}", "E_PRIVATE_DOMAIN");
    try reject("fn f<T:copy>(x:Positive)->i64{return unwrap(x);}", "E_PRIVATE_DOMAIN");
    try reject("fn f<T:copy>(n:i64)->Positive{return Positive.raw(n);}", "E_PRIVATE_FUNCTION");
    try reject("fn f<T:copy>()->Decoded{return codec_decode<Positive>();}", "E_CODEC_ARITY");
    try reject("fn f<T:copy>(n:T)->Wire{return codec_encode<Positive>(n);}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy>(n:T)->T{return codec_encode<T>(n);}", "E_GENERIC_BODY_UNSUPPORTED");
    try reject("fn f<T:copy>()->i64{discard codec_decode<Positive>(new Wire{n:1});return 0;}", "E_RESULT_DISCARD");
}
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, "module main;import model as m;fn f<T:copy>(x:T)->i64{discard x;match codec_decode<m::Positive>(new m::Wire{n:23}){" ++
            "m::Decoded.ok(p)=>{return codec_encode<m::Positive>(p).n;},m::Decoded.err(e)=>{return e;}}}fn main()->i64{return f::<bool>(false);}");
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8, "module model;export Wire;export Decoded;export Positive;" ++ domain);
        return error.NotFound;
    }
};
fn projectScenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 23), (try language.vm.run(allocator, compilation.code.?)).value);
}
test "generic codecs follow imported contracts and declaring domain privacy through module relocation" {
    try projectScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), projectScenario, .{});
}
