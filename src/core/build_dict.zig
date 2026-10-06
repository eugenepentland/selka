//! Dictionary and set lowering through layout-independent Core operations.
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const typed = @import("mylang").typed;
const Operation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");
const ordinal_symbol = "myl_core_dict_ordinal";

/// Allocation or an unsupported source construct stops lowering.
pub const Error = error{ OutOfMemory, Unsupported };

/// Hashable scalar and text keys supported by the dictionary runtime.
pub fn keySupported(module: ir.Module, key: ir.Type) bool {
    if (key.integer() != null or key == .bool or key == .void) return true;
    if (key == .str or key == .bytes or key == .f64) return true;
    return switch (module.kind(key) orelse return false) {
        .record => blk: {
            for (module.compound(key).record) |field| if (!keySupported(module, field)) break :blk false;
            break :blk true;
        },
        .@"union" => blk: {
            for (module.compound(key).@"union") |case| if (!keySupported(module, case)) break :blk false;
            break :blk true;
        },
        .array => keySupported(module, module.compound(key).array.elem),
        .box, .list => true,
        else => false,
    };
}

/// Find a key without mutating the table or caching a mutable hint.
pub fn find(comptime Context: type, b: Context, dict: ir.Ref, key: ir.Ref, span: u32) Error!ir.Ref {
    return b.emit(.{ .op = .dict_find, .ty = .i64, .a = dict, .b = key, .span = span });
}

/// Dictionary literals evaluate each key and value once, in source order.
pub fn literal(comptime Context: type, b: Context, ty: ir.Type, items: []const typed.NodeId, span: u32) Error!ir.Ref {
    var dict = try b.emit(.{ .op = .dict_new, .ty = ty, .a = try b.constant(.u64, @intCast(items.len / 2)), .span = span });
    var at: usize = 0;
    while (at < items.len) : (at += 2) {
        const key = try b.expression(items[at]);
        const value = try b.expression(items[at + 1]);
        if (b.current == null) return .none;
        dict = try put(Context, b, dict, key, value, span);
    }
    return dict;
}

fn present(comptime Context: type, b: Context, probe: ir.Ref, span: u32) Error!ir.Ref {
    return b.emit(.{ .op = .cmp, .ty = .bool, .a = probe, .b = try b.constant(.i64, 0), .data = @backingInt(ir.Predicate.ge), .span = span });
}

fn valueAt(comptime Context: type, b: Context, dict: ir.Ref, probe: ir.Ref, span: u32) Error!ir.Ref {
    const value_type = b.module().compound(b.typeOfRef(dict)).dict.value;
    return if (value_type == .void) .none else b.emit(.{ .op = .dict_entry_value, .ty = value_type, .a = dict, .b = probe, .span = span });
}

/// A required lookup traps with the old core missing-key category.
pub fn requirePresent(comptime Context: type, b: Context, probe: ir.Ref, span: u32) Error!void {
    const yes = try b.newBlock();
    const no = try b.newBlock();
    try b.branch(try present(Context, b, probe, span), yes, no, span);
    try b.seal(yes);
    try b.seal(no);
    b.current = no;
    _ = try b.emit(.{ .op = .@"unreachable", .ty = .void, .data = flags.dict_missing_trap, .span = span });
    b.current = yes;
}

/// Replace or append one entry, preserving the probe's SSA provenance.
pub fn put(comptime Context: type, b: Context, dict: ir.Ref, key: ir.Ref, value: ir.Ref, span: u32) Error!ir.Ref {
    const stored_value = if (value == .none) try b.emit(.{ .op = .undef, .ty = .void }) else value;
    const probe = try find(Context, b, dict, key, span);
    const found = try b.newBlock();
    const missing = try b.newBlock();
    const join = try b.newBlock();
    const ty = b.typeOfRef(dict);
    const result = try b.synthetic(ty);
    try b.branch(try present(Context, b, probe, span), found, missing, span);
    try b.seal(found);
    try b.seal(missing);
    b.current = found;
    const updated = if (value == .none) dict else try b.emit(.{ .op = .dict_set_value, .ty = ty, .a = dict, .b = probe, .data = try b.extraSlice(&.{value}), .span = span });
    try b.write(result, b.current.?, updated);
    try b.jump(join);
    b.current = missing;
    const inserted = try b.emit(.{ .op = .dict_insert, .ty = ty, .a = dict, .b = probe, .data = try b.extraSlice(&.{ key, stored_value }), .span = span });
    try b.write(result, b.current.?, inserted);
    try b.jump(join);
    try b.seal(join);
    b.enter(join);
    return b.read(result, join);
}

