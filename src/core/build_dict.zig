//! Dictionary and set lowering through layout-independent Core operations.
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const single_owner_copy = @import("single_owner_copy.zig");
const typed = @import("selka").typed;
const Operation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");
const ordinal_symbol = "myl_core_dict_ordinal";

/// Allocation or an unsupported source construct stops lowering.
pub const Error = error{ OutOfMemory, Unsupported };

/// Evaluated inputs of a borrowing lookup. Explicit copying can select its
/// source before forming an owning phi, without repeating effects or lookup.
pub const DefaultSelection = struct { dict: ir.Ref, probe: ir.Ref, fallback: ir.Ref };

/// Copy only the selected borrowed lookup value before constructing an owning join.
pub fn copyDefault(comptime Context: type, b: Context, selection: DefaultSelection, span: u32) Error!ir.Ref {
    const ty = b.module().compound(b.module().storageType(b.typeOfRef(selection.dict))).dict.value;
    const result = try b.synthetic(ty);
    const found = try b.newBlock();
    const missing = try b.newBlock();
    const end = try b.newBlock();
    try b.branch(try present(Context, b, selection.probe, span), found, missing, span);
    try b.seal(found);
    b.enter(found);
    const selected = try valueAt(Context, b, selection.dict, selection.probe, span);
    const copied = try single_owner_copy.copyAs(Context, b, selected, ty, span);
    try b.write(result, b.current.?, copied);
    try b.jump(end);
    try b.seal(missing);
    b.enter(missing);
    const copied_default = try single_owner_copy.copyAs(Context, b, selection.fallback, ty, span);
    try b.write(result, b.current.?, copied_default);
    try b.jump(end);
    try b.seal(end);
    b.enter(end);
    return b.read(result, end);
}

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
    // A key read through a borrow (a `const` bound to an element) is probed in its storage layout.
    const probed = try b.borrowStorage(try storedKey(Context, b, dict, key), span);
    return b.emit(.{ .op = .dict_find, .ty = .i64, .a = dict, .b = probed, .span = span });
}

/// Source unit keys occupy a canonical false byte in a physical bool slot.
/// Keep one reference for both probing and insertion (the frozen IR verifies it).
fn storedKey(comptime Context: type, b: Context, dict: ir.Ref, key: ir.Ref) Error!ir.Ref {
    if (key != .none) return key;
    return switch (b.module().compound(b.module().storageType(b.typeOfRef(dict))).dict.key) {
        .bool => b.constant(.bool, 0),
        .void => b.emit(.{ .op = .undef, .ty = .void }),
        else => error.Unsupported,
    };
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
    return valueAtMode(Context, b, dict, probe, false, span);
}

fn valueAtMode(comptime Context: type, b: Context, dict: ir.Ref, probe: ir.Ref, take: bool, span: u32) Error!ir.Ref {
    const value_type = b.module().compound(b.module().storageType(b.typeOfRef(dict))).dict.value;
    return if (value_type == .void) .none else b.emit(.{ .op = .dict_entry_value, .ty = value_type, .a = dict, .b = probe, .data = if (take) flags.dict_take_value else 0, .span = span });
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
    return putKey(Context, b, dict, key, value, .consumed, span);
}

/// Whether a store consumes its key or only reads it.
pub const KeyMode = enum {
    /// The key is an owned value the store takes: a new entry stores it, an existing one drops it.
    consumed,
    /// The key is borrowed (`d[k] = v` with `k` a place): a new entry stores an independent copy made on the
    /// missing edge, and an existing entry keeps the key it has, so a hit allocates nothing.
    borrowed,
};

