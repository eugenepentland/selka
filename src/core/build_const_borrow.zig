//! Const source-place loans keep one read-only representation across branches.
const std = @import("std");
const language = @import("selka");
const typed = language.typed;
const owner = @import("single_owner.zig");
const ir = @import("ir.zig");

/// Allocation or an unsupported borrowed representation stops lowering.
pub const Error = error{ OutOfMemory, Unsupported };

/// Source declarations participate; receiver and ownership staging do not.
fn namedConst(local: typed.Local) bool {
    return !local.mutable and !local.usage.temporary and !local.ownership.view and
        local.origin != .contract_value and local.origin != .iteration and local.origin != .pattern and
        !std.mem.startsWith(u8, local.name, "<");
}

/// Choose the slot's representation before either branch is built. A fresh arm
/// must lend its new storage too when another arm initializes a source loan.
pub fn prepare(comptime Context: type, b: Context) Error!void {
    var walk = try language.typed_walk.Walker.init(b.allocator(), b.mb.input.program, b.checked.scope.body);
    defer walk.deinit();
    while (try walk.next()) |item| {
        if (item != .statement) continue;
        const statement = b.nodeOfStatement(item.statement);
        if (statement.data != .initialize) continue;
        const store = statement.data.initialize;
        const slot = b.local(store.slot);
        const local = b.checked.scope.locals[slot];
        if (store.unpack != null or store.transfer) continue;
        if (!namedConst(local) or b.nodeOf(store.value).own) continue;
        const mapped = b.ssa.types.items[slot];
        if (!b.module().managed(mapped) or b.module().containsBorrow(mapped)) continue;
        // A `const` of a lent option (H2) holds the read-only overlay of its option, which the lent union is.
        if (try b.lentLocalOption(store.value)) {
            b.ssa.types.items[slot] = try b.module().borrowedType(b.allocator(), mapped);
            continue;
        }
        // A `const` of a place borrows it (B9), and so does a `const` of a borrowed record (1A).
        if (owner.constBorrowPlace(b.mb.input.program, b.checked, store.value) == null and !try b.borrowedRecord(store.value)) continue;
        try borrowSlot(Context, b, slot);
    }
    // A `mut` local whose every store reads a place holds a borrow too (4f): every assignment adapts its value.
    const eligible = try owner.borrowedMutLocals(b.allocator(), b.mb.input.program, try b.mb.linearTypes(), b.checked, try b.mb.casePayloads());
    defer b.allocator().free(eligible);
    for (eligible, 0..) |borrowed, slot| if (borrowed) {
        const mapped = b.ssa.types.items[slot];
        if (!b.module().managed(mapped) or b.module().containsBorrow(mapped)) continue;
        try borrowSlot(Context, b, slot);
        try b.ssa.borrowed_mut.put(b.allocator(), @intCast(slot), {});
    };
    // A borrowed collection (RB2) lends its elements: its slot holds a list of read-only overlays.
    const collections = try owner.BorrowedCollections.init(b.allocator(), b.mb.input.program, try b.mb.linearTypes(), b.checked, try b.mb.casePayloads(), &.{});
    if (!collections.any()) return;
    b.borrowed_collections = collections;
    for (collections.slots, 0..) |lent, slot| if (lent) {
        const mapped = b.ssa.types.items[slot];
        if (b.module().dictShape(mapped)) |shape| {
            const overlay = try b.module().borrowedType(b.allocator(), b.module().storageType(shape.value));
            b.ssa.types.items[slot] = try b.module().intern(b.allocator(), .{ .dict = .{ .key = shape.key, .value = overlay } });
            continue;
        }
        const element = b.module().listElement(mapped) orelse return error.Unsupported;
        const overlay = try b.module().borrowedType(b.allocator(), b.module().storageType(element));
        b.ssa.types.items[slot] = try b.module().intern(b.allocator(), .{ .list = overlay });
    };
}

/// Give a slot the read-only representation of its type: a view where its type has one, else the borrowed overlay.
fn borrowSlot(comptime Context: type, b: Context, slot: usize) Error!void {
    const local = b.checked.scope.locals[slot];
    const mapped = b.ssa.types.items[slot];
    const view = try b.mb.readOnlyParameter(local.ty, mapped, @intCast(local.declaration.start));
    b.ssa.types.items[slot] = if (view != mapped) view else try b.module().borrowedType(b.allocator(), mapped);
}

/// Whether stores to `slot` adapt their value to the slot's borrowed representation: a named `const` of a place, or a
/// `mut` local that holds a borrow (4f).
pub fn adapts(comptime Context: type, b: Context, slot: usize) bool {
    return namedConst(b.checked.scope.locals[slot]) or b.ssa.borrowed_mut.contains(@intCast(slot));
}

/// Every initializing arm uses the same representation, including fresh owners.
/// The ordinary borrow graph retains that arm's storage until the joined read.
pub fn adapt(comptime Context: type, b: Context, store: typed.Store, value: ir.Ref, span: u32) Error!ir.Ref {
    if (value == .none or !adapts(Context, b, b.local(store.slot))) return value;
    const target = b.ssa.types.items[b.local(store.slot)];
    if (!b.module().containsBorrow(target)) return value;
    return b.readOnlyArgument(value, target, span);
}
