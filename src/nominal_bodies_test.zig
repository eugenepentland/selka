//! Generic nominal bodies are checked before calls and specialize through the VM catalog.
const source_names = @import("source_names.zig");
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const definitions =
    \\record Box[T]:
    \\    value: T
    \\
    \\
    \\enum Slot[T]:
    \\    none
    \\    some(value: T)
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
    var compilation = try language.Compilation.init(allocator, "nominal-body.selka", text);
    defer compilation.deinit();
    const result = native.run(&compilation) catch |err| {
        if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqual(expected, result.value);
}
fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "bad-nominal-body.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
const basic = definitions ++
    \\func pack[T](x: T) -> Box[T]:
    \\    return Box[T](value=x)
    \\
    \\
    \\func extract[T](box: Box[T]) -> T:
    \\    return box.value
    \\
    \\
    \\func alter[T](mut box: Box[T], x: T) -> Box[T]:
    \\    box.value = x
    \\    return box
    \\
    \\
    \\func slot[T](x: T) -> Slot[T]:
    \\    return Slot.some(value=x)
    \\
    \\
    \\func choose[T](x: Slot[T], fallback: T) -> T:
    \\    match x:
    \\        case Slot.none:
    \\            return fallback
    \\        case Slot.some(value=value):
    \\            return value
    \\
    \\
    \\func main() -> i64:
    \\    mut boxed = pack[i64](3)
    \\    return extract[i64](alter[i64](mut boxed, choose[i64](slot[i64](7), 0)))
;
test "nominal bodies reject invalid uncalled field payload and identity operations" {
    try reject(definitions ++
        \\func wrong[T](x: T) -> Box[T]:
        \\    return Box[T](value=1)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
    try reject(definitions ++
        \\func wrong[T](x: Box[T]) -> T:
        \\    return x.missing
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_UNKNOWN_FIELD");
    try reject(definitions ++
        \\func wrong[T](x: Slot[T]) -> i64:
        \\    match x:
        \\        case Slot.none:
        \\            return 1
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_INCOMPLETE_MATCH");
    try reject(definitions ++
        \\func wrong[T, U](x: Box[T]) -> Box[U]:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
}
const results = definitions ++
    \\result Output[T]:
    \\    err: i64,
    \\    ok: Box[T]
    \\
    \\
    \\func plus[T: integer](x: R[T]) -> Output[T]:
    \\    mut n = try x
    \\    return Output.ok(Box[T](value=n + n))
    \\
    \\
    \\func main() -> i64:
    \\    match plus[i64](R.ok(6)):
    \\        case Output.ok(box):
    \\            return box.value
    \\        case Output.err(e):
    \\            return e
;
const arrays = definitions ++
    \\func pairs[T](x: T) -> FixedArray[T, 2]:
    \\    return FixedArray[T, 2]([x, x])
    \\
    \\
    \\func boxed[T](x: T) -> Box[FixedArray[T, 2]]:
    \\    return Box[FixedArray[T, 2]](value=pairs[T](x))
    \\
    \\
    \\func main() -> i64:
    \\    mut a = pairs[i64](1)
    \\    mut b = boxed[i64](8)
    \\    return a[0] + b.value[1]
;
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
    \\
    \\
    \\public record Box[T]:
    \\    value: T
    \\
    \\
    \\public func pack[T](x: T) -> Box[T] effects():
    \\    return Box[T](value=x)
    \\
    \\
    \\public func extract[T](box: Box[T]) -> T effects():
    \\    return box.value
;
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, source_names.entry)) return allocator.dupe(u8,
            \\import model as m
            \\
            \\
            \\func main() -> i64:
            \\    return m.extract[i64](m.pack[i64](23))
        );
        if (std.mem.eql(u8, path, "model.selka")) return allocator.dupe(u8, module_source);
        return error.NotFound;
    }
};
fn moduleScenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    const ty = try compilation.publicValueType("model::Box<i64>");
    try t.expectEqual(@import("typed.zig").Type.i64, compilation.program.?.records[ty.recordIndex()].fields[0].ty);
    try t.expectEqual(@as(i64, 23), (try native.run(&compilation)).value);
}
test "nominal bodies preserve imported declaration identity through specialization and public lookup" {
    try moduleScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), moduleScenario, .{});
}
test "nominal bodies bound growing function specialization before checking succeeds" {
    const source_text = definitions ++
        \\func grow[T](x: T) -> i64:
        \\    return grow[Box[T]](Box[T](value=x))
        \\
        \\
        \\func main() -> i64:
        \\    return grow[i64](0)
    ;
    var compilation = try language.Compilation.init(t.allocator, "growing-nominal.selka", source_text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_GENERIC_LIMIT", compilation.diagnostics.items[0].code);
    try t.expect(compilation.program == null);
}
test "nominal bodies propagate results with named error remapping and obligations" {
    try run(t.allocator, results, 12);
    try reject(definitions ++
        \\func drop[T](r: R[T]) -> i64:
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try run(t.allocator, definitions ++
        \\func drop[T](r: R[T]) -> i64:
        \\    _ = r
        \\    return 4
        \\
        \\
        \\func main() -> i64:
        \\    return drop[i64](R.ok(1))
    , 4);
}