/// Replace or append one entry (`put`), with the key consumed or only read.
pub fn putKey(comptime Context: type, b: Context, dict: ir.Ref, key: ir.Ref, value: ir.Ref, mode: KeyMode, span: u32) Error!ir.Ref {
    const stored_key = try storedKey(Context, b, dict, key);
    const stored_value = if (value == .none) try b.emit(.{ .op = .undef, .ty = .void }) else value;
    const probe = try find(Context, b, dict, stored_key, span);
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
    // A borrowed key is copied only here, where the entry is new; the copy is probed again, as the key copy that the
    // ownership pass delays to the insertion is, so the insertion's probe belongs to the key it stores.
    const inserted_key = if (mode == .borrowed) try b.copyOwned(stored_key, span) else stored_key;
    const inserted_probe = if (mode == .borrowed) try find(Context, b, dict, inserted_key, span) else probe;
    const borrowed_key: u64 = if (mode == .borrowed) flags.borrowed_key_insert else 0;
    const inserted = try b.emit(.{ .op = .dict_insert, .ty = ty, .a = dict, .b = inserted_probe, .data = (try b.extraSlice(&.{ inserted_key, stored_value })) | borrowed_key, .span = span });
    try b.write(result, b.current.?, inserted);
    try b.jump(join);
    try b.seal(join);
    b.enter(join);
    return b.read(result, join);
}

/// The list view of the value a probe found, or of `fallback` when the probe missed (C9 lists): a merge of list views,
/// each a borrow of a list that outlives the read.
fn selectView(comptime Context: type, b: Context, dict: ir.Ref, probe: ir.Ref, fallback: ir.Ref, span: u32) Error!ir.Ref {
    // The dictionary's values are lists: the view is of their elements.
    const element = b.module().compound(b.module().compound(b.module().storageType(b.typeOfRef(dict))).dict.value).list;
    const view_type = try b.module().intern(b.allocator(), .{ .list_view = element });
    const found = try b.newBlock();
    const missing = try b.newBlock();
    const join = try b.newBlock();
    const result = try b.synthetic(view_type);
    try b.branch(try present(Context, b, probe, span), found, missing, span);
    try b.seal(found);
    try b.seal(missing);
    b.enter(found);
    const stored = try valueAtMode(Context, b, dict, probe, false, span);
    const view = try b.emit(.{ .op = .list_view_of, .ty = view_type, .a = stored, .span = span });
    try b.write(result, b.current.?, view);
    try b.jump(join);
    b.enter(missing);
    try b.write(result, b.current.?, fallback);
    try b.jump(join);
    try b.seal(join);
    b.enter(join);
    return b.read(result, join);
}

/// The text or bytes view of the value a probe found, or of `fallback` when the probe missed (CX2): a merge of two borrowed
/// views, read in place. A copy of the selection copies it once; a read copies nothing. The view family is the default's.
fn selectSpanView(comptime Context: type, b: Context, dict: ir.Ref, probe: ir.Ref, fallback: ir.Ref, span: u32) Error!ir.Ref {
    const view_type = b.typeOfRef(fallback);
    const text = view_type == .str_view;
    const found = try b.newBlock();
    const missing = try b.newBlock();
    const join = try b.newBlock();
    const result = try b.synthetic(view_type);
    try b.branch(try present(Context, b, probe, span), found, missing, span);
    try b.seal(found);
    try b.seal(missing);
    b.enter(found);
    const stored = try valueAtMode(Context, b, dict, probe, false, span);
    const length = try b.emit(.{ .op = if (text) .str_len else .list_len, .ty = .u64, .a = stored, .span = span });
    const view = try b.emit(.{ .op = .str_view_of, .ty = view_type, .a = stored, .b = try b.constant(.u64, 0), .data = try b.extraSlice(&.{length}), .span = span });
    try b.write(result, b.current.?, view);
    try b.jump(join);
    b.enter(missing);
    try b.write(result, b.current.?, fallback);
    try b.jump(join);
    try b.seal(join);
    b.enter(join);
    return b.read(result, join);
}

