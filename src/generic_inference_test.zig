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
    \\func my_sum[T: integer](x: T) -> T:
    \\    if x == T(0):
    \\        return x
    \\    return x + my_sum(x - T(1))
    \\
    \\
    \\func forward[U: integer](x: U) -> U:
    \\    return id(my_sum(x))
    \\
    \\
    \\func main() -> i64:
    \\    mut small = forward(4u8)
    \\    mut wide = forward(5)
    \\    if id(True):
    \\        return i64(small) + wide + my_sum[i64](2)
    \\    return 0
;
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "inference.selka", text);
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
    var compilation = try language.Compilation.init(t.allocator, "shapes.selka", text_input);
    defer compilation.deinit();
    const result = try native.run(&compilation);
    try t.expectEqual(expected, result.value);
}
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.selka")) return allocator.dupe(u8,
            \\import helper as h
            \\
            \\
            \\func main() -> i64:
            \\    mut values: FixedArray[i64, 2] = FixedArray[i64, 2]([7, 9])
            \\    return h.first(values)
        );
        if (std.mem.eql(u8, path, "helper.selka")) return allocator.dupe(u8,
            \\
            \\
            \\public func first[T, const N: u64](x: [N]T) -> T:
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
    var source_compilation = try language.Compilation.init(t.allocator, "format.selka", text);
    defer source_compilation.deinit();
    const formatted = try source_compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try run(formatted, 28);
}

// spec-case: CHECK-SCALE-SUFFIX-1
test "suffix index distinguishes nested spans and preserves the first exact duplicate" {
    var c = try language.Compilation.init(t.allocator, "nested-suffix.selka",
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
    \\    return copy(value)
    \\public func forward[U: copy + storable](value: U[]?) -> U[]?:
    \\    return identity(value)
;
const suffix_main =
    \\import model
    \\func field[V: copy + field(value: model.Entry[]?)](box: V) -> model.Entry[]?:
    \\    return copy(box.value)
    \\func main() -> int:
    \\    mut entries: model.Entry[] = [model.Entry(value=42)]
    \\    mut pairs = FixedArray[model.Entry[]?, 2]([Some(copy(entries)), None])
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
            .{ .path = "main.selka", .bytes = main },
            .{ .path = "model.selka", .bytes = suffix_model },
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
        try t.expectEqualStrings("model.selka", compilation.src.locate(moved.span.start).path);
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

fn firstDiagnostic(text_input: []const u8, code: []const u8, message: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "diagnostic.selka", text_input);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const failure = compilation.diagnostics.items[0];
    try t.expectEqualStrings(code, failure.code);
    try t.expectEqualStrings(message, failure.message);
}

const fallible_callback =
    \\record Link:
    \\    label: str
    \\
    \\
    \\func link_of(value: str) -> Link fails str:
    \\    return Link(label=copy(value))
    \\
    \\
;

// F-58: two arguments that infer different types for one parameter are both named, and the note is at the first.
test "a conflict between two arguments names both and what each inferred" {
    const program = fallible_callback ++
        \\func pick[T](first: T, make: func(str) -> T fails str) -> T fails str:
        \\    return first
        \\
        \\
        \\func main() -> int:
        \\    const got = pick(3, link_of) else Err(_):
        \\        return 1
        \\    return got
    ;
    try firstDiagnostic(program, "E_GENERIC_INFERENCE", "the type parameter `T` is inferred as int from the argument `3` and as Link from the argument " ++
        "`link_of`; write the type arguments in brackets after the function's name, or make the two agree");
    var compilation = try language.Compilation.init(t.allocator, "diagnostic.selka", program);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("3", compilation.src.text(compilation.diagnostics.items[0].related.?.span));
    try t.expectEqualStrings("link_of", compilation.src.text(compilation.diagnostics.items[0].span));
}

// F-58: the expected result and an argument that disagree are named as such.
test "a conflict between the expected result and a callback argument names both" {
    try firstDiagnostic(fallible_callback ++
        \\func each[T](values: str[], make: func(str) -> T fails str) -> T[] fails str:
        \\    mut out: T[] = []
        \\    for value in values:
        \\        const item = try make(value)
        \\        append(mut out, own item)
        \\    return out
        \\
        \\
        \\func main() -> int:
        \\    const found: Result[int[], str] = each(["a"], link_of)
        \\    _ = found
        \\    return 0
    , "E_GENERIC_INFERENCE", "the type parameter `T` is inferred as int from the expected result and as Link from the argument `link_of`; write the type arguments in brackets after the function's name, or make the two agree");
}

// F-58: a call that still cannot be inferred names the type parameter no argument determines.
test "an undetermined type parameter is named" {
    try firstDiagnostic(
        \\func make_empty[T]() -> T[]:
        \\    return []
        \\
        \\
        \\func main() -> int:
        \\    return len(make_empty())
    , "E_GENERIC_INFERENCE", "no argument of this call and no expected result determines the type parameter `T`; write the type arguments in brackets after the function's name");
}

// F-58: a generic function cannot be passed as a function value, so it fixes no type argument; it is refused by name.
test "a generic function passed for a function-typed parameter is refused as a function value" {
    try firstDiagnostic(fallible_callback ++
        \\func each[T](values: str[], make: func(str) -> T fails str) -> T[] fails str:
        \\    mut out: T[] = []
        \\    for value in values:
        \\        const item = try make(value)
        \\        append(mut out, own item)
        \\    return out
        \\
        \\
        \\func same[V](value: V) -> V fails str:
        \\    return value
        \\
        \\
        \\func main() -> int:
        \\    const got = each(["a"], same) else Err(_):
        \\        return 1
        \\    return len(got)
    , "E_CALLBACK_TYPE", "function values require a nongeneric free function");
}
