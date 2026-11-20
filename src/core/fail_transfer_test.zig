//! Bare fail names share return transfers while written constructors keep markers.
const std = @import("std");
const language = @import("selka");
const support = @import("test_support.zig");
const ownership = @import("single_owner.zig");

fn accepted(a: std.mem.Allocator, source: []const u8) !void {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure);
}

fn repaired(a: std.mem.Allocator, source: []const u8, before: []const u8, after: []const u8) !void {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_OWN_MARKER", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.B2, failure.rule.?);
    try std.testing.expect(failure.repair == .explicit_fix);
    try std.testing.expectEqual(@as(usize, 1), failure.repair.explicit_fix.len);
    const edit = failure.repair.explicit_fix[0];
    const fixed = try std.mem.concat(a, u8, &.{ source[0..edit.span.start], edit.text, source[edit.span.end..] });
    const expected = try std.mem.replaceOwned(u8, a, source, before, after);
    try std.testing.expectEqualStrings(expected, fixed);
    try accepted(a, fixed);
}

test "F5 bare fail names preserve strict owned error IR and field carrier destruction" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const guest = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/lang/fail_transfers.selka", a, .limited(1 << 20));
    const source = try std.mem.concat(a, u8, &.{
        guest,
        \\
        \\func main() -> int:
        \\    if not test_F5_bare_owned_parameter_error():
        \\        return 1
        \\    if not test_F5_list_error():
        \\        return 1
        \\    if not test_F5_record_error():
        \\        return 1
        \\    if not test_F5_optional_errors():
        \\        return 1
        \\    if not test_F5_implicitly_injected_error():
        \\        return 1
        \\    if not test_F5_field_consumes_carrier_and_drops_sibling():
        \\        return 1
        \\    return 0
        \\
    });
    try accepted(a, source);
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const controls = [_][]const u8{ "message_error", "list_error", "record_error", "optional_error", "coerce_error", "field_error" };
    var inspected: usize = 0;
    var takes: usize = 0;
    for (module.functions.items) |function| {
        const selected = for (controls) |name| {
            if (std.mem.eql(u8, function.name, name)) break true;
        } else false;
        if (!selected) continue;
        inspected += 1;
        for (function.insts.items) |inst| {
            try std.testing.expect(inst.op != .list_copy and inst.op != .dict_copy and inst.op != .str_from_view);
            if (inst.op == .record_take) takes += 1;
        }
    }
    try std.testing.expectEqual(controls.len, inspected);
    try std.testing.expectEqual(@as(usize, 1), takes);
    const result = try @import("passes.zig").run(a, &module, .verify);
    try support.verified(a, &module, result.plans);
}

test "F5 redundant fail own deletes only the bare marker including injected and contracted errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_][]const u8{
        // migrate-embedded: skip intentional F5 redundant bare fail marker repair input
        \\func attempt(own message: str) -> int fails str:
        \\    fail own message
        \\func main() -> int:
        \\    return 0
        ,
        // migrate-embedded: skip intentional F5 redundant marker through implicit enum error injection
        \\enum Error:
        \\    message(text: str)
        \\func attempt(own message: str) -> int fails Error:
        \\    fail own message
        \\func main() -> int:
        \\    return 0
        ,
        // migrate-embedded: skip intentional F5 redundant fail marker with a postcondition
        \\@ensures(result > 0)
        \\func attempt(own message: str) -> int fails str:
        \\    fail own message
        \\func main() -> int:
        \\    return 0
        ,
    };
    for (cases) |source| try repaired(a, source, "fail own message", "fail message");
}

test "F5 written error constructors and fields keep their named child markers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_]struct { source: []const u8, before: []const u8, after: []const u8 }{
        .{
            .source =
            // migrate-embedded: skip intentional F5 missing marker inside written error constructor
            \\enum Error:
            \\    message(text: str)
            \\func attempt(own message: str) -> int fails Error:
            \\    fail Error.message(text=message)
            \\func main() -> int:
            \\    return 0
            ,
            .before = "text=message",
            .after = "text=own message",
        },
        .{
            .source =
            // migrate-embedded: skip intentional F5 missing marker inside written one-field record
            \\record Error:
            \\    message: str
            \\func attempt(own message: str) -> int fails Error:
            \\    fail Error(message=message)
            \\func main() -> int:
            \\    return 0
            ,
            .before = "message=message",
            .after = "message=own message",
        },
        .{
            .source =
            // migrate-embedded: skip intentional F5 missing marker inside written error list
            \\func attempt(own values: int[]) -> int fails int[][]:
            \\    fail [values]
            \\func main() -> int:
            \\    return 0
            ,
            .before = "[values]",
            .after = "[own values]",
        },
        .{
            .source =
            // migrate-embedded: skip intentional F5 missing marker inside written error Some
            \\func attempt(own values: int[]) -> int fails int[]?:
            \\    fail Some(values)
            \\func main() -> int:
            \\    return 0
            ,
            .before = "Some(values)",
            .after = "Some(own values)",
        },
        .{
            .source =
            // migrate-embedded: skip intentional F5 missing field carrier marker
            \\record Error:
            \\    message: str
            \\    sibling: int[]
            \\func attempt(own error: Error) -> int fails str:
            \\    fail error.message
            \\func main() -> int:
            \\    return 0
            ,
            .before = "fail error.message",
            .after = "fail own error.message",
        },
    };
    for (cases) |case| try repaired(a, case.source, case.before, case.after);
}

test "F5 bare fail exemption does not make borrowed errors transferable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func attempt(message: str) -> int fails str:
        \\    fail message
        \\func main() -> int:
        \\    return 0
    ;
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_BORROW", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.R1, failure.rule.?);
}

test "F5 failed value transfers run in forced debug verified release and ASAN modes" {
    try std.testing.expectEqual(@as(usize, 3), try @import("native_language_modes.zig").run(std.testing.allocator, .{
        .path = "tests/lang/fail_transfers.selka",
        .passed = 8,
        .label = "F5 fail transfers",
    }));
}
