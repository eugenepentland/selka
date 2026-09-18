//! Scalar domain equality preserves nominal boundaries without exposing backing values.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const typed = @import("typed.zig");
const declarations =
    \\public domain Id: u64:
    \\    def make(n: u64) -> Id effects():
    \\        return wrap[Id](n)
    \\
    \\
    \\domain Other: u64:
    \\    def make(n: u64) -> Other effects():
    \\        return wrap[Other](n)
    \\
    \\
    \\
;
const comparison = declarations ++
    \\def main() -> i64:
    \\    if Id.make(18446744073709551615u64) == Id.make(18446744073709551615u64):
    \\        return 1
    \\    return 0
;

fn expectValue(allocator: std.mem.Allocator, source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(allocator, "equality.my", source);
    defer compilation.deinit();
    try t.expectEqual(expected, (try native.run(&compilation)).value);
}

fn reject(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "equality.my", source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

fn allocationFailures(allocator: std.mem.Allocator) !void {
    try expectValue(allocator, comparison, 1);
}

test "domain equality releases operands on allocation failures" {
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocationFailures, .{});
}

fn domainComparison(code: language.bytecode.Program) !*language.bytecode.Instruction {
    for (code.functions) |function| for (function.scope.instructions) |*instruction| {
        if (instruction.op == .cmp_domain) return @constCast(instruction);
    };
    return error.TestUnexpectedResult;
}

test "domain equality bytecode rejects invalid comparison schemas and mismatched operand identities" {
    var compilation = try language.Compilation.init(t.allocator, "bytecode.my", comparison);
    defer compilation.deinit();
    try compilation.emit();
    const code = compilation.code.?;
    const dump = try @import("disassemble.zig").dump(t.allocator, code, compilation.src);
    defer t.allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "CMP_DOMAIN Id eq") != null);
    try language.bytecode.validate(t.allocator, code);
    const instruction = try domainComparison(code);
    const original = instruction.*;
    defer instruction.* = original;
    for ([_]typed.Type{ .i64, .bool, @fromBackingInt(999999) }) |invalid| {
        instruction.op.cmp_domain.ty = invalid;
        try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, code));
    }
    // Other is a valid domain schema, so validation accepts it on its own.
    instruction.op.cmp_domain.ty = code.records[1].id;
    try language.bytecode.validate(t.allocator, code);
}

test "domain equality emits native comparisons without a feature rejection" {
    var compilation = try language.Compilation.init(t.allocator, "native.my", comparison);
    defer compilation.deinit();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

const Modules = struct {
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, if (context == null)
            \\module main
            \\import left as a
            \\import bridge as b
            \\
            \\
            \\def main() -> i64:
            \\    if a.Id.make(9u64) == b.make(9u64):
            \\        return 1
            \\    return 0
        else
            \\module main
            \\import left as a
            \\import right as b
            \\
            \\
            \\def main() -> i64:
            \\    _ = a.Id.make(9u64) == b.Id.make(9u64)
            \\    return 0
        );
        if (std.mem.eql(u8, path, "bridge.my")) return allocator.dupe(u8,
            \\module bridge
            \\import left as alias
            \\
            \\
            \\public def make(n: u64) -> alias.Id effects():
            \\    return alias.Id.make(n)
        );
        if (std.mem.eql(u8, path, "left.my")) return allocator.dupe(u8, "module left\n" ++ declarations);
        if (std.mem.eql(u8, path, "right.my")) return allocator.dupe(u8, "module right\n" ++ declarations);
        return error.NotFound;
    }
};

test "domain equality resolves declaration identity through module aliases" {
    var marker: u8 = 0;
    for ([_]?*anyopaque{ null, &marker }) |context| {
        var project = language.project.Project.init(t.allocator);
        defer project.deinit();
        try project.load(.{ .context = context, .read = Modules.read }, "main", .{});
        var index = try language.interfaces.build(&project);
        var compilation = try language.project_compile.Compilation.init(&index);
        if (context == null) {
            try compilation.emit();
            try t.expectEqual(@as(i64, 1), (try native.run(&compilation)).value);
        } else {
            try t.expectError(error.SourceError, compilation.check());
            try t.expectEqualStrings("E_TYPE", compilation.diagnostics.items.items[0].code);
        }
    }
}

