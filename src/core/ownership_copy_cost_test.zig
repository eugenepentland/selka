//! Copy-cost optimizations preserve live donors and remove only dead ownership.
const std = @import("std");
const ir = @import("ir.zig");
const own = @import("own.zig");
const snapshot = @import("inline_snapshot.zig");
const support = @import("test_support.zig");
const contract = @import("single_owner.zig");
const build = @import("build.zig");
const language = @import("selka");
const flags = @import("flags.zig");
const passes = @import("passes.zig");
const Hand = support.Hand;

fn recursiveCopyUnit(a: std.mem.Allocator, shifted: bool) ![]const u8 {
    var module: ir.Module = .{};
    if (shifted) try module.compounds.append(a, .{ .list = .bytes });
    const record: ir.Type = @fromBackingInt(ir.Type.first_compound + @as(u32, @intCast(module.compounds.items.len)));
    const box: ir.Type = @fromBackingInt(@backingInt(record) + 1);
    try module.compounds.appendSlice(a, &.{ .{ .record = &.{ .str, box } }, .{ .box = record } });
    for ([_]ir.Type{ box, .bytes }) |ty| try module.functions.append(a, .{
        .name = try std.fmt.allocPrint(a, "myl_core_owned_copy_{d}", .{@backingInt(ty)}),
        .signature = .{ .params = &.{ty}, .ret = ty, .linkage = .runtime_c },
    });
    const catalog = try @import("emit_constants.zig").Catalog.init(a, &module);
    try std.testing.expect(std.mem.indexOf(u8, catalog.prelude, "define ") == null);
    const body = try std.fmt.allocPrint(a, "@selected = private constant ptr @myl.copy.{s}\n", .{catalog.ids.text(box)});
    return catalog.finish(a, body);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
// spec-case: NEW-CORE-S4-UNITS-1
test "ownership copy cost split units close recursive callbacks with stable local identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const original = try recursiveCopyUnit(arena.allocator(), false);
    const shifted = try recursiveCopyUnit(arena.allocator(), true);
    try std.testing.expectEqualStrings(original, shifted);
    // The box, record and text callbacks form a closed cycle. An unrelated
    // bytes adapter exists in the module but must not enter this unit.
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, original, "define internal void @myl.copy."));
    try std.testing.expect(std.mem.indexOf(u8, original, "@selected = private constant ptr @myl.copy.0\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, original, "ptr @myl.copy.1, i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, original, "call void @myl.copy.0(ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, original, "call void @myl.copy.2(ptr") != null);
}

const Generated = struct { run: support.Run, field_copies: usize, slice_copies: usize, keys_sunk: bool, mutation_sunk: bool };

/// Whether `function` is `name`: a project compilation qualifies it with its
/// module (`main::donated_field`), a single unit leaves it bare.
fn named(function: *const ir.Function, name: []const u8) bool {
    return std.mem.endsWith(u8, function.name, name);
}

fn keyCopiesAtInsertion(module: *const ir.Module, name: []const u8) bool {
    for (module.functions.items) |*function| {
        if (!named(function, name)) continue;
        var found = false;
        for (function.blocks.items) |block| for (block.insts.items) |ref| {
            const instruction = function.inst(ref);
            if (instruction.ty != .str or snapshot.source(module, function, instruction) == null) continue;
            found = true;
            const inserted = for (block.insts.items) |user| {
                const inst = function.inst(user);
                if (inst.op == .dict_insert and function.resolve(function.operands(inst.data)[0]) == ref) break true;
            } else false;
            if (!inserted) return false;
        };
        return found;
    }
    return false;
}

fn namedCopies(module: *const ir.Module, name: []const u8) usize {
    for (module.functions.items) |*function| {
        if (!named(function, name)) continue;
        var count: usize = 0;
        for (function.insts.items) |instruction| {
            if (snapshot.source(module, function, instruction) != null or spelledSnapshot(module, instruction)) count += 1;
        }
        return count;
    }
    return std.math.maxInt(usize);
}

/// A spelled `bytes(buffer)` snapshot: the runtime call the conversion makes (CX2, R-B17). A self-append that
/// spells its snapshot is the same one copy an implicit snapshot made.
fn spelledSnapshot(module: *const ir.Module, instruction: anytype) bool {
    return instruction.op == .call and std.mem.eql(u8, module.functions.items[instruction.a.index()].name, "myl_core_buffer_snapshot");
}

fn generatedCopies(a: std.mem.Allocator) !Generated {
    // The fixture imports `lists` and `strings`, so it is checked as a project.
    const program = try support.checkedProgram(a, @embedFile("ownership_copy_cost_fixture.selka"));
    var failure: contract.Failure = .{};
    try contract.check(a, program, &failure);
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = program }, &refusal);
    const run = try support.runOwned(a, &module, .{ .release = true });
    return .{
        .run = run,
        .field_copies = namedCopies(&module, "donated_field"),
        .slice_copies = namedCopies(&module, "donated_slice"),
        .keys_sunk = keyCopiesAtInsertion(&module, "test_dictionary_updates_copy_only_missing_keys"),
        .mutation_sunk = keyCopiesAtInsertion(&module, "test_dictionary_key_copy_precedes_source_mutation"),
    };
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership copy cost generated callbacks preserve live records arrays unions and dictionaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try generatedCopies(arena.allocator());
    const run = result.run;
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("True\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\n", run.stdout);
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expect(std.mem.indexOf(u8, run.llvm, "call ptr @myl_core_values_copy_generated") != null);
    try std.testing.expect(std.mem.indexOf(u8, run.llvm, "call ptr @myl_core_values_copy_box") == null);
    try std.testing.expect(std.mem.indexOf(u8, run.llvm, "@myl.empty.list.") != null);
    try std.testing.expectEqual(@as(usize, 0), result.field_copies);
    try std.testing.expectEqual(@as(usize, 0), result.slice_copies);
    try std.testing.expect(result.keys_sunk);
    try std.testing.expect(!result.mutation_sunk);
}

