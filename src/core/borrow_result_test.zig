//! Actual borrowed result provenance through wrappers and final mutable owners.
const std = @import("std");
const ir = @import("ir.zig");
const valid = @import("borrow_result.zig").valid;

test "wrapped result provenance rejects an undeclared same-family argument" {
    const builder = @import("test_builder.zig");
    const verify = @import("verify_ir.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const optional = try module.intern(a, .{ .@"union" = &.{ .void, .str_view } });
    var b: builder.Builder = .{ .arena = a, .function = .{ .name = "wrapped", .signature = .{
        .params = &.{ .str, .str },
        .ret = optional,
        .borrow = .{ .path = &.{.{ .payload = 1 }}, .sources = &.{.{ .argument = 0 }} },
    } } };
    const entry = try b.block();
    const declared = try b.detached(.{ .op = .param, .ty = .str, .data = 0 });
    const undeclared = try b.detached(.{ .op = .param, .ty = .str, .data = 1 });
    const zero = try b.constant(.u64, 0);
    const length = try b.constant(.u64, 1);
    const view = try b.put(entry, .{ .op = .str_view_of, .ty = .str_view, .a = undeclared, .b = zero, .data = try b.extra(&.{length}) });
    const some = try b.put(entry, .{ .op = .union_make, .ty = optional, .a = view, .data = 1 });
    _ = try b.put(entry, .{ .op = .ret, .ty = .void, .a = some });
    try module.functions.append(a, b.function);
    var failure: verify.Failure = .{};
    try std.testing.expectError(error.InvalidIr, verify.verifyModule(a, &module, &failure));
    try std.testing.expect(std.mem.indexOf(u8, failure.reason, "declared argument or final owner") != null);
    try std.testing.expectError(error.Unsupported, @import("own.zig").function(a, &module, &module.functions.items[0], .{}));
    module.functions.items[0].insts.items[view.index()].a = declared;
    try verify.verifyModule(a, &module, &failure);
    _ = try @import("own.zig").function(a, &module, &module.functions.items[0], .{});
}

test "mutable borrowed result provenance names the final returned owner" {
    const builder = @import("test_builder.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const returned = try module.intern(a, .{ .record = &.{ .str_view, .str } });
    const fresh = try builder.helper(a, &module, "fresh_text", &.{}, .str);
    var b: builder.Builder = .{ .arena = a, .function = .{ .name = "replace", .signature = .{
        .params = &.{.str},
        .ret = returned,
        .passing = .{ .owned = 1 },
        .borrow = .{ .path = &.{.{ .field = 0 }}, .sources = &.{.{ .result = &.{.{ .field = 1 }} }} },
    } } };
    const entry = try b.block();
    const old = try b.detached(.{ .op = .param, .ty = .str, .data = 0 });
    const owner = try b.call(entry, &module, fresh, &.{});
    const zero = try b.constant(.u64, 0);
    const length = try b.constant(.u64, 1);
    const view = try b.put(entry, .{ .op = .str_view_of, .ty = .str_view, .a = old, .b = zero, .data = try b.extra(&.{length}) });
    const result = try b.put(entry, .{ .op = .record_make, .ty = returned, .data = try b.extra(&.{ view, owner }) });
    _ = try b.put(entry, .{ .op = .ret, .ty = .void, .a = result });
    try std.testing.expect(!try valid(a, &module, &b.function, result));
    try module.functions.append(a, b.function);
    const function = &module.functions.items[module.functions.items.len - 1];
    try std.testing.expectError(error.Unsupported, @import("own.zig").function(a, &module, function, .{}));
    function.insts.items[view.index()].a = owner;
    try std.testing.expect(try valid(a, &module, function, result));
    const stats = try @import("own.zig").function(a, &module, function, .{});
    try std.testing.expectEqual(@as(u32, 1), stats.drops);
}

test "O3 final owner at parameter seventy carries a returned list loan" {
    const builder = @import("test_builder.zig");
    const verify = @import("verify_ir.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    const view_type = try module.intern(a, .{ .list_view = .i64 });
    const returned = try module.intern(a, .{ .record = &.{ view_type, list } });
    const params = try a.alloc(ir.Type, 70);
    @memset(params, .i64);
    params[69] = list;
    var b: builder.Builder = .{ .arena = a, .function = .{ .name = "last_owner", .signature = .{
        .params = params,
        .ret = returned,
        .passing = .{ .extra_owned = &.{69} },
        .borrow = .{ .path = &.{.{ .field = 0 }}, .sources = &.{.{ .result = &.{.{ .field = 1 }} }} },
    } } };
    const entry = try b.block();
    const owner = try b.detached(.{ .op = .param, .ty = list, .data = 69 });
    const zero = try b.constant(.i64, 0);
    const end = try b.constant(.i64, 1);
    const view = try b.put(entry, .{ .op = .list_slice_view, .ty = view_type, .a = owner, .b = zero, .data = try b.extra(&.{end}) });
    const result = try b.put(entry, .{ .op = .record_make, .ty = returned, .data = try b.extra(&.{ view, owner }) });
    _ = try b.put(entry, .{ .op = .ret, .ty = .void, .a = result });
    try module.functions.append(a, b.function);
    var failure: verify.Failure = .{};
    try verify.verifyModule(a, &module, &failure);
    const stats = try @import("own.zig").function(a, &module, &module.functions.items[0], .{});
    try std.testing.expectEqual(@as(u32, 0), stats.drops);
    try verify.verifyModule(a, &module, &failure);
}

test "an ordinary owning result cannot return an undeclared parameter borrow" {
    const builder = @import("test_builder.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    var b: builder.Builder = .{ .arena = a, .function = .{ .name = "undeclared", .signature = .{ .params = &.{.str}, .ret = .str } } };
    const entry = try b.block();
    const parameter = try b.detached(.{ .op = .param, .ty = .str, .data = 0 });
    _ = try b.put(entry, .{ .op = .ret, .ty = .void, .a = parameter });
    try module.functions.append(a, b.function);
    try std.testing.expectError(error.Unsupported, @import("own.zig").function(a, &module, &module.functions.items[0], .{}));
}

test "O3 const borrowed list calls preserve sources without literal slices" {
    const support = @import("test_support.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a,
        \\func choose(left: str[], right: str[]) -> str[] from left, right:
        \\    return right
        \\func final(mut values: str[]) -> str[] from values:
        \\    return values
        \\func main() -> int:
        \\    const selected = choose(["left"], ["right"])
        \\    const alias = selected
        \\    mut values = ["mutable"]
        \\    const borrowed = final(mut values)
        \\    return len(selected) + len(alias) + len(borrowed)
    , &refusal);
    var sources: usize = 0;
    for (module.functions.items) |function| {
        if (std.mem.eql(u8, function.name, "choose")) sources = function.signature.borrow.sources.len;
        for (function.insts.items) |inst| try std.testing.expect(inst.op != .list_copy);
    }
    try std.testing.expectEqual(@as(usize, 2), sources);
    _ = try @import("own.zig").run(a, &module, .{});
    try support.verified(a, &module, &.{});
}

const DropKinds = struct { borrowed: usize = 0, owned_result: usize = 0 };

fn dropKinds(module: *const ir.Module) DropKinds {
    var kinds: DropKinds = .{};
    for (module.functions.items) |function| for (function.insts.items) |instruction| {
        if (instruction.op != .drop) continue;
        const ty = function.inst(function.resolve(instruction.a)).ty;
        if (!module.managed(ty)) kinds.borrowed += 1;
        if (module.kind(ty) == .@"union" and module.managed(ty)) kinds.owned_result += 1;
    };
    return kinds;
}

test "O3 nested owned borrowed-result wrappers transfer through constructors and phi" {
    const builder = @import("test_builder.zig");
    const verify = @import("verify_ir.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const result_type = try module.intern(a, .{ .@"union" = &.{ .str_view, .str } });
    const optional = try module.intern(a, .{ .@"union" = &.{ .void, result_type } });
    const fresh = try builder.helper(a, &module, "fresh_error", &.{}, .str);
    var b: builder.Builder = .{ .arena = a, .function = .{ .name = "nested_join", .signature = .{
        .params = &.{ .str, .bool },
        .ret = optional,
        .borrow = .{ .path = &.{ .{ .payload = 1 }, .{ .payload = 0 } }, .sources = &.{.{ .argument = 0 }} },
    } } };
    const entry = try b.block();
    const success = try b.block();
    const failure = try b.block();
    const join = try b.block();
    const source = try b.detached(.{ .op = .param, .ty = .str, .data = 0 });
    const condition = try b.detached(.{ .op = .param, .ty = .bool, .data = 1 });
    const zero = try b.constant(.u64, 0);
    const length = try b.constant(.u64, 1);
    try b.branch(entry, condition, success, failure);
    const view = try b.put(success, .{ .op = .str_view_of, .ty = .str_view, .a = source, .b = zero, .data = try b.extra(&.{length}) });
    const ok = try b.put(success, .{ .op = .union_make, .ty = result_type, .a = view, .data = 0 });
    const some_ok = try b.put(success, .{ .op = .union_make, .ty = optional, .a = ok, .data = 1 });
    try b.jump(success, join);
    const error_text = try b.call(failure, &module, fresh, &.{});
    const err = try b.put(failure, .{ .op = .union_make, .ty = result_type, .a = error_text, .data = 1 });
    const some_err = try b.put(failure, .{ .op = .union_make, .ty = optional, .a = err, .data = 1 });
    try b.jump(failure, join);
    const selected = try b.put(join, .{ .op = .phi, .ty = optional, .data = try b.extra(&.{ some_ok, some_err }) });
    _ = try b.put(join, .{ .op = .ret, .ty = .void, .a = selected });
    const callee: u32 = @intCast(module.functions.items.len);
    try module.functions.append(a, b.function);
    var detail: verify.Failure = .{};
    try verify.verifyModule(a, &module, &detail);
    const own = @import("own.zig");
    const stats = try own.function(a, &module, &module.functions.items[callee], .{});
    try std.testing.expectEqual(@as(u32, 0), stats.drops);
    try verify.verifyModule(a, &module, &detail);
    var caller: builder.Builder = .{ .arena = a, .function = .{ .name = "caller", .signature = .{ .params = &.{}, .ret = .u32 } } };
    const call_entry = try caller.block();
    const argument = try caller.call(call_entry, &module, fresh, &.{});
    const failed = try caller.constant(.bool, 0);
    const value = try caller.call(call_entry, &module, callee, &.{ argument, failed });
    const tag = try caller.put(call_entry, .{ .op = .union_tag, .ty = .u32, .a = value });
    _ = try caller.put(call_entry, .{ .op = .ret, .ty = .void, .a = tag });
    try module.functions.append(a, caller.function);
    const caller_function = &module.functions.items[module.functions.items.len - 1];
    const cleanup = try own.function(a, &module, caller_function, .{});
    try std.testing.expectEqual(@as(u32, 2), cleanup.drops);
    try std.testing.expect(dropFollows(caller_function, argument, tag));
    try verify.verifyModule(a, &module, &detail);
}

fn dropFollows(function: *const ir.Function, owner: ir.Ref, use: ir.Ref) bool {
    for (function.blocks.items) |block| {
        const at = std.mem.indexOfScalar(ir.Ref, block.insts.items, use) orelse continue;
        for (block.insts.items, 0..) |ref, position| {
            const instruction = function.inst(ref);
            if (instruction.op == .drop and function.resolve(instruction.a) == owner) return position > at;
        }
    }
    return false;
}

test "O3 empty readonly wrapper adapters do not drop borrowed storage or lose owned errors" {
    const support = @import("test_support.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a,
        \\func read_optional(value: str?) -> int:
        \\    match value:
        \\        case Some(text):
        \\            return len(text)
        \\        case None:
        \\            return 0
        \\func read_result(value: Result[str, str]) -> int:
        \\    match value:
        \\        case Ok(text):
        \\            return len(text)
        \\        case Err(message):
        \\            return len(message)
        \\func main() -> int:
        \\    const empty: str? = None
        \\    const failure: Result[str, str] = Err("failure-" + str(1))
        \\    return read_optional(empty) + read_result(failure)
    , &refusal);
    _ = try @import("own.zig").run(a, &module, .{});
    try support.verified(a, &module, &.{});
    const drops = dropKinds(&module);
    try std.testing.expectEqual(@as(usize, 0), drops.borrowed);
    try std.testing.expect(drops.owned_result != 0);
}

fn callsTo(module: *const ir.Module, name: []const u8) usize {
    var count: usize = 0;
    for (module.functions.items) |function| for (function.insts.items) |instruction| {
        if (instruction.op != .call) continue;
        if (std.mem.eql(u8, module.functions.items[instruction.a.index()].name, name)) count += 1;
    };
    return count;
}

test "O3 inlined mutable list results retain owners through later allocations" {
    const support = @import("test_support.zig");
    const inliner = @import("inline.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a,
        \\func through(mut values: str[]) -> str[] from values:
        \\    return values
        \\func wrapped(mut values: str[], mut unrelated: str[]) -> str[]? from values:
        \\    _ = unrelated
        \\    return Some(values)
        \\func main() -> int:
        \\    mut values = ["mutable"]
        \\    const borrowed = through(mut values)
        \\    mut nested_values = ["wrapped"]
        \\    mut unrelated = ["other"]
        \\    const nested = wrapped(mut nested_values, mut unrelated)
        \\    append(mut unrelated, "second")
        \\    const allocated = ["allocated"]
        \\    assert borrowed[0] == "mutable"
        \\    match nested:
        \\        case Some(part):
        \\            assert part[0] == "wrapped"
        \\        case None:
        \\            return 1
        \\    assert allocated[0] == "allocated"
        \\    assert len(unrelated) == 2
        \\    return 42
    , &refusal);
    var provenance: @import("inline_origins.zig").Table = .{};
    try std.testing.expectEqual(@as(usize, 1), callsTo(&module, "through"));
    try std.testing.expectEqual(@as(usize, 1), callsTo(&module, "wrapped"));
    try std.testing.expect(try inliner.inlineLeaves(a, &module, &provenance) != 0);
    try std.testing.expectEqual(@as(usize, 0), callsTo(&module, "through"));
    try std.testing.expectEqual(@as(usize, 0), callsTo(&module, "wrapped"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 42), ran.status);
    try std.testing.expectEqualStrings("", ran.stderr);
}

/// A caller `-> str from <declared>` returning `field` of `lend(param0, param1)`, where `lend` lends the part of its
/// record result at `lent` from its argument 0 (FX16).
fn fieldOfLentCall(a: std.mem.Allocator, module: *ir.Module, lent: []const ir.BorrowProjection, field: u32, declared: u32) !bool {
    const builder = @import("test_builder.zig");
    const pair = try module.intern(a, .{ .record = &.{ .str, .str } });
    const lend = try builder.helper(a, module, "lend", &.{ .str, .str }, pair);
    module.functions.items[lend].signature.borrow = .{ .path = lent, .sources = &.{.{ .argument = 0 }} };
    var b: builder.Builder = .{ .arena = a, .function = .{ .name = "first_name", .signature = .{
        .params = &.{ .str, .str },
        .ret = .str,
        .borrow = .{ .sources = try a.dupe(ir.BorrowSource, &.{.{ .argument = declared }}) },
    } } };
    const entry = try b.block();
    const left = try b.detached(.{ .op = .param, .ty = .str, .data = 0 });
    const right = try b.detached(.{ .op = .param, .ty = .str, .data = 1 });
    const lent_record = try b.call(entry, module, lend, &.{ left, right });
    const name = try b.put(entry, .{ .op = .record_get, .ty = .str, .a = lent_record, .data = field });
    _ = try b.put(entry, .{ .op = .ret, .ty = .void, .a = name });
    return valid(a, module, &b.function, name);
}

test "FX16 a field of a call's lent result is the storage of the callee's declared source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    // `pick(xs).name` where `pick` lends its whole result from `xs`, and the caller declares `from xs`.
    try std.testing.expect(try fieldOfLentCall(a, &module, &.{}, 0, 0));
    try std.testing.expect(try fieldOfLentCall(a, &module, &.{}, 1, 0));
    // A record whose field 0 alone is lent: that field is the source's, field 1 is not.
    try std.testing.expect(try fieldOfLentCall(a, &module, &.{.{ .field = 0 }}, 0, 0));
    try std.testing.expect(!try fieldOfLentCall(a, &module, &.{.{ .field = 0 }}, 1, 0));
}

test "FX16 a field of a call's lent result is refused when the caller declares another argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    // The callee lends from the caller's first parameter; the caller declares its second.
    try std.testing.expect(!try fieldOfLentCall(a, &module, &.{}, 0, 1));
    try std.testing.expect(!try fieldOfLentCall(a, &module, &.{.{ .field = 0 }}, 0, 1));
}

test "FX16 an accessor that returns a field of another accessor's lent result builds and verifies" {
    const support = @import("test_support.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a,
        \\record Net:
        \\    name: str
        \\    tags: str[]
        \\func pick(xs: Net[]) -> Net from xs:
        \\    return xs[0]
        \\func first_name(xs: Net[]) -> str from xs:
        \\    return pick(xs).name
        \\func first_tag(xs: Net[]) -> str from xs:
        \\    const x = pick(xs)
        \\    return x.tags[1][1:]
        \\func main() -> int:
        \\    const nets = [Net(name="alpha", tags=["a", "bc"])]
        \\    return len(first_name(nets)) + len(first_tag(nets))
    , &refusal);
    var lent: usize = 0;
    for (module.functions.items) |function| {
        if (std.mem.endsWith(u8, function.name, "first_name") or std.mem.endsWith(u8, function.name, "first_tag")) lent += function.signature.borrow.sources.len;
    }
    try std.testing.expectEqual(@as(usize, 2), lent);
    _ = try @import("own.zig").run(a, &module, .{});
    try support.verified(a, &module, &.{});
}
