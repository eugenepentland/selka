//! Whole-record field transfers destroy siblings at the selected operation.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const own = @import("own.zig");
const verify = @import("verify_ir.zig");

test "O4 carrier take validates exact field types and rejects borrowed owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    const record = try module.intern(a, .{ .record = &.{ list, .str } });
    var h = try support.Hand.init(a, &module, "take", .{ .params = &.{record}, .ret = list, .passing = .{ .owned = 1 } });
    const taken = try h.emit(.{ .op = .record_take, .ty = list, .a = try h.param(0) });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = taken });
    _ = try h.finish();
    var failure: verify.Failure = .{};
    try verify.verifyModule(a, &module, &failure);
    module.functions.items[0].insts.items[taken.index()].data = 1;
    try std.testing.expectError(error.InvalidIr, verify.verifyModule(a, &module, &failure));
    module.functions.items[0].insts.items[taken.index()].data = 0;
    module.functions.items[0].signature.passing = .{};
    try std.testing.expectError(error.Unsupported, own.function(a, &module, &module.functions.items[0], .{}));
}

fn preservesWideField(a: std.mem.Allocator, release: bool) !u8 {
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    const wide = try module.intern(a, .{ .record = &.{ .i64, .i64, .i64, .i64, list } });
    const outer = try module.intern(a, .{ .record = &.{ list, wide } });
    var h = try support.Hand.init(a, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const zero = try h.int(.i64, 0);
    const empty = try h.emit(.{ .op = .list_new, .ty = list, .a = try h.int(.u64, 1) });
    const selected = try h.emit(.{ .op = .list_push, .ty = list, .a = empty, .b = try h.int(.i64, 42) });
    const spare = try h.emit(.{ .op = .list_new, .ty = list, .a = try h.int(.u64, 1) });
    const payload = try h.emit(.{ .op = .record_make, .ty = wide, .data = try h.extra(&.{ zero, zero, zero, zero, selected }) });
    const carrier = try h.emit(.{ .op = .record_make, .ty = outer, .data = try h.extra(&.{ spare, payload }) });
    const taken = try h.emit(.{ .op = .record_take, .ty = wide, .a = carrier, .data = 1 });
    const child = try h.emit(.{ .op = .record_take, .ty = list, .a = taken, .data = 4 });
    const answer = try h.emit(.{ .op = .list_get, .ty = .i64, .a = child, .b = try h.int(.u64, 0), .check = .exact });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = answer });
    module.entry = try h.finish();
    const run = try support.runOwned(a, &module, .{ .release = release, .verify = release });
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expect(std.mem.indexOf(u8, run.llvm, "call ptr @myl_core_values_copy") == null);
    return run.status;
}

test "O4 carrier take owns wide nested fields and destroys siblings without copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(u8, 42), try preservesWideField(arena.allocator(), false));
    try std.testing.expectEqual(@as(u8, 42), try preservesWideField(arena.allocator(), true));
}

test "O4 carrier lowering accepts own parameters branches loops resources and providers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/lang/owned_field_moves.selka", a, .limited(1 << 20));
    const main =
        \\func main() -> int:
        \\    assert test_local_field_transfer_preserves_earlier_reads()
        \\    assert test_own_parameter_field_transfer_destroys_managed_siblings()
        \\    assert test_earlier_argument_reads_precede_a_later_field_transfer()
        \\    assert test_branch_arms_consume_each_record_once()
        \\    assert test_untaken_branch_retains_ordinary_record_cleanup()
        \\    assert test_nested_field_transfer_consumes_every_enclosing_record()
        \\    assert test_wide_field_transfer_has_independent_storage()
        \\    assert test_loop_reinitialization_restores_the_complete_owner()
        \\    assert test_provider_sibling_is_destroyed_when_the_field_moves()
        \\    assert test_provider_field_transfer_clears_the_old_lexical_pin()
        \\    assert test_resource_siblings_close_before_the_next_acquisition()
        \\    assert test_resource_field_transfer_destroys_managed_siblings()
        \\    assert test_provider_const_aliases_preserve_the_original_owner()
        \\    assert test_provider_field_aliases_share_the_existing_pin()
        \\    assert test_provider_alias_last_use_allows_a_real_transfer()
        \\    assert test_own_parameter_provider_aliases_survive_branch_joins()
        \\    assert test_generic_field_markers_read_scalars_and_transfer_managed_values()
        \\    assert test_carrier_rhs_destroys_siblings_before_effectful_destination_index()
        \\    assert test_dictionary_field_writeback_borrows_its_existing_managed_key()
        \\    return 42
    ;
    const source = try std.mem.concat(a, u8, &.{ fixture, "\n", main });
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    var takes: usize = 0;
    for (module.functions.items) |function| {
        for (function.insts.items) |inst| if (inst.op == .record_take) {
            takes += 1;
        };
    }
    try std.testing.expect(takes >= 12);
    const result = try @import("passes.zig").run(a, &module, .verify);
    try support.verified(a, &module, result.plans);
}

