//! Concrete nominal instances execute through ordinary typed IR and the checked bytecode VM.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const typed = @import("typed.zig");
const definitions =
    \\record Box[T]:
    \\    value: T
    \\
    \\
    \\union Slot[T]:
    \\    none,
    \\    some: T
    \\
    \\
    \\result Answer[T]:
    \\    ok: T,
    \\    err: i64
    \\
    \\
    \\
;
fn run(allocator: std.mem.Allocator, text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(allocator, "instances.my", text);
    defer compilation.deinit();
    const output = try native.run(&compilation);
    try t.expectEqual(expected, output.value);
}
fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "bad-instances.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
const basic = definitions ++
    \\def main() -> i64:
    \\    a = Box[i64](value=7)
    \\    b = a
    \\    b.value = 9
    \\    slot: Slot[Box[i64]] = Slot.some(b)
    \\    match slot:
    \\        case Slot.none:
    \\            return 0
    \\        case Slot.some(value):
    \\            return a.value + value.value
;
test "nominal instances preserve argument order and nominal declaration identity" {
    try reject(definitions ++
        \\def takes(x: Box[i64]) -> i64:
        \\    return x.value
        \\
        \\
        \\def main() -> i64:
        \\    return takes(Box[bool](value=True))
    , "E_TYPE");
    try reject(
        \\record Pair[A, B]:
        \\    a: A
        \\    b: B
        \\
        \\
        \\def takes(x: Pair[i64, bool]) -> i64:
        \\    return x.a
        \\
        \\
        \\def main() -> i64:
        \\    return takes(Pair[bool, i64](a=True, b=1))
    , "E_TYPE");
    try reject(
        \\record A[T]:
        \\    value: T
        \\
        \\
        \\record B[T]:
        \\    value: T
        \\
        \\
        \\def takes(x: A[i64]) -> i64:
        \\    return x.value
        \\
        \\
        \\def main() -> i64:
        \\    return takes(B[i64](value=1))
    , "E_TYPE");
    try reject(definitions ++
        \\def main() -> i64:
        \\    x: Box = 1
        \\    return x
    , "E_GENERIC_ARITY");
    try reject(definitions ++
        \\def Box() -> i64:
        \\    return 1
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_DUPLICATE_NAME");
}
fn allocations(allocator: std.mem.Allocator) !void {
    try run(allocator, basic, 16);
}
test "nominal catalog collect and VM execution clean up every allocation failure" {
    try allocations(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocations, .{});
}
test "nominal instances retain concrete checks within generic bodies" {
    try run(t.allocator, definitions ++
        \\def identity[T](x: Box[T]) -> Box[T]:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return identity[i64](Box[i64](value=5)).value
    , 5);
    try reject(definitions ++
        \\def bad[T]() -> i64:
        \\    box = Box[i64](value=True)
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
    try run(t.allocator, definitions ++
        \\def concrete[T]() -> i64:
        \\    box = Box[i64](value=4)
        \\    return box.value
        \\
        \\
        \\def main() -> i64:
        \\    return concrete[bool]()
    , 4);
}
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\module main
            \\import model as m
            \\
            \\
            \\def main() -> i64:
            \\    x = m.Box[i64](value=4)
            \\    return m.twice(x).value
        );
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8,
            \\module model
            \\
            \\
            \\public record Box[T]:
            \\    value: T
            \\
            \\
            \\public record Empty[T]:
            \\    pass
            \\
            \\
            \\record Hidden:
            \\    value: i64
            \\
            \\
            \\public def twice(x: Box[i64]) -> Box[i64] effects():
            \\    y = x
            \\    y.value = x.value * 2
            \\    return y
            \\
            \\
            \\def hidden_values(x: Box[Hidden], y: Empty[Hidden]) -> i64:
            \\    _ = x
            \\    _ = y
            \\    return 0
        );
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
    const public_type = try compilation.publicValueType("model::Box<i64>");
    try t.expectEqual(typed.Type.i64, compilation.program.?.records[public_type.recordIndex()].fields[0].ty);
    try t.expectError(error.UnknownPublicValueType, compilation.publicValueType("model::Box<model::Hidden>"));
    try t.expectError(error.UnknownPublicValueType, compilation.publicValueType("model::Empty<model::Hidden>"));
    try t.expectEqual(@as(i64, 8), (try native.run(&compilation)).value);
}
test "nominal instances share declaration identity through imported signatures and constructors" {
    try moduleScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), moduleScenario, .{});
}
/// `count` records whose names are `length` bytes each, plus a trivial entry.
fn longNamedRecords(allocator: std.mem.Allocator, count: usize, length: usize) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    const stem = try allocator.alloc(u8, length - 6);
    defer allocator.free(stem);
    @memset(stem, 'n');
    for (0..count) |index| try text.writer.print("record R{s}{d:0>5}:\n    v: i64\n\n\n", .{ stem, index });
    try text.writer.writeAll("def main() -> i64:\n    return 0\n");
    return text.toOwnedSlice();
}
// spec: NOMINAL-NAME-BUDGET-1
test "nominal display names are budgeted by the program's size, not a fixed 1 MiB" {
    // 2,000 records with 600-byte names: 1.2 MB of display names, over the
    // old fixed 1 MiB and under the program's own 1.3 MB of source.
    const text = try longNamedRecords(t.allocator, 2000, 600);
    defer t.allocator.free(text);
    var compilation = try language.Compilation.init(t.allocator, "names.my", text);
    defer compilation.deinit();
    try compilation.check();
    try t.expect(compilation.program.?.records.len >= 2000);
}
/// `count` record types, each used through `list[R<i>]` and `list[i64]` in its own function.
fn listUses(allocator: std.mem.Allocator, count: usize) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    for (0..count) |i| try text.writer.print(
        \\record R{d}:
        \\    v: i64
        \\
        \\def f{d}(n: i64) -> i64:
        \\    xs: list[R{d}] = []
        \\    ys: list[i64] = []
        \\    for j in range(n):
        \\        xs.append(R{d}(j))
        \\        ys.append(j)
        \\    return len(xs) + len(ys)
        \\
        \\
    , .{ i, i, i, i });
    try text.writer.writeAll("def main() -> i64:\n    total = 0\n");
    for (0..count) |i| try text.writer.print("    total += f{d}(3)\n", .{i});
    try text.writer.writeAll("    return total\n");
    return text.toOwnedSlice();
}
/// How many list types of the program hold `element`, or any record when `element` is null.
fn listsOf(records: []const typed.Record, element: ?typed.Type) usize {
    var count: usize = 0;
    for (records) |record| if (record.isCollection() and !std.mem.eql(u8, record.name, "str")) {
        const held = record.shape.buffer.?;
        if (if (element) |wanted| held == wanted else held.isAggregate()) count += 1;
    };
    return count;
}
// spec: CATALOG-INTERN-1
test "nominal catalog interns each list type once however often the checker asks for it" {
    const text = try listUses(t.allocator, 40);
    defer t.allocator.free(text);
    var compilation = try language.Compilation.init(t.allocator, "interned.my", text);
    defer compilation.deinit();
    try compilation.check();
    const records = compilation.program.?.records;
    try t.expectEqual(@as(usize, 1), listsOf(records, .i64));
    try t.expectEqual(@as(usize, 40), listsOf(records, null));
    const output = try native.run(&compilation);
    try t.expectEqual(@as(i64, 240), output.value);
}
// spec-case: CATALOG-INTERN-1
test "nominal catalog reuses nested generic instances whose arguments complete later" {
    try run(t.allocator, definitions ++
        \\def boxes(n: i64) -> list[Box[list[i64]]]:
        \\    out: list[Box[list[i64]]] = []
        \\    for j in range(n):
        \\        out.append(Box[list[i64]](value=[j, j + 1]))
        \\    return out
        \\
        \\def total(items: list[Box[list[i64]]]) -> i64:
        \\    sum = 0
        \\    for item in items:
        \\        inner: list[i64] = item.value
        \\        sum += inner[0] + inner[1]
        \\    return sum
        \\
        \\def main() -> i64:
        \\    slot: Slot[Box[list[i64]]] = Slot.some(Box[list[i64]](value=[5]))
        \\    extra = 0
        \\    match slot:
        \\        case Slot.some(box):
        \\            extra = box.value[0]
        \\        case Slot.none:
        \\            extra = 0
        \\    return total(boxes(4)) + total(boxes(2)) + extra
    , 16 + 4 + 5);
}
fn largeNames(allocator: std.mem.Allocator) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.writeAll(
        \\record Pair[A, B]:
        \\    a: A
        \\    b: B
        \\
        \\
        \\
    );
    for (0..18) |i| try text.writer.print("record Chain{d}[T]:\n    next: Chain{d}[Pair[T, T]]\n\n\n", .{ i, i + 1 });
    try text.writer.writeAll(
        \\record Chain18[T]:
        \\    pass
        \\
        \\
        \\def takes(x: Chain0[i64]) -> i64:
        \\    _ = x
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    return text.toOwnedSlice();
}
// spec-case: NOMINAL-NAME-BUDGET-1
test "nominal concrete type names stop expansion before excessive diagnostic allocation" {
    const text = try largeNames(t.allocator);
    defer t.allocator.free(text);
    try reject(text, "E_GENERIC_LIMIT");
}
test "nominal exported type constructors are symbolic schema templates rather than concrete callable roots" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    const bytes = try language.schema.render(t.allocator, &compilation);
    defer t.allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
    defer parsed.deinit();
    const templates = parsed.value.object.get("generic_templates").?.array.items;
    try t.expect(templates.len >= 1);
    try t.expect(!templates[0].object.get("contract").?.object.get("callable").?.bool);
    try t.expect(templates[0].object.get("contract").?.object.get("requires_explicit_instantiation").?.bool);
}
/// Count move-only filesystem resource declarations in a checked program.
fn filesystemResources(records: []const typed.Record) usize {
    var found: usize = 0;
    for (records) |record| {
        const kind = record.shape.resource orelse continue;
        if (kind == .filesystem and record.contract.move_only) found += 1;
    }
    return found;
}
test "nominal instances carry domain payloads beside resource declarations" {
    const program = definitions ++
        \\domain Id: i64:
        \\    def make(n: i64) -> Id:
        \\        return wrap[Id](n)
        \\
        \\    def number(n: Id) -> i64:
        \\        return unwrap(n)
        \\
        \\
        \\resource File: filesystem
        \\
        \\
        \\def main() -> i64:
        \\    box = Box[Id](value=Id.make(13))
        \\    return Id.number(box.value)
    ;
    var compilation = try language.Compilation.init(t.allocator, "nominal-domain.my", program);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 13), (try native.run(&compilation)).value);
    try t.expectEqual(@as(usize, 1), filesystemResources(compilation.program.?.records));
}
