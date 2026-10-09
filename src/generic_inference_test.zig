//! Omitted generic arguments use the same checked substitutions as explicit calls.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const text =
    \\func id[T](value: T) -> T:
    \\    return value
    \\
    \\
    \\func sum[T: integer](x: T) -> T:
    \\    if x == T(0):
    \\        return x
    \\    return x + sum(x - T(1))
    \\
    \\
    \\func forward[U: integer](x: U) -> U:
    \\    return id(sum(x))
    \\
    \\
    \\func main() -> i64:
    \\    mut small = forward(4u8)
    \\    mut wide = forward(5)
    \\    if id(True):
    \\        return i64(small) + wide + sum[i64](2)
    \\    return 0
;
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "inference.my", text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 28), (try native.run(&compilation)).value);
    try t.expectEqual(@as(usize, 8), compilation.program.?.functions.len);
}
// spec: GENERIC-INFERENCE-1
test "generic inferCall allocation failures preserve widths forwarding recursion and instance reuse" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn run(text_input: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "shapes.my", text_input);
    defer compilation.deinit();
    const result = try native.run(&compilation);
    try t.expectEqual(expected, result.value);
}
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\import helper as h
            \\
            \\
            \\func main() -> i64:
            \\    mut values: FixedArray[i64, 2] = FixedArray[i64, 2]([7, 9])
            \\    return h.first(values)
        );
        if (std.mem.eql(u8, path, "helper.my")) return allocator.dupe(u8,
            \\
            \\
            \\public func first[T, const N: u64](x: [N]T) -> T effects():
            \\    return x[0]
        );
        return error.NotFound;
    }
};
test "generic inference keeps module relocation and formatter source identity" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    try t.expectEqual(@as(i64, 7), (try native.run(&compilation)).value);
    var source_compilation = try language.Compilation.init(t.allocator, "format.my", text);
    defer source_compilation.deinit();
    const formatted = try source_compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try run(formatted, 28);
}

// spec-case: CHECK-SCALE-SUFFIX-1
test "suffix index distinguishes nested spans and preserves the first exact duplicate" {
    var c = try language.Compilation.init(t.allocator, "nested-suffix.my",
        \\record Box[T: copy + storable]:
        \\    value: T[]?
        \\func main() -> int:
        \\    return 0
    );
    defer c.deinit();
    try c.parse();
    var syntax = c.syntax.?;
    const original = syntax.types.expressions.suffixes;
    const outer = for (original) |suffix| {
        if (std.mem.eql(u8, c.src.text(suffix.span), "T[]?")) break suffix;
    } else return error.TestUnexpectedResult;
    try t.expectEqual(outer.span.start, outer.base.start);
    try t.expect(outer.span.end != outer.base.end);
    const duplicated = try c.arena.allocator().alloc(@import("ast.zig").TypeSuffix, original.len + 1);
    @memcpy(duplicated[0..original.len], original);
    duplicated[original.len] = .{ .span = outer.span, .base = outer.base, .kind = .growable };
    syntax.types.expressions.suffixes = duplicated;
    var sink: language.diagnostic.Sink = .{ .allocator = c.arena.allocator() };
    var index = try @import("nominal_templates.zig").collect(c.arena.allocator(), c.src, syntax, &sink, null);
    const parameters = index.declarations.items[index.names.get("Box").?].parameters;
    const resolved = try index.expression(outer.span, parameters);
    try t.expect(resolved == .application);
    try t.expectEqual(index.names.get("Option").?, resolved.application.declaration);
    const inner = resolved.application.arguments[0];
    try t.expect(inner == .application);
    try t.expectEqual(index.names.get("list").?, inner.application.declaration);
    try t.expectEqual(@as(usize, 0), inner.application.arguments[0].parameter);
}

const SuffixFiles = struct {
    entries: []const language.embedded_project.File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *SuffixFiles = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, self.entries, path, limit);
    }
};
const suffix_model =
    \\public record Entry:
    \\    value: int
    \\public record Holder[T: copy + storable]:
    \\    value: T[]?
    \\    pairs: FixedArray[T[]?, 2]
    \\public func identity[T: copy + storable](value: T[]?) -> T[]?:
    \\    return value
    \\public func forward[U: copy + storable](value: U[]?) -> U[]?:
    \\    return identity(value)
;
const suffix_main =
    \\import model
    \\func field[V: copy + field(value: model.Entry[]?)](box: V) -> model.Entry[]?:
    \\    return box.value
    \\func main() -> int:
    \\    mut entries: model.Entry[] = [model.Entry(value=42)]
    \\    mut pairs = FixedArray[model.Entry[]?, 2]([Some(entries), None])
    \\    mut box = model.Holder[model.Entry](value=Some(entries), pairs=pairs)
    \\    mut returned = model.forward(field(box))
    \\    if returned is None:
    \\        return 0
    \\    return len(returned) + len(box.pairs)
;

// spec: CHECK-SCALE-SUFFIX-1
test "suffix index preserves qualified optional lists fixed arrays and generic forwarding after module relocation" {
    var previous: usize = 0;
    for ([_][]const u8{ "", "\n\n\n\n\n" }) |prefix| {
        const main = try std.mem.concat(t.allocator, u8, &.{ prefix, suffix_main });
        defer t.allocator.free(main);
        const entries = [_]language.embedded_project.File{
            .{ .path = "main.my", .bytes = main },
            .{ .path = "model.my", .bytes = suffix_model },
        };
        var files: SuffixFiles = .{ .entries = &entries };
        var project = language.project.Project.init(t.allocator);
        defer project.deinit();
        try project.load(.{ .context = &files, .read = SuffixFiles.read }, "main", .{});
        var index = try language.interfaces.build(&project);
        var compilation = try language.project_compile.Compilation.init(&index);
        try compilation.check();
        const moved = for (compilation.syntax.types.expressions.suffixes) |suffix| {
            if (std.mem.eql(u8, compilation.src.text(suffix.span), "T[]?")) break suffix;
        } else return error.TestUnexpectedResult;
        try t.expectEqualStrings("model.my", compilation.src.locate(moved.span.start).path);
        if (prefix.len != 0) try t.expect(moved.span.start > previous);
        previous = moved.span.start;
        var fixed_optional_lists = false;
        for (compilation.program.?.records) |record| {
            const array = record.shape.array orelse continue;
            if (array.length != 2) continue;
            const optional = @import("prelude.zig").optionShape(array.element, compilation.program.?.records) orelse continue;
            if (optional.element.isAggregate() and compilation.program.?.records[optional.element.recordIndex()].collection.kind == .list) fixed_optional_lists = true;
        }
        try t.expect(fixed_optional_lists);
    }
}
