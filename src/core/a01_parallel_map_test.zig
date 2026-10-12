//! Bounded map captures and result transfer through the generated range worker.
const std = @import("std");
const printDiagnostics = std.debug.print;
const language = @import("mylang");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const contract = @import("single_owner.zig");
const passes = @import("passes.zig");

const source =
    \\import parallel
    \\func transform(value: str) -> str:
    \\    return value + "!"
    \\func main(out: Stream) -> int:
    \\    const result = parallel.map(["input-" + str(7)], transform)
    \\    out.print(result[0])
    \\    return 0
;

const Entry = struct {
    text: []const u8,
    /// Load the entry and leave standard imports to the embedded loader.
    pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "result_support.my")) return a.dupe(u8, result_library);
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        return a.dupe(u8, (@as(*Entry, @ptrCast(@alignCast(context.?)))).text);
    }
};

fn module(a: std.mem.Allocator, input: []const u8) !ir.Module {
    var context: Entry = .{ .text = input };
    var project: language.embedded_project.Program = undefined;
    project.init(a, .{ .context = &context, .read = Entry.read }) catch |err| {
        for (project.compilation.diagnostics.items.items) |issue| printDiagnostics("{s}: {s} at {d}\n", .{ issue.code, issue.message, issue.span.start });
        return err;
    };
    const checked = project.compilation.program.?;
    var failure: contract.Failure = .{};
    try contract.checkMode(a, checked, &failure, true);
    var refusal: @import("build.zig").Refusal = .{};
    return @import("build.zig").buildExecutable(a, .{ .program = checked, .source = project.compilation.src, .single_owner = true, .zero_rc = true }, &refusal);
}

// spec-case: NEW-CORE-ZERO-RC-TASKS-2
test "zero RC map worker borrows one source list and returns one owned chunk without element boxes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m = try module(a, source);
    try support.verified(a, &m, &.{});
    var found: usize = 0;
    for (m.functions.items) |function| {
        if (!std.mem.startsWith(u8, function.name, "<parallel.map.worker.")) continue;
        found += 1;
        try std.testing.expectEqual(.list, m.kind(function.signature.ret));
        const capture = m.compound(m.compound(function.signature.params[0]).box).record;
        try std.testing.expectEqual(@as(usize, 4), capture.len);
        try std.testing.expectEqual(.list, m.kind(capture[0]));
        try std.testing.expectEqual(@as(usize, 1), function.loops.items.len);
        var marked = false;
        for (function.insts.items) |inst| {
            try std.testing.expect(inst.op != .box_make);
            if (inst.op == .call and std.mem.eql(u8, m.functions.items[inst.a.index()].name, "myl_core_task_item")) marked = true;
        }
        try std.testing.expect(marked);
    }
    try std.testing.expectEqual(@as(usize, 1), found);
    const result = try passes.run(a, &m, .verify);
    try support.verified(a, &m, result.plans);
    var failure: contract.Failure = .{};
    try contract.verifyLowered(&m, &failure);
}

const result_source =
    \\import parallel
    \\func attempt(value: int) -> Result[str, str]:
    \\    if value % 2 == 0:
    \\        return Ok("ok-" + str(value))
    \\    return Err("bad-" + str(value))
    \\func size(value: Result[str, str]) -> int:
    \\    match value:
    \\        case Ok(text):
    \\            return len(text)
    \\        case Err(text):
    \\            return len(text)
    \\func main(out: Stream) -> int:
    \\    mut values = parallel.map([0, 1, 2, 3], attempt)
    \\    const saved = values.copy()
    \\    mut total = len(values)
    \\    for value in values:
    \\        total += size(value)
    \\    match values.pop():
    \\        case Ok(text):
    \\            total += len(text)
    \\        case Err(text):
    \\            total += len(text)
    \\    _ = values
    \\    const sizes = parallel.map(saved, size)
    \\    out.print(total, sizes[0], sizes[1], sizes[2], sizes[3])
    \\    _ = parallel.map([4, 5], attempt)
    \\    return 0
;

// spec: NEW-CORE-ZERO-RC-RESULT-LISTS-1
test "A01 Result list map preserves managed payload ownership and explicit acknowledgment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m = try module(a, result_source);
    const result = try passes.run(a, &m, .verify);
    try support.verified(a, &m, result.plans);
    var failure: contract.Failure = .{};
    try contract.verifyLowered(&m, &failure);
}

fn refusesResultList(a: std.mem.Allocator, body: []const u8, code: []const u8) !void {
    var unit = try language.Compilation.init(a, "a01-results.my", body);
    defer unit.deinit();
    try std.testing.expectError(error.SourceError, unit.check());
    try std.testing.expectEqualStrings(code, unit.diagnostics.items[0].code);
}