test "O4 generic field markers preserve scalar reads and destroy managed carrier siblings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Holder[T]:
        \\    value: T
        \\    spare: str
        \\func extract[T](own holder: Holder[T]) -> T:
        \\    return own holder.value
        \\func main() -> int:
        \\    const scalar = extract[int](Holder[int](value=33, spare="scalar-" + str(1)))
        \\    const text = extract[str](Holder[str](value="managed-" + str(2), spare="sibling-" + str(3)))
        \\    return scalar + len(text)
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    var takes: usize = 0;
    for (module.functions.items) |function| {
        for (function.insts.items) |inst| if (inst.op == .record_take) {
            takes += 1;
        };
    }
    try std.testing.expectEqual(@as(usize, 1), takes);
    const result = try @import("passes.zig").run(a, &module, .verify);
    try support.verified(a, &module, result.plans);
}

test "O4 dictionary field writebacks borrow keys and only replace proven existing entries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Box:
        \\    items: int[]
        \\    spare: str
        \\record Counter:
        \\    value: int
        \\record MappingHolder:
        \\    rows: dict[str, Box]
        \\    counts: dict[str, Counter]
        \\    spare: str
        \\func write_existing(mut rows: dict[str, Box], key: str, own values: int[]):
        \\    rows[key].items = own values
        \\func write_counter(mut rows: dict[str, Counter], key: str, value: int):
        \\    rows[key].value = value
        \\func write_nested(mut holder: MappingHolder, key: str, own values: int[]):
        \\    holder.rows[key].items = own values
        \\func write_nested_counter(mut holder: MappingHolder, key: str, value: int):
        \\    holder.counts[key].value = value
        \\func main() -> int:
        \\    const key = "k-" + str(1)
        \\    mut rows = {"k-1": Box(items=[1], spare="keep-" + str(2))}
        \\    const source = [39]
        \\    write_existing(mut rows, key, own source)
        \\    mut counts = {"k-1": Counter(value=1)}
        \\    write_counter(mut counts, key, 42)
        \\    assert rows[key].spare == "keep-2" and counts[key].value == 42
        \\    mut holder = MappingHolder(rows={"k-1": Box(items=[2], spare="nested")}, counts={"k-1": Counter(value=1)}, spare="outer-" + str(3))
        \\    const nested_source = [7, 8]
        \\    write_nested(mut holder, key, own nested_source)
        \\    write_nested_counter(mut holder, key, 10)
        \\    assert holder.rows[key].items == [7, 8] and holder.rows[key].spare == "nested" and holder.counts[key].value == 10 and holder.spare == "outer-3"
        \\    return rows[key].items[0] + len(key)
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    var checked: usize = 0;
    for (module.functions.items) |function| {
        if (!std.mem.startsWith(u8, function.name, "write_")) continue;
        checked += 1;
        for (function.insts.items) |inst| try std.testing.expect(inst.op != .dict_insert and inst.op != .list_copy and inst.op != .dict_copy);
    }
    try std.testing.expectEqual(@as(usize, 4), checked);
    const result = try @import("passes.zig").run(a, &module, .verify);
    try support.verified(a, &module, result.plans);
}

fn deferredWithoutCopies(module: *const ir.Module) !usize {
    var checked: usize = 0;
    for (module.functions.items) |function| {
        const name = if (std.mem.lastIndexOf(u8, function.name, "::")) |at| function.name[at + 2 ..] else function.name;
        const selected = std.mem.startsWith(u8, name, "deferred_select_");
        const owned = std.mem.startsWith(u8, name, "deferred_owned_");
        if (!selected and !owned) continue;
        checked += 1;
        for (function.insts.items) |inst| {
            try std.testing.expect(inst.op != .list_copy and inst.op != .dict_copy);
            try std.testing.expect(inst.op != .buffer_copy and inst.op != .str_from_view);
            if (inst.op != .call) continue;
            const callee = module.functions.items[inst.a.index()].name;
            try std.testing.expect(!std.mem.eql(u8, callee, "myl_core_owned_octets_copy"));
            try std.testing.expect(!std.mem.startsWith(u8, callee, @import("emit_values.zig").copy_prefix));
        }
    }
    return checked;
}

test "O4 deferred const joins keep readonly ABI and branch lenders without hidden copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/lang/owned_field_moves.selka", a, .limited(1 << 20));
    const main =
        \\func main() -> int:
        \\    assert test_deferred_const_list_branches_keep_borrowed_and_fresh_storage()
        \\    assert test_deferred_const_text_branches_keep_borrowed_and_fresh_storage()
        \\    assert test_deferred_const_two_lenders_are_reusable_after_the_last_read()
        \\    assert test_deferred_const_branch_local_lenders_survive_allocation_pressure()
        \\    assert test_deferred_const_option_arms_keep_borrowed_and_fresh_storage()
        \\    assert test_deferred_const_fresh_and_explicit_own_arms_keep_owning_returns()
        \\    assert test_deferred_const_loop_backedges_forget_dead_branch_lenders()
        \\    return 42
    ;
    const source = try std.mem.concat(a, u8, &.{ fixture, "\n", main });
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    try std.testing.expectEqual(@as(usize, 11), try deferredWithoutCopies(&module));
    const result = try @import("passes.zig").run(a, &module, .verify);
    try support.verified(a, &module, result.plans);
}
