//! S2-F source lowering and target specialization contracts.
const std = @import("std");
const support = @import("test_support.zig");

const known =
    \\func inc(x: int) -> int:
    \\    return x + 1
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut f = inc
    \\    out.print(f(41))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-S2-IR-1
test "a known function value lowers to a direct call before release inlining" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), known);
    try std.testing.expect(std.mem.indexOf(u8, text, "call i64 inc(41:i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call_indirect") == null);
}

const choice =
    \\func first(x: int) -> int:
    \\    return x * 3 + 7
    \\
    \\
    \\func second(x: int) -> int:
    \\    return x * 5 + 11
    \\
    \\
    \\func total(n: int, seed: int) -> int:
    \\    mut f = if (seed % 2 == 0) then (first) else (second)
    \\    mut acc = 0
    \\    for i in range(n):
    \\        acc += f(i)
    \\    return acc
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(total(4, 7))
    \\    return 0
    \\
;

const identity_comparison =
    \\func compare(left: func(int) -> int effects(), right: func(int) -> int effects()) -> bool effects():
    \\    return same_function(left, right)
    \\
    \\func first(value: int) -> int effects():
    \\    return value + 1
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(compare(first, first))
    \\    return 0
;

// spec-case: FUNCTION-IDENTITY-1
test "same_function lowers to a pointer comparison without making addresses insignificant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.llvmText(arena.allocator(), identity_comparison);
    try std.testing.expect(std.mem.indexOf(u8, text, "icmp eq ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, ") unnamed_addr") == null);
}

// spec-case: NEW-CORE-S2-IR-1
test "two constant callback targets become direct branches and unswitch the inner loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const before = try support.irText(arena.allocator(), choice);
    const after = try support.optimizedText(arena.allocator(), choice);
    try std.testing.expect(std.mem.indexOf(u8, before, "call_indirect") == null);
    try std.testing.expect(std.mem.indexOf(u8, after, "call_indirect") == null);
    try std.testing.expect(std.mem.indexOf(u8, after, "call i64 first") == null);
    try std.testing.expect(std.mem.indexOf(u8, after, "call i64 second") == null);
    try std.testing.expect(std.mem.indexOf(u8, after, "mul.proven i64") != null);
}

// spec-case: NEW-CORE-S2-IR-1
test "an escaped callback caller keeps unproved arithmetic as real source callees" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const entry = try std.mem.replaceOwned(u8, a, choice, "total(4, 7)", "apply(total, 4, 7)");
    const source = try std.mem.concat(a, u8, &.{ entry, "\nfunc apply(f: func(int, int) -> int, n: int, seed: int) -> int:\n    return f(n, seed)\n" });
    const text = try support.optimizedText(a, source);
    try std.testing.expect(std.mem.indexOf(u8, text, "call i64 first") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call i64 second") != null);
}

// spec-case: DEBUG-OPTIMIZE-1
test "loop optimization preserves early returns when the latch is unreachable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\func choose(xs: int[], flag: int) -> int:
        \\    for value in reversed(xs):
        \\        if flag > 0:
        \\            return value
        \\        return 0
        \\    return 7
        \\func main() -> int:
        \\    return choose([1, 2, 3], 1)
    ;
    const text = try support.optimizedText(arena.allocator(), source);
    try std.testing.expect(std.mem.indexOf(u8, text, "ret") != null);
}

const callable_keys = @import("callable_digest.zig");
const identity_ir = @import("ir.zig");
const key_context: callable_keys.Context = .{ .tool = @splat(7), .cpu = @splat(8), .build = "debug" };
const key_position: u8 = 0;
fn keyLocation(_: *const anyopaque, _: u32) @import("emit_llvm.zig").Location {
    return .{ .line = 1, .column = 1, .path = "fixture.my" };
}
const key_locator: @import("emit_llvm.zig").Locator = .{ .context = &key_position, .locate = keyLocation };

fn keyFixture(a: std.mem.Allocator, helper_value: i64, other_value: i64, indirect: bool) !identity_ir.Module {
    var module: identity_ir.Module = .{};
    const inner = try module.intern(a, .{ .@"fn" = .{ .params = &.{}, .ret = .i64 } });
    const parameters = try a.dupe(identity_ir.Type, &.{if (indirect) inner else .i64});
    const root_signature: identity_ir.Signature = .{ .params = parameters, .ret = .i64 };
    const callback = try module.intern(a, .{ .@"fn" = root_signature });
    var root = try support.Hand.init(a, &module, "root", root_signature);
    const result = if (indirect)
        try root.emit(.{ .op = .call_indirect, .ty = .i64, .a = try root.param(0), .data = try root.extra(&.{}) })
    else
        try root.emit(.{ .op = .call, .ty = .i64, .a = @fromBackingInt(1), .data = try root.extra(&.{}) });
    _ = try root.emit(.{ .op = .ret, .ty = .void, .a = result });
    _ = try root.finish();
    try keyLeaf(a, &module, "helper", helper_value);
    try keyLeaf(a, &module, "other", other_value);
    if (!indirect) module.functions.items[2].signature.params = parameters;
    try module.functions.append(a, .{ .name = callable_keys.prefix ++ "schema", .signature = .{ .params = try a.dupe(identity_ir.Type, &.{callback}), .ret = .str, .linkage = .runtime_c } });
    return module;
}
fn keyLeaf(a: std.mem.Allocator, module: *identity_ir.Module, name: []const u8, value: i64) !void {
    var leaf = try support.Hand.init(a, module, name, .{ .params = &.{}, .ret = .i64 });
    _ = try leaf.emit(.{ .op = .ret, .ty = .void, .a = try leaf.int(.i64, value) });
    _ = try leaf.finish();
}
fn issuedKey(a: std.mem.Allocator, module: *identity_ir.Module, context: callable_keys.Context) ![]const u8 {
    try callable_keys.prepare(a, module, key_locator, context, null);
    try support.verified(a, module, &.{});
    return module.strings.items[0];
}