// spec-case: NEW-CORE-ZERO-RC-RESULT-LISTS-1
test "A01 Result list rejects implicit abandonment overwrite clear and inspection loss" {
    const prefix = "func main() -> int:\n    mut values: Result[int, int][] = [Ok(3), Err(7)]\n";
    const cases = .{
        .{ "    return 0\n", "E_RESULT_UNHANDLED" },
        .{ "    return len(values)\n", "E_RESULT_UNHANDLED" },
        .{ "    values = []\n    _ = values\n    return 0\n", "E_RESULT_OVERWRITE" },
        .{ "    values.clear()\n    _ = values\n    return 0\n", "E_RESULT_OPERATION" },
        .{ "    _ = values[0]\n    return 0\n", "E_RESULT_UNHANDLED" },
        .{ "    for value in values:\n        _ = value\n        break\n    return 0\n", "E_RESULT_UNHANDLED" },
        .{ "    for value in values:\n        _ = value\n        return 0\n    _ = values\n    return 0\n", "E_RESULT_UNHANDLED" },
        .{ "    _ = values\n    _ = values.copy()\n    return 0\n", "E_RESULT_CONSUMED" },
        .{ "    _ = values[0:1]\n    _ = values\n    return 0\n", "E_RESULT_OPERATION" },
        .{ "    values.sort(reverse=True)\n    _ = values\n    return 0\n", "E_RESULT_OPERATION" },
        .{ "    const clone = values.copy()\n    _ = values\n    return 0\n", "E_RESULT_UNHANDLED" },
        .{ "    for value in values:\n        continue\n    _ = values\n    return 0\n", "E_RESULT_UNHANDLED" },
        .{ "    _ = list(values)\n    _ = values\n    return 0\n", "E_RESULT_OPERATION" },
        .{ "    _ = sorted(values)\n    _ = values\n    return 0\n", "E_RESULT_OPERATION" },
        .{ "    for value in reversed(values):\n        _ = value\n    _ = values\n    return 0\n", "E_RESULT_OPERATION" },
    };
    inline for (cases) |case| try refusesResultList(std.testing.allocator, prefix ++ case[0], case[1]);
}

const result_library =
    \\public func make(value: int) -> Result[str, str][]:
    \\    return [Ok("ok-" + str(value)), Err("bad-" + str(value))]
    \\public func duplicate[T: storable](values: T[]) -> T[]:
    \\    const saved = values.copy()
    \\    _ = values
    \\    return saved
;

// spec-case: NEW-CORE-ZERO-RC-RESULT-LISTS-1
test "A01 public Result list interfaces preserve storage and handling independently" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m = try module(a,
        \\import result_support
        \\func main() -> int:
        \\    const values = result_support.make(3)
        \\    const copied = result_support.duplicate(values)
        \\    for value in copied:
        \\        _ = value
        \\    _ = copied
        \\    return 0
    );
    const optimized = try passes.run(a, &m, .verify);
    try support.verified(a, &m, optimized.plans);
    var context: Entry = .{ .text =
        \\import result_support
        \\func main() -> int:
        \\    const values = result_support.make(3)
        \\    return len(values)
    };
    var project: language.embedded_project.Program = undefined;
    try std.testing.expectError(error.SourceError, project.init(a, .{ .context = &context, .read = Entry.read }));
    try std.testing.expectEqualStrings("E_RESULT_UNHANDLED", project.compilation.diagnostics.items.items[0].code);
}

// spec-case: NEW-CORE-ZERO-RC-RESULT-LISTS-1
test "A01 pending Results retain resource capability container boxing and generic copy boundaries" {
    try refusesResultList(std.testing.allocator,
        \\resource File: filesystem
        \\func main() -> int:
        \\    const values: Result[File, str][] = []
        \\    _ = values
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try refusesResultList(std.testing.allocator,
        \\func main() -> int:
        \\    const values: Result[Filesystem, str][] = []
        \\    _ = values
        \\    return 0
    , "E_LIST_CAPABILITY");
    try refusesResultList(std.testing.allocator,
        \\func main() -> int:
        \\    const values: dict[int, Result[int, int]] = {}
        \\    _ = values
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try refusesResultList(std.testing.allocator,
        \\func main() -> int:
        \\    const values: set[Result[int, int]] = {}
        \\    _ = values
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try refusesResultList(std.testing.allocator,
        \\record Node:
        \\    value: Result[int, int]
        \\    next: Node?
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try refusesResultList(std.testing.allocator,
        \\record Box[T]:
        \\    value: T
        \\record Pending:
        \\    values: Result[int, int][]
        \\record Bad:
        \\    value: Box[Pending]
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try refusesResultList(std.testing.allocator,
        \\func ignore[T: storable](value: T) -> int:
        \\    return 0
        \\func main() -> int:
        \\    return ignore(3)
    , "E_RESULT_UNHANDLED");
}