fn remainingCopies(a: std.mem.Allocator, count: usize, padding: usize, live: bool) !usize {
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    var h = try Hand.init(a, &module, "copies", .{ .params = &.{}, .ret = .u64 });
    var total = try h.int(.u64, 0);
    for (0..padding) |_| total = try h.emit(.{ .op = .add, .ty = .u64, .a = total, .b = try h.int(.u64, 0) });
    for (0..count) |_| {
        const donor = try h.emit(.{ .op = .list_new, .ty = list, .a = try h.int(.u64, 1) });
        const copied = try h.emit(.{ .op = .list_copy, .ty = list, .a = donor });
        const length = try h.emit(.{ .op = .list_len, .ty = .u64, .a = copied });
        total = try h.emit(.{ .op = .add, .ty = .u64, .a = total, .b = length });
        if (live) {
            const kept = try h.emit(.{ .op = .list_len, .ty = .u64, .a = donor });
            total = try h.emit(.{ .op = .add, .ty = .u64, .a = total, .b = kept });
        }
    }
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = total });
    _ = try h.finish();
    _ = try own.run(a, &module, .{});
    var remaining: usize = 0;
    for (module.functions.items[0].insts.items) |inst| {
        if (inst.op == .list_copy) remaining += 1;
    }
    return remaining;
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership copy cost elides every dead primitive donor beyond old size limits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 0), try remainingCopies(arena.allocator(), 40, 4100, false));
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership copy cost preserves copies whose primitive donor remains live" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 2), try remainingCopies(arena.allocator(), 2, 0, true));
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership copy cost preserves borrowed call copies without resolving callee indices as values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    // Keep the callee index outside this caller's SSA table, as in large programs.
    for (0..32) |index| try module.functions.append(a, .{
        .name = try std.fmt.allocPrint(a, "unused_{d}", .{index}),
        .signature = .{ .params = &.{}, .ret = .void, .linkage = .runtime_c },
    });
    const selected = try support.declareChoice(a, &module, .min_text, .str, .str);
    const copier: u32 = @intCast(module.functions.items.len);
    try module.functions.append(a, .{ .name = "myl_core_owned_octets_copy", .signature = .{ .params = &.{.str}, .ret = .str, .linkage = .runtime_c } });
    var h = try Hand.init(a, &module, "borrowed_call_copy", .{ .params = &.{ .str, .str }, .ret = .str });
    const first = try h.param(0);
    const second = try h.param(1);
    const borrowed = try h.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(selected), .data = try h.extra(&.{ first, first, second }) });
    const copied = try h.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(copier), .data = try h.extra(&.{borrowed}) });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = copied });
    try std.testing.expect(selected >= h.function.insts.items.len);
    _ = try h.finish();
    try support.verified(a, &module, &.{});
    _ = try own.run(a, &module, .{});
    try support.verified(a, &module, &.{});
    try std.testing.expectEqual(@as(usize, 1), namedCopies(&module, "borrowed_call_copy"));
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership copy cost recognizes buffers but refuses managed shallow lists and place copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const texts = try module.intern(a, .{ .list = .str });
    const integers = try module.intern(a, .{ .list = .i64 });
    var h = try Hand.init(a, &module, "sources", .{ .params = &.{}, .ret = .void });
    const buffer = try h.emit(.{ .op = .buffer_new, .ty = .byte_buffer });
    const managed = try h.emit(.{ .op = .list_new, .ty = texts });
    const primitive = try h.emit(.{ .op = .list_new, .ty = integers });
    try std.testing.expectEqual(buffer, snapshot.source(&module, &h.function, .{ .op = .buffer_copy, .ty = .byte_buffer, .a = buffer }).?);
    try std.testing.expect(snapshot.source(&module, &h.function, .{ .op = .list_copy, .ty = texts, .a = managed }) == null);
    try std.testing.expect(snapshot.source(&module, &h.function, .{ .op = .list_copy, .ty = integers, .a = primitive, .data = flags.place_copy }) == null);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
