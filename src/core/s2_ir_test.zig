//! S2-0: operation signatures, valid LLVM placeholders and executable foundational IR.
const std = @import("std");
const ir = @import("ir.zig");
const print = @import("print.zig");
const verify_ir = @import("verify_ir.zig");
const support = @import("test_support.zig");
const own = @import("own.zig");
const passes = @import("passes.zig");
const Hand = support.Hand;

const Program = struct { module: ir.Module, operation: ir.Ref };

fn operationProgram(a: std.mem.Allocator, op: ir.Op) !Program {
    var m: ir.Module = .{};
    const dict = try m.intern(a, .{ .dict = .{ .key = .i64, .value = .i64 } });
    const array = try m.intern(a, .{ .array = .{ .elem = .i64, .n = 2 } });
    const list = try m.intern(a, .{ .list = .i64 });
    const fn_ty = try m.intern(a, .{ .@"fn" = .{ .params = &.{.i64}, .ret = .i64 } });
    var target = try Hand.init(a, &m, "identity", .{ .params = &.{.i64}, .ret = .i64 });
    _ = try target.emit(.{ .op = .ret, .ty = .void, .a = try target.param(0) });
    _ = try target.finish();
    m.entry = 1;
    try m.strings.append(a, "Aé💩");
    var h = try Hand.init(a, &m, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const d = try h.loose(.{ .op = .undef, .ty = dict });
    const xs = try h.loose(.{ .op = .undef, .ty = list });
    const ar = try h.emit(.{ .op = .record_make, .ty = array, .data = try h.extra(&.{ try h.int(.i64, 0), try h.int(.i64, 0) }) });
    const text = try h.loose(.{ .op = .str_const, .ty = .str });
    const offset = try h.int(.u64, 0);
    const entry = try h.int(.i64, 0);
    const value = try h.int(.i64, 42);
    const fn_ref = try h.loose(.{ .op = .func_ref, .ty = fn_ty, .data = 0 });
    var inst: ir.Inst = .{ .op = op, .ty = dict, .a = d };
    switch (op) {
        .dict_new => inst.a = offset,
        .dict_len, .dict_entries => inst.ty = .u64,
        .dict_find => {
            inst.ty = .i64;
            inst.b = value;
        },
        .dict_entry_key, .dict_entry_value => {
            inst.ty = .i64;
            inst.b = entry;
        },
        .dict_set_value => {
            inst.b = entry;
            inst.data = try h.extra(&.{value});
        },
        .dict_insert => {
            inst.b = try h.emit(.{ .op = .dict_find, .ty = .i64, .a = d, .b = value });
            inst.data = try h.extra(&.{ value, value });
        },
        .dict_remove => inst.b = entry,
        .dict_entry_live => {
            inst.ty = .bool;
            inst.b = entry;
        },
        .dict_copy, .dict_clear => {},
        .str_char, .str_width, .str_code => {
            inst.ty = if (op == .str_width) .u64 else if (op == .str_code) .u32 else .str;
            inst.a = text;
            inst.b = offset;
        },
        .str_append => {
            inst.ty = .str;
            inst.a = text;
            inst.b = text;
        },
        .str_append_char => {
            inst.ty = .str;
            inst.a = text;
            inst.b = text;
            inst.data = try h.extra(&.{offset});
        },
        .str_slice => {
            inst.ty = .str;
            inst.a = text;
            inst.b = entry;
            inst.data = try h.extra(&.{try h.int(.i64, 1)});
        },
        .str_view_of => {
            inst.ty = .str_view;
            inst.a = text;
            inst.b = offset;
            inst.data = try h.extra(&.{try h.int(.u64, 1)});
        },
        .str_from_view => {
            inst.ty = .str;
            inst.a = try h.emit(.{ .op = .str_view_of, .ty = .str_view, .a = text, .b = offset, .data = try h.extra(&.{try h.int(.u64, 1)}) });
        },
        .list_sort => {
            inst.ty = list;
            inst.a = xs;
            inst.b = try h.int(.bool, 0);
        },
        .array_get => {
            inst.ty = .i64;
            inst.a = ar;
            inst.b = entry;
            inst.check = .exact;
        },
        .array_set => {
            inst.ty = array;
            inst.a = ar;
            inst.b = entry;
            inst.data = try h.extra(&.{value});
            inst.check = .exact;
        },
        .func_ref => {
            inst.ty = fn_ty;
            inst.a = .none;
        },
        .call_indirect => {
            inst.ty = .i64;
            inst.a = fn_ref;
            inst.data = try h.extra(&.{value});
        },
        else => unreachable,
    }
    const ref = try h.emit(inst);
    if (op == .str_char or op == .str_from_view or op == .call_indirect or op == .array_get) try h.printValues(try h.param(0), &.{ref});
    if (op == .array_set) {
        const read = try h.emit(.{ .op = .array_get, .ty = .i64, .a = ref, .b = entry, .check = .exact });
        try h.printValues(try h.param(0), &.{read});
    }
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return .{ .module = m, .operation = ref };
}

fn exercise(op: ir.Op, allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var program = try operationProgram(a, op);
    var failure: verify_ir.Failure = .{};
    try verify_ir.verifyModule(a, &program.module, &failure);
    const text = try print.module(a, &program.module);
    try std.testing.expect(std.mem.indexOf(u8, text, @tagName(op)) != null);
    const ran = try support.runModule(a, &program.module, false);
    const expected: ?[]const u8 = switch (op) {
        .str_char, .str_from_view => "A\n",
        .array_get => "0\n",
        .array_set, .call_indirect => "42\n",
        .func_ref, .str_view_of => "",
        else => null,
    };
    if (expected) |stdout| {
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings(stdout, ran.stdout);
    } else {
        try std.testing.expectEqual(@as(u8, 1), ran.status);
        try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "E_CORE_UNSUPPORTED") != null);
    }
    const original = program.module.functions.items[1].insts.items[program.operation.index()];
    program.module.functions.items[1].insts.items[program.operation.index()].ty = .cap;
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &program.module, &failure));
    program.module.functions.items[1].insts.items[program.operation.index()] = original;
    const f = &program.module.functions.items[1];
    if (op == .func_ref) {
        f.insts.items[program.operation.index()].data = program.module.functions.items.len;
    } else {
        const wrong: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
        try f.insts.append(a, .{ .op = .iconst, .ty = .bool, .data = 1 });
        f.insts.items[program.operation.index()].a = wrong;
    }
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &program.module, &failure));
}