fn selectValue(comptime Context: type, b: Context, dict: ir.Ref, probe: ir.Ref, fallback: ir.Ref, span: u32) Error!ir.Ref {
    const ty = b.module().compound(b.typeOfRef(dict)).dict.value;
    const found = try b.newBlock();
    const missing = try b.newBlock();
    const join = try b.newBlock();
    const result = if (ty == .void) null else try b.synthetic(ty);
    try b.branch(try present(Context, b, probe, span), found, missing, span);
    try b.seal(found);
    try b.seal(missing);
    b.current = found;
    if (result) |slot| try b.write(slot, b.current.?, try valueAt(Context, b, dict, probe, span));
    try b.jump(join);
    b.current = missing;
    if (result) |slot| try b.write(slot, b.current.?, fallback);
    try b.jump(join);
    try b.seal(join);
    b.enter(join);
    return if (result) |slot| b.read(slot, join) else .none;
}

/// Lower checked dictionary methods; iteration guards use the shared builder path.
pub fn operation(comptime Context: type, b: Context, op: Operation, ty: ir.Type, span: u32, out: ?*?@import("std").meta.Child(Context).FeaturePlace) Error!ir.Ref {
    const owner = op.owner;
    const args = op.arguments;
    switch (op.kind) {
        .length => return b.emit(.{ .op = .dict_len, .ty = .u64, .a = try b.receiverOf(owner), .span = span }),
        .capacity => return b.emit(.{ .op = .dict_entries, .ty = .u64, .a = try b.receiverOf(owner), .span = span }),
        .copy => return b.receiverOf(owner),
        .keys, .values => {
            const dict = try b.receiverOf(owner);
            const length = try b.emit(.{ .op = .dict_len, .ty = .u64, .a = dict, .span = span });
            const list = try b.emit(.{ .op = .list_new, .ty = ty, .a = length, .span = span });
            return copyEntries(Context, b, dict, list, op.kind == .keys, span);
        },
        .update => {
            const other = try b.expression(args[0]);
            if (b.current == null) return .none;
            const dict = try b.writableReceiverOf(owner, span);
            try b.writeOwner(owner, try copyEntries(Context, b, other, dict, true, span), span);
            return .none;
        },
        .pop => {
            const dict = try b.writableReceiverOf(owner, span);
            const length = try b.emit(.{ .op = .dict_len, .ty = .u64, .a = dict, .span = span });
            const index = try b.emit(.{ .op = .sub, .ty = .i64, .a = try b.emit(.{ .op = .convert, .ty = .i64, .a = length, .check = .exact }), .b = try b.constant(.i64, 1), .span = span });
            try requirePresent(Context, b, index, span);
            const entry = try b.runtimeCall(ordinal_symbol, &.{ b.typeOfRef(dict), .i64 }, .i64, &.{ dict, index }, span);
            const value = try b.emit(.{ .op = .dict_entry_key, .ty = ty, .a = dict, .b = entry, .span = span });
            try b.writeOwner(owner, try b.emit(.{ .op = .dict_remove, .ty = b.typeOfRef(dict), .a = dict, .b = entry, .span = span }), span);
            return value;
        },
        .read, .get, .contains => {
            const dict = try b.receiverOf(owner);
            const key = try b.expression(args[0]);
            if (b.current == null) return .none;
            const fallback = if (op.kind == .get) try b.expression(args[1]) else .none;
            if (b.current == null) return .none;
            const probe = try find(Context, b, dict, key, span);
            if (op.kind == .contains) return present(Context, b, probe, span);
            if (op.kind == .get) return selectValue(Context, b, dict, probe, fallback, span);
            try requirePresent(Context, b, probe, span);
            if (out) |place| place.* = try b.extendPlace(try b.placeOfLocal(owner), .{ .element = probe });
            return valueAt(Context, b, dict, probe, span);
        },
        .write => {
            const key = try b.expression(args[0]);
            const value = try b.expression(args[1]);
            if (b.current == null) return .none;
            const dict = try b.writableReceiverOf(owner, span);
            try b.writeOwner(owner, try put(Context, b, dict, key, value, span), span);
            return .none;
        },
        .clear => {
            const dict = try b.writableReceiverOf(owner, span);
            try b.writeOwner(owner, try b.emit(.{ .op = .dict_clear, .ty = b.typeOfRef(dict), .a = dict, .span = span }), span);
            return .none;
        },
        .key_at, .value_at => {
            const index = try b.expression(args[0]);
            if (b.current == null) return .none;
            const dict = try b.receiverOf(owner);
            const entry = try b.runtimeCall(ordinal_symbol, &.{ b.typeOfRef(dict), .i64 }, .i64, &.{ dict, index }, span);
            return if (ty == .void) .none else b.emit(.{ .op = if (op.kind == .key_at) .dict_entry_key else .dict_entry_value, .ty = ty, .a = dict, .b = entry, .span = span });
        },
        .pop_key, .pop_default => {
            const key = try b.expression(args[0]);
            const fallback = if (op.kind == .pop_default) try b.expression(args[1]) else .none;
            if (b.current == null) return .none;
            const dict = try b.writableReceiverOf(owner, span);
            const probe = try find(Context, b, dict, key, span);
            if (op.kind == .pop_key) try requirePresent(Context, b, probe, span);
            const result = if (op.kind == .pop_key) try valueAt(Context, b, dict, probe, span) else try selectValue(Context, b, dict, probe, fallback, span);
            const found = try b.newBlock();
            const join = try b.newBlock();
            try b.branch(try present(Context, b, probe, span), found, join, span);
            try b.seal(found);
            b.current = found;
            const removed = try b.emit(.{ .op = .dict_remove, .ty = b.typeOfRef(dict), .a = dict, .b = probe, .span = span });
            try b.writeOwner(owner, removed, span);
            try b.jump(join);
            try b.seal(join);
            b.enter(join);
            return result;
        },
        .setdefault => {
            const key = try b.expression(args[0]);
            const given = try b.expression(args[1]);
            const fallback = if (given == .none) try b.emit(.{ .op = .undef, .ty = .void }) else given;
            if (b.current == null) return .none;
            const dict = try b.writableReceiverOf(owner, span);
            const probe = try find(Context, b, dict, key, span);
            const result = try selectValue(Context, b, dict, probe, fallback, span);
            const missing = try b.newBlock();
            const join = try b.newBlock();
            try b.branch(try present(Context, b, probe, span), join, missing, span);
            try b.seal(missing);
            b.current = missing;
            const inserted = try b.emit(.{ .op = .dict_insert, .ty = b.typeOfRef(dict), .a = dict, .b = probe, .data = try b.extraSlice(&.{ key, fallback }), .span = span });
            try b.writeOwner(owner, inserted, span);
            try b.jump(join);
            try b.seal(join);
            b.enter(join);
            return result;
        },
        else => return b.refuse(@tagName(op.kind), span),
    }
}