fn selectValue(comptime Context: type, b: Context, dict: ir.Ref, probe: ir.Ref, fallback: ir.Ref, take: bool, span: u32) Error!ir.Ref {
    const stored = b.module().compound(b.module().storageType(b.typeOfRef(dict))).dict.value;
    // Read-only wrapper defaults keep their transient ABI on both edges. A
    // removal still transfers the canonical owning dictionary value.
    const borrowed = !take and b.module().containsBorrow(b.typeOfRef(fallback));
    const ty = if (borrowed) b.typeOfRef(fallback) else stored;
    const found = try b.newBlock();
    const missing = try b.newBlock();
    const join = try b.newBlock();
    const result = if (ty == .void) null else try b.synthetic(ty);
    try b.branch(try present(Context, b, probe, span), found, missing, span);
    try b.seal(found);
    try b.seal(missing);
    b.current = found;
    if (result) |slot| {
        const value = try valueAtMode(Context, b, dict, probe, take, span);
        const selected = if (borrowed) try b.readOnlyArgument(value, ty, span) else value;
        try b.write(slot, b.current.?, selected);
    }
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
        .copy => {
            const source = try b.receiverOf(owner);
            return copy(Context, b, source, span);
        },
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
            const value = if (ty == .void) .none else try b.emit(.{ .op = .dict_entry_key, .ty = ty, .a = dict, .b = entry, .data = flags.dict_take_key, .span = span });
            try b.writeOwner(owner, try b.emit(.{ .op = .dict_remove, .ty = b.typeOfRef(dict), .a = dict, .b = entry, .data = flags.dict_take_key, .span = span }), span);
            return value;
        },
        .read, .get, .contains => {
            // The probe, selected value and exact borrowing marker must name
            // one physical dictionary alias while retaining its borrow parent.
            const dict = try b.borrowStorage(try b.receiverOf(owner), span);
            const key = try b.expression(args[0]);
            if (b.current == null) return .none;
            // A literal `[]` default is the static empty list, an immortal constant (4c, 4e).
            const fallback = if (op.kind != .get) .none else (try b.staticEmptyList(args[1], span)) orelse try b.expression(args[1]);
            if (b.current == null) return .none;
            const stored_key = try storedKey(Context, b, dict, key);
            const probe = try find(Context, b, dict, stored_key, span);
            if (op.kind == .contains) return present(Context, b, probe, span);
            if (op.kind == .get) {
                // A list-view default makes the selection a list view too (C9 lists): a borrow of the selected list, read in
                // place, so the default is passed as it is and nothing is copied for it.
                if (b.mb.module.kind(b.typeOfRef(fallback)) == .list_view) return selectView(Context, b, dict, probe, fallback, span);
                // A text or bytes view default selects a view the same way (CX2): no copy is made for a read.
                if (b.typeOfRef(fallback).isSpan()) return selectSpanView(Context, b, dict, probe, fallback, span);
                const selected = try selectValue(Context, b, dict, probe, fallback, false, span);
                if (!b.module().managed(ty)) return selected;
                // Transient wrappers carry their loan ancestry through their
                // payloads and phi, as top-level spans and list views do.
                const result = if (b.module().containsBorrow(b.typeOfRef(selected))) selected else try b.borrowSelection(selected, dict, fallback, span);
                try b.rememberDefault(result, .{ .dict = dict, .probe = probe, .fallback = fallback });
                return result;
            }
            try requirePresent(Context, b, probe, span);
            if (out) |place| place.* = try b.extendPlace(try b.placeOfLocal(owner), .{ .mapping = stored_key });
            return valueAt(Context, b, dict, probe, span);
        },
        .write => {
            const key = try b.expression(args[0]);
            const given = try b.expression(args[1]);
            if (b.current == null) return .none;
            const captured = try b.receiverOf(owner);
            // Validate the current place and prepare parent reconstruction even
            // when the exact entry below reuses its captured dictionary. A value that is the hidden read of the entry
            // rebuilds the parents from the reads the dictionary was reached by, so they are taken once (FR66).
            const dict = try b.writableReceiverReusing(owner, b.slotReads(args[1], .entry), span);
            const stored_key = try storedKey(Context, b, dict, key);
            // A dictionary of borrows (RB2) holds the value's read-only overlay.
            const value = try b.lentElementOf(dict, given, span);
            if (try b.transferSlotRead(args[1], captured, stored_key)) |probe| {
                // A reconstructed field goes back into its already-read entry.
                // The key remains a lookup loan; no insertion can own it.
                try requirePresent(Context, b, probe, span);
                try b.writeOwner(owner, try b.listSet(captured, probe, value, span), span);
            } else try b.writeOwner(owner, try putKey(Context, b, dict, stored_key, value, if (op.borrowed_key) .borrowed else .consumed, span), span);
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
        .pop_key, .pop_default => return popEntry(Context, b, op, span),
        .setdefault => {
            const key = try b.expression(args[0]);
            const given = try b.expression(args[1]);
            const fallback = if (given == .none) try b.emit(.{ .op = .undef, .ty = .void }) else given;
            if (b.current == null) return .none;
            const dict = try b.writableReceiverOf(owner, span);
            const stored_key = try storedKey(Context, b, dict, key);
            const probe = try find(Context, b, dict, stored_key, span);
            return ownedDefault(Context, b, owner, dict, probe, .{ .key = stored_key, .fallback = fallback, .borrowed = op.borrowed_key }, span);
        },
        else => return b.refuse(@tagName(op.kind), span),
    }
}

