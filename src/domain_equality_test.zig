//! Scalar domain equality preserves nominal boundaries without exposing backing values.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const typed = @import("typed.zig");
const declarations =
    // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
    \\public domain Id: u64:
    \\    func make(n: u64) -> Id effects():
    \\        return wrap[Id](n)
    \\
    \\
    \\domain Other: u64:
    \\    func make(n: u64) -> Other effects():
    \\        return wrap[Other](n)
    \\
    \\
    \\
;
const comparison = declarations ++
    \\func main() -> i64:
    \\    if Id.make(18446744073709551615u64) == Id.make(18446744073709551615u64):
    \\        return 1
    \\    return 0
;

fn expectValue(allocator: std.mem.Allocator, source: []const u8, expected: i64) !void {
    var compilation = try recognizedCompilation(allocator, "equality.selka", source);
    defer compilation.deinit();
    try expectSourceError(compilation.check());
    try t.expect(hasCode(compilation.diagnostics.items, "E_DOMAIN_REMOVED"));
    const modern = try recordCounterpart(allocator, compilation.src.bytes);
    defer allocator.free(modern);
    var current = try language.Compilation.init(allocator, "record-equality.selka", modern);
    defer current.deinit();
    try t.expectEqual(expected, (try native.run(&current)).value);
}

fn reject(source: []const u8, code: []const u8) !void {
    var compilation = try recognizedCompilation(t.allocator, "equality.selka", source);
    defer compilation.deinit();
    try expectSourceError(compilation.check());
    try t.expect(hasCode(compilation.diagnostics.items, code));
}

fn allocationFailures(allocator: std.mem.Allocator) !void {
    try expectValue(allocator, comparison, 1);
}

test "domain equality releases operands on allocation failures" {
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocationFailures, .{});
}

test "domain equality emits native comparisons without a feature rejection" {
    var compilation = try recognizedCompilation(t.allocator, "native.selka", comparison);
    defer compilation.deinit();
    try expectSourceError(compilation.check());
    try t.expect(hasCode(compilation.diagnostics.items, "E_DOMAIN_REMOVED"));
    const modern = try recordCounterpart(t.allocator, compilation.src.bytes);
    defer t.allocator.free(modern);
    var current = try language.Compilation.init(t.allocator, "record-native.selka", modern);
    defer current.deinit();
    try t.expectEqual(@as(i64, 1), (try native.run(&current)).value);
}

const Modules = struct {
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.selka")) return allocator.dupe(u8, if (context == null)
            \\import left as a
            \\import bridge as b
            \\
            \\
            \\func main() -> i64:
            \\    if a.Id.make(9u64) == b.make(9u64):
            \\        return 1
            \\    return 0
        else
            \\import left as a
            \\import right as b
            \\
            \\
            \\func main() -> i64:
            \\    _ = a.Id.make(9u64) == b.Id.make(9u64)
            \\    return 0
        );
        if (std.mem.eql(u8, path, "bridge.selka")) return allocator.dupe(u8,
            \\import left as alias
            \\
            \\
            \\public func make(n: u64) -> alias.Id effects():
            \\    return alias.Id.make(n)
        );
        if (std.mem.eql(u8, path, "left.selka")) return allocator.dupe(u8, "" ++ declarations);
        if (std.mem.eql(u8, path, "right.selka")) return allocator.dupe(u8, "" ++ declarations);
        return error.NotFound;
    }
    fn readErased(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const bytes = try read(context, allocator, path, limit);
        defer allocator.free(bytes);
        return eraseEffects(allocator, bytes);
    }
    fn readRecords(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "left.selka") or std.mem.eql(u8, path, "right.selka"))
            return allocator.dupe(u8, record_declarations ++ "public func make(n: u64) -> Id:\n    return Id(value=n)\n");
        const bytes = try readErased(context, allocator, path, limit);
        defer allocator.free(bytes);
        const first = try std.mem.replaceOwned(u8, allocator, bytes, "a.Id.make(", "a.Id(value=");
        defer allocator.free(first);
        const second = try std.mem.replaceOwned(u8, allocator, first, "b.Id.make(", "b.Id(value=");
        defer allocator.free(second);
        return std.mem.replaceOwned(u8, allocator, second, "alias.Id.make(", "alias.make(");
    }
};