// spec: FUNCTION-DIGEST-1
test "function_digest closure keys invalidate helper edits preserve unrelated changes and restore on revert" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var baseline = try keyFixture(a, 3, 9, false);
    var unrelated = try keyFixture(a, 3, 10, false);
    var helper_edit = try keyFixture(a, 4, 9, false);
    var reverted = try keyFixture(a, 3, 9, false);
    const expected = try issuedKey(a, &baseline, key_context);
    try std.testing.expectEqual(@as(usize, 64), expected.len);
    try std.testing.expectEqualStrings(expected, try issuedKey(a, &unrelated, key_context));
    try std.testing.expect(!std.mem.eql(u8, expected, try issuedKey(a, &helper_edit, key_context)));
    try std.testing.expectEqualStrings(expected, try issuedKey(a, &reverted, key_context));
}

// spec-case: FUNCTION-DIGEST-1
test "function_digest unknown indirect calls bind all compatible targets and context" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var baseline = try keyFixture(a, 3, 9, true);
    var edited = try keyFixture(a, 3, 10, true);
    var mode = try keyFixture(a, 3, 9, true);
    var tool = try keyFixture(a, 3, 9, true);
    var cpu = try keyFixture(a, 3, 9, true);
    const expected = try issuedKey(a, &baseline, key_context);
    try std.testing.expect(!std.mem.eql(u8, expected, try issuedKey(a, &edited, key_context)));
    try std.testing.expect(!std.mem.eql(u8, expected, try issuedKey(a, &mode, .{ .tool = key_context.tool, .cpu = key_context.cpu, .build = "release" })));
    try std.testing.expect(!std.mem.eql(u8, expected, try issuedKey(a, &tool, .{ .tool = @splat(9), .cpu = key_context.cpu, .build = key_context.build })));
    try std.testing.expect(!std.mem.eql(u8, expected, try issuedKey(a, &cpu, .{ .tool = key_context.tool, .cpu = @splat(9), .build = key_context.build })));
}

// spec-case: FUNCTION-DIGEST-1
test "function_digest handles recursive closures and refuses external or self-digest authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var recursive = try keyFixture(a, 3, 9, false);
    _ = try recursive.functions.items[1].insts.append(a, .{ .op = .call, .ty = .i64, .a = @fromBackingInt(1) });
    var no_tool = try keyFixture(a, 3, 9, false);
    var external = try keyFixture(a, 3, 9, false);
    external.functions.items[1].signature.linkage = .extern_c;
    external.functions.items[1].insts = .empty;
    external.functions.items[1].blocks = .empty;
    const raw = try @import("test_runner_identity.zig").Shared.build(a, &recursive, key_locator);
    try std.testing.expect((try callable_keys.digest(a, &recursive, raw, 0, "schema", key_context)) != null);
    try std.testing.expectEqualStrings("", try issuedKey(a, &no_tool, .{}));
    const external_raw = try @import("test_runner_identity.zig").Shared.build(a, &external, key_locator);
    try std.testing.expect((try callable_keys.digest(a, &external, external_raw, 0, "schema", key_context)) == null);
    const self_source = "func identify(value: int) -> str effects(managed_allocation):\n    return function_digest(identify)\nfunc main() -> int:\n    _ = function_digest(identify)\n    return 0\n";
    var refusal: @import("build.zig").Refusal = .{};
    var self = try support.buildSource(a, self_source, &refusal);
    try callable_keys.prepare(a, &self, key_locator, key_context, null);
    try std.testing.expectEqual(@as(usize, 1), self.strings.items.len);
    try std.testing.expectEqualStrings("", self.strings.items[0]);
}

fn schemaKey(a: std.mem.Allocator, field: []const u8, extra: []const u8) ![]const u8 {
    const format = "{s}record Output:\n    {s}: int\n" ++
        "func compute(value: int) -> Output effects(managed_allocation):\n    return Output({s}=value)\n" ++
        "func main() -> int:\n    _ = function_digest(compute)\n    return 0\n";
    const source = try std.fmt.allocPrint(a, format, .{ extra, field, field });
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    return issuedKey(a, &module, key_context);
}

// spec-case: FUNCTION-DIGEST-1
test "function_digest binds nominal result schema without binding unrelated catalog ordinals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const baseline = try schemaKey(a, "value", "");
    const field_edit = try schemaKey(a, "count", "");
    const unrelated = try schemaKey(a, "value", "record Other:\n    number: bool\n");
    try std.testing.expectEqual(@as(usize, 64), baseline.len);
    try std.testing.expect(!std.mem.eql(u8, baseline, field_edit));
    try std.testing.expectEqualStrings(baseline, unrelated);
}