/// Order-independent dictionary equality compares each live key and value.
pub fn equal(comptime Context: type, b: Context, left: ir.Ref, right: ir.Ref, span: u32) Error!ir.Ref {
    const len_left = try b.emit(.{ .op = .dict_len, .ty = .u64, .a = left, .span = span });
    const len_right = try b.emit(.{ .op = .dict_len, .ty = .u64, .a = right, .span = span });
    const lengths = try b.emit(.{ .op = .cmp, .ty = .bool, .a = len_left, .b = len_right, .data = @backingInt(ir.Predicate.eq), .span = span });
    const result = try b.synthetic(.bool);
    const index = try b.synthetic(.u64);
    try b.write(result, b.current.?, lengths);
    try b.write(index, b.current.?, try b.constant(.u64, 0));
    const header = try b.newBlock();
    const body = try b.newBlock();
    const found = try b.newBlock();
    const missing = try b.newBlock();
    const latch = try b.newBlock();
    const join = try b.newBlock();
    try b.branch(lengths, header, join, span);
    b.current = header;
    const cursor = try b.read(index, header);
    const more = try b.emit(.{ .op = .cmp, .ty = .bool, .a = cursor, .b = len_left, .data = @backingInt(ir.Predicate.lt), .span = span });
    try b.branch(more, body, join, span);
    try b.seal(body);
    b.current = body;
    const entry = try b.runtimeCall(ordinal_symbol, &.{ b.typeOfRef(left), .u64 }, .i64, &.{ left, cursor }, span);
    const key_type = b.module().compound(b.typeOfRef(left)).dict.key;
    const key = try b.emit(.{ .op = .dict_entry_key, .ty = key_type, .a = left, .b = entry, .span = span });
    const probe = try find(Context, b, right, key, span);
    try b.branch(try present(Context, b, probe, span), found, missing, span);
    try b.seal(found);
    try b.seal(missing);
    b.current = missing;
    try b.write(result, b.current.?, try b.constant(.bool, 0));
    try b.jump(join);
    b.current = found;
    const same = if (b.module().compound(b.typeOfRef(left)).dict.value == .void) try b.constant(.bool, 1) else try b.equal(try valueAt(Context, b, left, entry, span), try valueAt(Context, b, right, probe, span), span);
    try b.write(result, b.current.?, same);
    try b.branch(same, latch, join, span);
    try b.seal(latch);
    b.current = latch;
    const next = try b.emit(.{ .op = .add, .ty = .u64, .a = cursor, .b = try b.constant(.u64, 1), .span = span });
    try b.write(index, b.current.?, next);
    try b.jump(header);
    try b.seal(header);
    try b.seal(join);
    b.enter(join);
    return b.read(result, join);
}