// An `own` parameter is never emptied (lane G, D-G-1): its certificate can state a parameter only owned, borrowed or
// scalar. The front end transfers a field with `record_take` (`return own carrier.file`); a bare field read returned
// from the parameter is a borrow the function does not declare, and the pass refuses it.
test "ownership copy cost transfers an owned parameter field with only scalar siblings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const carrier = try module.intern(a, .{ .record = &.{ .i64, .resource } });
    var h = try Hand.init(a, &module, "take_resource", .{ .params = &.{carrier}, .ret = .resource, .passing = .{ .consumes = 1 } });
    const field = try h.emit(.{ .op = .record_take, .ty = .resource, .a = try h.param(0), .data = 1 });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = field });
    _ = try h.finish();
    const result = try own.run(a, &module, .{});
    try std.testing.expectEqual(@as(u32, 0), result.drops);
    try support.verified(a, &module, &.{});
    var read_module: ir.Module = .{};
    const read_carrier = try read_module.intern(a, .{ .record = &.{ .i64, .resource } });
    var r = try Hand.init(a, &read_module, "read_resource", .{ .params = &.{read_carrier}, .ret = .resource, .passing = .{ .consumes = 1 } });
    const read = try r.emit(.{ .op = .record_get, .ty = .resource, .a = try r.param(0), .data = 1 });
    _ = try r.emit(.{ .op = .ret, .ty = .void, .a = read });
    _ = try r.finish();
    try std.testing.expectError(error.Unsupported, own.run(a, &read_module, .{}));
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership copy cost sibling writebacks retain only disjoint transfer tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f: ir.Function = .{ .name = "siblings", .signature = .{ .params = &.{}, .ret = .void } };
    const ref = struct {
        fn of(index: u32) ir.Ref {
            return @fromBackingInt(index);
        }
    }.of;
    try f.insts.appendSlice(a, &.{
        .{ .op = .undef, .ty = .u64 },
        .{ .op = .iconst, .ty = .u64 },
        .{ .op = .iconst, .ty = .u64, .data = 1 },
        .{ .op = .list_get, .ty = .u64, .a = ref(0), .b = ref(1), .data = flags.place_read },
        .{ .op = .list_get, .ty = .u64, .a = ref(0), .b = ref(2), .data = flags.place_read },
        .{ .op = .list_set, .ty = .u64, .a = ref(0), .b = ref(1) },
        .{ .op = .list_set, .ty = .u64, .a = ref(5), .b = ref(2) },
        .{ .op = .list_set, .ty = .u64, .a = ref(6), .b = ref(1) },
        .{ .op = .ret, .ty = .void },
    });
    var block: ir.Block = .{};
    for (0..f.insts.items.len) |index| try block.insts.append(a, ref(@intCast(index)));
    try f.blocks.append(a, block);
    const transfer = @import("transfers.zig");
    const taken = try transfer.slots(a, &f);
    try std.testing.expect(taken[5] and taken[6] and !taken[7]);
    // An unknown index can overlap either slot, so it invalidates the second token.
    f.insts.items[1].op = .param;
    const uncertain = try transfer.slots(a, &f);
    try std.testing.expect(uncertain[5] and !uncertain[6] and !uncertain[7]);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership copy cost release writebacks transfer recursive boxes and discard unchanged fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "writeback.selka", @embedFile("ownership_writeback_fixture.selka"));
    try unit.check();
    var failure: contract.Failure = .{};
    try contract.check(a, unit.program.?, &failure);
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = unit.program.? }, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    const run = try support.runOwned(a, &module, .{ .own = false, .release = true, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("True\nTrue\n", run.stdout);
    try std.testing.expectEqualStrings("", run.stderr);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership copy cost cannot take a box from a borrowed parent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const boxed = try module.intern(a, .{ .box = .str });
    var h = try Hand.init(a, &module, "borrowed", .{ .params = &.{boxed}, .ret = .str });
    const value = try h.emit(.{ .op = .box_take, .ty = .str, .a = try h.param(0) });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = value });
    try module.functions.append(a, h.function);
    try std.testing.expectError(error.Unsupported, own.run(a, &module, .{}));
}