// spec: NEW-CORE-S2-IR-1
test "S2 IR dict_new emits valid LLVM and verifies its result type" {
    try exercise(.dict_new, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR dict_len emits valid LLVM and verifies its result type" {
    try exercise(.dict_len, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR dict_find emits valid LLVM and verifies its result type" {
    try exercise(.dict_find, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR dict_entry_key emits valid LLVM and verifies its result type" {
    try exercise(.dict_entry_key, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR dict_entry_value emits valid LLVM and verifies its result type" {
    try exercise(.dict_entry_value, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR dict_set_value emits valid LLVM and verifies its result type" {
    try exercise(.dict_set_value, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR dict_insert emits valid LLVM and verifies its result type" {
    try exercise(.dict_insert, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR dict_remove emits valid LLVM and verifies its result type" {
    try exercise(.dict_remove, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR dict_entries emits valid LLVM and verifies its result type" {
    try exercise(.dict_entries, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR dict_entry_live emits valid LLVM and verifies its result type" {
    try exercise(.dict_entry_live, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR dict_copy emits valid LLVM and verifies its result type" {
    try exercise(.dict_copy, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR dict_clear emits valid LLVM and verifies its result type" {
    try exercise(.dict_clear, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR str_char emits valid LLVM and verifies its result type" {
    try exercise(.str_char, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR str_width emits valid LLVM and verifies its result type" {
    try exercise(.str_width, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR str_code emits valid LLVM and verifies its result type" {
    try exercise(.str_code, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR str_append emits valid LLVM and verifies its result type" {
    try exercise(.str_append, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR str_append_char emits valid LLVM and verifies its result type" {
    try exercise(.str_append_char, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR str_slice emits valid LLVM and verifies its result type" {
    try exercise(.str_slice, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR str_view_of emits valid LLVM and verifies its result type" {
    try exercise(.str_view_of, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR str_from_view emits valid LLVM and verifies its result type" {
    try exercise(.str_from_view, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR list_sort emits valid LLVM and verifies its result type" {
    try exercise(.list_sort, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR array_get emits valid LLVM and verifies its result type" {
    try exercise(.array_get, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR array_set emits valid LLVM and verifies its result type" {
    try exercise(.array_set, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR func_ref emits valid LLVM and verifies its result type" {
    try exercise(.func_ref, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 IR call_indirect emits valid LLVM and verifies its result type" {
    try exercise(.call_indirect, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 foundations intern types, preserve layout and print complete operand shapes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m: ir.Module = .{};
    const dict = try m.intern(a, .{ .dict = .{ .key = .str, .value = .i64 } });
    const array = try m.intern(a, .{ .array = .{ .elem = .i16, .n = 3 } });
    const big = try m.intern(a, .{ .array = .{ .elem = .str, .n = 5 } });
    const fn_ty = try m.intern(a, .{ .@"fn" = .{ .params = &.{ array, .i64 }, .ret = .bool, .owned = 1 } });
    try std.testing.expectEqual(fn_ty, try m.intern(a, .{ .@"fn" = .{ .params = &.{ array, .i64 }, .ret = .bool, .owned = 1 } }));
    try std.testing.expectEqualStrings("dict[str, i64]", try print.typeName(a, &m, dict));
    try std.testing.expectEqualStrings("[3]i16", try print.typeName(a, &m, array));
    try std.testing.expectEqualStrings("fn{[3]i16, i64} -> bool", try print.typeName(a, &m, fn_ty));
    try std.testing.expectEqual(@as(u32, 6), m.size(array));
    try std.testing.expectEqual(@as(u32, 2), m.alignment(array));
    try std.testing.expect(m.isBlock(dict) and m.isBlock(.bytes) and !m.isBlock(array));
    try std.testing.expect(m.managed(big) and !m.managed(array) and !m.managed(fn_ty) and !m.managed(.str_view));
    try std.testing.expect(m.passedInMemory(big));
    try std.testing.expectEqual(@as(u32, 4), m.pathTarget(array, ir.FieldPath.init(&.{2}).?).?.offset);
    try std.testing.expectEqual(ir.UnionForm.niche, m.unionLayout(try m.option(a, dict)).form);
    const program = try operationProgram(a, .dict_insert);
    try std.testing.expect(std.mem.indexOf(u8, try print.module(a, &program.module), "dict_insert dict[i64, i64] undef, %") != null);
    try std.testing.expect(ir.Op.dict_insert.consumesOperand0() and ir.Op.str_append.consumesOperand0() and ir.Op.list_sort.consumesOperand0());
    try std.testing.expect(!ir.Op.dict_find.consumesOperand0());
}

fn cowProgram(a: std.mem.Allocator, owned: bool) !ir.Module {
    var m: ir.Module = .{};
    const dict = try m.intern(a, .{ .dict = .{ .key = .i64, .value = .i64 } });
    const list = try m.intern(a, .{ .list = .i64 });
    var h = try Hand.init(a, &m, "updates", .{ .params = try a.dupe(ir.Type, &.{ dict, .str, list }), .ret = .void, .owned = if (owned) 7 else 0 });
    const d = try h.param(0);
    const text = try h.param(1);
    const xs = try h.param(2);
    const key = try h.int(.i64, 7);
    const probe = try h.emit(.{ .op = .dict_find, .ty = .i64, .a = d, .b = key });
    _ = try h.emit(.{ .op = .dict_insert, .ty = dict, .a = d, .b = probe, .data = try h.extra(&.{ key, key }) });
    _ = try h.emit(.{ .op = .str_append, .ty = .str, .a = text, .b = text });
    _ = try h.emit(.{ .op = .list_sort, .ty = list, .a = xs, .b = try h.int(.bool, 0) });
    _ = try h.emit(.{ .op = .ret, .ty = .void });
    _ = try h.finish();
    return m;
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 ownership copies borrowed updates and recomputes insert probes on copied dictionaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var borrowed = try cowProgram(a, false);
    const stats = try own.run(a, &borrowed, .{ .verify = true });
    try support.verified(a, &borrowed, &.{});
    const text = try print.module(a, &borrowed);
    try std.testing.expectEqual(@as(u32, 3), stats.copied);
    try std.testing.expect(std.mem.indexOf(u8, text, "dict_copy") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "str_from_view") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_copy") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, text, "dict_find"));
    var owned = try cowProgram(a, true);
    const owned_stats = try own.run(a, &owned, .{});
    try support.verified(a, &owned, &.{});
    try std.testing.expectEqual(@as(u32, 3), owned_stats.tested);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, try print.module(a, &owned), "is_unique"));
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 verifier rejects insert probes from a different dictionary or key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var program = try operationProgram(a, .dict_insert);
    const f = &program.module.functions.items[1];
    const inst = f.inst(program.operation);
    const probe = f.resolve(inst.b);
    const other: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(a, .{ .op = .undef, .ty = inst.ty });
    f.insts.items[probe.index()].a = other;
    var failure: verify_ir.Failure = .{};
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &program.module, &failure));
    try std.testing.expect(std.mem.indexOf(u8, failure.reason, "same dictionary and key") != null);
    f.insts.items[probe.index()].a = inst.a;
    f.insts.items[probe.index()].b = other;
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &program.module, &failure));
}

fn viewEscape(a: std.mem.Allocator, escape: ir.Op) !ir.Module {
    var program = try operationProgram(a, .str_view_of);
    const f = &program.module.functions.items[1];
    const block = &f.blocks.items[0];
    const term = block.insts.items[block.insts.items.len - 1];
    const value = program.operation;
    var inst: ir.Inst = .{ .op = escape, .ty = .void, .a = value };
    switch (escape) {
        .ret => {
            f.insts.items[term.index()].a = value;
            return program.module;
        },
        .phi => {
            inst.ty = .str_view;
            inst.a = .none;
            inst.data = (ir.ExtraSlice{ .start = 0, .len = 0 }).pack();
        },
        .box_make => inst.ty = try program.module.intern(a, .{ .box = .str }),
        .call => {
            inst.a = @fromBackingInt(0);
            const start: u32 = @intCast(f.extra.items.len);
            try f.extra.append(a, value);
            inst.data = (ir.ExtraSlice{ .start = start, .len = 1 }).pack();
            inst.ty = .i64;
        },
        else => unreachable,
    }
    const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(a, inst);
    try block.insts.insert(a, if (escape == .phi) 0 else block.insts.items.len - 1, ref);
    return program.module;
}

fn rejectView(a: std.mem.Allocator, escape: ir.Op) !void {
    const m = try viewEscape(a, escape);
    var failure: verify_ir.Failure = .{};
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &m, &failure));
    try std.testing.expect(std.mem.indexOf(u8, failure.reason, "str_view") != null);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 verifier rejects string views at phis, stores, returns and non-admitted calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try rejectView(a, .phi);
    try rejectView(a, .box_make);
    try rejectView(a, .ret);
    try rejectView(a, .call);
    try std.testing.expect(true);
}

fn arrayOwnedProgram(a: std.mem.Allocator, count: u32) !ir.Module {
    var m: ir.Module = .{};
    try m.strings.append(a, "ab");
    const array = try m.intern(a, .{ .array = .{ .elem = .str, .n = count } });
    const list = try m.intern(a, .{ .list = array });
    const sig: ir.Signature = .{ .params = try a.dupe(ir.Type, &.{array}), .ret = array, .owned = 1 };
    const fn_ty = try m.intern(a, .{ .@"fn" = sig });
    var target = try Hand.init(a, &m, "replace", sig);
    const text = try target.loose(.{ .op = .str_const, .ty = .str });
    const fresh = try target.emit(.{ .op = .str_char, .ty = .str, .a = text, .b = try target.int(.u64, 1) });
    const updated = try target.emit(.{ .op = .array_set, .ty = array, .a = try target.param(0), .b = try target.int(.i64, 0), .data = try target.extra(&.{fresh}), .check = .exact });
    _ = try target.emit(.{ .op = .ret, .ty = .void, .a = updated });
    _ = try target.finish();
    m.entry = 1;
    var h = try Hand.init(a, &m, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const literal = try h.loose(.{ .op = .str_const, .ty = .str });
    const first = try h.emit(.{ .op = .str_char, .ty = .str, .a = literal, .b = try h.int(.u64, 0) });
    const elements = try a.alloc(ir.Ref, count);
    @memset(elements, first);
    const initial = try h.emit(.{ .op = .record_make, .ty = array, .data = try h.extra(elements) });
    const pointer = try h.loose(.{ .op = .func_ref, .ty = fn_ty, .data = 0 });
    const result = try h.emit(.{ .op = .call_indirect, .ty = array, .a = pointer, .data = try h.extra(&.{initial}) });
    const old = try h.emit(.{ .op = .array_get, .ty = .str, .a = initial, .b = try h.int(.i64, 0), .check = .exact });
    const new = try h.emit(.{ .op = .array_get, .ty = .str, .a = result, .b = try h.int(.i64, 0), .check = .exact });
    try h.printValues(try h.param(0), &.{ old, new });
    const container = try h.emit(.{ .op = .list_new, .ty = list, .a = try h.int(.u64, 1) });
    _ = try h.emit(.{ .op = .list_push, .ty = list, .a = container, .b = result });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return m;
}

fn exerciseArrayOwnership(count: u32, allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m = try arrayOwnedProgram(a, count);
    const debug = try support.runOwned(a, &m, .{ .verify = true });
    try std.testing.expectEqual(@as(u8, 0), debug.status);
    try std.testing.expectEqualStrings("a b\n", debug.stdout);
    try std.testing.expectEqualStrings("", debug.stderr);
    const core = try print.module(a, &m);
    try std.testing.expect(std.mem.indexOf(u8, core, "retain ") != null);
    try std.testing.expect(std.mem.indexOf(u8, debug.llvm, "@myl.layout.") != null);
    var release_m = try arrayOwnedProgram(a, count);
    const result = try passes.run(a, &release_m, .verify);
    try support.verified(a, &release_m, result.plans);
    const release = try support.runOwned(a, &release_m, .{ .release = true, .verify = true, .own = false });
    try std.testing.expectEqual(@as(u8, 0), release.status);
    try std.testing.expectEqualStrings(debug.stdout, release.stdout);
    try std.testing.expectEqualStrings("", release.stderr);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 indirect calls own managed array arguments and return arrays in registers" {
    try exerciseArrayOwnership(2, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 indirect calls own managed array arguments and return arrays through sret" {
    try exerciseArrayOwnership(5, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 array construction rejects wrong arity and element types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m = try arrayOwnedProgram(a, 2);
    const f = &m.functions.items[1];
    var failure: verify_ir.Failure = .{};
    const made: ir.Ref = @fromBackingInt(3);
    try std.testing.expectEqual(ir.Op.record_make, f.inst(made).op);
    const original = f.inst(made);
    f.insts.items[made.index()].data = (ir.ExtraSlice{ .start = ir.ExtraSlice.unpack(original.data).start, .len = 1 }).pack();
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &m, &failure));
    f.insts.items[made.index()] = original;
    const wrong: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(a, .{ .op = .iconst, .ty = .bool, .data = 1 });
    f.extra.items[ir.ExtraSlice.unpack(original.data).start] = wrong;
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &m, &failure));
}

fn spanProgram(a: std.mem.Allocator) !ir.Module {
    var m: ir.Module = .{};
    const list = try m.intern(a, .{ .list = .str });
    try m.strings.append(a, "Aé💩");
    try m.functions.append(a, .{ .name = "myl_core_ir_span_materialize", .signature = .{ .params = &.{.str}, .ret = .str, .linkage = .extern_c, .views = 1 } });
    m.entry = 1;
    var h = try Hand.init(a, &m, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const text = try h.loose(.{ .op = .str_const, .ty = .str });
    const first = try h.emit(.{ .op = .str_char, .ty = .str, .a = text, .b = try h.int(.u64, 1) });
    const last = try h.emit(.{ .op = .str_char, .ty = .str, .a = text, .b = try h.int(.u64, 3) });
    const view = try h.emit(.{ .op = .str_view_of, .ty = .str_view, .a = first, .b = try h.int(.u64, 0), .data = try h.extra(&.{try h.int(.u64, 2)}) });
    const xs = try h.emit(.{ .op = .list_new, .ty = list, .a = try h.int(.u64, 1) });
    _ = try h.emit(.{ .op = .list_push, .ty = list, .a = xs, .b = first });
    const copy = try h.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(0), .data = try h.extra(&.{view}) });
    try h.printValues(try h.param(0), &.{ copy, last });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return m;
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 views admit explicit extern span helpers and keep their owner live without counting the span" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m = try spanProgram(a);
    const ran = try support.runOwned(a, &m, .{ .release = true, .verify = true });
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("é 💩\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
    try std.testing.expect(std.mem.indexOf(u8, ran.llvm, "declare ptr @myl_core_ir_span_materialize(ptr, i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, try print.module(a, &m), "retain %") != null);
    var unadmitted = try spanProgram(a);
    unadmitted.functions.items[0].signature.views = 0;
    var failure: verify_ir.Failure = .{};
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &unadmitted, &failure));
    try std.testing.expect(std.mem.indexOf(u8, failure.reason, "str_view escapes through call") != null);
}

fn rejectStoredView(a: std.mem.Allocator, compound: ir.Compound) !void {
    var m: ir.Module = .{};
    if (std.meta.activeTag(compound) == .box) _ = try m.intern(a, .{ .record = &.{.str_view} });
    _ = try m.intern(a, compound);
    var failure: verify_ir.Failure = .{};
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &m, &failure));
    try std.testing.expect(std.mem.indexOf(u8, failure.reason, "storage representation") != null);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 string views have no storage representation even in nested aggregates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try rejectStoredView(a, .{ .list = .str_view });
    try rejectStoredView(a, .{ .array = .{ .elem = .str_view, .n = 2 } });
    try rejectStoredView(a, .{ .@"union" = &.{ .void, .str_view } });
    try rejectStoredView(a, .{ .box = @fromBackingInt(ir.Type.first_compound) });
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 function references and indirect calls reject differing parameter, result and ownership signatures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var program = try operationProgram(a, .call_indirect);
    const f = &program.module.functions.items[1];
    const callee = f.resolve(f.inst(program.operation).a);
    const ty = f.inst(callee).ty;
    const compound = &program.module.compounds.items[@backingInt(ty) - ir.Type.first_compound];
    var failure: verify_ir.Failure = .{};
    compound.@"fn".owned = 1;
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &program.module, &failure));
    compound.@"fn".owned = 0;
    compound.@"fn".ret = .bool;
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &program.module, &failure));
    compound.@"fn".ret = .i64;
    compound.@"fn".params = &.{.bool};
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &program.module, &failure));
}

fn refuseSource(a: std.mem.Allocator, source: []const u8, reason: []const u8) !void {
    var refusal: @import("build.zig").Refusal = .{};
    try std.testing.expectError(error.Unsupported, support.buildSource(a, source, &refusal));
    try std.testing.expectEqualStrings(reason, refusal.reason);
}

// spec-case: NEW-CORE-S2-IR-1
test "S2 builder dispatch stubs keep precise source refusals until Wave B" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try refuseSource(a, "def main() -> int:\n    d: dict[int, int] = {}\n    return len(d)\n", "dict type");
    try refuseSource(a, "def main() -> int:\n    raw = b\"abc\"\n    return len(raw)\n", "bytes type");
    try refuseSource(a, "def main() -> int:\n    xs: [2]int = [1, 2]\n    return xs[0]\n", "fixed array type");
    try refuseSource(a, "def target(x: int) -> int effects():\n    return x\ndef main() -> int:\n    f = target\n    return f(1)\n", "function_value");
    try refuseSource(a, "def main() -> int:\n    s = \"abc\"\n    ch = s[0]\n    return len(ch)\n", "index");
    try std.testing.expect(true);
}