fn copyEntries(comptime Context: type, b: Context, source: ir.Ref, initial: ir.Ref, keys: bool, span: u32) Error!ir.Ref {
    const m = b.module();
    const target_type = b.typeOfRef(initial);
    const dictionary = m.kind(target_type) == .dict;
    const shape = m.compound(b.typeOfRef(source)).dict;
    const limit = try b.emit(.{ .op = .dict_len, .ty = .u64, .a = source, .span = span });
    const cursor = try b.synthetic(.u64);
    const target = try b.synthetic(target_type);
    try b.write(cursor, b.current.?, try b.constant(.u64, 0));
    try b.write(target, b.current.?, initial);
    const header = try b.newBlock();
    const body = try b.newBlock();
    const exit = try b.newBlock();
    try b.jump(header);
    b.enter(header);
    const index = try b.read(cursor, header);
    const output = try b.read(target, header);
    const more = try b.emit(.{ .op = .cmp, .ty = .bool, .a = index, .b = limit, .data = @backingInt(ir.Predicate.lt), .span = span });
    try b.branch(more, body, exit, span);
    try b.seal(body);
    b.enter(body);
    const entry = try b.runtimeCall(ordinal_symbol, &.{ b.typeOfRef(source), .u64 }, .i64, &.{ source, index }, span);
    const key = if (keys or dictionary) try b.emit(.{ .op = .dict_entry_key, .ty = shape.key, .a = source, .b = entry, .span = span }) else .none;
    const value = if (shape.value == .void) .none else if (!keys or dictionary) try valueAt(Context, b, source, entry, span) else .none;
    const list_value = if (keys) key else if (value == .none) try b.constant(.bool, 0) else value;
    const updated = if (dictionary) try put(Context, b, output, key, value, span) else try b.emit(.{ .op = .list_push, .ty = target_type, .a = output, .b = list_value, .span = span });
    try b.write(target, b.current.?, updated);
    try b.write(cursor, b.current.?, try b.emit(.{ .op = .add, .ty = .u64, .a = index, .b = try b.constant(.u64, 1), .span = span }));
    try b.jump(header);
    try b.seal(header);
    try b.seal(exit);
    b.enter(exit);
    return b.read(target, exit);
}