// Required removal has one continuing owner edge; a default keeps the missing edge.
fn popEntry(comptime Context: type, b: Context, op: Operation, span: u32) Error!ir.Ref {
    const owner = op.owner;
    const args = op.arguments;
    const key = try b.expression(args[0]);
    const fallback = if (op.kind == .pop_default) try b.expression(args[1]) else .none;
    if (b.current == null) return .none;
    const dict = try b.writableReceiverOf(owner, span);
    const probe = try find(Context, b, dict, key, span);
    if (op.kind == .pop_key) try requirePresent(Context, b, probe, span);
    const result = if (op.kind == .pop_key) try valueAtMode(Context, b, dict, probe, true, span) else try selectValue(Context, b, dict, probe, fallback, true, span);
    if (op.kind == .pop_key) {
        // The missing edge already traps. Keep the owner transfer on
        // this edge instead of joining it with the unmodified owner.
        const removed = try b.emit(.{ .op = .dict_remove, .ty = b.typeOfRef(dict), .a = dict, .b = probe, .data = flags.dict_take_value, .span = span });
        try b.writeOwner(owner, removed, span);
        return result;
    }
    // The dictionary is written back after the join on both edges, the removal's result on one and the dictionary
    // itself on the other, so a dictionary field of a `mut` record is taken out and put back on every path: a write-back
    // on the found edge alone leaves the field borrowed on the missing edge, which the ownership pass cannot schedule
    // (`sets.discard(mut st.seen, name)`, F-RA-807).
    const found = try b.newBlock();
    const missing = try b.newBlock();
    const join = try b.newBlock();
    const merged = try b.synthetic(b.typeOfRef(dict));
    try b.branch(try present(Context, b, probe, span), found, missing, span);
    try b.seal(found);
    try b.seal(missing);
    b.current = found;
    const removed = try b.emit(.{ .op = .dict_remove, .ty = b.typeOfRef(dict), .a = dict, .b = probe, .data = flags.dict_take_value, .span = span });
    try b.write(merged, b.current.?, removed);
    try b.jump(join);
    b.current = missing;
    try b.write(merged, b.current.?, dict);
    try b.jump(join);
    try b.seal(join);
    b.enter(join);
    try b.writeOwner(owner, try b.read(merged, join), span);
    return result;
}