test "domain equality resolves declaration identity through module aliases" {
    var marker: u8 = 0;
    for ([_]?*anyopaque{ null, &marker }) |context| {
        var original = language.project.Project.init(t.allocator);
        defer original.deinit();
        try original.load(.{ .context = context, .read = Modules.read }, "main", .{});
        if (language.interfaces.build(&original)) |_| return error.TestExpectedError else |err| {
            if (err != error.SourceError) return err;
        }
        try t.expectEqualStrings("E_EFFECTS_REMOVED", original.problem.?.code);
        var project = language.project.Project.init(t.allocator);
        defer project.deinit();
        try project.load(.{ .context = context, .read = Modules.readErased }, "main", .{});
        var index = try language.interfaces.build(&project);
        var compilation = try language.project_compile.Compilation.init(&index);
        if (context == null) {
            try expectSourceError(compilation.check());
            try t.expect(hasCode(compilation.diagnostics.items.items, "E_DOMAIN_REMOVED"));
        } else {
            try expectSourceError(compilation.check());
            try t.expect(hasCode(compilation.diagnostics.items.items, "E_TYPE"));
        }
        var records = language.project.Project.init(t.allocator);
        defer records.deinit();
        try records.load(.{ .context = context, .read = Modules.readRecords }, "main", .{});
        var record_index = try language.interfaces.build(&records);
        var current = try language.project_compile.Compilation.init(&record_index);
        if (context == null) {
            try current.check();
            try t.expectEqual(@as(i64, 1), (try native.run(&current)).value);
        } else {
            try expectSourceError(current.check());
            try t.expect(hasCode(current.diagnostics.items.items, "E_TYPE"));
        }
    }
}

// spec: DOMAIN-EQUALITY-1
test "domain equality compares every scalar backing by value" {
    for ([_][]const u8{ "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64" }) |width| {
        const source = try std.fmt.allocPrint(t.allocator,
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\domain D: {s}:
            \\    func make(n: {s}) -> D:
            \\        return wrap[D](n)
            \\
            \\
            \\func main() -> i64:
            \\    const a = D.make(7{s})
            \\    const b = D.make(8{s})
            \\    if a == a and a != b and not (a == b) and not (a != a):
            \\        return 1
            \\    return 0
        , .{ width, width, width, width });
        defer t.allocator.free(source);
        try expectValue(t.allocator, source, 1);
    }
    try expectValue(t.allocator, comparison, 1);
    try expectValue(t.allocator,
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\domain D: i64:
        \\    func make(n: i64) -> D:
        \\        return wrap[D](n)
        \\
        \\
        \\func main() -> i64:
        \\    if D.make(-9223372036854775808) == D.make(-9223372036854775808) and D.make(-1) != D.make(1):
        \\        return 1
        \\    return 0
    , 1);
    try expectValue(t.allocator,
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\domain D: bool:
        \\    func make(n: bool) -> D:
        \\        return wrap[D](n)
        \\
        \\
        \\func main() -> i64:
        \\    mut a = D.make(True)
        \\    mut b = D.make(False)
        \\    if a == a and b == b and a != b and not (a == b) and not (a != a):
        \\        return 1
        \\    return 0
    , 1);
}

test "domain equality preserves opacity and rejects mixed IDs arithmetic ordering and integer requirements" {
    const cases = [_]struct { source: []const u8, code: []const u8 = "E_TYPE" }{
        .{ .source =
        \\func main() -> i64:
        \\    _ = Id.make(1u64) == Other.make(1u64)
        \\    return 0
        },
        .{ .source =
        \\func main() -> i64:
        \\    _ = Id.make(1u64) != Other.make(1u64)
        \\    return 0
        },
        .{ .source =
        \\func main() -> i64:
        \\    _ = Id.make(1u64) == 1u64
        \\    return 0
        },
        .{ .source =
        \\func main() -> i64:
        \\    _ = Id.make(1u64) + Id.make(1u64)
        \\    return 0
        },
        .{ .source =
        \\func main() -> i64:
        \\    _ = Id.make(1u64) < Id.make(1u64)
        \\    return 0
        },
        .{
            .source =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\func main() -> i64:
            \\    _ = unwrap(Id.make(1u64))
            \\    return 0
            ,
            .code = "E_PRIVATE_DOMAIN",
        },
        .{ .source =
        \\func same[T: integer](a: T, b: T) -> bool:
        \\    return a == b
        \\
        \\
        \\func main() -> i64:
        \\    _ = same[Id](Id.make(1u64), Id.make(1u64))
        \\    return 0
        , .code = "E_GENERIC_ARGUMENT" },
    };
    for (cases) |case| {
        const source = try std.mem.concat(t.allocator, u8, &.{ declarations, case.source });
        defer t.allocator.free(source);
        var compilation = try recognizedCompilation(t.allocator, "bad.selka", source);
        defer compilation.deinit();
        try expectSourceError(compilation.check());
        try t.expect(hasCode(compilation.diagnostics.items, case.code));
    }
}

