//! Generic nominal bodies are checked before calls and specialize through the VM catalog.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const definitions =
    \\class Box[T]:
    \\    value: T
    \\
    \\
    \\union Slot[T]:
    \\    none,
    \\    some: T
    \\
    \\
    \\result R[T]:
    \\    ok: T,
    \\    err: i64
    \\
    \\
    \\
;
fn run(allocator: std.mem.Allocator, text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(allocator, "nominal-body.my", text);
    defer compilation.deinit();
    const result = native.run(&compilation) catch |err| {
        if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqual(expected, result.value);
}
fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "bad-nominal-body.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
const basic = definitions ++
    \\def pack[T](x: T) -> Box[T]:
    \\    return Box[T](value=x)
    \\
    \\
    \\def extract[T](box: Box[T]) -> T:
    \\    return box.value
    \\
    \\
    \\def alter[T](box: Box[T], x: T) -> Box[T]:
    \\    y = box
    \\    y.value = x
    \\    return y
    \\
    \\
    \\def slot[T](x: T) -> Slot[T]:
    \\    return Slot.some(x)
    \\
    \\
    \\def choose[T](x: Slot[T], fallback: T) -> T:
    \\    match x:
    \\        case Slot.none:
    \\            return fallback
    \\        case Slot.some(value):
    \\            return value
    \\
    \\
    \\def main() -> i64:
    \\    return extract[i64](alter[i64](pack[i64](3), choose[i64](slot[i64](7), 0)))
;
// spec: NOMINAL-BODY-1
test "nominal bodies construct project update match and forward symbolic arguments" {
    try run(t.allocator, basic, 7);
}
test "nominal bodies reject invalid uncalled field payload and identity operations" {
    try reject(definitions ++
        \\def wrong[T](x: T) -> Box[T]:
        \\    return Box[T](value=1)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
    try reject(definitions ++
        \\def wrong[T](x: Box[T]) -> T:
        \\    return x.missing
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_UNKNOWN_FIELD");
    try reject(definitions ++
        \\def wrong[T](x: Slot[T]) -> i64:
        \\    match x:
        \\        case Slot.none:
        \\            return 1
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_INCOMPLETE_MATCH");
    try reject(definitions ++
        \\def wrong[T, U](x: Box[T]) -> Box[U]:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
}
const results = definitions ++
    \\result Output[T]:
    \\    err: i64,
    \\    ok: Box[T]
    \\
    \\
    \\def plus[T: integer](x: R[T]) -> Output[T]:
    \\    n = x?
    \\    return Output.ok(Box[T](value=n + n))
    \\
    \\
    \\def main() -> i64:
    \\    match plus[i64](R.ok(6)):
    \\        case Output.ok(box):
    \\            return box.value
    \\        case Output.err(e):
    \\            return e
;
const arrays = definitions ++
    \\def pairs[T](x: T) -> [2]T:
    \\    return [x, x]
    \\
    \\
    \\def boxed[T](x: T) -> Box[[2]T]:
    \\    return Box[[2]T](value=pairs[T](x))
    \\
    \\
    \\def main() -> i64:
    \\    a = pairs[i64](1)
    \\    b = boxed[i64](8)
    \\    return a[0] + b.value[1]
;
test "nominal bodies reuse concrete array identities created by earlier function specialization" {
    try run(t.allocator, arrays, 9);
}
fn allocations(allocator: std.mem.Allocator) !void {
    try run(allocator, basic, 7);
    try run(allocator, results, 12);
    try run(allocator, arrays, 9);
}
test "nominal bodies release shape catalogs and VM storage after every allocation failure" {
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocations, .{});
}
const module_source =
    \\module model
    \\export Box
    \\export pack
    \\export extract
    \\
    \\
    \\class Box[T]:
    \\    value: T
    \\
    \\
    \\def pack[T](x: T) -> Box[T]:
    \\    return Box[T](value=x)
    \\
    \\
    \\def extract[T](box: Box[T]) -> T:
    \\    return box.value
;
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\module main
            \\import model as m
            \\
            \\
            \\def main() -> i64:
            \\    return m.extract[i64](m.pack[i64](23))
        );
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8, module_source);
        return error.NotFound;
    }
};
fn moduleScenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    const ty = try compilation.publicValueType("model::Box<i64>");
    try t.expectEqual(@import("typed.zig").Type.i64, compilation.program.?.records[ty.recordIndex()].fields[0].ty);
    try t.expectEqual(@as(i64, 23), (try native.run(&compilation)).value);
}
test "nominal bodies preserve imported declaration identity through specialization and public lookup" {
    try moduleScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), moduleScenario, .{});
}
test "nominal bodies bound growing function specialization before executable output" {
    const source_text = definitions ++
        \\def grow[T](x: T) -> i64:
        \\    return grow[Box[T]](Box[T](value=x))
        \\
        \\
        \\def main() -> i64:
        \\    return grow[i64](0)
    ;
    var compilation = try language.Compilation.init(t.allocator, "growing-nominal.my", source_text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.emit());
    try t.expectEqualStrings("E_GENERIC_LIMIT", compilation.diagnostics.items[0].code);
    try t.expect(compilation.program == null and compilation.code == null);
}
test "nominal bodies propagate results with named error remapping and obligations" {
    try run(t.allocator, results, 12);
    try reject(definitions ++
        \\def drop[T](r: R[T]) -> i64:
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try run(t.allocator, definitions ++
        \\def drop[T](r: R[T]) -> i64:
        \\    _ = r
        \\    return 4
        \\
        \\
        \\def main() -> i64:
        \\    return drop[i64](R.ok(1))
    , 4);
}
