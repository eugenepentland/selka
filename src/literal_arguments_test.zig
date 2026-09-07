//! Literal slice arguments have a call-bounded borrow with ordinary runtime cleanup.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
// spec: LITERAL-SLICE-1
test "slice literal arguments support multiple empty generic and repeated calls" {
    const source = "fn size(s:&[]u8)->i64{return cast<i64>(len_slice(s));}" ++
        "fn pair(a:&[]u8,b:&[]u8)->i64{return size(a)+size(b);}" ++
        "fn generic<T:integer>(n:T)->T{discard size(\"generic\");return n;}" ++
        "fn main()->i64{let mut n=0;while n<3{n+=pair(\"x\",\"\");}return generic::<i64>(n)+size(\"é\");}";
    var compilation = try language.Compilation.init(t.allocator, "literal.my", source);
    defer compilation.deinit();
    const result = compilation.execute(t.allocator) catch |err| {
        @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqual(@as(i64, 5), result.value);
}

fn reject(source: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "literal-error.my", source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(@import("diagnostic.zig").reference_argument, compilation.diagnostics.items[0].code);
}
// spec: LITERAL-SLICE-2
test "slice literal arguments reject mutation wrong element types and escaped lifetimes" {
    try reject("fn f(s:&mut []u8)->i64{write_slice(s,0,0u8);return 0;}fn main()->i64{return f(\"a\");}");
    try reject("fn f(s:&[]i64)->i64{return cast<i64>(len_slice(s));}fn main()->i64{return f(\"a\");}");
    try reject("fn f(s:&[]u8)->&[]u8 from s{return s;}fn main()->i64{borrow f(\"a\") as view{return cast<i64>(len_slice(view));}}");
    try reject("fn f(s:&mut []u8)->i64{write_slice(s,0,0u8);return 0;}fn g<T:copy>(n:T)->T{discard f(\"a\");return n;}fn main()->i64{return 0;}");
}
fn execute(allocator: std.mem.Allocator, program: language.bytecode.Program) !void {
    var stats: @import("memory.zig").Statistics = .{};
    const outcome = try language.vm.runWithOptions(allocator, program, .{ .memory = .{ .limits = .{ .max_allocations = 1 }, .statistics = &stats } });
    try t.expectEqual(@as(i64, 10), outcome.value);
    try t.expectEqual(@as(usize, 0), stats.live_allocations);
    try t.expectEqual(stats.created, stats.released);
}
// spec: LITERAL-SLICE-3
test "slice literal call cleanup releases backing before the next call including allocation failures" {
    const source = "fn size(s:&[]u8)->i64{return cast<i64>(len_slice(s));}" ++
        "fn main()->i64{let mut n=0;while n<10{n+=size(\"x\");}return n;}";
    var compilation = try language.Compilation.init(t.allocator, "literal-cleanup.my", source);
    defer compilation.deinit();
    try compilation.emit();
    try execute(t.allocator, compilation.code.?);
    try t.checkAllAllocationFailures(t.allocator, execute, .{compilation.code.?});
}