fn childCopies(a: std.mem.Allocator, op: ir.Op, owned: bool, live: bool) !usize {
    var module: ir.Module = .{};
    const parent = try module.intern(a, switch (op) {
        .list_get => .{ .list = .str },
        .union_payload => .{ .@"union" = &.{.str} },
        .box_get => .{ .box = .str },
        else => unreachable,
    });
    try module.functions.append(a, .{ .name = "myl_core_owned_octets_copy", .signature = .{ .params = &.{.str}, .ret = .str, .linkage = .runtime_c } });
    var h = try Hand.init(a, &module, "child", .{ .params = &.{parent}, .ret = .str, .passing = .{ .consumes = if (owned) 1 else 0 } });
    const owner = try h.param(0);
    const index = if (op == .list_get) try h.int(.u64, 0) else .none;
    const read = try h.emit(.{ .op = op, .ty = .str, .a = owner, .b = index });
    const copy = try h.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(0), .data = try h.extra(&.{read}) });
    if (live) {
        const kept = try h.emit(.{ .op = op, .ty = .str, .a = owner, .b = index });
        _ = try h.emit(.{ .op = .str_len, .ty = .u64, .a = kept });
    }
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = copy });
    _ = try h.finish();
    _ = try own.run(a, &module, .{});
    try support.verified(a, &module, &.{});
    var count: usize = 0;
    const f = &module.functions.items[1];
    for (f.insts.items) |inst| if (snapshot.source(&module, f, inst) != null) {
        count += 1;
    };
    return count;
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership copy cost moves selected list and match children only from dead owned parents" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for ([_]ir.Op{ .list_get, .union_payload, .box_get }) |op| {
        try std.testing.expectEqual(@as(usize, 0), try childCopies(arena.allocator(), op, true, false));
        try std.testing.expectEqual(@as(usize, 1), try childCopies(arena.allocator(), op, true, true));
        try std.testing.expectEqual(@as(usize, 1), try childCopies(arena.allocator(), op, false, false));
    }
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership copy cost donated elements drop siblings and borrowed elements remain independent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "donors.selka", @embedFile("ownership_donor_fixture.selka"));
    try unit.check();
    var failure: contract.Failure = .{};
    try contract.check(a, unit.program.?, &failure);
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = unit.program.? }, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    try std.testing.expectEqual(@as(usize, 0), namedCopies(&module, "donated_element"));
    try std.testing.expectEqual(@as(usize, 0), namedCopies(&module, "donated_match"));
    try std.testing.expectEqual(@as(usize, 1), namedCopies(&module, "borrowed_element"));
    const run = try support.runOwned(a, &module, .{ .own = false, .release = true, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("True\nTrue\nTrue\n", run.stdout);
    try std.testing.expectEqualStrings("", run.stderr);
}

fn bufferSelfAppend(backing: std.mem.Allocator, mode: passes.Mode) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try support.checkedProgram(a,
        \\import buffers
        \\
        \\func self_append(mut target: byte_buffer, start: int, end: int) -> bool:
        \\    return buffers.append_range(mut target, bytes(target), start, end)
        \\func disjoint_append(mut target: byte_buffer, source: byte_buffer) -> bool:
        \\    return buffers.append_range(mut target, source, 0, len(source))
        \\func main(out: Stream) -> int:
        \\    mut buffer = byte_buffer([97, 98, 99, 100])
        \\    _ = buffers.reserve(mut buffer, 64)
        \\    const before = bytes(buffer)
        \\    print(out, self_append(mut buffer, 1, 3), buffer == b"abcdbc", before == b"abcd")
        \\    print(out, self_append(mut buffer, 2, 2), self_append(mut buffer, 4, 3), self_append(mut buffer, 0, 99))
        \\    mut source = byte_buffer([88, 89])
        \\    print(out, disjoint_append(mut buffer, source), buffer == b"abcdbcXY", source == b"XY")
        \\    _ = buffers.append_byte(mut source, 33)
        \\    print(out, buffer == b"abcdbcXY", before == b"abcd")
        \\    return 0
    );
    var failure: contract.Failure = .{};
    try contract.check(a, program, &failure);
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = program }, &refusal);
    const result = try support.runPasses(a, &module, mode);
    try std.testing.expectEqual(@as(usize, 1), namedCopies(&module, "self_append"));
    try std.testing.expectEqual(@as(usize, 0), namedCopies(&module, "disjoint_append"));
    const run = try support.runOwned(a, &module, .{ .own = false, .release = mode != .off, .verify = mode == .verify, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("True True True\nTrue False False\nTrue True True\nTrue True\n", run.stdout);
    try std.testing.expectEqualStrings("", run.stderr);
}

// spec-case: PY-BYTES-6
test "ownership copy cost snapshots exact byte buffer self appends and borrows disjoint inputs" {
    try bufferSelfAppend(std.testing.allocator, .off);
    try bufferSelfAppend(std.testing.allocator, .trusted);
    try bufferSelfAppend(std.testing.allocator, .verify);
}

fn expectHomeOverlapRefused(a: std.mem.Allocator, call: []const u8) !void {
    const head = "import buffers\n\nfunc grow(mut buffer: byte_buffer) -> int:\n    _ = buffers.append_byte(mut buffer, 1)\n    return 2\n\n";
    const body = "func main() -> int:\n    mut buffer = byte_buffer([1])\n    _ = ";
    const source = try std.fmt.allocPrint(a, "{s}{s}{s}\n    return len(buffer)\n", .{ head, body, call });
    const program = try support.checkedProgram(a, source);
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.check(a, program, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
}

// A byte buffer's home takes its receiver `mut`, so a second `mut` argument of the same
// buffer is the ownership rule's overlap (the method's receiver rule no longer applies).
// spec-case: PY-BYTES-6
test "a byte buffer home whose mut argument overlaps another mut argument is refused by ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectHomeOverlapRefused(a, "buffers.append_byte(mut buffer, grow(mut buffer))");
    try expectHomeOverlapRefused(a, "buffers.reserve(mut buffer, grow(mut buffer))");
}

// spec-case: PY-BYTES-6
test "ownership copy cost self append does not admit a general overlapping borrow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try support.checkedProgram(a,
        \\import buffers
        \\
        \\func my_append(mut target: byte_buffer, source: byte_buffer) -> bool:
        \\    return buffers.append_range(mut target, source, 0, len(source))
        \\func main() -> int:
        \\    mut buffer = byte_buffer([97, 98])
        \\    _ = my_append(mut buffer, buffer)
        \\    return 0
    );
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.check(a, program, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
}