test "domain equality loops complete and traps name the failing frame" {
    var compilation = try recognizedCompilation(t.allocator, "loop.selka", declarations ++
        \\func main() -> i64:
        \\    mut n = 0u64
        \\    while Id.make(n) != Id.make(10000u64):
        \\        n = n + 1u64
        \\    return i64(n)
    );
    defer compilation.deinit();
    try expectSourceError(compilation.check());
    try t.expect(hasCode(compilation.diagnostics.items, "E_DOMAIN_REMOVED"));
    var trapped = try recognizedCompilation(t.allocator, "order.selka", declarations ++
        \\func left() -> Id:
        \\    return Id.make(1u64 // 0u64)
        \\
        \\
        \\func right() -> Id:
        \\    return Id.make(18446744073709551615u64 + 1u64)
        \\
        \\
        \\func main() -> i64:
        \\    _ = left() == right()
        \\    return 0
    );
    defer trapped.deinit();
    try expectSourceError(trapped.check());
    try t.expect(hasCode(trapped.diagnostics.items, "E_DOMAIN_REMOVED"));
    const loop_source = try recordCounterpart(t.allocator, compilation.src.bytes);
    defer t.allocator.free(loop_source);
    var current_loop = try language.Compilation.init(t.allocator, "record-loop.selka", loop_source);
    defer current_loop.deinit();
    try t.expectEqual(@as(i64, 10000), (try native.run(&current_loop)).value);
    const trap_source = try recordCounterpart(t.allocator, trapped.src.bytes);
    defer t.allocator.free(trap_source);
    var current_trap = try language.Compilation.init(t.allocator, "record-order.selka", trap_source);
    defer current_trap.deinit();
    const run = try native.run(&current_trap);
    try t.expectEqualStrings("R_DIVISION_BY_ZERO", run.trap.code);
    try t.expectEqualStrings("left", run.trap.frames[0].function);
}

// spec-case: VALUE-EQUALITY-1
test "value equality rejects an aggregate that reaches a callback field" {
    try reject(
        \\record Holder:
        \\    action: func(int) -> int effects()
        \\
        \\
        \\func identity(value: int) -> int effects():
        \\    return value
        \\
        \\
        \\func main() -> int:
        \\    mut first = Holder(action=identity)
        \\    mut second = Holder(action=identity)
        \\    if first == second:
        \\        return 1
        \\    return 0
    , "E_TYPE");
}

fn hasCode(items: anytype, code: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item.code, code)) return true;
    return false;
}

fn expectSourceError(outcome: anyerror!void) anyerror!void {
    outcome catch |err| {
        if (err == error.SourceError) return;
        return err;
    };
    return error.TestExpectedError;
}

fn eraseEffects(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]u8 {
    return std.mem.replaceOwned(u8, allocator, bytes, " effects()", "");
}
fn recognizedCompilation(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !language.Compilation {
    if (std.mem.indexOf(u8, bytes, " effects()") != null) {
        var original = try language.Compilation.init(allocator, path, bytes);
        defer original.deinit();
        try expectSourceError(original.check());
        try t.expectEqualStrings("E_EFFECTS_REMOVED", original.diagnostics.items[0].code);
    }
    const current = try eraseEffects(allocator, bytes);
    defer allocator.free(current);
    return language.Compilation.init(allocator, path, current);
}
const record_declarations = "public record Id:\n    value: u64\nrecord Other:\n    value: u64\n";
// These fixtures have only identity factories `return wrap[D](n)`. Keep the
// original recognizer check and execute an explicit ordinary-record analogue.
fn recordCounterpart(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const old = try eraseEffects(allocator, declarations);
    defer allocator.free(old);
    if (std.mem.startsWith(u8, bytes, old)) {
        const first = try std.mem.replaceOwned(u8, allocator, bytes[old.len..], "Id.make(", "Id(value=");
        defer allocator.free(first);
        const second = try std.mem.replaceOwned(u8, allocator, first, "Other.make(", "Other(value=");
        defer allocator.free(second);
        return std.mem.concat(allocator, u8, &.{ record_declarations, second });
    }
    const domain_head = "domain D: ";
    const start = std.mem.indexOf(u8, bytes, domain_head) orelse return error.TestUnexpectedResult;
    const tail = bytes[start + domain_head.len ..];
    const end = std.mem.indexOfScalar(u8, tail, ':') orelse return error.TestUnexpectedResult;
    const main = std.mem.indexOf(u8, bytes, "func main()") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, bytes[0..main], "return wrap[D](n)") != null);
    const prefix = try std.fmt.allocPrint(allocator, "record D:\n    value: {s}\n", .{tail[0..end]});
    defer allocator.free(prefix);
    const body = try std.mem.replaceOwned(u8, allocator, bytes[main..], "D.make(", "D(value=");
    defer allocator.free(body);
    return std.mem.concat(allocator, u8, &.{ prefix, body });
}