// spec: DOMAIN-EQUALITY-1
test "domain equality compares every scalar backing by value" {
    for ([_][]const u8{ "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64" }) |width| {
        const source = try std.fmt.allocPrint(t.allocator,
            \\domain D: {s}:
            \\    def make(n: {s}) -> D:
            \\        return wrap[D](n)
            \\
            \\
            \\def main() -> i64:
            \\    a = D.make(7{s})
            \\    b = D.make(8{s})
            \\    if a == a and a != b and not (a == b) and not (a != a):
            \\        return 1
            \\    return 0
        , .{ width, width, width, width });
        defer t.allocator.free(source);
        try expectValue(t.allocator, source, 1);
    }
    try expectValue(t.allocator, comparison, 1);
    try expectValue(t.allocator,
        \\domain D: i64:
        \\    def make(n: i64) -> D:
        \\        return wrap[D](n)
        \\
        \\
        \\def main() -> i64:
        \\    if D.make(-9223372036854775808) == D.make(-9223372036854775808) and D.make(-1) != D.make(1):
        \\        return 1
        \\    return 0
    , 1);
    try expectValue(t.allocator,
        \\domain D: bool:
        \\    def make(n: bool) -> D:
        \\        return wrap[D](n)
        \\
        \\
        \\def main() -> i64:
        \\    a = D.make(True)
        \\    b = D.make(False)
        \\    if a == a and b == b and a != b and not (a == b) and not (a != a):
        \\        return 1
        \\    return 0
    , 1);
}

test "domain equality preserves opacity and rejects mixed IDs arithmetic ordering and integer requirements" {
    const cases = [_]struct { source: []const u8, code: []const u8 = "E_TYPE" }{
        .{ .source =
        \\def main() -> i64:
        \\    _ = Id.make(1u64) == Other.make(1u64)
        \\    return 0
        },
        .{ .source =
        \\def main() -> i64:
        \\    _ = Id.make(1u64) != Other.make(1u64)
        \\    return 0
        },
        .{ .source =
        \\def main() -> i64:
        \\    _ = Id.make(1u64) == 1u64
        \\    return 0
        },
        .{ .source =
        \\def main() -> i64:
        \\    _ = Id.make(1u64) + Id.make(1u64)
        \\    return 0
        },
        .{ .source =
        \\def main() -> i64:
        \\    _ = Id.make(1u64) < Id.make(1u64)
        \\    return 0
        },
        .{ .source =
        \\def main() -> i64:
        \\    _ = unwrap(Id.make(1u64))
        \\    return 0
        , .code = "E_PRIVATE_DOMAIN" },
        .{ .source =
        \\def same[T: integer](a: T, b: T) -> bool:
        \\    return a == b
        \\
        \\
        \\def main() -> i64:
        \\    _ = same[Id](Id.make(1u64), Id.make(1u64))
        \\    return 0
        , .code = "E_GENERIC_ARGUMENT" },
    };
    for (cases) |case| {
        const source = try std.mem.concat(t.allocator, u8, &.{ declarations, case.source });
        defer t.allocator.free(source);
        var compilation = try language.Compilation.init(t.allocator, "bad.my", source);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "domain equality loops complete and traps name the failing frame" {
    var compilation = try language.Compilation.init(t.allocator, "loop.my", declarations ++
        \\def main() -> i64:
        \\    n = 0u64
        \\    while Id.make(n) != Id.make(10000u64):
        \\        n = n + 1u64
        \\    return i64(n)
    );
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 10000), (try native.run(&compilation)).value);
    const budgeted = try native.runWithOptions(&compilation, .{ .max_steps = 50 });
    try t.expectEqualStrings("R_STEP_LIMIT", budgeted.trap.code);
    var trapped = try language.Compilation.init(t.allocator, "order.my", declarations ++
        \\def left() -> Id:
        \\    return Id.make(1u64 // 0u64)
        \\
        \\
        \\def right() -> Id:
        \\    return Id.make(18446744073709551615u64 + 1u64)
        \\
        \\
        \\def main() -> i64:
        \\    _ = left() == right()
        \\    return 0
    );
    defer trapped.deinit();
    const outcome = try native.run(&trapped);
    try t.expectEqualStrings("R_DIVISION_BY_ZERO", outcome.trap.code);
    try t.expectEqualStrings("left", outcome.trap.frames[0].function);
}

// spec-case: VALUE-EQUALITY-1
test "value equality rejects an aggregate that reaches a callback field" {
    try reject(
        \\record Holder:
        \\    action: def(int) -> int effects()
        \\
        \\
        \\def identity(value: int) -> int effects():
        \\    return value
        \\
        \\
        \\def main() -> int:
        \\    first = Holder(action=identity)
        \\    second = Holder(action=identity)
        \\    if first == second:
        \\        return 1
        \\    return 0
    , "E_TYPE");
}