/// Insert first and borrow from the joined owner, never from an owning payload phi.
fn ownedDefault(comptime Context: type, b: Context, owner: typed.LocalId, dict: ir.Ref, probe: ir.Ref, values: struct { key: ir.Ref, fallback: ir.Ref, borrowed: bool = false }, span: u32) Error!ir.Ref {
    const entry = try b.synthetic(.i64);
    try b.write(entry, b.current.?, probe);
    const missing = try b.newBlock();
    const join = try b.newBlock();
    try b.branch(try present(Context, b, probe, span), join, missing, span);
    try b.seal(missing);
    b.current = missing;
    // A borrowed key is copied here, on the missing edge, and probed again so the insertion's probe belongs to the key it stores.
    const stored = if (values.borrowed) try b.copyOwned(values.key, span) else values.key;
    const stored_probe = if (values.borrowed) try find(Context, b, dict, stored, span) else probe;
    const borrowed_key: u64 = if (values.borrowed) flags.borrowed_key_insert else 0;
    const inserted = try b.emit(.{ .op = .dict_insert, .ty = b.typeOfRef(dict), .a = dict, .b = stored_probe, .data = (try b.extraSlice(&.{ stored, values.fallback })) | borrowed_key, .span = span });
    // Insertion appends one entry even after tombstones or storage growth.
    // The physical entry count gives its slot without a second key lookup.
    const count = try b.emit(.{ .op = .dict_entries, .ty = .u64, .a = inserted, .span = span });
    const last = try b.emit(.{ .op = .sub, .ty = .u64, .a = count, .b = try b.constant(.u64, 1), .span = span });
    const index = try b.emit(.{ .op = .convert, .ty = .i64, .a = last, .span = span });
    try b.write(entry, b.current.?, index);
    try b.writeOwner(owner, inserted, span);
    try b.jump(join);
    try b.seal(join);
    b.enter(join);
    return valueAt(Context, b, try b.receiverOf(owner), try b.read(entry, join), span);
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
    const key_type = b.module().compound(b.module().storageType(b.typeOfRef(left))).dict.key;
    const key = try b.emit(.{ .op = .dict_entry_key, .ty = key_type, .a = left, .b = entry, .span = span });
    const probe = try find(Context, b, right, key, span);
    try b.branch(try present(Context, b, probe, span), found, missing, span);
    try b.seal(found);
    try b.seal(missing);
    b.current = missing;
    try b.write(result, b.current.?, try b.constant(.bool, 0));
    try b.jump(join);
    b.current = found;
    const value_type = b.module().compound(b.module().storageType(b.typeOfRef(left))).dict.value;
    const same = if (value_type == .void)
        try b.constant(.bool, 1)
    else
        try b.equal(try valueAt(Context, b, left, entry, span), try valueAt(Context, b, right, probe, span), span);
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

/// Materialize independent keys and values in insertion order.
pub fn copy(comptime Context: type, b: Context, source: ir.Ref, span: u32) Error!ir.Ref {
    const length = try b.emit(.{ .op = .dict_len, .ty = .u64, .a = source, .span = span });
    const target = try b.emit(.{ .op = .dict_new, .ty = b.typeOfRef(source), .a = length, .span = span });
    return copyEntries(Context, b, source, target, true, span);
}

fn copyEntries(comptime Context: type, b: Context, source: ir.Ref, initial: ir.Ref, keys: bool, span: u32) Error!ir.Ref {
    const m = b.module();
    const target_type = b.typeOfRef(initial);
    const dictionary = m.kind(target_type) == .dict;
    const shape = m.compound(m.storageType(b.typeOfRef(source))).dict;
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
    var key = if (keys or dictionary) try b.emit(.{ .op = .dict_entry_key, .ty = shape.key, .a = source, .b = entry, .span = span }) else .none;
    var value = if (shape.value == .void) .none else if (!keys or dictionary) try valueAt(Context, b, source, entry, span) else .none;
    {
        if (key != .none) key = try b.copyOwned(key, span);
        if (value != .none) value = try b.copyOwned(value, span);
    }
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
