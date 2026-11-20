//! Source ownership contract: managed values move, calls borrow, and copies are explicit.
//! Complete typed trees are checked before optimization; selected bodies reuse only
//! ownership proofs whose inputs remain valid.
const std = @import("std");
const language = @import("selka");
const typed = language.typed;
const return_borrow = language.return_borrow;
const ownership_rules = language.ownership_rules;
const Rule = ownership_rules.Rule;
const Refusal = ownership_rules.Refusal;
const ir = @import("ir.zig");
const resources = @import("single_owner_resource.zig");
const files = @import("single_owner_files.zig");
const providers = @import("aggregate_provider.zig");
const borrow_repair = @import("borrow_repair.zig");
const receiver_repair = @import("receiver_repair.zig");
const borrow_return_repair = @import("borrow_return_repair.zig");
const instance_borrow = @import("instance_borrow.zig");
const own_marker = @import("own_marker.zig");
const alias_places = @import("alias_places.zig");
const escape_message = @import("escape_message.zig");
const pattern_message = @import("pattern_message.zig");
const read_first = @import("read_first.zig");
const take_fields = @import("take_fields.zig");
const field_moves = @import("field_moves.zig");
const typed_walk = language.typed_walk;
const Observer = @import("ownership_observations.zig").Observer;
const Span = language.source.Span;
const none = std.math.maxInt(usize);
/// The `none` of the local tables shared with lowering (`BorrowedCollections.receiver`, `literal`): no local.
pub const no_local = none;
const borrow_error = "E_SINGLE_OWNER_BORROW";
const mixed_error = "E_BORROW_MIXED";
/// O4: a borrowed record holding `Some(p)` of a recursive field keeps `p`'s box in this call's frame.
const frame_return = "this value holds Some(...) of a parameter, whose box lives in this call's frame, so it cannot be returned, even under `from`; return copy(...) of it, or return a value the caller's own storage holds";
const view_escape = "E_SLICE_ESCAPES";
const borrowed_record_escape = "a record whose fields all borrow places is a borrowed value, so it cannot be stored, moved or changed; " ++
    "write copy(...) for independent storage, or own in its fields to move them";
const place_scrutinee = "`match own` consumes a named owner, not a field or element place; remove own to borrow the payload, " ++
    "or bind the value first (`const value = own record.field`, or take an element out with pop() or exchange()) and match `own value`";
const mut_scrutinee = "'{s}' is a mut parameter, which borrows caller storage, so `match own` cannot consume it; " ++
    "remove own (or write `match mut {s}:` to write into it), or declare the parameter `own`";
/// P4: what an open file is used through instead, ending the two `E_WITH_RESOURCE` refusals of a file that leaves its scope.
const file_lend = "call its methods there, or lend it to a helper declared `mut f: File` and called as `put(mut f, data)`";
const file_given_away = "an open file belongs to its `with` block, so it cannot be returned, stored or given away with `own`; " ++ file_lend;
const file_held = "an open file cannot be held inside a list, record, variant or callback type: it belongs to its `with` block; " ++ file_lend;
/// A marked scrutinee that `match own` cannot consume reads its value (W2), as a marked scrutinee always did before 2A.
const own_read: Refusal = .{ .code = "E_OWN_MARKER", .rule = .W2 };
const overlap_error = "E_SINGLE_OWNER_OVERLAP";
/// LOOPDETACH condition 2: the value an exit from a `detach` loop hands on borrows from the collection the loop puts back first.
const detach_exit_borrow = "this exit hands on a value that borrows from the loop's element or its collection, which the `detach` loop puts " ++
    "back before the exit; return copy(...) of it, or return a position and read the element after the loop";
const resource_escape = "E_RESOURCE_ESCAPE";
const resource_origin = "E_RESOURCE_ORIGIN";

/// Match may consume a freshly produced union, never a local or a projection.
/// Shared by checking and lowering so the source rule does not depend on SSA use counts.
pub fn matchOwnsTemporary(nodes: []const typed.Node, id: typed.NodeId) bool {
    return switch (nodes[@backingInt(id)].data) {
        // A file read or directory listing builds its result afresh, as a call does.
        .call, .invoke, .variant, .file_access, .file_method => true,
        .block_value => |block| matchOwnsTemporary(nodes, block.value),
        .buffer_operation => |operation| switch (operation.kind) {
            .copy,
            .pop,
            .exchange,
            .pop_key,
            .pop_default,
            .decode,
            .from_hex,
            .scalar_count,
            .scalar_count_range,
            .parse_int,
            .parse_float,
            .parse_f32,
            .parse_int_range,
            .parse_float_range,
            => true,
            else => false,
        },
        else => false,
    };
}

/// Whether a checked value is an empty dictionary literal `{}` (RB2): a dictionary made with no entries.
fn emptyDictLiteral(program: typed.Program, id: typed.NodeId) bool {
    const node = program.nodes[@backingInt(id)];
    if (node.data != .array or node.data.array.len != 0) return false;
    if (!node.ty.isAggregate() or node.ty.recordIndex() >= program.records.len) return false;
    const record = program.records[node.ty.recordIndex()];
    return record.isCollection() and record.collection.kind == .dictionary and !record.collection.set;
}

/// Whether a checked value is an empty list literal `[]`: the block that initializes a list temporary with no capacity and
/// reads it back. A `from` accessor may return one beside its borrows (4e): the lowering returns a view of the runtime's
/// static empty list, an immortal constant, so the result borrows nothing and owns nothing.
pub fn emptyListLiteral(program: typed.Program, id: typed.NodeId) bool {
    const node = program.nodes[@backingInt(id)];
    if (node.data != .block_value) return false;
    const read = program.nodes[@backingInt(node.data.block_value.value)];
    const body = program.statements[@backingInt(node.data.block_value.body)];
    if (read.data != .local or body.data != .block or body.data.block.len != 1) return false;
    const init = program.statements[@backingInt(body.data.block[0])];
    if (init.data != .initialize or init.data.initialize.slot != read.data.local) return false;
    const value = program.nodes[@backingInt(init.data.initialize.value)];
    if (value.data != .acquire_buffer) return false;
    const capacity = program.nodes[@backingInt(value.data.acquire_buffer.capacity)];
    return capacity.data == .integer and capacity.data.integer == 0;
}

/// `match own name:` (2A): a source `own` marker on a named scrutinee consumes that owner, so the match takes its payload
/// as it takes a matched temporary's. Shared by checking and lowering: the checker refuses every marked scrutinee that is not
/// an owned local or `own` parameter, so lowering trusts the shape.
pub fn matchConsumesNamed(program: typed.Program, linear: []const bool, id: typed.NodeId) bool {
    const node = program.nodes[@backingInt(id)];
    return node.own and node.data == .local and isOwned(linear, node.ty) and !resources.affine(program, node.ty);
}

/// A binding the source names: a declared local, a loop variable or a pattern binding, never a lowering temporary or a
/// contract value. A borrow of a place lies in such a binding's owner.
pub fn namedLocal(local: typed.Local) bool {
    const source_binder = local.origin == .iteration or local.origin == .pattern;
    return (!local.usage.temporary or source_binder) and !std.mem.startsWith(u8, local.name, "<") and
        local.origin != .contract_value and local.origin != .contract_old;
}

/// 4f: the declared `mut` locals that hold a borrow. A local qualifies when its type is an owned, non-resource value, it
/// is stored at least twice (a single store is a `const` in all but name), and every store to it, its initializer and each
/// assignment, is an unmarked read of a named place (`constBorrowPlace`), as a `const` of a place borrows (B9). Its loans are the union of every assignment's roots, held to its last use. Shared
/// by checking and lowering, so both see the same set; the checker refuses a write through such a local, a move of it,
/// and an escape without a `from` contract. The result is indexed by local and owned by `a`.
/// A store of a borrowed record (1A) is a borrow too; `payloads` is `BorrowedRecords.casePayloads` of the program.
pub fn borrowedMutLocals(a: std.mem.Allocator, program: typed.Program, linear: []const bool, function: typed.Function, payloads: []const bool) error{OutOfMemory}![]bool {
    const locals = function.scope.locals;
    const eligible = try a.alloc(bool, locals.len);
    @memset(eligible, false);
    const stored = try a.alloc(u8, locals.len);
    defer a.free(stored);
    @memset(stored, 0);
    var any = false;
    for (locals, 0..) |local, slot| {
        // `collection_copy` labels a local whose last store, in source order, reads an element (`best = xs[i]`), and `view` one
        // whose last store is a slice (`c = c[1:]`, H4).
        const declared = local.origin == .local or local.origin == .collection_copy or local.origin == .view;
        if (slot < function.signature.parameter_count or !declared) continue;
        if (!local.mutable) continue;
        if (!namedLocal(local) or local.ownership.view) continue;
        if (!isOwned(linear, local.ty)) continue;
        if (resources.affine(program, local.ty) or resources.dependent(program, local.ty)) continue;
        eligible[slot] = true;
        any = true;
    }
    if (!any) return eligible;
    // A local qualifies only when one of its stores borrows: literals alone keep it an owner.
    const borrowing = try a.alloc(bool, locals.len);
    defer a.free(borrowing);
    @memset(borrowing, false);
    // A literal qualifies only beside borrows of the caller's storage (a plain parameter, or an element a loop reads): a local
    // that also takes a place of one of this function's owners keeps the owning store and its repair (`text = own value`).
    const literal = try a.alloc(bool, locals.len);
    defer a.free(literal);
    @memset(literal, false);
    const owner_place = try a.alloc(bool, locals.len);
    defer a.free(owner_place);
    @memset(owner_place, false);
    const written = try a.alloc(bool, locals.len);
    defer a.free(written);
    @memset(written, false);
    // The initializer of each `const` local, so a borrow of a `const` alias is traced to the storage it aliases.
    var aliases: std.AutoHashMapUnmanaged(u32, typed.NodeId) = .empty;
    defer aliases.deinit(a);
    var records: ?BorrowedRecords = null;
    var walker = try typed_walk.Walker.init(a, program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| {
        if (item != .statement) continue;
        const store = switch (program.statements[@backingInt(item.statement)].data) {
            .initialize => |store| store,
            .assign => |store| store,
            else => continue,
        };
        const slot = @backingInt(store.slot);
        if (program.statements[@backingInt(item.statement)].data == .initialize and store.unpack == null)
            try aliases.put(a, @intCast(slot), store.value);
        if (!eligible[slot]) continue;
        // A field or element write through the local (`c.f = v`, `c[i] = v`) is no store of it (D4): the checker refuses it at
        // the write when the local is stored once, and a local assigned more than once keeps its owning store.
        if (writeThrough(program, &aliases, store, slot)) {
            written[slot] = true;
            continue;
        }
        stored[slot] +|= 1;
        const plain_store = store.unpack == null and !store.element and !store.transfer;
        if (plain_store and program.nodes[@backingInt(store.value)].data == .record) {
            if (records == null) records = try BorrowedRecords.init(a, program, linear, function, payloads);
            eligible[slot] = records.?.constructor(store.value);
            borrowing[slot] = true;
            continue;
        }
        // A text or bytes literal beside the borrows is static storage that needs no owner (zero-copy part 1, F-RA-303).
        if (plain_store and !program.nodes[@backingInt(store.value)].own and staticText(program, store.value)) {
            literal[slot] = true;
            continue;
        }
        eligible[slot] = borrowStore(program, function, store);
        borrowing[slot] = true;
        if (constBorrowPlace(program, function, store.value) orelse slicePlace(program, function, store.value)) |place| {
            if (!callerStorage(program, function, &aliases, @backingInt(place))) owner_place[slot] = true;
        }
    }
    // A `mut` local stored once from a place borrows it as a `const` does (D4); a write through it is refused at the write.
    // A local stored more than once and written through keeps the owning store's diagnostics and repairs.
    for (eligible, stored, borrowing, literal, owner_place, written) |*keep, seen, borrows, constant, owned, writes| {
        keep.* = keep.* and seen >= 1 and borrows and !(constant and owned) and (!writes or seen == 1);
    }
    return eligible;
}

/// Whether `store` writes a field or an element of local `slot` in place (`c.f = v`, `c[i] = v`): an assignment of the local
/// whose value updates the local itself, read directly or through the lowering temporary that stages it as a receiver.
pub fn writeThrough(program: typed.Program, aliases: *const std.AutoHashMapUnmanaged(u32, typed.NodeId), store: typed.Store, slot: usize) bool {
    if (store.unpack != null) return false;
    const base = switch (program.nodes[@backingInt(store.value)].data) {
        .update => |update| update.base,
        .replace => |replace| replace.base,
        else => return false,
    };
    var current = base;
    var depth: usize = 0;
    while (depth < 4) : (depth += 1) {
        const node = program.nodes[@backingInt(current)];
        if (node.data != .local) return false;
        const read = @backingInt(node.data.local);
        if (read == slot) return true;
        current = aliases.get(@intCast(read)) orelse return false;
    }
    return false;
}

/// Whether local `slot` reads the caller's storage: a plain parameter, a variable of a loop over borrowed elements, or a
/// `const` alias of a place of one of them (`const p = props[i]`).
fn callerStorage(program: typed.Program, function: typed.Function, aliases: *const std.AutoHashMapUnmanaged(u32, typed.NodeId), start: usize) bool {
    var slot = start;
    var depth: usize = 0;
    while (depth < 16) : (depth += 1) {
        const local = function.scope.locals[slot];
        if (slot < function.signature.parameter_count) {
            const own = slot < function.scope.own_parameters.len and function.scope.own_parameters[slot];
            return !own and !local.mutable;
        }
        if (local.origin == .iteration) return !local.mutable;
        // A lowering temporary (the receiver of `props[i]`) names the place it was initialized from.
        const staged = std.mem.startsWith(u8, local.name, "<") and local.origin == .local;
        const declared = local.origin == .local or local.origin == .collection_copy;
        const constant = declared and !local.mutable;
        if (!staged and !constant) return false;
        const initializer = aliases.get(@intCast(slot)) orelse return false;
        const place = constBorrowPlace(program, function, initializer) orelse return false;
        if (@backingInt(place) == slot) return false;
        slot = @backingInt(place);
    }
    return false;
}

/// Whether a store reads a named place without taking it: no `own` marker, no unpacking, element or staged transfer.
fn borrowStore(program: typed.Program, function: typed.Function, store: typed.Store) bool {
    if (store.unpack != null or store.element or store.transfer) return false;
    if (program.nodes[@backingInt(store.value)].own) return false;
    // A result that borrows (a call with a `from` contract, its `try`) holds the call's owners (F-RA-311).
    if (borrowedCallStore(program, store.value)) return true;
    const place = constBorrowPlace(program, function, store.value) orelse slicePlace(program, function, store.value) orelse return false;
    const source = function.scope.locals[@backingInt(place)];
    return namedLocal(source) and !source.ownership.view;
}

/// H4: the local a slice of an unmarked place reads (`p[0:2]`, `r.name[1:]`, `xs[a:b]`), or null for any other value. A text
/// or bytes slice is a block that initializes the slice's owner temporary from the place and then slices that temporary; a
/// list slice is the copy loop `collection_lower` builds, whose block initializes its source temporary first. Shared by
/// checking and lowering, so a `mut` local stored from such a slice borrows the place as a store of the place does (D4).
pub fn slicePlace(program: typed.Program, function: typed.Function, id: typed.NodeId) ?typed.LocalId {
    const node = program.nodes[@backingInt(id)];
    if (node.own or node.data != .block_value) return null;
    const children = switch (program.statements[@backingInt(node.data.block_value.body)].data) {
        .block => |children| children,
        else => return null,
    };
    if (children.len == 0) return null;
    const source = switch (program.statements[@backingInt(children[0])].data) {
        .initialize => |initialize| initialize,
        else => return null,
    };
    if (source.unpack != null or source.transfer or program.nodes[@backingInt(source.value)].own) return null;
    const value = program.nodes[@backingInt(node.data.block_value.value)];
    const text = children.len == 1 and value.view and value.data == .buffer_operation and
        (value.data.buffer_operation.kind == .slice_bytes or value.data.buffer_operation.kind == .slice) and
        value.data.buffer_operation.owner == source.slot;
    if (!text and !listSliceBlock(program, node, children)) return null;
    return constBorrowPlace(program, function, source.value);
}

/// Whether `node`, a block value with statements `children`, is the copy loop a checked list slice lowers to
/// (`collection_lower.Builder.slice`): the source, the two clamped endpoints, a fresh buffer the value reads, then the loop.
fn listSliceBlock(program: typed.Program, node: typed.Node, children: []const typed.StatementId) bool {
    if (!node.view or children.len < 5) return false;
    const output = switch (program.statements[@backingInt(children[3])].data) {
        .initialize => |initialize| initialize,
        else => return false,
    };
    if (program.nodes[@backingInt(output.value)].data != .acquire_buffer) return false;
    if (program.statements[@backingInt(children[4])].data != .loop) return false;
    const read = program.nodes[@backingInt(node.data.block_value.value)];
    return read.data == .local and read.data.local == output.slot;
}

/// 1A: which record constructors are borrowed values. A source constructor of a plain record whose managed fields all borrow
/// block-backed places (and at least one does) reads its fields in place: the record is a read-only overlay of their storage,
/// never dropped, with the loans of every field's owner. The same syntactic test serves checking and lowering, so the
/// checker refuses every such constructor in a position that would store or move it (the ordinary move rules already refuse
/// an unmarked place there), and lowering trusts the shape wherever it meets it.
pub const BorrowedRecords = struct {
    program: typed.Program,
    function: typed.Function,
    linear: []const bool,
    /// Indexed by local: a bare read of the local is a block (an owner, an `own` or `mut` parameter, a loop variable, or any
    /// local of a plain record type), never a view of text, bytes or a list (a plain parameter or a borrowing local is).
    block: []const bool,
    /// Indexed by local: a plain read-only text, bytes or list parameter, which arrives as a view. A borrowed record holds
    /// it bare as a frame block (RB1, `ir.Op.block_frame`): the caller's block for a whole argument, else a copy this call
    /// makes once and frees when it returns, so such a record never leaves the call.
    framed: []const bool,
    /// Indexed by record: the payload record of a fielded case. Sema builds those around a `fail` value it widens, and a bare
    /// `fail` transfers its local, so they are never borrowed.
    case_payload: []const bool,

    /// The payload records of the fielded cases of `program` (`case_payload`), indexed by record and owned by `a`.
    pub fn casePayloads(a: std.mem.Allocator, program: typed.Program) error{OutOfMemory}![]bool {
        const payloads = try a.alloc(bool, program.records.len);
        @memset(payloads, false);
        for (program.records) |record| if (record.shape.variants) |variants| for (variants.cases) |case| {
            if (!case.fielded) continue;
            const payload = case.payload orelse continue;
            if (payload.isAggregate() and payload.recordIndex() < payloads.len) payloads[payload.recordIndex()] = true;
        };
        return payloads;
    }

    /// The tables for `function`, allocated in `a`; `payloads` is `casePayloads` of the same program.
    pub fn init(a: std.mem.Allocator, program: typed.Program, linear: []const bool, function: typed.Function, payloads: []const bool) error{OutOfMemory}!BorrowedRecords {
        const locals = function.scope.locals;
        const block = try a.alloc(bool, locals.len);
        errdefer a.free(block);
        for (locals, block, 0..) |local, *out, slot| out.* = blockOrigin(program, function, local, slot);
        const framed = try a.alloc(bool, locals.len);
        errdefer a.free(framed);
        for (locals, framed, 0..) |local, *out, slot| out.* = framedParameter(program, function, local, slot);
        var walker = try typed_walk.Walker.init(a, program, function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item != .statement) continue;
            const store = switch (program.statements[@backingInt(item.statement)].data) {
                .initialize => |store| store,
                .assign => |store| store,
                .match => |match| {
                    // A payload bound from a borrowed result (`if text_a(node) is Some(design)` with `-> bytes? from node`)
                    // is a view of text, bytes or a list, as the result is, never a block (F-RA-202).
                    const scrutinee = program.nodes[@backingInt(match.value)].data;
                    const viewed_local = scrutinee == .local and @backingInt(scrutinee.local) < block.len and !block[@backingInt(scrutinee.local)] and
                        !plainRecord(program, locals[@backingInt(scrutinee.local)].ty) and locals[@backingInt(scrutinee.local)].origin == .local;
                    if (!borrowedResult(program, match.value) and !viewed_local) continue;
                    for (match.arms) |arm| {
                        const bound = arm.slot orelse continue;
                        const slot = @backingInt(bound);
                        if (slot < block.len and !plainRecord(program, locals[slot].ty)) block[slot] = false;
                    }
                    continue;
                },
                else => continue,
            };
            const slot = @backingInt(store.slot);
            if (slot >= block.len or !block[slot] or plainRecord(program, locals[slot].ty)) continue;
            if (slot < function.signature.parameter_count or locals[slot].origin == .iteration) continue;
            if (borrowShape(program, function, store.value)) block[slot] = false;
        }
        return .{ .program = program, .function = function, .linear = linear, .block = block, .framed = framed, .case_payload = payloads };
    }

    /// Whether constructor `id` is a borrowed record: a plain, unmanaged, unboxed record with no capability, file or resource
    /// field, whose managed fields are each a borrowed field value (`borrowedField`) or a static text or bytes literal, at least one
    /// of them a borrow. A record of fresh or moved values keeps its owning construction.
    pub fn constructor(self: BorrowedRecords, id: typed.NodeId) bool {
        const node = self.program.nodes[@backingInt(id)];
        if (node.data != .record or node.own or !plainRecord(self.program, node.ty)) return false;
        const index = node.ty.recordIndex();
        const declared = self.program.records[index];
        if (self.case_payload[index] or declared.shape.tuple) return false;
        for (declared.fields) |field| if (field.boxed) return false;
        var borrows = false;
        for (node.data.record) |field| {
            const value = self.program.nodes[@backingInt(field.value)];
            if (!isOwned(self.linear, value.ty)) continue;
            if (value.ty.isFile()) return false;
            if (resources.affine(self.program, value.ty) or resources.dependent(self.program, value.ty)) return false;
            if (staticText(self.program, field.value) or self.emptyOption(field.value)) continue;
            if (!self.borrowedField(field.value)) return false;
            borrows = true;
        }
        return borrows;
    }

    /// The field that keeps constructor `id` from being a borrowed record (W2): the first managed field whose value is not
    /// a borrow, a static text or `None`, when it is the only reason (`constructor` would hold without it) and another field
    /// borrows. Null for a borrowed record and for one that owns for any other reason.
    pub fn owningField(self: BorrowedRecords, id: typed.NodeId) ?typed.FieldInit {
        const node = self.program.nodes[@backingInt(id)];
        if (node.data != .record or node.own or !plainRecord(self.program, node.ty)) return null;
        const index = node.ty.recordIndex();
        const declared = self.program.records[index];
        if (self.case_payload[index] or declared.shape.tuple) return null;
        for (declared.fields) |field| if (field.boxed) return null;
        var borrows = false;
        var owning: ?typed.FieldInit = null;
        for (node.data.record) |field| {
            const value = self.program.nodes[@backingInt(field.value)];
            if (!isOwned(self.linear, value.ty)) continue;
            if (value.ty.isFile()) return null;
            if (resources.affine(self.program, value.ty) or resources.dependent(self.program, value.ty)) return null;
            if (staticText(self.program, field.value) or self.emptyOption(field.value)) continue;
            if (self.borrowedField(field.value)) {
                borrows = true;
            } else if (owning == null) owning = field;
        }
        return if (borrows) owning else null;
    }

    /// Whether a field value is `None` of an option (O4): a payload-less case owns nothing, so it may stand beside the
    /// borrows of a borrowed record, as a text literal may.
    pub fn emptyOption(self: BorrowedRecords, value: typed.NodeId) bool {
        const node = self.program.nodes[@backingInt(value)];
        if (node.data != .variant or node.own or node.data.variant.value != null) return false;
        const step = optionStep(self.program, node.ty) orelse return false;
        return node.data.variant.tag != step.tag;
    }

    /// The local a lent option borrows: `Some(p)` where `p` is an unmarked bare read of a plain parameter (not `own`, not
    /// `mut`) of a plain record type (O4), or `Some(place)` where `place` is an unmarked projection of a named block-backed
    /// binding with an unboxed payload (RB1). The parameter is caller storage that cannot change during the call, so
    /// every evaluation of the option holds the same value; a boxed payload lives in this call's frame (`box_frame`).
    pub fn lentOption(self: BorrowedRecords, value: typed.NodeId) ?typed.LocalId {
        const node = self.program.nodes[@backingInt(value)];
        if (node.data != .variant or node.own) return null;
        const step = optionStep(self.program, node.ty) orelse return null;
        if (node.data.variant.tag != step.tag) return null;
        const payload_id = node.data.variant.value orelse return null;
        const payload = self.program.nodes[@backingInt(payload_id)];
        if (payload.own) return null;
        // `Some(owner.a)`, `Some(xs[i])`: a projection of a named block-backed place is lent, as a field holding it bare is
        // (RB1). A boxed (recursive) payload would need storage per evaluation (D-O4-5), so only an unboxed case is lent.
        if (payload.data != .local) {
            const variants = self.program.records[node.ty.recordIndex()].shape.variants orelse return null;
            if (variants.cases[step.tag].boxed) return null;
            if (payload.data == .record or payload.data == .variant) return null;
            const place = constBorrowPlace(self.program, self.function, payload_id) orelse return null;
            const source = self.function.scope.locals[@backingInt(place)];
            if (!namedLocal(source) or source.ownership.view) return null;
            return place;
        }
        const slot = @backingInt(payload.data.local);
        if (slot >= self.function.signature.parameter_count) return null;
        const local = self.function.scope.locals[slot];
        const own = slot < self.function.scope.own_parameters.len and self.function.scope.own_parameters[slot];
        if (own or local.mutable) return null;
        if (!namedLocal(local) or local.ownership.view) return null;
        if (!plainRecord(self.program, local.ty)) return null;
        return payload.data.local;
    }

    /// Whether a `const` option local's initializer lends its payload (H2, lane OC): a lent option (`lentOption`), `Some` of a
    /// borrowed record result of a call (`lentRecordResult`, H3), or `Some(name)` of a bare read of a block local (an owner, an
    /// `own` or `mut` parameter) or of a framed text, bytes or list parameter (RB1), with an unboxed payload. Such a local is a
    /// borrowed option, as `Box(value=name)` is a borrowed record: it owns nothing and holds its payload's roots until its last
    /// use.
    pub fn lentLocalOption(self: BorrowedRecords, value: typed.NodeId) bool {
        const node = self.program.nodes[@backingInt(value)];
        if (node.data != .variant or node.own) return false;
        const step = optionStep(self.program, node.ty) orelse return false;
        if (node.data.variant.tag != step.tag) return false;
        const variants = self.program.records[node.ty.recordIndex()].shape.variants orelse return false;
        if (variants.cases[step.tag].boxed) return false;
        const payload = self.program.nodes[@backingInt(node.data.variant.value orelse return false)];
        // A capability is a shared handle, copied freely, never lent; a file or resource is not lent either.
        if (!isLinear(self.linear, payload.ty) or payload.ty.isFile()) return false;
        if (resources.affine(self.program, payload.ty) or resources.dependent(self.program, payload.ty)) return false;
        if (self.lentOption(value) != null) return true;
        if (self.lentRecordResult(node.data.variant.value.?)) return true;
        if (payload.own or payload.data != .local) return false;
        const slot = @backingInt(payload.data.local);
        const local = self.function.scope.locals[slot];
        if (!namedLocal(local) or local.ownership.view) return false;
        if (!self.block[slot] and !self.framed[slot]) return false;
        return true;
    }

    /// Whether a lent option's `Some` payload is boxed (a recursive field): its box is a slot of this call's frame, so a
    /// record that holds it never leaves the call (O4).
    pub fn frameOption(self: BorrowedRecords, value: typed.NodeId) bool {
        if (self.lentOption(value) == null) return false;
        const node = self.program.nodes[@backingInt(value)];
        const variants = self.program.records[node.ty.recordIndex()].shape.variants orelse return false;
        return variants.cases[node.data.variant.tag].boxed;
    }

    /// Whether a field value borrows a block-backed place: an unmarked projection (a field, an element, a dictionary value)
    /// of a named place that is not a view, a bare read of a block local (`block`), or a nested borrowed record.
    pub fn borrowedField(self: BorrowedRecords, value: typed.NodeId) bool {
        const node = self.program.nodes[@backingInt(value)];
        if (node.own) return false;
        if (node.data == .record) return self.constructor(value);
        if (node.data == .variant) return self.lentOption(value) != null;
        if (self.lentRecordResult(value)) return true;
        const place = constBorrowPlace(self.program, self.function, value) orelse return false;
        const slot = @backingInt(place);
        const source = self.function.scope.locals[slot];
        if (!namedLocal(source) or source.ownership.view) return false;
        if (node.data == .local) return self.block[slot] or self.framed[slot];
        return true;
    }

    /// Whether `value` is a call whose result borrows (a `from` contract) and is a plain record (H3, lane OC): a block of the
    /// call's sources, lent where the field it returns would be, so a borrowed record, a collection of borrows or a lent option
    /// may hold it with the call's sources as its owners. A view result (text, bytes, a list) is not a block and stays refused.
    pub fn lentRecordResult(self: BorrowedRecords, value: typed.NodeId) bool {
        const node = self.program.nodes[@backingInt(value)];
        if (node.own or node.data != .call) return false;
        return borrowedResult(self.program, value) and plainRecord(self.program, node.ty);
    }

    /// Whether a field value is a bare read of a framed parameter (RB1): the record holds a frame block of it.
    pub fn framedRead(self: BorrowedRecords, value: typed.NodeId) bool {
        const node = self.program.nodes[@backingInt(value)];
        if (node.own or node.data != .local) return false;
        const slot = @backingInt(node.data.local);
        return slot < self.framed.len and self.framed[slot] and !self.block[slot];
    }
};

/// RB2: the local collections of borrows. A collection is a borrowed collection when it is a declared `mut` local list whose
/// element type owns storage, made empty (`[]`) and never assigned again, whose every element store (`append`)
/// stores a borrow (`BorrowedRecords.borrowedField`, a bare framed parameter's frame block included, H5) or a text literal, at least one a borrow, and whose
/// only other uses read it: an element read, its length, an iteration, or a bare read without `own`, and no `return` of it.
/// Its elements are lent: the list owns its buffer and never its elements (`list[borrowed T]` in Core), and its loans are
/// the union of what its stores borrow. Shared by checking and lowering, so both see the same set.
pub const BorrowedCollections = struct {
    /// Indexed by local: the borrowed collections.
    slots: []bool,
    /// Indexed by local: for a lowering temporary that stages a borrowed collection as a receiver (`<collection>`), the
    /// collection's local; `none` for any other local.
    receiver: []usize,
    /// Indexed by local: for a collection initialized with a list literal, the lowering temporary that builds the literal
    /// (itself a borrowed collection); `none` for any other local.
    literal: []usize,
    /// Indexed by local: for the lowering temporary an element write into a borrowed collection stages its value in, that
    /// collection; `none` for any other local. The temporary lends its value, as an appended value is lent.
    staged: []usize,
    /// Indexed by local: the first use that kept a candidate from lending (W2), for the note of a refusal it causes.
    why: []Owning,

    /// What made a candidate collection own its elements, and where.
    pub const Owning = struct {
        span: Span = .{ .start = 0, .end = 0 },
        kind: enum { none, initialized, assigned, returned, moved, fresh, changed } = .none,
    };

    /// Whether local `slot` is a borrowed collection.
    pub fn holds(self: BorrowedCollections, slot: usize) bool {
        return slot < self.slots.len and self.slots[slot];
    }

    /// The borrowed collection a receiver or a local names, or null.
    pub fn collectionOf(self: BorrowedCollections, slot: usize) ?usize {
        if (self.holds(slot)) return slot;
        if (slot < self.receiver.len and self.receiver[slot] != none) return self.receiver[slot];
        return null;
    }

    /// Whether any local is a borrowed collection.
    pub fn any(self: BorrowedCollections) bool {
        return std.mem.indexOfScalar(bool, self.slots, true) != null;
    }

    /// The value an element store `operation` stores, when its receiver is a borrowed collection: the appended value, or the
    /// lowering temporary an element write `xs[i] = v` or `d[k] = v` stages its value in (`staged`). Null for any other
    /// operation.
    pub fn storedValue(self: BorrowedCollections, operation: @FieldType(@FieldType(typed.Node, "data"), "buffer_operation")) ?typed.NodeId {
        _ = self.collectionOf(@backingInt(operation.owner)) orelse return null;
        if (operation.kind == .append and operation.arguments.len == 1) return operation.arguments[0];
        if (operation.kind == .write and operation.arguments.len == 2) return operation.arguments[1];
        return null;
    }

    /// The tables for `function`, allocated in `a`. `plain` masks locals a re-check treats as owners.
    pub fn init(a: std.mem.Allocator, program: typed.Program, linear: []const bool, function: typed.Function, payloads: []const bool, plain: []const bool) error{OutOfMemory}!BorrowedCollections {
        const locals = function.scope.locals;
        const slots = try a.alloc(bool, locals.len);
        errdefer a.free(slots);
        @memset(slots, false);
        const receiver = try a.alloc(usize, locals.len);
        errdefer a.free(receiver);
        @memset(receiver, none);
        const literal = try a.alloc(usize, locals.len);
        errdefer a.free(literal);
        @memset(literal, none);
        const staged = try a.alloc(usize, locals.len);
        errdefer a.free(staged);
        @memset(staged, none);
        const why = try a.alloc(Owning, locals.len);
        errdefer a.free(why);
        @memset(why, .{});
        const result: BorrowedCollections = .{ .slots = slots, .receiver = receiver, .literal = literal, .staged = staged, .why = why };
        if (!candidates(program, linear, function, plain, slots)) return result;
        try result.markUses(a, program, function);
        try result.markStores(a, program, linear, function, payloads);
        // A collection initialized with a literal lends only when its literal does.
        for (slots, literal) |*keep, *made| if (made.* != none and !slots[made.*]) {
            keep.* = false;
            made.* = none;
        };
        for (receiver) |*read| if (read.* != none and !slots[read.*]) {
            read.* = none;
        };
        for (staged) |*into| if (into.* != none and !slots[into.*]) {
            into.* = none;
        };
        return result;
    }

    /// Mark the declared `mut` locals of a list type with lendable elements; false when there is none.
    fn candidates(program: typed.Program, linear: []const bool, function: typed.Function, plain: []const bool, slots: []bool) bool {
        var any_candidate = false;
        for (function.scope.locals, 0..) |local, slot| {
            if (slot < function.signature.parameter_count or local.origin != .local or local.ownership.view) continue;
            // A list literal is built in a lowering temporary; a named collection is a declared `const` or `mut` local.
            const named = namedLocal(local);
            if (!named and !std.mem.eql(u8, local.name, "<collection>")) continue;
            if (slot < plain.len and plain[slot]) continue;
            if (borrowableCollection(program, linear, local.ty) == null) continue;
            slots[slot] = true;
            any_candidate = true;
        }
        return any_candidate;
    }

    /// Pass 1: a candidate is made empty and never assigned, moved or returned; note the lowering temporaries that stage one
    /// as a receiver.
    fn markUses(self: BorrowedCollections, a: std.mem.Allocator, program: typed.Program, function: typed.Function) error{OutOfMemory}!void {
        var walker = try typed_walk.Walker.init(a, program, function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .statement => |id| self.noteStatement(program, function, program.statements[@backingInt(id)]),
            .expression => |id| {
                const node = program.nodes[@backingInt(id)];
                if (node.data == .local and node.own) self.dropFor(@backingInt(node.data.local), .{ .span = node.span, .kind = .moved });
            },
        };
    }

    fn noteStatement(self: BorrowedCollections, program: typed.Program, function: typed.Function, statement: typed.Statement) void {
        switch (statement.data) {
            .initialize => |store| {
                const slot = @backingInt(store.slot);
                const value = program.nodes[@backingInt(store.value)];
                if (self.slots[slot] and store.unpack == null and self.lendingStart(program, function.scope.locals[slot], slot, store.value)) return;
                self.dropFor(slot, .{ .span = statement.span, .kind = .initialized });
                if (value.data != .local or store.unpack != null or !temporaryLocal(function.scope.locals[slot])) return;
                const read = @backingInt(value.data.local);
                if (!self.holds(read)) return;
                if (value.own) self.dropFor(read, .{ .span = value.span, .kind = .moved }) else self.receiver[slot] = read;
            },
            .assign => |store| self.dropFor(@backingInt(store.slot), .{ .span = statement.span, .kind = .assigned }),
            .ret => |returned| {
                var value = returned;
                while (program.nodes[@backingInt(value)].data == .block_value) value = program.nodes[@backingInt(value)].data.block_value.value;
                const node = program.nodes[@backingInt(value)];
                if (node.data == .local) self.dropFor(@backingInt(node.data.local), .{ .span = statement.span, .kind = .returned });
            },
            else => {},
        }
    }

    /// Whether a candidate's initializer starts a collection of borrows: a literal's temporary made by `acquire_buffer`, a
    /// `mut` local made empty, or a local initialized with a literal (noted in `literal`). A receiver's temporary, read from
    /// its collection, is not one.
    fn lendingStart(self: BorrowedCollections, program: typed.Program, local: typed.Local, slot: usize, value: typed.NodeId) bool {
        if (!namedLocal(local)) return program.nodes[@backingInt(value)].data == .acquire_buffer;
        if (local.mutable and (emptyListLiteral(program, value) or emptyDictLiteral(program, value))) return true;
        const made = literalTemporary(program, value) orelse return false;
        if (!self.holds(made)) return false;
        self.literal[slot] = made;
        return true;
    }

    /// The lowering temporary a list literal `[a, b]` builds: a block whose value reads the temporary it appended to.
    fn literalTemporary(program: typed.Program, value: typed.NodeId) ?usize {
        const node = program.nodes[@backingInt(value)];
        if (node.data != .block_value) return null;
        const read = program.nodes[@backingInt(node.data.block_value.value)];
        if (read.data != .local or read.own) return null;
        return @backingInt(read.data.local);
    }

    /// Stop candidate `slot` from lending, keeping the first reason a candidate had (`why`).
    fn dropFor(self: BorrowedCollections, slot: usize, reason: Owning) void {
        if (slot >= self.slots.len) return;
        if (self.slots[slot] and self.why[slot].kind == .none) self.why[slot] = reason;
        self.slots[slot] = false;
    }

    /// An entry of `literal`, `receiver` or `staged` that names no local: the table, the slot and the index it holds.
    pub const Stray = struct { table: []const u8, slot: usize, index: usize };

    /// The first entry of `literal`, `receiver` or `staged` that is neither `none` nor a local below `slots.len`, or null. Every
    /// store into these tables writes a local `holds` accepted, so a stray is memory overwritten under the table (FR83).
    pub fn stray(self: BorrowedCollections) ?Stray {
        const tables = [_]struct { name: []const u8, entries: []const usize }{
            .{ .name = "literal", .entries = self.literal },
            .{ .name = "receiver", .entries = self.receiver },
            .{ .name = "staged", .entries = self.staged },
        };
        for (tables) |table| for (table.entries, 0..) |index, slot| {
            if (index != none and index >= self.slots.len) return .{ .table = table.name, .slot = slot, .index = index };
        };
        return null;
    }

    /// FR83: stop a Debug or ReleaseSafe compiler where a table entry first names no local, naming the step, the table, the slot and
    /// the index (`0xaaaaaaaaaaaaaaaa` is memory a Debug allocator wrote as undefined). Nothing in ReleaseFast.
    fn expectIndices(self: BorrowedCollections, step: []const u8, function: typed.Function) void {
        if (!std.debug.runtime_safety) return;
        const found = self.stray() orelse return;
        std.debug.panic("FR83: BorrowedCollections.{s}[{d}] = 0x{x} names no local (of {d}) {s} in `{s}`; table at {*}", .{ found.table, found.slot, found.index, self.slots.len, step, function.name, self.literal.ptr });
    }

    /// Pass 2: every operation on a candidate reads it or appends a borrow, and at least one appends a borrow.
    fn markStores(self: BorrowedCollections, a: std.mem.Allocator, program: typed.Program, linear: []const bool, function: typed.Function, payloads: []const bool) error{OutOfMemory}!void {
        self.expectIndices("at the start of markStores", function);
        const borrows = try a.alloc(bool, self.slots.len);
        defer a.free(borrows);
        @memset(borrows, false);
        var records: ?BorrowedRecords = null;
        // The initializer of each lowering temporary, for the values element writes stage.
        var initializers: std.AutoHashMapUnmanaged(usize, typed.NodeId) = .empty;
        defer initializers.deinit(a);
        var walker = try typed_walk.Walker.init(a, program, function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item == .statement) {
                const data = program.statements[@backingInt(item.statement)].data;
                if (data == .initialize and temporaryLocal(function.scope.locals[@backingInt(data.initialize.slot)]))
                    try initializers.put(a, @backingInt(data.initialize.slot), data.initialize.value);
                continue;
            }
            const node = program.nodes[@backingInt(item.expression)];
            if (node.data != .buffer_operation) continue;
            const operation = node.data.buffer_operation;
            const slot = self.collectionOf(@backingInt(operation.owner)) orelse continue;
            if (!self.slots[slot]) continue;
            switch (operation.kind) {
                .read, .length, .iteration_check, .get, .contains, .key_at, .value_at => {},
                .append, .write => {
                    var stored = self.storedValue(operation).?;
                    if (operation.kind == .write) {
                        const temporary = self.stagedTemporary(program, stored, &initializers) orelse {
                            self.dropFor(slot, .{ .span = node.span, .kind = .fresh });
                            continue;
                        };
                        self.staged[temporary.slot] = slot;
                        stored = temporary.value;
                    }
                    if (staticText(program, stored)) continue;
                    if (records == null) {
                        records = try BorrowedRecords.init(a, program, linear, function, payloads);
                        self.expectIndices("after BorrowedRecords.init in markStores", function);
                    }
                    // `None` owns nothing, as a text literal does.
                    if (records.?.emptyOption(stored)) continue;
                    if (!lendable(records.?, stored)) {
                        self.dropFor(slot, .{ .span = node.span, .kind = .fresh });
                        continue;
                    }
                    borrows[slot] = true;
                },
                else => self.dropFor(slot, .{ .span = node.span, .kind = .changed }),
            }
        }
        self.expectIndices("before markStores reads literal", function);
        for (self.slots, borrows, self.literal) |*keep, borrowed, made| {
            const literal_borrows = made != none and borrows[made];
            keep.* = keep.* and (borrowed or literal_borrows);
        }
    }

    /// The temporary an element write stages its value in, and that value; null when the write reads anything else.
    fn stagedTemporary(self: BorrowedCollections, program: typed.Program, stored: typed.NodeId, made: *const std.AutoHashMapUnmanaged(usize, typed.NodeId)) ?struct { slot: usize, value: typed.NodeId } {
        _ = self;
        const node = program.nodes[@backingInt(stored)];
        if (node.data != .local or node.own) return null;
        const slot = @backingInt(node.data.local);
        const value = made.get(slot) orelse return null;
        return .{ .slot = slot, .value = value };
    }

    /// Whether an appended value is a borrow a collection may hold: a borrowed record's field value, not a frame box. A bare
    /// framed parameter is one (H5): the store holds its frame block, as a borrowed record's field does (RB1).
    fn lendable(table: BorrowedRecords, value: typed.NodeId) bool {
        if (someRecord(table, value) != null) return true;
        return table.borrowedField(value) and !table.frameOption(value);
    }

    /// The borrowed record `Some(record)` wraps when an option of a borrowed record is an element (RB2), or null. The case
    /// must be unboxed: the payload is held in the option, as a lent `Some(place)` holds its place.
    pub fn someRecord(table: BorrowedRecords, value: typed.NodeId) ?typed.NodeId {
        const node = table.program.nodes[@backingInt(value)];
        if (node.data != .variant or node.own) return null;
        const payload = node.data.variant.value orelse return null;
        if (table.program.nodes[@backingInt(payload)].data != .record or !table.constructor(payload)) return null;
        const step = optionStep(table.program, node.ty) orelse return null;
        if (node.data.variant.tag != step.tag) return null;
        const variants = table.program.records[node.ty.recordIndex()].shape.variants orelse return null;
        return if (variants.cases[step.tag].boxed) null else payload;
    }
};

/// The element type of a list type whose elements own storage and may be lent: not a resource, a file or a capability-
/// dependent value. Null for any other type.
fn borrowableList(program: typed.Program, linear: []const bool, ty: typed.Type) ?typed.Type {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return null;
    if (program.records[ty.recordIndex()].collection.kind != .list) return null;
    return borrowableCollection(program, linear, ty);
}

/// The element type of a list, or the value type of a dictionary (not a set), whose elements own storage and may be lent
/// (RB2), as `borrowableList` says of a list. Null for any other type.
fn borrowableCollection(program: typed.Program, linear: []const bool, ty: typed.Type) ?typed.Type {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return null;
    const record = program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.box) return null;
    if (record.collection.kind != .list and (record.collection.kind != .dictionary or record.collection.set)) return null;
    const element = record.shape.buffer orelse return null;
    if (!isOwned(linear, element) or element.isFile()) return null;
    if (resources.affine(program, element) or resources.dependent(program, element)) return null;
    return element;
}

/// The `Some` step of an option type (not a result), or null.
fn optionStep(program: typed.Program, ty: typed.Type) ?return_borrow.Step {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return null;
    const name = program.records[ty.recordIndex()].name;
    if (!std.mem.startsWith(u8, name, "Option<") and !std.mem.startsWith(u8, name, "std_result::Option<")) return null;
    return return_borrow.step(program.records, ty);
}

/// Whether `ty` is a plain record: no collection, runtime identity, value representation, managed reference or builtin policy.
fn plainRecord(program: typed.Program, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    const record = program.records[ty.recordIndex()];
    return record.isRecord() and !record.isCollection() and !record.managed and !record.collection.box and
        record.shape.builtin == .none and record.contract.callback == null;
}

/// Whether local `slot` is a plain read-only text, bytes or list parameter (RB1): not `own`, not `mut`, not declared
/// written, not move-only, so it arrives as a view (`build.viewParameter`) that a borrowed record holds as a frame block.
fn framedParameter(program: typed.Program, function: typed.Function, local: typed.Local, slot: usize) bool {
    if (slot >= function.signature.parameter_count) return false;
    if (function.policy.c_abi or function.policy.host != null) return false;
    if (!namedLocal(local) or local.ownership.view or local.mutable) return false;
    if (slot < function.scope.own_parameters.len and function.scope.own_parameters[slot]) return false;
    if (std.mem.indexOfScalar(u16, function.signature.declared_mutates, @intCast(slot)) != null) return false;
    if (resources.affine(program, local.ty)) return false;
    if (!local.ty.isAggregate() or local.ty.recordIndex() >= program.records.len) return false;
    const record = program.records[local.ty.recordIndex()];
    if (!record.isCollection() or record.collection.box) return false;
    return switch (record.collection.kind) {
        .string, .bytes, .list => true,
        .dictionary => false,
    };
}

/// Whether `ty` is a dictionary or a set: a collection with no view form, so a plain parameter of it arrives as the caller's
/// block (`fn g(dict[bytes, i64])`), which a field of a borrowed record can lend as it lends a record parameter (RB1).
fn blockCollection(program: typed.Program, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    const record = program.records[ty.recordIndex()];
    return record.isCollection() and record.collection.kind == .dictionary and !record.collection.box;
}

/// Whether a local's bare read is a block before its stores are seen: an `own` or `mut` parameter, a loop variable, a declared
/// local, or a local of a plain record type (a record has no view form). A plain text, bytes or list parameter and a pattern
/// binding of one arrive as views.
fn blockOrigin(program: typed.Program, function: typed.Function, local: typed.Local, slot: usize) bool {
    if (!namedLocal(local) or local.ownership.view) return false;
    if (plainRecord(program, local.ty)) return true;
    if (slot < function.signature.parameter_count) {
        const own = slot < function.scope.own_parameters.len and function.scope.own_parameters[slot];
        // A dictionary or set has no view form: a plain parameter of one is the caller's block (RB1).
        return own or local.mutable or blockCollection(program, local.ty);
    }
    return local.origin == .local or local.origin == .collection_copy or local.origin == .iteration;
}

/// Whether a store makes its local a borrow rather than an owner: an unmarked read of a place (a `const` of a place, or a
/// `mut` local whose stores all read places), or a result that borrows (a call with a `from` contract, its `try`, a borrowed
/// selection, a dictionary read with a default, a text trim). Such a local is a view of text, bytes or a list.
fn borrowShape(program: typed.Program, function: typed.Function, value: typed.NodeId) bool {
    if (!program.nodes[@backingInt(value)].own and constBorrowPlace(program, function, value) != null) return true;
    return borrowedResult(program, value);
}

/// Whether a value is a result that borrows: a call with a `from` contract, its `try`, a borrowed selection, a dictionary
/// read with a default or a text trim, through the blocks the lowering wraps it in.
pub fn borrowedResult(program: typed.Program, value: typed.NodeId) bool {
    return switch (program.nodes[@backingInt(value)].data) {
        .call => |call| @backingInt(call.function) < program.functions.len and
            return_borrow.effectiveSources(program.records, program.functions[@backingInt(call.function)].signature).len != 0,
        .propagate => |propagated| borrowedResult(program, propagated.value),
        .block_value => |block| borrowedResult(program, block.value),
        .borrow_selection => true,
        .buffer_operation => |operation| switch (operation.kind) {
            .get, .setdefault, .strip, .lstrip, .rstrip, .borrow_view => true,
            else => false,
        },
        else => false,
    };
}

/// Whether a store of a `mut` local that holds a borrow reads a result that borrows: a call with a `from` contract, its `try`,
/// a borrowed selection (`atom_of(x).unwrap_or(b"")`), a dictionary read with a default or a text trim.
fn borrowedCallStore(program: typed.Program, value: typed.NodeId) bool {
    return borrowedResult(program, value);
}

/// Whether a value is a text or bytes literal: a static constant a borrowed record may hold beside its borrows.
fn staticText(program: typed.Program, id: typed.NodeId) bool {
    const node = program.nodes[@backingInt(id)];
    if (node.data != .array or !node.ty.isAggregate() or node.ty.recordIndex() >= program.records.len) return false;
    const record = program.records[node.ty.recordIndex()];
    if (!record.isCollection() or (record.collection.kind != .string and record.collection.kind != .bytes)) return false;
    for (node.data.array) |item| if (program.nodes[@backingInt(item)].data != .integer) return false;
    return true;
}

/// The source place an initializer reads, before ownership state is applied.
/// Canonical receiver staging preserves a place; arbitrary hidden results do not.
pub fn constBorrowPlace(program: typed.Program, function: typed.Function, id: typed.NodeId) ?typed.LocalId {
    var current = id;
    var remaining = program.nodes.len + 1;
    while (remaining != 0) : (remaining -= 1) {
        switch (program.nodes[@backingInt(current)].data) {
            .local => |slot| return slot,
            .field => |field| current = field.base,
            .index => |index| {
                const base = program.nodes[@backingInt(index.base)].ty;
                if (base.isAggregate() and program.records[base.recordIndex()].collection.kind == .string) return null;
                current = index.base;
            },
            .buffer_operation => |operation| {
                if (operation.kind != .read) return null;
                const ty = function.scope.locals[@backingInt(operation.owner)].ty;
                if (!ty.isAggregate()) return null;
                const kind = program.records[ty.recordIndex()].collection.kind;
                return if (kind == .list or kind == .dictionary) operation.owner else null;
            },
            .block_value => |block| current = receiverConstPlace(program, function, block.body, block.value) orelse
                narrowedOption(program, block.body, block.value) orelse return null,
            else => return null,
        }
    }
    return null;
}

/// The option a narrowed read projects (`option_flow.payloadValue`): after `if x is None: return` (or `fail`, `break`,
/// `continue`), a read of `x` is a block whose one statement matches `x` with a `Some` arm that binds a temporary and a
/// `None` arm that only asserts, and whose value reads that temporary. The read is then the payload of the place `x`
/// names, as `x.unwrap_or(d)` on an option local borrows its payload (zero-copy part 1, F-RA-204). Null for any other block.
pub fn narrowedOption(program: typed.Program, body: typed.StatementId, value: typed.NodeId) ?typed.NodeId {
    const block = program.statements[@backingInt(body)];
    if (block.data != .block or block.data.block.len != 1) return null;
    const statement = program.statements[@backingInt(block.data.block[0])];
    if (statement.data != .match) return null;
    const match = statement.data.match;
    const read = program.nodes[@backingInt(value)];
    if (match.arms.len != 2 or read.data != .local or match.borrowed or match.exclusive) return null;
    var bound = false;
    var asserted = false;
    for (match.arms) |arm| {
        if (arm.slot) |slot| {
            if (slot != read.data.local or arm.unpack != null) return null;
            const arm_body = program.statements[@backingInt(arm.body)];
            if (arm_body.data != .block or arm_body.data.block.len != 0) return null;
            bound = true;
        } else {
            const arm_body = program.statements[@backingInt(arm.body)];
            if (arm_body.data != .assertion or !std.mem.eql(u8, arm_body.data.assertion.message, "invalidated Option narrowing")) return null;
            asserted = true;
        }
    }
    return if (bound and asserted) match.value else null;
}

fn receiverConstPlace(program: typed.Program, function: typed.Function, body: typed.StatementId, value: typed.NodeId) ?typed.NodeId {
    const block = program.statements[@backingInt(body)];
    if (block.data != .block or block.data.block.len != 1) return null;
    const statement = program.statements[@backingInt(block.data.block[0])];
    if (statement.data != .initialize) return null;
    const init = statement.data.initialize;
    if (!temporaryLocal(function.scope.locals[@backingInt(init.slot)]) or init.unpack != null) return null;
    const read = program.nodes[@backingInt(value)];
    if (read.data != .buffer_operation) return null;
    const operation = read.data.buffer_operation;
    if (operation.kind != .read or operation.owner != init.slot or operation.arguments.len != 1) return null;
    const container = program.nodes[@backingInt(init.value)].ty;
    if (!container.isAggregate()) return null;
    const kind = program.records[container.recordIndex()].collection.kind;
    return if (kind == .list or kind == .dictionary) init.value else null;
}

/// Whether `id` is `copy(place)` as the lowering writes it: a block that binds one temporary to a value and copies it.
fn copiedPlace(program: typed.Program, id: typed.NodeId) bool {
    const node = program.nodes[@backingInt(id)];
    if (node.data != .block_value) return false;
    const body = program.statements[@backingInt(node.data.block_value.body)];
    if (body.data != .block or body.data.block.len != 1) return false;
    const statement = program.statements[@backingInt(body.data.block[0])];
    if (statement.data != .initialize or statement.data.initialize.unpack != null) return false;
    const value = program.nodes[@backingInt(node.data.block_value.value)];
    if (value.data != .buffer_operation) return false;
    const operation = value.data.buffer_operation;
    return operation.kind == .copy and operation.owner == statement.data.initialize.slot and operation.arguments.len == 0;
}

/// Whether `local` is the hidden local of a generated invariant check that reads a container a running `match mut` arm
/// holds (`typed.invariant_hold_read`, made only by `sema_contracts.checkAfterBindingWrites`).
fn generatedHoldRead(local: typed.Local) bool {
    return local.origin == .contract_value and std.mem.eql(u8, local.name, typed.invariant_hold_read);
}

fn temporaryLocal(local: typed.Local) bool {
    if (std.mem.eql(u8, local.name, "<conditional>") or std.mem.eql(u8, local.name, "<fold-accumulator>")) return false;
    if (local.origin == .contract_value) return true;
    return std.mem.startsWith(u8, local.name, "<") or local.origin == .iteration or local.origin == .pattern;
}

/// The saved element being reconstructed by a compiler-generated slot writeback.
/// Checking proves its live read source; lowering proves the matching SSA read.
pub fn slotWritebackLocal(program: typed.Program, function: typed.Function, value: typed.NodeId) ?typed.LocalId {
    const base = switch (program.nodes[@backingInt(value)].data) {
        .update => |update| update.base,
        .replace => |replace| replace.base,
        else => return null,
    };
    const slot = switch (program.nodes[@backingInt(base)].data) {
        .local => |local| local,
        else => return null,
    };
    const local = function.scope.locals[@backingInt(slot)];
    return if (local.usage.temporary and std.mem.startsWith(u8, local.name, "<")) slot else null;
}

/// Whether `id` reads an element of a list or a dictionary (`xs[i]`, `d[k]`), through the blocks that stage its receiver.
fn elementRead(program: typed.Program, id: typed.NodeId) bool {
    var node = program.nodes[@backingInt(id)];
    while (node.data == .block_value) node = program.nodes[@backingInt(node.data.block_value.value)];
    if (node.data != .buffer_operation) return false;
    return node.data.buffer_operation.kind == .read or node.data.buffer_operation.kind == .get;
}

/// A second located fact a refusal carries beside its own span.
pub const Related = struct { span: Span, message: []const u8 };
/// The located facts a refusal carries beside its own span (W2). `related` is the refusal's own second fact (where a value
/// was declared, moved or borrowed); `cause` is the statement that made a borrowing local, record or collection own, which
/// is why the refused line needs `copy(...)` or `own`. The two never displace each other: a diagnostic prints both, the
/// related note first, and `diagnostic-v1` carries the cause as a note of role `cause`.
pub const Notes = struct { related: ?Related = null, cause: ?Related = null };
/// The certain `copy(...)` repairs of a refusal: one span (`span`, checked
/// against `name` when given) or, for a mixed return, every borrowed return
/// (`borrowed`). Each span gets `copy(` before it and `)` after it, and the repair
/// is offered only when every span is a whole expression.
pub const Copy = struct {
    span: ?Span = null,
    name: ?[]const u8 = null,
    borrowed: []const Span = &.{},
    /// The store the value is refused at fills a set, whose repair is `sets.include` (which copies only a new element) and
    /// not `copy(...)`: when the span is the last argument of a `sets.add` call, the repair is that one rename.
    into_set: bool = false,
};
/// A located refusal from the source ownership contract.
pub const Failure = struct {
    code: []const u8 = "",
    message: []const u8 = "",
    span: Span = .{ .start = 0, .end = 0 },
    copy: Copy = .{},
    /// The second located fact, such as where a value was declared or moved, and the statement that caused the refusal.
    notes: Notes = .{},
    /// The certain repair beside the copy repair (C6 and L16).
    repair: Repair = .none,
    /// The ownership rule this refusal enforces; compiler defects carry none.
    rule: ?Rule = null,
};
/// A certain repair a refusal offers. The copy repair stays where none is set; a
/// borrow repair replaces it, because a borrow is what keeps the copy from running.
pub const Repair = union(enum) {
    none,
    /// The name span of a `mut` parameter this refusal can turn into `own`
    /// (L16): a resource the callee stores or consumes is given away, so the
    /// certain repair rewrites the declaration's `mut` marker and every call
    /// site then passes `own arg`.
    own_parameter: Span,
    /// The name span of a `mut` binding of an element read that the function never
    /// changes: its `mut` marker becomes `const`, and the element is borrowed (C6 (a)).
    const_binding: Span,
    /// The edits that rewrite `mut x = xs[i]` and its write-back into the element
    /// place, each proven by `borrow_repair.zig` (C6 (b)).
    write_back: []const language.diagnostic.Edit,
    /// A source repair prepared by a rule's shared diagnostic renderer.
    explicit_fix: []const language.diagnostic.Edit,
    /// The receiver conflict whose scalar call can be moved into a preceding binding.
    receiver: receiver_repair.Site,
};
/// Allocation failure or a source contract violation.
pub const Error = error{ OutOfMemory, Rejected };

/// A node a certain marker or copy repair rewrites, and the binding whose borrow the repair ends.
const Mark = struct { id: typed.NodeId, slot: ?usize = null };
/// The repair of the last refusal a check raised, for `checkEvery` to apply and check the function again.
const Recovery = struct {
    const Kind = enum { own, unmark, copy };
    /// A general-purpose allocator for what a top-level check of `checkEvery` releases as soon as it is done: the check's own
    /// work arena.
    work: std.mem.Allocator,
    /// The refusal the repair belongs to; a repair recorded for any other refusal is not used.
    span: Span = .{ .start = 0, .end = 0 },
    /// The repair, when the last refusal raised has a certain one: the node it marks, unmarks or copies. `checkEvery` makes the
    /// rewrite once the check has returned, so nothing is patched while the check unwinds.
    repair: ?struct { mark: Mark, kind: Kind } = null,
    /// Whether a node whose type names a type parameter takes the repair this instance proves (`Every.stand_in_repairs`).
    stand_in: bool = false,
    /// Whether, under `stand_in`, a repair was looked for at a node whose type names a type parameter.
    type_dependent: bool = false,
};
/// The refusals of one function `checkEvery` reports at most; the function's later code is checked again after a fix.
pub const function_limit = 20;
/// Every refusal of a check, in the order the functions were checked, and the functions refused.
pub const Every = struct {
    failures: std.ArrayList(Failure) = .empty,
    /// The index of each refused function, once.
    rejected: std.ArrayList(usize) = .empty,
    /// Whether a function reached `function_limit` with refusals still to report.
    truncated: bool = false,
    /// A general-purpose allocator for each function's transient work: its checks, the probes that prove its repairs, and the
    /// rewrites its certain repairs make, each released when it is done. A rewrite copies the whole program's node and statement
    /// tables, so this must be an allocator that frees: with null the work is made in the results allocator, which is right
    /// only when that one frees too (in an arena every refused function's copies would stay until the whole check ends).
    work: ?std.mem.Allocator = null,
    /// Whether the rewrites of repairs patch one shared copy of the program's tables (`Scratch`); false makes each rewrite copy them,
    /// which reads the same and costs the size of the program per repair. Only a test turns it off, to compare the two.
    share_tables: bool = true,
    /// Whether a node whose type names a type parameter takes the repair its instance proves: only `judgeStandIns`' re-check of
    /// one refused instance, which keeps a repair only when every refused kind of type argument proves the same edits. Elsewhere
    /// one instance's proof says nothing of another's, and such a node has no repair.
    stand_in_repairs: bool = false,
    /// Under `stand_in_repairs`, whether a repair of a function's first refusal was looked for at a node whose type names a type
    /// parameter (`Checker.typeDependentRepair`): such a repair may not hold for an instance the check accepted (`StandInRepair`).
    first_type_dependent: bool = false,
};

/// Check and render every source refusal; false means the command must not continue. The refusals and the report are
/// allocated from `a`, which may be an arena; each function's transient work from `work`, a general-purpose allocator
/// (`Every.work`).
pub fn validate(a: std.mem.Allocator, work: std.mem.Allocator, program: typed.Program, src: language.source.Source, format: language.diagnostic_output.Format, report: *std.ArrayList(u8)) error{OutOfMemory}!bool {
    var every: Every = .{ .work = work };
    try checkEvery(a, program, null, src, &every);
    if (every.failures.items.len == 0) return true;
    try judgeStandIns(a, program, src, &every);
    try renderEvery(a, src, &every, format, report);
    return false;
}

/// Check every selected function and collect each refusal instead of stopping at the first (F-RC-214). A refused function is
/// checked again with the refusal's certain repair applied (a missing or misplaced `own`, a proven copy), the rewrite the
/// repair's own proof checked, so the next refusal is one the repaired source would report, never one the first caused; a
/// refusal with no certain repair ends its function. Each function reports at most `function_limit` refusals.
pub fn checkEvery(a: std.mem.Allocator, program: typed.Program, selected: ?[]const bool, source: ?language.source.Source, every: *Every) error{OutOfMemory}!void {
    std.debug.assert(selected == null or selected.?.len == program.functions.len);
    try markCallViews(a, program);
    const linear = try ownedTypes(a, program);
    defer a.free(linear);
    var walk = try files.Walk.init(a, program.records.len);
    defer walk.deinit();
    const payloads = try BorrowedRecords.casePayloads(a, program);
    defer a.free(payloads);
    var copy_claim: CopyClaim = .{};
    var scratch = Scratch.init(every.work orelse a, program);
    defer scratch.deinit();
    const shared: Shared = .{ .program = program, .linear = linear, .source = source, .files = &walk, .case_payloads = payloads, .copy_claim = &copy_claim, .scratch = if (every.share_tables) &scratch else null };
    for (program.functions, 0..) |function, function_index| {
        if (selected) |selection| if (!selection[function_index]) continue;
        try checkRecovering(a, shared, function, function_index, every);
    }
}

/// One function of `checkEvery`: check it, and while it is refused with a certain repair, check the repaired function again.
/// The refusals are allocated from `a`; everything else from `every.work`. The small parts of the rewrites (locals, the copy's
/// block) live in one arena for the function. The program's node and statement tables are not copied for a rewrite: the repairs patch
/// the check's one scratch copy (`Scratch`) and the function's patches are undone when it is done. Without a scratch copy
/// (`Every.share_tables`, or none could be made) the tables are copied for each rewrite and held one pair at a time: a rewrite's
/// tables are released once the next rewrite has copied them, and the last when the function is done.
/// The re-check mask that makes `function`'s borrowed collections (RB2) owners, with `shared`'s own mask; null when it has none.
fn plainCollections(a: std.mem.Allocator, shared: Shared, function: typed.Function) error{OutOfMemory}!?[]const bool {
    const payloads = if (shared.case_payloads.len == shared.program.records.len) shared.case_payloads else try BorrowedRecords.casePayloads(a, shared.program);
    const table = try BorrowedCollections.init(a, shared.program, shared.linear, function, payloads, shared.plain_mut);
    if (!table.any()) return null;
    const plain = try a.alloc(bool, table.slots.len);
    for (plain, table.slots, 0..) |*out, lent, slot| out.* = lent or (slot < shared.plain_mut.len and shared.plain_mut[slot]);
    return plain;
}

fn checkRecovering(a: std.mem.Allocator, shared: Shared, function: typed.Function, function_index: usize, every: *Every) error{OutOfMemory}!void {
    const work = every.work orelse a;
    var arena = std.heap.ArenaAllocator.init(work);
    defer arena.deinit();
    var current = shared;
    var subject = function;
    // The scratch copy's state before this function's patches, which are undone when it is done.
    const scratch_mark = if (shared.scratch) |scratch| scratch.mark() else null;
    defer if (shared.scratch) |scratch| scratch.rollback(scratch_mark.?);
    // The tables of the current rewrite, allocated from `work`: null while the function reads from the checked program or the scratch copy.
    var owned: Tables = .{};
    defer owned.release(work);
    // A function with borrowed collections (RB2) that is refused at all is reported, every refusal and repair, as it is when
    // they own their elements, as before RB2. The first refusal keeps the cause note that check found (W2).
    var first: Failure = .{};
    if (try plainCollections(arena.allocator(), shared, function)) |plain| {
        checkFunction(a, shared, function, &first, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Rejected => current.plain_mut = plain,
        };
        if (current.plain_mut.ptr != plain.ptr) return;
    }
    var refused: usize = 0;
    while (true) : (refused += 1) {
        var failure: Failure = .{};
        var recovery: Recovery = .{ .work = work, .stand_in = every.stand_in_repairs };
        checkFunction(a, current, subject, &failure, .{ .recovery = &recovery }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Rejected => {
                const same_first = std.meta.eql(first.span, failure.span) and std.mem.eql(u8, first.code, failure.code);
                if (refused == 0 and same_first and failure.notes.cause == null) failure.notes.cause = first.notes.cause;
                if (refused == 0) try every.rejected.append(a, function_index);
                if (refused == 0 and recovery.type_dependent) every.first_type_dependent = true;
                if (refused != 0) {
                    const previous = every.failures.items[every.failures.items.len - 1];
                    // A repair that leaves the same refusal in place made no progress.
                    if (previous.span.start == failure.span.start and previous.span.end == failure.span.end and std.mem.eql(u8, previous.code, failure.code)) return;
                }
                try every.failures.append(a, failure);
                const repair = recovery.repair orelse return;
                if (recovery.span.start != failure.span.start or recovery.span.end != failure.span.end) return;
                if (refused + 1 == function_limit) {
                    every.truncated = true;
                    return;
                }
                switch (repair.kind) {
                    .copy => {
                        const next = try Checker.rewriteCopy(arena.allocator(), work, current.scratch, .{ .program = current.program, .function = subject }, repair.mark.id, repair.mark.slot);
                        owned.release(work);
                        owned = if (next.owned) Tables.of(next.program) else .{};
                        current.program = next.program;
                        subject = next.function;
                    },
                    .own, .unmark => {
                        const own = repair.kind == .own;
                        const view = if (current.scratch) |scratch| scratch.adopt(current.program, 0, 0) else null;
                        if (view) |patched| {
                            try current.scratch.?.setOwn(@backingInt(repair.mark.id), own);
                            current.program = patched;
                        } else try patchOwn(work, &owned, &current, repair.mark.id, own);
                        if (repair.mark.slot) |slot| {
                            const locals = try arena.allocator().dupe(typed.Local, subject.scope.locals);
                            locals[slot].ownership.view = false;
                            subject.scope.locals = locals;
                        }
                    },
                }
                continue;
            },
        };
        return;
    }
}

/// Write the marker flag of node `id` into a private copy of the program's nodes, which `owned` then holds (made on the first write).
fn patchOwn(work: std.mem.Allocator, owned: *Tables, current: *Shared, id: typed.NodeId, own: bool) error{OutOfMemory}!void {
    if (owned.nodes == null) owned.nodes = try work.dupe(typed.Node, current.program.nodes);
    const nodes = owned.nodes.?;
    nodes[@backingInt(id)].own = own;
    current.program.nodes = nodes;
}

/// The program-sized tables a rewrite of `checkRecovering` allocated from its work allocator; null for a table the rewrite
/// shares with the checked program.
const Tables = struct {
    nodes: ?[]typed.Node = null,
    statements: ?[]typed.Statement = null,

    /// The tables of a copy's rewrite made by copying (`Checker.rewriteCopy`), which allocates both.
    fn of(program: typed.Program) Tables {
        return .{ .nodes = @constCast(program.nodes), .statements = @constCast(program.statements) };
    }

    fn release(self: Tables, work: std.mem.Allocator) void {
        if (self.nodes) |nodes| work.free(nodes);
        if (self.statements) |statements| work.free(statements);
    }
};

/// Report the refusals of generic instances once per template, at its declaration (W3 step 2): the message names the type
/// parameters and the kinds of argument that refuse (`template_stand_ins.describe`, the kinds from `stand_in_kinds`), the first
/// refusal's place and words become the note, and its repair (` from x`, `copy(...)`, an `own` written or removed) is the fix when
/// it is certain for the template (`StandInRepair`). `check` makes one
/// instance per kind a template's bounds admit (`diagnostic.Probes.declaration`), so there every body is judged for every kind;
/// a build judges the instances its program makes and reports them the same way. Every refusal of `every` at a place and code an
/// instance refused there leaves the list. Each refused instance is checked again alone to learn its own refusals; a program
/// with no refused instance is left as it is, and nothing runs when nothing is refused.
pub fn judgeStandIns(a: std.mem.Allocator, program: typed.Program, src: language.source.Source, every: *Every) error{OutOfMemory}!void {
    const any = for (every.rejected.items) |index| {
        if (index < program.functions.len and program.functions[index].type_arguments.len != 0) break true;
    } else false;
    if (!any) return;
    const Group = struct { declaration: Span, first: Failure, conditions: std.ArrayList(language.template_stand_ins.Condition), repair: StandInRepair };
    var groups: std.ArrayList(Group) = .empty;
    var removed: std.ArrayList(Failure) = .empty;
    var joined: std.ArrayList(usize) = .empty;
    const selected = try a.alloc(bool, program.functions.len);
    for (every.rejected.items) |index| {
        if (index >= program.functions.len or program.functions[index].type_arguments.len == 0) continue;
        const function = program.functions[index];
        @memset(selected, false);
        selected[index] = true;
        var alone: Every = .{ .work = every.work, .stand_in_repairs = true };
        try checkEvery(a, program, selected, src, &alone);
        if (alone.failures.items.len == 0) continue;
        // A result the instance's view sources cannot lend (`E_BORROW_SOURCE`) is already reported at the call, naming the
        // instance (`refuseUnlendable`): it stays as it is.
        if (std.mem.eql(u8, alone.failures.items[0].code, "E_BORROW_SOURCE")) continue;
        try removed.appendSlice(a, alone.failures.items);
        const found = language.stand_in_kinds.condition(function.type_arguments, program.records);
        const fix = try standInFix(a, src, alone.failures.items[0], function.declaration);
        const group = for (groups.items) |*group| {
            if (std.meta.eql(group.declaration, function.declaration)) break group;
        } else blk: {
            try groups.append(a, .{ .declaration = function.declaration, .first = alone.failures.items[0], .conditions = .empty, .repair = .{ .fix = fix } });
            break :blk &groups.items[groups.items.len - 1];
        };
        group.repair.add(alone.first_type_dependent, fix);
        try joined.append(a, index);
        try language.template_stand_ins.addCondition(a, &group.conditions, found.parameters, found.kind);
    }
    var kept: usize = 0;
    for (every.failures.items) |failure| {
        const repeated = for (removed.items) |instance| {
            if (std.meta.eql(instance.span, failure.span) and std.mem.eql(u8, instance.code, failure.code)) break true;
        } else false;
        if (repeated) continue;
        every.failures.items[kept] = failure;
        kept += 1;
    }
    every.failures.shrinkRetainingCapacity(kept);
    for (groups.items) |*group| {
        const names = try language.template_stand_ins.parameterNames(a, src.bytes, group.declaration.end);
        var failure = group.first;
        // `copy(...)` of a value of a type parameter whose bound does not admit `copy` is no repair (`T: storable`).
        if (!language.template_stand_ins.parametersCopy(src.bytes, group.declaration.end)) failure.copy = .{};
        if (!group.repair.certain(program, group.declaration, joined.items)) {
            failure.copy = .{};
            failure.repair = .none;
        }
        failure.span = group.declaration;
        failure.message = try language.template_stand_ins.describe(a, src.text(group.declaration), names, group.conditions.items);
        failure.notes.related = .{ .span = group.first.span, .message = group.first.message };
        try every.failures.append(a, failure);
    }
}

/// Whether the repair of a generic body's first refusal is certain for the template: every refused instance's first refusal has
/// the same edits (`diagnostic.Fix.same`), and, for a repair at a node whose type names a type parameter
/// (`Every.first_type_dependent`), every instance of the template the check did not refuse has only scalar type arguments,
/// where a written `own` is ignored and a `copy(...)` copies a scalar (an accepted instance with a managed argument might be
/// refused once the marker is written). An instance refused for another reason (`E_BORROW_SOURCE`) joins no group and so
/// counts as unrefused.
const StandInRepair = struct {
    fix: ?language.diagnostic.Fix,
    same: bool = true,
    type_dependent: bool = false,

    fn add(self: *StandInRepair, type_dependent: bool, fix: ?language.diagnostic.Fix) void {
        if (type_dependent) self.type_dependent = true;
        const mine = self.fix orelse {
            self.same = false;
            return;
        };
        const theirs = fix orelse {
            self.same = false;
            return;
        };
        if (!mine.same(theirs)) self.same = false;
    }

    /// `joined` holds the function index of every instance whose refusal joined a group.
    fn certain(self: StandInRepair, program: typed.Program, declaration: Span, joined: []const usize) bool {
        if (!self.same or self.fix == null) return false;
        if (!self.type_dependent) return true;
        for (program.functions, 0..) |function, index| {
            if (function.type_arguments.len == 0 or !std.meta.eql(function.declaration, declaration)) continue;
            const refused = for (joined) |at| {
                if (at == index) break true;
            } else false;
            if (refused) continue;
            if (language.stand_in_kinds.condition(function.type_arguments, program.records).kind != .int) return false;
        }
        return true;
    }
};

/// The fix the refusal `failure` of an instance of the template at `declaration` renders with (`diagnosticOf`), with the copy
/// repair dropped where the template's bounds do not admit `copy`.
fn standInFix(a: std.mem.Allocator, src: language.source.Source, failure: Failure, declaration: Span) error{OutOfMemory}!?language.diagnostic.Fix {
    var judged = failure;
    if (!language.template_stand_ins.parametersCopy(src.bytes, declaration.end)) judged.copy = .{};
    return (try diagnosticOf(a, src, judged)).diagnostic.provenance.fix;
}

/// Render the refusals of `every` in source order, each distinct refusal once (`distinct`).
pub fn renderEvery(a: std.mem.Allocator, src: language.source.Source, every: *Every, format: language.diagnostic_output.Format, report: *std.ArrayList(u8)) error{OutOfMemory}!void {
    for (distinct(every)) |failure| try render(a, src, failure, format, report);
}

/// The refusals of `every` in source order, each distinct refusal once: the instances of one generic body repeat theirs.
/// The order is kept in `every`, whose list shrinks to the result.
pub fn distinct(every: *Every) []const Failure {
    const items = every.failures.items;
    std.sort.insertion(Failure, items, {}, failureBefore);
    var kept: usize = 0;
    for (items) |failure| {
        const repeated = for (items[0..kept]) |earlier| {
            if (earlier.span.start == failure.span.start and earlier.span.end == failure.span.end and
                std.mem.eql(u8, earlier.code, failure.code) and std.mem.eql(u8, earlier.message, failure.message)) break true;
        } else false;
        if (repeated) continue;
        items[kept] = failure;
        kept += 1;
    }
    every.failures.shrinkRetainingCapacity(kept);
    return every.failures.items;
}

fn failureBefore(_: void, left: Failure, right: Failure) bool {
    return left.span.start < right.span.start;
}

/// Validate every checked function, including bodies reached through callbacks.
pub fn check(a: std.mem.Allocator, program: typed.Program, failure: *Failure) Error!void {
    return checkSelected(a, program, failure, null, null);
}

/// `check` with the entry source, which identifies the standard `parallel.map` (CX2, R-B2).
pub fn checkWithSource(a: std.mem.Allocator, program: typed.Program, src: language.source.Source, failure: *Failure) Error!void {
    return checkSelected(a, program, failure, null, src);
}

/// Mark bindings whose initializers all return a view of a checked argument.
pub fn markCallViews(a: std.mem.Allocator, program: typed.Program) std.mem.Allocator.Error!void {
    return language.call_views.markCallViews(a, program);
}

/// Validate selected function contracts after preparing shared type classification.
/// Callers may skip a function only when its ownership proof remains valid.
pub fn checkSelected(a: std.mem.Allocator, program: typed.Program, failure: *Failure, selected: ?[]const bool, source: ?language.source.Source) Error!void {
    var rejected: ?usize = null;
    return checkSelectedAt(a, program, failure, selected, source, &rejected);
}

/// `checkSelected`, also saying which function was refused: `rejected_at` is the index of the function whose check failed when
/// the result is `error.Rejected`, and is left alone otherwise.
pub fn checkSelectedAt(a: std.mem.Allocator, program: typed.Program, failure: *Failure, selected: ?[]const bool, source: ?language.source.Source, rejected_at: *?usize) Error!void {
    std.debug.assert(selected == null or selected.?.len == program.functions.len);
    try markCallViews(a, program);
    const linear = try ownedTypes(a, program);
    defer a.free(linear);
    var walk = try files.Walk.init(a, program.records.len);
    defer walk.deinit();
    const payloads = try BorrowedRecords.casePayloads(a, program);
    defer a.free(payloads);
    var copy_claim: CopyClaim = .{};
    const shared: Shared = .{ .program = program, .linear = linear, .source = source, .files = &walk, .case_payloads = payloads, .copy_claim = &copy_claim };
    for (program.functions, 0..) |function, function_index| {
        if (selected) |selection| if (!selection[function_index]) continue;
        checkFunction(a, shared, function, failure, .{}) catch |err| {
            if (err == error.Rejected) rejected_at.* = function_index;
            return err;
        };
    }
}

/// Compare every function with the front end's duplicate checks reported as warnings.
/// A refusal ends only that function's walk; later functions still contribute observations.
pub fn audit(a: std.mem.Allocator, program: typed.Program, src: language.source.Source, report: *std.ArrayList(u8)) error{OutOfMemory}!bool {
    try markCallViews(a, program);
    const linear = try ownedTypes(a, program);
    defer a.free(linear);
    var observer: Observer = .{ .source = src, .sink = .{ .allocator = a, .output = report } };
    var walk = try files.Walk.init(a, program.records.len);
    defer walk.deinit();
    const payloads = try BorrowedRecords.casePayloads(a, program);
    defer a.free(payloads);
    var copy_claim: CopyClaim = .{};
    const shared: Shared = .{ .program = program, .linear = linear, .source = src, .observer = &observer, .files = &walk, .case_payloads = payloads, .copy_claim = &copy_claim };
    try observer.record("program", .{ .start = 0, .end = 0 }, .{ .functions = program.functions.len, .typed_views = @as(usize, 0) });
    var accepted = true;
    for (program.functions, 0..) |function, index| {
        const sources = return_borrow.sources(function.signature);
        if (sources.len != 0) try observer.record("from", function.declaration, .{ .name = function.name, .sources = sources });
        var failure: Failure = .{};
        const valid = valid: {
            checkFunction(a, shared, function, &failure, .{}) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Rejected => {
                    try render(a, src, failure, .json, report);
                    accepted = false;
                    break :valid false;
                },
            };
            break :valid true;
        };
        try observer.record("function", function.declaration, .{ .index = index, .name = function.name, .specialized = function.type_arguments.len != 0, .accepted = valid });
    }
    return accepted;
}

/// Whether the entry source declares or binds the prelude name `copy`, which a copy repair would capture. The answer depends on the
/// source text alone and finding it lexes the whole source, so a check learns it once and every repair candidate reads it.
pub const CopyClaim = struct {
    known: ?bool = null,

    /// Whether `bytes` claims `copy`: lexed on the first ask. An allocation failure is "claimed" for this ask only (no repair is
    /// offered) and is asked again, so the answer a later ask learns is the real one.
    pub fn claimed(self: *CopyClaim, a: std.mem.Allocator, bytes: []const u8) bool {
        if (self.known) |answer| return answer;
        const answer = language.lexer.claimsName(a, bytes, "copy") catch return true;
        self.known = answer;
        return answer;
    }
};

/// One copy of a check's node and statement tables that the rewrites of its repairs patch instead of copying. A rewrite (a copy
/// repair's temporary, a marker written or removed) differs from the checked program in a few nodes and statements, but its check
/// reads whole tables, so each rewrite copied both: the size of the program for every repair, which a program of 20,000 functions
/// beside 600 refusals paid 1,200 times. The scratch holds one copy, made when a repair first needs it, with `slack` entries of room
/// above it for what a rewrite appends. A patch is journaled, and `rollback` undoes it: a probe undoes its patches when it has
/// proved its repair, and a function its own when it is done. A patch is read through the scratch's own tables only, so whoever
/// applies one must not read the program it patched from until it has rolled back (the check that raised a repair has returned
/// before `checkRecovering` applies it).
const Scratch = struct {
    /// Allocates the tables and the journal.
    gpa: std.mem.Allocator,
    /// The program whose tables the scratch copies; a rewrite of it, or of the scratch, is made in place.
    base: typed.Program,
    /// The copied tables with `slack` entries more than `base` has: null until a rewrite needs them.
    nodes: ?[]typed.Node = null,
    statements: ?[]typed.Statement = null,
    /// The entries of each table in use now: `base`'s, and two more for each copy rewrite not yet undone.
    node_len: usize,
    statement_len: usize,
    /// The nodes the patches replaced, newest last.
    journal: std.ArrayList(Undo) = .empty,

    const slack = 1024;
    const Undo = struct { index: usize, node: typed.Node };
    /// How much of the scratch is in use: `rollback` returns to it.
    const Extent = struct { journal: usize, nodes: usize, statements: usize };
    const TablePair = struct { nodes: []typed.Node, statements: []typed.Statement };

    fn init(gpa: std.mem.Allocator, base: typed.Program) Scratch {
        return .{ .gpa = gpa, .base = base, .node_len = base.nodes.len, .statement_len = base.statements.len };
    }

    fn deinit(self: *Scratch) void {
        if (self.nodes) |nodes| self.gpa.free(nodes);
        if (self.statements) |statements| self.gpa.free(statements);
        self.journal.deinit(self.gpa);
    }

    fn mark(self: *const Scratch) Extent {
        return .{ .journal = self.journal.items.len, .nodes = self.node_len, .statements = self.statement_len };
    }

    /// Undo every patch made since `at`, in reverse order.
    fn rollback(self: *Scratch, at: Extent) void {
        if (self.nodes) |nodes| while (self.journal.items.len > at.journal) {
            const undo = self.journal.pop().?;
            nodes[undo.index] = undo.node;
        };
        self.node_len = at.nodes;
        self.statement_len = at.statements;
    }

    /// Whether `program` is the scratch as it reads now, or the base while the scratch is untouched.
    fn reads(self: *const Scratch, program: typed.Program) bool {
        const nodes = self.nodes orelse return false;
        const statements = self.statements orelse return false;
        return program.nodes.ptr == nodes.ptr and program.nodes.len == self.node_len and
            program.statements.ptr == statements.ptr and program.statements.len == self.statement_len;
    }

    fn readsBase(self: *const Scratch, program: typed.Program) bool {
        return program.nodes.ptr == self.base.nodes.ptr and program.nodes.len == self.base.nodes.len and
            program.statements.ptr == self.base.statements.ptr and program.statements.len == self.base.statements.len;
    }

    /// Whether `program`'s tables are the scratch's, patches included.
    fn holds(self: *const Scratch, program: typed.Program) bool {
        const nodes = self.nodes orelse return false;
        return program.nodes.ptr == nodes.ptr;
    }

    /// `program` as the scratch holds it now, when `program` reads as the scratch does (or is the untouched base) and `nodes` more
    /// nodes and `statements` more statements fit above it; null when the caller must copy the tables. Makes the copy of the base's
    /// tables on the first use.
    fn adopt(self: *Scratch, program: typed.Program, nodes: usize, statements: usize) ?typed.Program {
        if (self.nodes == null) {
            if (!self.readsBase(program)) return null;
            self.copy() catch return null;
        }
        const untouched = self.journal.items.len == 0 and self.node_len == self.base.nodes.len and self.statement_len == self.base.statements.len;
        const is_base = untouched and self.readsBase(program);
        if (!self.reads(program) and !is_base) return null;
        if (self.node_len + nodes > self.nodes.?.len or self.statement_len + statements > self.statements.?.len) return null;
        var view = program;
        view.nodes = self.nodes.?[0..self.node_len];
        view.statements = self.statements.?[0..self.statement_len];
        return view;
    }

    fn copy(self: *Scratch) error{OutOfMemory}!void {
        const nodes = try self.gpa.alloc(typed.Node, self.base.nodes.len + slack);
        errdefer self.gpa.free(nodes);
        const statements = try self.gpa.alloc(typed.Statement, self.base.statements.len + slack);
        @memcpy(nodes[0..self.base.nodes.len], self.base.nodes);
        @memcpy(statements[0..self.base.statements.len], self.base.statements);
        self.nodes = nodes;
        self.statements = statements;
    }

    /// Set the marker flag of node `id` in the scratch, journaled.
    fn setOwn(self: *Scratch, id: usize, own: bool) error{OutOfMemory}!void {
        const nodes = self.nodes.?;
        try self.journal.append(self.gpa, .{ .index = id, .node = nodes[id] });
        nodes[id].own = own;
    }

    /// Replace node `id` in the scratch, journaled.
    fn setNode(self: *Scratch, id: usize, node: typed.Node) error{OutOfMemory}!void {
        const nodes = self.nodes.?;
        try self.journal.append(self.gpa, .{ .index = id, .node = nodes[id] });
        nodes[id] = node;
    }

    /// FR63: `program` with each node of `moves` (a field moved with `own`) replaced by `take(mut place)` of that field, the place being
    /// a node of its own appended after the nodes in use; null when `adopt` says no. Each replaced node is journaled.
    fn exchange(self: *Scratch, program: typed.Program, moves: []const typed.NodeId) error{OutOfMemory}!?typed.Program {
        var view = self.adopt(program, moves.len, 0) orelse return null;
        const nodes = self.nodes.?;
        for (moves) |move| {
            const index = @backingInt(move);
            try self.journal.append(self.gpa, .{ .index = index, .node = nodes[index] });
            nodes[self.node_len] = nodes[index];
            nodes[self.node_len].own = false;
            nodes[index] = taking(nodes[index], @fromBackingInt(self.node_len));
            self.node_len += 1;
        }
        view.nodes = nodes[0..self.node_len];
        return view;
    }

    /// Make room for one copy rewrite of node `definition` of `program`: journal the node, which the rewrite replaces, and take two
    /// more entries of each table. The tables come back with those entries counted, for the caller to fill; null when `adopt` says no.
    fn extend(self: *Scratch, program: typed.Program, definition: typed.NodeId) error{OutOfMemory}!?TablePair {
        _ = self.adopt(program, 2, 2) orelse return null;
        const nodes = self.nodes.?;
        try self.journal.append(self.gpa, .{ .index = @backingInt(definition), .node = nodes[@backingInt(definition)] });
        self.node_len += 2;
        self.statement_len += 2;
        return .{ .nodes = nodes[0..self.node_len], .statements = self.statements.?[0..self.statement_len] };
    }
};

/// `take(mut place)` for the field moved at `moved`: the moved value, the type's default left at `place` (FR63).
fn taking(moved: typed.Node, place: typed.NodeId) typed.Node {
    return .{ .span = moved.span, .ty = moved.ty, .data = .{ .place_exchange = .{ .place = place, .value = null } } };
}

/// FR91B: the names joined by dots that the source writes from `start` (`p.lo` of `own p.lo, ...`).
fn placeChain(bytes: []const u8, start: usize) []const u8 {
    var end = start;
    while (end < bytes.len and (std.ascii.isAlphanumeric(bytes[end]) or bytes[end] == '_' or bytes[end] == '.')) end += 1;
    while (end > start and bytes[end - 1] == '.') end -= 1;
    return bytes[start..end];
}

/// The program-wide tables one function's check reads, shared by every function
/// and by the probes that re-check a function with one binding changed.
const Shared = struct {
    program: typed.Program,
    linear: []const bool,
    source: ?language.source.Source,
    observer: ?*Observer = null,
    /// What the walks of this program's functions have learned about stored files (`single_owner_files.zig`): one set of marks for the
    /// whole check, so a type is walked once however many locals have it. Null for a re-check over records of its own.
    files: ?*files.Walk = null,
    /// The `mut` locals a re-check treats as owners although every store to them is a place (4f), so a refusal that holding a
    /// borrow causes is reported as it was before 4f: indexed by local, empty for none.
    plain_mut: []const bool = &.{},
    /// The record constructors a re-check builds as owners although they are borrowed records (1A), so a refusal a
    /// borrowed record causes is reported as it was before 1A: indexed by node, empty for none.
    plain_records: []const bool = &.{},
    /// `BorrowedRecords.casePayloads` of the program, computed once per check; empty when a re-check has records of its own.
    case_payloads: []const bool = &.{},
    /// What the check has learned about the source's use of the name `copy`; null asks each repair candidate to lex the source itself.
    copy_claim: ?*CopyClaim = null,
    /// The one copy of the tables the check's rewrites patch; null makes each rewrite copy them.
    scratch: ?*Scratch = null,
};

const BindingOwn = struct { slot: usize, definition: typed.NodeId };
const MissingMove = struct { definition: typed.NodeId, moved: Span };
const CopySite = struct { definition: typed.NodeId, borrowed_slot: ?usize = null };
const CopyBoundary = struct { definition: typed.NodeId, result: bool = true };
/// One complete proof pass's refusal and the exact source sites it observed.
const RepairObservations = struct {
    failure: Failure = .{},
    needed_own: ?BindingOwn = null,
    needed_copy: ?CopySite = null,
    needed_removal: ?typed.NodeId = null,
    moves: std.ArrayList(MissingMove) = .empty,
};
const RepairProbe = struct {
    active: bool = false,
    /// Where a check that keeps going past a refusal (`checkEvery`) receives the rewrite of the refusal's certain repair.
    /// Only the top-level check of `checkEvery` sets it; a probe never does.
    recovery: ?*Recovery = null,
    needed_own: ?*?BindingOwn = null,
    needed_copy: ?*?CopySite = null,
    needed_removal: ?*?typed.NodeId = null,
    moves: ?*std.ArrayList(MissingMove) = null,
};

/// Check one function body against the ownership contract. `probe` marks a
/// re-check made to prove a borrow repair; a probe never offers repairs itself.
fn checkFunction(a: std.mem.Allocator, shared: Shared, function: typed.Function, failure: *Failure, probe: RepairProbe) Error!void {
    const program = shared.program;
    const linear = shared.linear;
    {
        // A top-level check of `checkEvery` makes its work where it is freed when the check returns, whatever `a` is.
        var work = std.heap.ArenaAllocator.init(if (probe.recovery) |recovery| recovery.work else a);
        defer work.deinit();
        var private: files.Walk = undefined;
        const walk = shared.files orelse fresh: {
            private = try files.Walk.init(work.allocator(), program.records.len);
            break :fresh &private;
        };
        var c: Checker = .{
            .source = shared.source,
            .a = work.allocator(),
            .diagnostics = .{ .allocator = a, .observer = shared.observer },
            .program = program,
            .function = function,
            .linear = linear,
            .files = walk,
            .failure = failure,
            .probing = probe,
            .state = try work.allocator().alloc(State, function.scope.locals.len),
        };
        @memset(c.state, .{});
        const payloads = if (shared.case_payloads.len == program.records.len) shared.case_payloads else try BorrowedRecords.casePayloads(work.allocator(), program);
        c.case_payloads = payloads;
        c.copy_claim = shared.copy_claim;
        c.scratch = shared.scratch;
        c.plain_records = shared.plain_records;
        const borrowed_mut = try borrowedMutLocals(work.allocator(), program, linear, function, payloads);
        for (shared.plain_mut, 0..) |plain, slot| if (plain and slot < borrowed_mut.len) {
            borrowed_mut[slot] = false;
        };
        c.borrowed_mut = borrowed_mut;
        c.plain_mut = shared.plain_mut;
        const collections = try BorrowedCollections.init(work.allocator(), program, linear, function, payloads, shared.plain_mut);
        if (collections.any()) {
            const held = try work.allocator().create(CollectionState);
            held.* = .{ .table = collections, .roots = try work.allocator().alloc(Roots, function.scope.locals.len) };
            @memset(held.roots, .{});
            c.collections = held;
        }
        try c.collectWrites();
        for (function.scope.locals, 0..) |local, index| {
            try c.supportedFiles(local.ty, local.declaration);
            if (index < function.signature.parameter_count) {
                // One of three declared modes. `own` takes the value, so the
                // callee owns it and may store, return or move it. `mut` is an
                // exclusive borrow for every type, a resource included (L16):
                // it may read and write through the parameter but cannot keep
                // it. A plain parameter of an affine (move-only) type is
                // refused by the front end; it must declare `own` or `mut`.
                const own = index < function.scope.own_parameters.len and function.scope.own_parameters[index];
                const affine = resources.affine(program, local.ty);
                c.state[index] = .{
                    .available = true,
                    .dependency = if (resources.dependent(program, local.ty)) index else none,
                    .traits = .{
                        .borrowed = if (own) false else if (affine) local.mutable else isOwned(linear, local.ty),
                        .rule = if (local.mutable) .M1 else .R1,
                        .writable = local.mutable,
                    },
                };
            }
        }
        try c.supportedFiles(function.signature.return_type, function.declaration);
        if (resources.dependent(program, function.signature.return_type)) _ = try c.resourceParameter(function, function.declaration);
        if (instance_borrow.unlendable(program, function)) return c.refuseUnlendable();
        if (function.policy.c_abi or function.policy.host != null) return;
        c.finishFunction(c.finishReturns(c.checkStatement(function.scope.body))) catch |err| {
            if (err == error.Rejected) {
                try c.recoverCopy();
                try c.withoutHiddenNames();
            }
            return err;
        };
    }
}

/// Resolve owned leaves to a fixed point once before selecting function bodies (`owned_types.zig`).
fn ownedTypes(a: std.mem.Allocator, program: typed.Program) error{OutOfMemory}![]bool {
    return language.owned_types.table(a, program);
}

fn isLinear(linear: []const bool, ty: typed.Type) bool {
    return language.owned_types.isLinear(linear, ty);
}

/// Whether a record is an ordinary one: not managed, not a collection or a box, no array, variant, resource, domain or callback
/// shape, and no boxed field. Only its fields are disjoint storage, so a field of it can be moved out or passed apart.
fn ordinaryRecord(record: typed.Record) bool {
    if (record.managed or record.collection.box or record.isCollection()) return false;
    if (record.shape.array != null or record.shape.variants != null or record.shape.resource != null) return false;
    if (record.shape.domain != null or record.contract.callback != null) return false;
    for (record.fields) |field| if (field.boxed) return false;
    return true;
}

/// Whether a value of type `ty` owns storage the ownership pass tracks: a file, or a type `linear` (`ownedTypesOf`) marks.
pub fn isOwned(linear: []const bool, ty: typed.Type) bool {
    return language.owned_types.isOwned(linear, ty);
}

/// Whether a match reads the call `id` in place: its result borrows the owners named by the callee's `from` clause, and
/// the result is an owning, non-view, non-resource value. The checker and Core decide a match's scrutinee with this one
/// predicate, so the arms' ownership cannot disagree between them (R3b).
pub fn borrowedCallValue(program: typed.Program, linear: []const bool, id: typed.NodeId) bool {
    const node = program.nodes[@backingInt(id)];
    if (node.data != .call) return false;
    if (resources.affine(program, node.ty)) return false;
    if (!isOwned(linear, node.ty)) return false;
    const call = node.data.call;
    if (@backingInt(call.function) >= program.functions.len) return false;
    const signature = program.functions[@backingInt(call.function)].signature;
    return return_borrow.effectiveSources(program.records, signature).len != 0;
}

/// The owning-type table `borrowedCallValue` reads, for a builder outside the checker.
pub fn ownedTypesOf(a: std.mem.Allocator, program: typed.Program) error{OutOfMemory}![]bool {
    return ownedTypes(a, program);
}

const BindingTraits = struct {
    borrowed: bool = false,
    writable: bool = false,
    transferable: bool = false,
    ambiguous_borrow: bool = false,
    /// A scoped handle may be lent whole to a `mut` argument.
    scoped_resource: bool = false,
    /// Why a store of this borrowed binding is refused.
    rule: Rule = .B7,
    /// FR91: a field move of a group consumed this record (at `State.moved_span`); the group's other moves may follow.
    field_opened: bool = false,
};
const SliceRule = enum { V3, V5 };

fn sliceRefusal(rule: SliceRule) Refusal {
    return switch (rule) {
        .V3 => .{ .code = "E_SLICE_ESCAPES", .rule = .V3 },
        .V5 => .{ .code = "E_SLICE_ESCAPES", .rule = .V5 },
    };
}

/// A running `match mut`'s place and its scrutinee's span (FX9), and the payload slot of its running arm (`none` before one runs).
const HeldPlace = struct { place: typed.NodeId, span: Span, payload: usize = none };

const State = struct {
    available: bool = false,
    traits: BindingTraits = .{},
    root: usize = none,
    view_definition: ViewDefinition = .{},
    dependency: usize = none,
    moved_span: Span = .{ .start = 0, .end = 0 },
    /// An invalidated slice differs from a slice joined from incompatible sources.
    view_rule: SliceRule = .V3,
};
const ConstOrigin = struct { definition: typed.NodeId, roots: Roots, borrowed: bool };
/// The change to a slice view's source that made the view unreadable: where it is and whether it moved or wrote the source (FR57).
const Invalidation = struct { span: Span, access: Access };
/// What defines a view binding: its slice expression or selection, and the change to its source that made it unreadable.
const ViewDefinition = struct { node: ?typed.NodeId = null, const_origins: []const ConstOrigin = &.{}, invalidated: ?Invalidation = null };
const Access = enum { read, move, mutate, update, writeback };
fn writebackBase(access: Access) Access {
    return switch (access) {
        .writeback => .read,
        .update => .mutate,
        else => .move,
    };
}
const PlaceStep = union(enum) { field: usize, index: typed.NodeId };
const PlacePath = struct { root: usize = none, steps: std.ArrayList(PlaceStep) = .empty };
/// F-24: the loans of a call's earlier arguments (`begin` up to `end`) whose conflicting reads wait for the value of the
/// argument being evaluated, and the first loan such a read met, with the place read (`read`) and where.
const OwnValueRead = struct { begin: usize, end: usize, conflict: ?Loan = null, read: DeferredRead = .{} };
/// The read a deferred conflict met: the slot read, the span of the read and the argument being checked then.
const DeferredRead = struct { slot: usize = none, span: Span = .{ .start = 0, .end = 0 }, argument: ArgumentContext = .{} };
/// The argument of a call being checked (`Checker.argument`).
const ArgumentContext = struct { value: ?typed.NodeId = null, path: ?PlacePath = null, write: bool = false, call: bool = false };
/// The name of the temporary `in` and `not in` stage an operand in (`src/sema_operators.zig`, the membership arm).
const membership_operand = "<membership>";
/// The overlap refusal of a loan whose source the checker does not name more closely.
const generic_overlap = "a value cannot be moved or mutated while another argument or iteration borrows it; copy it with copy(value) or finish the borrow first";
const Hold = union(enum) { none, argument: Span, matched: Span, receiver: Span, constant: typed.StatementId, scope: Span };

/// A read or write hold on an owner. `hold` identifies its source argument, match or receiver,
/// so a refusal can name the source that established the hold.
/// `binding` is the `const` local whose borrow this is (B7), and `release` the statement of its block after which the borrow ends.
const Loan = struct { root: usize, write: bool, path: ?PlacePath = null, hold: Hold = .none, rule: Rule = .R2, binding: usize = none, release: usize = none };
/// The source of a `for` loop's iterable and the element type of its list, kept beside the iteration loan at index `loan` of the loans.
const Iterated = struct { loan: usize, span: Span, element: typed.Type };
const TaskLoan = struct { root: usize, group: typed.LocalId, span: Span };
const TaskExit = struct { target: usize, continuing: bool, loan: TaskLoan };
/// Task loans survive expression, alias and nested-block lifetimes. Only the
/// group's join releases them; branch joins union their continuing paths.
const Tasks = struct {
    loans: std.ArrayList(TaskLoan) = .empty,
    exits: std.ArrayList(TaskExit) = .empty,

    fn add(tasks: *Tasks, a: std.mem.Allocator, loan: TaskLoan) Error!void {
        for (tasks.loans.items) |held| if (held.root == loan.root and held.group == loan.group) return;
        try tasks.loans.append(a, loan);
    }

    fn close(tasks: *Tasks, group: typed.LocalId) void {
        var position = tasks.loans.items.len;
        while (position != 0) {
            position -= 1;
            if (tasks.loans.items[position].group == group) _ = tasks.loans.orderedRemove(position);
        }
        position = tasks.exits.items.len;
        while (position != 0) {
            position -= 1;
            if (tasks.exits.items[position].loan.group == group) _ = tasks.exits.orderedRemove(position);
        }
    }
};
/// A loop being checked: its id, the state before its body, and its body's source span (a local declared inside it is made
/// again in each iteration).
const Loop = struct { id: usize, before: []const State, body: Span };
/// What a `return` value is, judged before it is checked (R3a): a place of a
/// borrowed parameter, a new value, a value with no storage (`None`, a literal),
/// or another view that the escape rules judge.
const ReturnKind = enum { place, new, neutral, other };
/// The returns of the function being checked, for the mixed-return refusal (R3a).
/// A borrowed return is refused as it is reached, and the refusal waits for the
/// function's last return: a function that also returns a new value is
/// `E_BORROW_MIXED`, and any other function keeps the first refusal it would
/// have raised.
const ReturnTally = struct {
    /// The copy repair of every borrowed return, in source order.
    borrowed: std.ArrayList(Span) = .empty,
    /// Actual return-expression identities, retained for exact source-copy proofs.
    borrowed_values: std.ArrayList(typed.NodeId) = .empty,
    /// The first return of a new value.
    new_value: ?Span = null,
    /// The first refused borrowed return, with the refusal it raised.
    refused: ?Failure = null,
    /// Every owner the accepted borrowed returns read from.
    roots: Roots = .{},
    /// Parameter places returned without being named in the declaration.
    missing: Roots = .{},
    /// The first return that uses a lender missing from the declaration.
    first_missing: ?Span = null,
};

/// An immutable, arena-owned set of every owner a borrowed value reads.
/// Flags retain temporary and representation facts without limiting its size.
const Roots = struct {
    items: []const usize = &.{},
    temp: bool = false,
    unknown: bool = false,
    view: bool = false,
    /// The value holds a box of this call's frame (O4, a lent `Some(p)` of a recursive field): it never leaves the call.
    frame: bool = false,
    /// The value holds a frame block of a text, bytes or list parameter (RB1): it never leaves the call either.
    block_frame: bool = false,

    fn add(self: *Roots, a: std.mem.Allocator, root: usize) Error!void {
        if (std.mem.indexOfScalar(usize, self.items, root) != null) return;
        const items = try a.alloc(usize, self.items.len + 1);
        @memcpy(items[0..self.items.len], self.items);
        items[self.items.len] = root;
        self.items = items;
    }

    fn merge(self: *Roots, a: std.mem.Allocator, other: Roots) Error!void {
        for (other.items) |root| try self.add(a, root);
        self.temp = self.temp or other.temp;
        self.unknown = self.unknown or other.unknown;
        self.view = self.view or other.view;
        self.frame = self.frame or other.frame;
        self.block_frame = self.block_frame or other.block_frame;
    }

    fn slice(self: *const Roots) []const usize {
        return self.items;
    }
};

/// The borrowed collections of a function being checked (RB2): the table, and per local the union of the roots its element
/// stores have borrowed so far, which the collection holds to its last use.
const CollectionState = struct {
    table: BorrowedCollections,
    roots: []Roots,
    /// Whether the receiver now checked is that of an element store, the one change a borrowed collection may take.
    storing: bool = false,
};

/// The loan a match arm holds on its named scrutinee (C3), keyed by the arm's body statement.
const ArmHold = struct { body: typed.StatementId, loan: Loan };

/// Distinct outer record fields separate staged receivers before any shared list step.
fn differentOuterFields(left: PlacePath, right: PlacePath) bool {
    const a = left.steps.items;
    const b = right.steps.items;
    for (0..@min(a.len, b.len)) |offset| {
        const first = a[a.len - 1 - offset];
        const second = b[b.len - 1 - offset];
        if (first != .field or second != .field) return false;
        if (first.field != second.field) return true;
    }
    return false;
}

/// What reads a temporary that stages an owning store: a collection operation on its owner, or a record field update.
const Staged = union(enum) { collection: usize, update: struct { base: typed.NodeId, index: usize } };

const Checker = struct {
    a: std.mem.Allocator,
    /// The entry source, when the caller has one: it names the standard `parallel.map` (R-B2).
    source: ?language.source.Source = null,
    diagnostics: struct { allocator: std.mem.Allocator, observer: ?*Observer = null },
    program: typed.Program,
    function: typed.Function,
    linear: []const bool,
    /// The marks of the stored-file walk, shared by every function of the check (`Shared.files`).
    files: *files.Walk,
    /// What the check has learned about the source's use of the name `copy` (`Shared.copy_claim`).
    copy_claim: ?*CopyClaim = null,
    /// The check's shared copy of the tables for rewrites (`Shared.scratch`).
    scratch: ?*Scratch = null,
    failure: *Failure,
    state: []State,
    /// The argument being checked; `call` when it is an argument of a direct call (not a print, an invoke or a resource).
    argument: ArgumentContext = .{},
    loans: std.ArrayList(Loan) = .empty,
    /// The iterable a `for` loop wrote, with the loan that holds it, for the refusal of a change to its owner (`iterationLoopMessage`).
    iterated: std.ArrayList(Iterated) = .empty,
    tasks: Tasks = .{},
    loops: std.ArrayList(Loop) = .empty,
    /// The value each temporary was initialized with, so an escape check can see
    /// through the temporaries the lowering wraps a slice's endpoints in.
    temporary_definitions: std.AutoHashMapUnmanaged(u32, typed.NodeId) = .empty,
    /// Whether the value being checked is a statement's returned value, where a
    /// view binding is checked against the declaration's complete borrow sources.
    returning: bool = false,
    /// Where the value being moved ends up, for the message of an Escape refusal (`escape_message.zig`); the innermost store,
    /// constructor field or return that started the move.
    sink: escape_message.Destination = .elsewhere,
    /// The span of the element read that `collection` last refused as borrowed, so a `mut` binding it initialized can name its repair.
    element_read: ?Span = null,
    /// The function whose arguments are being checked (its index), for the `own` parameter an argument is given to.
    callee: ?usize = null,
    /// What reads each compiler temporary that stages an owning store, built on first use (`stagedSink`).
    staged: ?std.AutoHashMapUnmanaged(u32, Staged) = null,
    /// The two sources a view binding was assigned on the branches that joined (V5), by binding.
    joined: std.AutoHashMapUnmanaged(u32, [2]usize) = .empty,
    /// A written marker authorizes only its source place, never nested calls;
    /// a bare returned local has the same narrowly scoped implicit transfer.
    marker: struct { permitted: ?typed.NodeId = null, returned: ?typed.NodeId = null } = .{},
    /// Whether this check re-checks a function to prove a repair. A probe reports
    /// the refusal and offers no repair of its own, so the probes never nest.
    probing: RepairProbe = .{},
    /// F-24: the managed read argument being evaluated beside a `mut` argument of the same call, whose conflicting reads
    /// wait for its value (`deferOwnValueRead`).
    own_value_read: ?*OwnValueRead = null,
    /// Generated setup may share the complete source expression's span and
    /// even its final read node. Only its result path represents a source copy.
    copy_boundary: ?CopyBoundary = null,
    /// Whether the value being checked initializes or assigns a plain local. A
    /// view binding may re-bind a copy into an owned local; only owning storage,
    /// a return or an invalidation is the escape W3 refuses.
    local_store: bool = false,
    /// The innermost block being checked, for the borrows of its `const` bindings (B7).
    block: ?BlockContext = null,
    /// The returns of this function, for the mixed-return refusal (R3a).
    returns: ReturnTally = .{},
    /// The scrutinee holds of the match arms being checked (C3): each is pushed as a loan when its arm's body block is
    /// entered, and released after that block's last use of one of the arm's payload bindings.
    arm_holds: std.ArrayList(ArmHold) = .empty,
    /// The payload bindings of the `match mut` arms checked so far (C1): each writes through to the matched place, so it
    /// may be written and read but never moved, and it may touch its own container while its arm's hold is live.
    exclusive_binders: std.ArrayList(usize) = .empty,
    /// The compiler temporary that holds the `match mut` scrutinee's receiver (the list or dictionary a place read goes
    /// through): a binding's write back into the container reaches the container through it (C1).
    exclusive_receivers: std.ArrayList(usize) = .empty,
    /// The places of the running `match mut`s, with the scrutinee's span their arms' holds carry (FX9): which writes to
    /// a held owner replace the matched place, and which inner match is on an enclosing arm's binding.
    held_places: std.ArrayList(HeldPlace) = .empty,
    /// The locals this function's body writes, for a compiler temporary declared `mut` that nothing writes (R3b).
    written: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// The initializer of each plain local, so a compiler temporary nothing writes can be read through it (R3b).
    definitions: std.AutoHashMapUnmanaged(u32, typed.NodeId) = .empty,
    /// The `const` bindings of a record place whose record this body writes later (`alias_places`): a write to a field disjoint from
    /// the place may stand while one is live, because the lowering reads such a binding's place again after the write. Found on the
    /// first conflict with a binding's loan, so a body that never has one pays nothing.
    place_bindings: ?[]const alias_places.Flags = null,
    /// The `mut` locals that hold a borrow (4f, `borrowedMutLocals`), indexed by local.
    borrowed_mut: []const bool = &.{},
    /// The re-check mask of `Shared.plain_mut`, kept so a repair probe judges the same locals as owners.
    plain_mut: []const bool = &.{},
    /// The borrowed `mut` local whose borrow caused the last refusal raised, with that refusal's span and code.
    plain_cause: ?struct { slot: usize, span: Span, code: []const u8 } = null,
    /// Which record constructors of this function are borrowed values (1A, `BorrowedRecords`), built on first use.
    records: ?BorrowedRecords = null,
    /// `BorrowedRecords.casePayloads` of the program.
    case_payloads: []const bool = &.{},
    /// The re-check mask of `Shared.plain_records`, kept so a repair probe builds the same records as owners.
    plain_records: []const bool = &.{},
    /// The borrowed record whose borrow caused the last refusal raised, with that refusal's span and code (1A).
    record_cause: ?struct { node: typed.NodeId, span: Span, code: []const u8 } = null,
    /// The borrowed collection whose use or loan caused the last refusal raised, with that refusal's span and code (W2).
    collection_cause: ?struct { slot: usize, span: Span, code: []const u8 } = null,
    /// The call a task group submits: its arguments are lent to the task, so none is a borrowed record (1A).
    task_call: ?typed.NodeId = null,
    /// FR91: the field moves of the statement being checked that leave one record together (`field_moves.zig`).
    field_moves: field_moves.Groups = .{},
    /// The constructor a `const` initializer, a borrowed `mut` store or a `from` return is reading as a borrowed record.
    record_permit: ?typed.NodeId = null,
    /// The borrowed records passed as read-only call arguments so far, by argument span: a refusal of a loan one holds is
    /// caused by that record.
    record_arguments: std.ArrayList(struct { span: Span, node: typed.NodeId }) = .empty,
    /// The borrowed collections of this function (RB2, `BorrowedCollections`) and the roots each one's stores borrow so far;
    /// null when it has none.
    collections: ?*CollectionState = null,

    fn reject(c: *Checker, span: Span, refusal: Refusal, message: []const u8) Error {
        std.debug.assert(ownership_rules.valid(refusal));
        c.failure.* = .{ .code = refusal.code, .rule = refusal.rule, .message = message, .span = span };
        if (c.probing.recovery) |recovery| recovery.repair = null;
        return error.Rejected;
    }

    fn rejectInternal(c: *Checker, span: Span, code: []const u8, message: []const u8) Error {
        c.failure.* = .{ .code = code, .message = message, .span = span };
        if (c.probing.recovery) |recovery| recovery.repair = null;
        return error.Rejected;
    }

    /// The refusal's messages with each name the compiler made for a layer of a pattern put in words: no diagnostic of this check
    /// prints one (`pattern_message.hidden`). The sites that know the pattern name it; this is the one place that covers the rest.
    /// A `detach` loop's hidden local is written as the place the user wrote (`typed.withDetachedNamesWritten`).
    fn withoutHiddenNames(c: *Checker) Error!void {
        const a = c.diagnostics.allocator;
        c.failure.message = try typed.withDetachedNamesWritten(a, try pattern_message.withoutHiddenNames(a, c.failure.message));
        if (c.failure.notes.related) |*related| related.message = try typed.withDetachedNamesWritten(a, try pattern_message.withoutHiddenNames(a, related.message));
        if (c.failure.notes.cause) |*cause| cause.message = try typed.withDetachedNamesWritten(a, try pattern_message.withoutHiddenNames(a, cause.message));
    }

    /// A refusal whose only repair is the rendered `copy(...)` of one whole expression: hand `checkEvery` the function with
    /// that expression copied, as `recoverAt` does for a proven copy. The copied node is the outermost one the span covers,
    /// the expression the source edit wraps.
    fn recoverCopy(c: *Checker) Error!void {
        const recovery = c.probing.recovery orelse return;
        if (recovery.repair != null or c.failure.repair != .none or c.failure.copy.borrowed.len != 0) return;
        const span = c.failure.copy.span orelse return;
        const src = c.source orelse return;
        if (c.failure.copy.name != null and !std.mem.eql(u8, src.text(span), c.failure.copy.name.?)) return;
        if (!try copyExpressionSource(c.a, src, span)) return;
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        const id = while (try walker.next()) |item| {
            if (item != .expression) continue;
            const node = c.program.nodes[@backingInt(item.expression)];
            if (node.span.start == span.start and node.span.end == span.end) break item.expression;
        } else return;
        if (!c.copyRepairAvailable(id)) return;
        const slot: ?usize = for (c.program.statements) |statement| {
            if (statement.data == .initialize and statement.data.initialize.value == id) break @backingInt(statement.data.initialize.slot);
        } else null;
        c.recoverAt(.{ .id = id, .slot = slot }, .copy);
    }

    /// Tell `checkEvery` the repair of the refusal just raised: the marker written (`own`) or removed (`unmark`) at `mark`, or the
    /// value copied (`copy`). `checkEvery` makes the rewrite once this check has returned, the same rewrite the repair's own proof
    /// checked (`rewriteCopy`); the checked tree stays untouched while this check unwinds. Nothing is recorded unless `checkEvery`
    /// asked for it.
    /// Whether a repair at `node` is withheld because its type names a type parameter: one instance's proof holds for that
    /// instance only, save in `judgeStandIns`' re-check of a refused instance (`Recovery.stand_in`), which compares the repairs of
    /// every refused kind of type argument and keeps one only when they are the same edits.
    fn typeDependentRepair(c: *const Checker, node: typed.Node) bool {
        if (!node.type_dependent) return false;
        const recovery = c.probing.recovery orelse return true;
        if (!recovery.stand_in) return true;
        recovery.type_dependent = true;
        return false;
    }

    fn recoverAt(c: *Checker, mark: Mark, kind: Recovery.Kind) void {
        const recovery = c.probing.recovery orelse return;
        recovery.span = c.failure.span;
        recovery.repair = .{ .mark = mark, .kind = kind };
    }

    /// Record the certain `mut` → `own` repair when this refusal is a `mut`
    /// resource parameter that the callee stores or returns. A resource is
    /// move-only, so the copy repair is not available for it, and `mut` is an
    /// exclusive borrow (L16): the code that wanted to keep the value must spell
    /// `own`, and every call site then passes `own arg`. Every other borrowed
    /// value keeps the cheaper `copy(value)` repair.
    fn offerOwnParameter(c: *Checker, slot: usize) void {
        if (slot >= c.function.signature.parameter_count) return;
        const local = c.function.scope.locals[slot];
        if (!local.mutable or !resources.affine(c.program, local.ty)) return;
        c.failure.repair = .{ .own_parameter = local.declaration };
        c.failure.copy = .{};
        c.failure.message = "a `mut` parameter is an exclusive borrow, and this resource is stored or returned; " ++
            "a resource cannot be copied, so declare the parameter `own` and pass `own arg` at its call sites";
    }

    /// Copy repairs only an ownership transfer of a still-readable, copyable value.
    fn rejectCopy(c: *Checker, span: Span, ty: typed.Type, refusal: Refusal, message: []const u8) Error {
        const result = c.reject(span, refusal, message);
        if (span.start >= span.end or !c.owns(ty)) return result;
        for (c.function.scope.locals) |local| {
            if (local.origin != .local and local.origin != .parameter) continue;
            if (std.mem.startsWith(u8, local.name, "<")) continue;
            if (span.start == local.declaration.start and span.end == local.declaration.end) return result;
        }
        if (resources.affine(c.program, ty)) return result;
        c.failure.copy = .{ .span = span, .into_set = escape_message.fillsSet(c.sink) };
        return result;
    }

    /// Whether a slice type is one the escape rule covers: text, bytes and lists
    /// alike (D43). Every slice is a view of its source, so every store, return or
    /// invalidation of one needs the copy.
    fn slicesIntoOwning(c: *const Checker, ty: typed.Type) bool {
        if (!ty.isAggregate() or ty.recordIndex() >= c.program.records.len) return false;
        if (!c.owns(ty)) return false;
        return switch (c.program.records[ty.recordIndex()].collection.kind) {
            .string, .bytes, .list => true,
            else => false,
        };
    }

    /// A view of a local cannot escape. Declared parameter views were accepted
    /// by the ordinary borrowed-return validation before reaching this fallback.
    fn sliceReturn(c: *Checker, value: typed.NodeId) Error!void {
        const payload = c.returnedPayload(value);
        const span = c.listSliceSpan(payload) orelse c.callViewSpan(payload) orelse c.sliceSpan(payload) orelse return;
        const lender = c.viewSourceSlot(payload) orelse c.sliceRoot(payload) orelse c.origin(payload);
        return c.rejectCopy(span, c.program.nodes[@backingInt(payload)].ty, .{ .code = view_escape, .rule = .V4 }, try c.escapeMessageTo(span, lender, .returned, .copy, ""));
    }

    /// Returning a view of a declared parameter reads that parameter while any
    /// surrounding match still holds it; it never transfers the borrowed owner.
    fn partOfBorrowableParameter(c: *const Checker, slot: usize, root: usize) bool {
        if (!c.viewLike(slot)) return false;
        return std.mem.indexOfScalar(u16, return_borrow.sources(c.function.signature), std.math.cast(u16, root) orelse return false) != null;
    }

    /// Which collection families a slice lookup accepts: the escape rule covers
    /// text and lists today, a view binding also covers bytes.
    const SliceFamily = enum { text_or_list, any };

    fn sliceFamilyOk(c: *const Checker, ty: typed.Type, family: SliceFamily) bool {
        if (!ty.isAggregate() or ty.recordIndex() >= c.program.records.len) return false;
        if (!c.owns(ty)) return false;
        // Every slice is a view of its source, so the escape rule covers text,
        // bytes and list slices alike (D43).
        _ = family;
        const kind = c.program.records[ty.recordIndex()].collection.kind;
        return kind == .string or kind == .bytes or kind == .list;
    }

    /// The span of the slice a lowering temporary holds, when `slot` is such a
    /// temporary. The slice's own definition is recorded when its block is
    /// checked, which is before any move of the temporary.
    fn temporarySliceSpan(c: *Checker, slot: usize) ?Span {
        if (!c.temporary(slot)) return null;
        const definition = c.temporary_definitions.get(@intCast(slot)) orelse return null;
        return c.sliceSpan(definition) orelse c.listSliceSpan(definition);
    }

    /// The slice operation `id` stands for, following the temporaries the
    /// lowering wraps its endpoints in; null when it is not a covered slice.
    fn sliceNode(c: *const Checker, id: typed.NodeId, depth: usize) ?typed.Node {
        return c.sliceNodeFamily(id, depth, .text_or_list);
    }

    fn sliceNodeFamily(c: *const Checker, id: typed.NodeId, depth: usize, family: SliceFamily) ?typed.Node {
        if (depth > 8) return null;
        const node = c.program.nodes[@backingInt(id)];
        return switch (node.data) {
            .buffer_operation => if (node.view and c.sliceFamilyOk(node.ty, family)) node else null,
            .local => |slot| blk: {
                const binding = @backingInt(slot);
                if (binding >= c.state.len) break :blk null;
                // A lowering temporary and a named view binding both stand for
                // the slice expression they were initialized with, so a store or
                // return of either is the same escape (W3: one rule whether or
                // not the slice is bound).
                if (!c.sliceStandIn(binding)) break :blk null;
                const definition = c.temporary_definitions.get(@intCast(binding)) orelse
                    c.state[binding].view_definition.node orelse break :blk null;
                break :blk c.sliceNodeFamily(definition, depth + 1, family);
            },
            .block_value => |block| c.sliceNodeFamily(block.value, depth + 1, family),
            else => null,
        };
    }

    /// Whether a local stands for the slice expression it was initialized with:
    /// a lowering temporary, or a named view binding of either representation.
    fn sliceStandIn(c: *const Checker, binding: usize) bool {
        if (c.temporary(binding)) return true;
        if (c.sliceView(binding)) return true;
        return false;
    }

    /// The root local a checked list slice's copy loop borrows: the source
    /// binding that loop's block initializes first.
    fn listSliceSource(c: *Checker, id: typed.NodeId) ?usize {
        const node = c.program.nodes[@backingInt(id)];
        if (!node.view or node.data != .block_value) return null;
        const children = switch (c.program.statements[@backingInt(node.data.block_value.body)].data) {
            .block => |children| children,
            else => return null,
        };
        if (children.len < 5) return null;
        // The exact copy loop `collection_lower.Builder.slice` builds: the
        // source, the two clamped endpoints, a fresh buffer, then the loop. A
        // builtin that lowers to a block with a loop of its own (`sorted`) is not
        // a slice and must not be refused as one.
        const fourth = c.program.statements[@backingInt(children[3])].data;
        if (fourth != .initialize) return null;
        if (c.program.nodes[@backingInt(fourth.initialize.value)].data != .acquire_buffer) return null;
        if (c.program.statements[@backingInt(children[4])].data != .loop) return null;
        const source = switch (c.program.statements[@backingInt(children[0])].data) {
            .initialize => |initialize| initialize,
            else => return null,
        };
        const first = switch (c.program.statements[@backingInt(children[1])].data) {
            .initialize => |initialize| initialize,
            else => return null,
        };
        const last = switch (c.program.statements[@backingInt(children[2])].data) {
            .initialize => |initialize| initialize,
            else => return null,
        };
        _ = first;
        _ = last;
        return c.origin(source.value);
    }

    /// A slice expression is a view of its source (`s[a:b]`, `xs[a:b]`,
    /// `b[a:b]`), so moving it into owning storage would outlive that source.
    /// List slices join the rule so text, bytes and lists behave alike (X3).
    fn sliceEscape(c: *Checker, id: typed.NodeId) Error!void {
        if (c.callViewSpan(id)) |span| return c.rejectCopy(
            span,
            c.program.nodes[@backingInt(id)].ty,
            .{ .code = view_escape, .rule = .V2 },
            try c.escapeMessage(span, c.sliceLender(id), .copy, ""),
        );
        const span = c.sliceSpan(id) orelse c.listSliceSpan(id) orelse return;
        return c.rejectCopy(span, c.program.nodes[@backingInt(id)].ty, .{ .code = view_escape, .rule = .V2 }, try c.escapeMessage(span, c.sliceLender(id), .copy, ""));
    }

    /// Rule C (C1): an owned local is an independent value, so a slice or a view
    /// binding stored into one is a copy that the source never writes. Every
    /// such store is refused, and its certain repair writes `copy(...)` around
    /// the view. Compiler temporaries keep their own borrows (`checkStore`).
    fn ownedViewStore(c: *Checker, slot: usize, value: typed.NodeId) Error!void {
        c.checkOwnedViewStore(slot, value) catch |err| {
            if (err == error.Rejected) {
                c.noteSliceCopy(slot, value);
                try c.borrowedMarkerRepair(value);
            }
            return err;
        };
    }

    fn checkOwnedViewStore(c: *Checker, slot: usize, value: typed.NodeId) Error!void {
        const local = c.function.scope.locals[slot];
        if (!c.owns(local.ty) or c.temporary(slot)) return;
        const destination: escape_message.Destination = .{ .binding = .{ .name = local.name, .mutable = local.mutable } };
        const ty = c.program.nodes[@backingInt(value)].ty;
        if (c.callViewSpan(value)) |span| {
            const message = try c.escapeMessageTo(span, c.viewSourceSlot(value) orelse c.origin(value), destination, .copy, "");
            return c.rejectCopy(span, ty, .{ .code = view_escape, .rule = .V2 }, message);
        }
        const span = c.viewSpan(value) orelse return;
        const lender = c.sliceLender(value);
        const message = try c.escapeMessageTo(span, lender, destination, .copy, if (c.program.nodes[@backingInt(value)].data == .local) c.localName(value) else "");
        return c.rejectCopy(span, ty, .{ .code = view_escape, .rule = .V2 }, message);
    }

    /// What an owned local of this type holds, for a message: its text, its
    /// bytes or its list.
    fn ownedNoun(c: *const Checker, ty: typed.Type) []const u8 {
        if (!ty.isAggregate() or ty.recordIndex() >= c.program.records.len) return "value";
        return switch (c.program.records[ty.recordIndex()].collection.kind) {
            .string => "text",
            .bytes => "bytes",
            .list => "list",
            else => "value",
        };
    }

    /// A signature-declared view call stored as an owner would copy a view
    /// the source never writes. Null for ordinary owned calls.
    fn callViewSpan(c: *const Checker, id: typed.NodeId) ?Span {
        if (c.callViewCallee(id) == null and !c.trimView(id, 0)) return null;
        return c.program.nodes[@backingInt(id)].span;
    }

    /// Whether a value is the text trim `strings.strip(text)`, `lstrip` or `rstrip` lowers to, through the blocks its
    /// operands' temporaries wrap it in: a view of its text exactly as the declared `-> str from text` says, so it is
    /// kept out of owning storage as a call with that contract is (W13, slice 3: the trims became `builtin func`
    /// homes, and their call is the operation, no longer a call of a function with a `from` contract).
    fn trimView(c: *const Checker, id: typed.NodeId, depth: usize) bool {
        if (depth > 8) return false;
        return switch (c.program.nodes[@backingInt(id)].data) {
            .buffer_operation => |operation| c.textTrimBorrow(operation),
            .block_value => |block| c.trimView(block.value, depth + 1),
            else => false,
        };
    }

    /// The name of the function a view-returning call calls, or null when `id` is
    /// not such a call.
    fn callViewCallee(c: *const Checker, id: typed.NodeId) ?[]const u8 {
        const node = c.program.nodes[@backingInt(id)];
        if (node.data != .call) return null;
        const call = node.data.call;
        if (@backingInt(call.function) >= c.program.functions.len) return null;
        const function = c.program.functions[@backingInt(call.function)];
        const kind = return_borrow.shape(c.program.records, function.signature).kind;
        if (kind != .text and kind != .bytes and kind != .list) return null;
        return function.name;
    }

    /// The span a view names in the source: a slice expression, a list slice, or
    /// the use of a named view binding. Null when the value is not a view.
    fn viewSpan(c: *Checker, value: typed.NodeId) ?Span {
        const node = c.program.nodes[@backingInt(value)];
        if (node.data == .local) return if (c.viewDefinition(value) != value) node.span else null;
        return c.sliceSpan(value) orelse c.listSliceSpan(value);
    }

    /// The slice expression a named view binding stands for, or the value itself.
    fn viewDefinition(c: *const Checker, value: typed.NodeId) typed.NodeId {
        const node = c.program.nodes[@backingInt(value)];
        if (node.data != .local) return value;
        const binding = @backingInt(node.data.local);
        if (binding >= c.state.len or !c.sliceView(binding)) return value;
        return c.state[binding].view_definition.node orelse value;
    }

    /// The name of the local a view borrows, for a message; empty when the source
    /// is a compiler temporary, which has no name to show.
    fn viewSourceName(c: *Checker, value: typed.NodeId) []const u8 {
        const slot = c.viewSourceSlot(value) orelse return "";
        return c.function.scope.locals[slot].name;
    }

    /// Who lends the view `value` stands for, for a message: the hidden owner of a fresh record the slice's field is read from,
    /// else the named local the view borrows, else its root or origin.
    fn sliceLender(c: *Checker, value: typed.NodeId) ?usize {
        return c.freshRecordOf(value) orelse c.viewSourceSlot(value) orelse c.sliceRoot(value) orelse c.origin(value);
    }

    /// The hidden owner of a fresh record that the slice expression `value` is wrapped around (`Name(...).text[0:2]`): a
    /// temporary the block of the slice initializes with a record, or null.
    fn freshRecordOf(c: *const Checker, value: typed.NodeId) ?usize {
        var current = value;
        for (0..16) |_| {
            const node = c.program.nodes[@backingInt(current)];
            if (node.data != .block_value) return null;
            const body = c.program.statements[@backingInt(node.data.block_value.body)];
            if (body.data == .block) for (body.data.block) |child| {
                const statement = c.program.statements[@backingInt(child)];
                if (statement.data != .initialize) continue;
                const slot = @backingInt(statement.data.initialize.slot);
                if (c.hiddenRecord(slot)) return slot;
            };
            current = node.data.block_value.value;
        }
        return null;
    }

    /// The named local a view's source is, through the temporaries the lowering wraps it in; null when the source has no name.
    fn viewSourceSlot(c: *Checker, value: typed.NodeId) ?usize {
        const definition = c.viewDefinition(value);
        const owner: ?usize = c.listSliceSource(definition) orelse if (c.sliceNode(definition, 0)) |slice| @backingInt(slice.data.buffer_operation.owner) else null;
        const found = owner orelse return null;
        if (found >= c.state.len) return null;
        const slot = c.rootOf(found);
        if (slot >= c.function.scope.locals.len) return null;
        if (std.mem.startsWith(u8, c.function.scope.locals[slot].name, "<")) return null;
        return slot;
    }

    /// The name of the local a value reads, or of a view binding's use.
    fn localName(c: *const Checker, value: typed.NodeId) []const u8 {
        const node = c.program.nodes[@backingInt(value)];
        if (node.data != .local) return "";
        const binding = @backingInt(node.data.local);
        if (binding >= c.function.scope.locals.len) return "";
        return c.function.scope.locals[binding].name;
    }

    /// The value a return hands back once a `Some` or a success wrapper is looked
    /// through: the view a copy of a returned slice has to wrap.
    fn returnedPayload(c: *const Checker, id: typed.NodeId) typed.NodeId {
        var current = id;
        var remaining = c.program.nodes.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            const node = c.program.nodes[@backingInt(current)];
            switch (node.data) {
                .variant => |variant| {
                    const step = return_borrow.step(c.program.records, node.ty) orelse return current;
                    if (variant.tag != step.tag) return current;
                    current = variant.value orelse return current;
                },
                .wrap => |value| current = value,
                else => return current,
            }
        }
        return current;
    }

    /// Empty option and failure alternatives own no borrowed success payload.
    fn neutralWrapper(c: *const Checker, id: typed.NodeId) bool {
        var current = id;
        var remaining = c.program.nodes.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            const node = c.program.nodes[@backingInt(current)];
            if (node.data != .variant) return false;
            const variant = node.data.variant;
            const step = return_borrow.step(c.program.records, node.ty) orelse return false;
            if (variant.tag != step.tag or variant.value == null) return true;
            current = variant.value.?;
        }
        return false;
    }

    /// The span of a checked list slice, recognized by the copy loop its block
    /// lowers to; null when `id` is not one. A named view binding stands for the
    /// slice it was initialized with, so a store, append, element store or
    /// return of the binding is the same escape as the inline slice's (B1).
    fn listSliceSpan(c: *Checker, id: typed.NodeId) ?Span {
        if (c.listSliceSource(id) != null) return c.program.nodes[@backingInt(id)].span;
        const node = c.program.nodes[@backingInt(id)];
        if (node.data != .local) return null;
        const binding = @backingInt(node.data.local);
        if (binding >= c.state.len or !c.sliceView(binding)) return null;
        const definition = c.state[binding].view_definition.node orelse return null;
        if (c.listSliceSource(definition) == null) return null;
        return c.program.nodes[@backingInt(definition)].span;
    }

    /// The span of the slice expression `id` is, or of the value the temporary
    /// it names was initialized with; null when `id` is not a slice. The
    /// lowering wraps a slice in endpoints' temporaries, so those are followed.
    fn sliceSpan(c: *const Checker, id: typed.NodeId) ?Span {
        const node = c.sliceNode(id, 0) orelse return null;
        return node.span;
    }

    /// Generated aliases may carry a statement span rather than source expression.
    fn rejectLocalCopy(c: *Checker, slot: usize, span: Span, refusal: Refusal, message: []const u8) Error {
        const local = c.function.scope.locals[slot];
        const result = c.rejectCopy(span, local.ty, refusal, message);
        // A move spelled `own name` names the local at the span's end: the repair wraps that name (`own copy(name)`).
        if (std.mem.startsWith(u8, local.name, "<")) {
            c.failure.copy.span = null;
        } else if (span.end - span.start != local.name.len) {
            const name_length: u32 = @intCast(local.name.len);
            c.failure.copy.span = if (span.end - span.start > name_length) .{ .start = span.end - name_length, .end = span.end } else null;
        }
        c.failure.copy.name = local.name;
        return result;
    }

    fn owns(c: *const Checker, ty: typed.Type) bool {
        return isOwned(c.linear, ty);
    }

    /// File owners stay in named scopes, including when a callback or generic type would contain one. The walk is
    /// memoized across the check (`single_owner_files.zig`); a refusal names `span`.
    fn supportedFiles(c: *Checker, ty: typed.Type, span: Span) Error!void {
        c.files.supported(c.program.records, ty) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.StoredFile => return c.reject(span, .{ .code = "E_WITH_RESOURCE", .rule = .P4 }, file_held),
        };
    }

    /// The tables a probe's re-check reads. The stored-file marks describe one program's records, so only a probe over the same records
    /// (the repairs change nodes and locals, never records) shares them.
    fn probeShared(c: *const Checker, program: typed.Program) Shared {
        const same = program.records.ptr == c.program.records.ptr and program.records.len == c.program.records.len;
        return .{
            .program = program,
            .linear = c.linear,
            .source = c.source,
            .files = if (same) c.files else null,
            .plain_mut = c.plain_mut,
            .plain_records = c.plain_records,
            .case_payloads = if (same) c.case_payloads else &.{},
            .copy_claim = c.copy_claim,
            .scratch = c.scratch,
        };
    }

    fn tracked(c: *const Checker, ty: typed.Type) bool {
        return c.owns(ty);
    }

    /// Whether binding `slot` holds a view of another local's text (wave 3's
    /// `const piece = text[a:b]`). The binding's own type is `str`; the view is
    /// its representation.
    fn sliceView(c: *const Checker, slot: usize) bool {
        return slot < c.function.scope.locals.len and c.function.scope.locals[slot].ownership.view;
    }

    /// Whether `slot` is a view for lifetime purposes, of either representation.
    fn viewLike(c: *const Checker, slot: usize) bool {
        return c.sliceView(slot);
    }

    /// Make the views of `root` unreadable, and record the change at `span` (a move or a write, by `access`) that did it, for the
    /// message of the refusal at their next read.
    fn invalidateViews(c: *Checker, root: usize, span: Span, access: Access) void {
        for (c.state, 0..) |*state, slot| {
            if (slot != root and state.available and c.viewLike(slot) and c.rootOf(slot) == root) {
                state.available = false;
                state.view_rule = .V3;
                state.view_definition.invalidated = .{ .span = span, .access = access };
            }
        }
    }

    fn rootOf(c: *const Checker, slot: usize) usize {
        var result = slot;
        var remaining = c.state.len;
        while (c.state[result].root != none and remaining != 0) : (remaining -= 1) result = c.state[result].root;
        return result;
    }

    /// Whether a move of `slot` is the escape the rule refuses: a view binding
    /// that is not being returned (the declared borrow sources judge that) and is not
    /// re-binding an owned local (which copies).
    fn sliceMoveRefused(c: *const Checker, slot: usize) bool {
        if (!c.sliceView(slot)) return false;
        if (c.returning) return false;
        return !c.local_store;
    }

    /// Refuse a change to `root` while a slice view of it is held: the view is
    /// the value that cannot survive the change, so it names itself and offers
    /// its copy. A view whose last read already happened is not held, so it does
    /// not block the change (REGRESSION-R4).
    fn escapeLiveView(c: *Checker, root: usize, span: Span, access: Access) Error!void {
        if (c.sourceView(root, false)) |slot| {
            const generic = "this slice view was invalidated by a change to its source; bind a copy with copy(value)";
            const message = (try c.invalidatedMessage(slot, .{ .span = span, .access = access }, null)) orelse generic;
            return c.rejectSliceView(slot, span, .{ .code = view_escape, .rule = .V3 }, message);
        }
    }

    /// The message of a view that a change to its source made unreadable (FR57): the view and its slice, the line and column of the
    /// write or move that changed the lender, the read that is refused (`read`; null where a loan found the view live at the change),
    /// and the repairs that copy nothing before the copy. Null where the check has no source text or no name for the view, the
    /// lender or the change, and the site keeps its words. The reorder is offered when the change lies between the binding and the
    /// read in the source; the span when the change is a write, not a move, and the slice names an owner directly (a local or a
    /// parameter that borrows from no other, with the slice spelled from its name: a loop element or an alias is not).
    fn invalidatedMessage(c: *Checker, slot: usize, change: Invalidation, read: ?Span) Error!?[]const u8 {
        const src = c.source orelse return null;
        const local = c.function.scope.locals[slot];
        const definition = c.state[slot].view_definition.node orelse return null;
        const bound = c.program.nodes[@backingInt(definition)].span;
        const written = change.span;
        if (std.mem.startsWith(u8, local.name, "<") or pattern_message.hidden(local.name)) return null;
        if (written.start >= written.end or written.end > src.bytes.len or bound.start >= bound.end or bound.end > src.bytes.len) return null;
        const root = c.rootOf(slot);
        const lender = c.lenderOf(root);
        if (lender.name() == null) return null;
        const at = src.locate(written.start);
        const read_at: ?escape_message.Place = if (read) |use| blk: {
            const found = src.locate(use.start);
            break :blk .{ .line = found.line, .column = found.column };
        } else null;
        const root_origin = c.function.scope.locals[root].origin;
        const owner = c.state[slot].root == root and (root_origin == .local or root_origin == .parameter) and
            escape_message.startsWithName(src.text(bound), lender.name().?);
        const write = change.access != .move;
        const message = try escape_message.composeInvalidated(c.diagnostics.allocator, .{
            .view = local.name,
            .slice = src.text(bound),
            .lender = lender,
            .change = .{ .kind = if (write) .write else .move, .text = src.text(written), .at = .{ .line = at.line, .column = at.column } },
            .read = read_at,
            .reorder = bound.end <= written.start and (if (read) |use| written.end <= use.start else true),
            .respan = write and owner,
        });
        return message;
    }

    /// A view of this owner, including invalidated definitions when judging a repair.
    fn sourceView(c: *const Checker, root: usize, include_invalidated: bool) ?usize {
        var slot: usize = 0;
        while (slot < c.state.len) : (slot += 1) {
            if (!include_invalidated and !c.state[slot].available) continue;
            if (!c.sliceView(slot)) continue;
            if (include_invalidated and c.state[slot].view_definition.node == null) continue;
            if (c.rootOf(slot) != root) continue;
            return slot;
        }
        return null;
    }

    /// Refuse a store or return of a named view binding, with the copy repair on
    /// the binding's own slice expression.
    fn rejectSliceView(c: *Checker, slot: usize, span: Span, refusal: Refusal, message: []const u8) Error {
        const definition = c.state[slot].view_definition.node orelse return c.reject(span, refusal, message);
        return c.rejectCopy(c.program.nodes[@backingInt(definition)].span, c.function.scope.locals[slot].ty, refusal, message);
    }

    /// The Escape message of a view binding that two branches assigned different sources (V5): lent by both, so after the join
    /// no one source covers it. `generic` stands when the join did not record its sources.
    fn joinedViewMessage(c: *Checker, slot: usize, span: Span, generic: []const u8) Error![]const u8 {
        const found = c.joined.get(@intCast(slot)) orelse return generic;
        const local = c.function.scope.locals[slot];
        const destination: escape_message.Destination = .{ .binding = .{ .name = local.name, .mutable = local.mutable } };
        return c.escapeMessageAmong(span, .{ found[0], found[1] }, destination, .each_branch, local.name);
    }

    /// Report a binding whose value is gone: an invalidated view of either
    /// representation, or a moved owner.
    fn rejectUnavailable(c: *Checker, slot: usize, span: Span) Error {
        const local = c.function.scope.locals[slot];
        if (c.sliceView(slot)) {
            const refusal = sliceRefusal(c.state[slot].view_rule);
            const generic = "this slice view was invalidated by a move, mutation, replacement or branch of its source; bind a copy with copy(value) when the source changes";
            const message = if (refusal.rule == .V5)
                try c.joinedViewMessage(slot, span, generic)
            else if (c.state[slot].view_definition.invalidated) |change|
                (try c.invalidatedMessage(slot, change, span)) orelse generic
            else
                generic;
            if (c.state[slot].view_definition.node) |definition| return c.rejectCopy(c.program.nodes[@backingInt(definition)].span, local.ty, refusal, message);
            return c.reject(span, refusal, message);
        }
        const fallback = "the value is unavailable on this path; use copy(value) when both values are needed";
        const format = "'{s}' was moved or is unavailable on this path; use copy(value) when both values are needed";
        const message = std.fmt.allocPrint(c.diagnostics.allocator, format, .{local.name}) catch return c.reject(span, .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 }, fallback);
        const moved = c.state[slot].moved_span;
        const result = c.reject(span, .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 }, message);
        if (moved.start < moved.end) {
            c.failure.notes.related = .{ .span = moved, .message = std.fmt.allocPrint(c.diagnostics.allocator, "'{s}' is moved here", .{local.name}) catch "" };
            // FR91: a read in the statement whose group of moves consumed the record is repaired as a second move would be
            // (FR63's `take` of each move), so the refusal names a move of the group, not the read.
            const group = if (c.state[slot].traits.field_opened) c.field_moves.otherMove(c.program, slot, moved) else null;
            if (!try c.readBeforeMove(slot, moved, span) and !try c.takeFieldsRepair(slot, moved, group orelse span, group != null))
                try c.readAfterFieldMove(slot, moved, span, group != null);
        }
        return result;
    }

    /// Successful named moves are the migration sites; compiler temporaries are excluded.
    fn observeMove(c: *Checker, slot: usize, span: Span) error{OutOfMemory}!void {
        const observer = c.diagnostics.observer orelse return;
        if (!c.namedBinding(slot)) {
            const state = c.state[slot];
            const root = c.rootOf(slot);
            if (!state.traits.borrowed or !state.traits.transferable) return;
            if (root == slot or !c.namedBinding(root)) return;
            const definition = state.view_definition.node orelse return;
            return c.observeMove(root, c.observedBindingSpan(definition) orelse return);
        }
        const local = c.function.scope.locals[slot];
        const kind = observer.moveKind(span);
        try observer.record(kind, span, .{ .name = local.name, .function = c.function.name, .explicit_own = observer.spellsOwn(span) });
        if (local.mutable or slot < c.function.signature.parameter_count) return;
        const definition = c.definitions.get(@intCast(slot)) orelse return;
        const node = c.program.nodes[@backingInt(Observer.sourceValue(c.program, definition))];
        if (node.data != .local or observer.spellsOwn(node.span)) return;
        const source_slot = @backingInt(node.data.local);
        if (!c.namedBinding(source_slot)) return;
        if (source_slot < c.function.signature.parameter_count) {
            const own = c.function.scope.own_parameters;
            if (source_slot >= own.len or !own[source_slot]) return;
        }
        try observer.record("const_own", local.declaration, .{ .name = local.name, .source = c.function.scope.locals[source_slot].name });
    }

    // Pattern payloads can own a fresh match result even though the lifetime checker
    // treats their bindings like temporary aliases. They remain source migration sites.
    fn namedBinding(c: *const Checker, slot: usize) bool {
        return namedLocal(c.function.scope.locals[slot]);
    }

    // A staged operand may be a transferable alias. Name the source binding the
    // final move consumes rather than the lowering's hidden alias declaration.
    fn observedBindingSpan(c: *const Checker, value: typed.NodeId) ?Span {
        var current = value;
        var remaining = c.program.nodes.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            current = Observer.sourceValue(c.program, current);
            const node = c.program.nodes[@backingInt(current)];
            switch (node.data) {
                .field => |field| current = field.base,
                .local => |id| {
                    const slot = @backingInt(id);
                    if (c.namedBinding(slot)) return node.span;
                    current = c.state[slot].view_definition.node orelse c.definitions.get(@intCast(slot)) orelse return null;
                },
                else => return null,
            }
        }
        return null;
    }

    // Contracts stage their returned expression in a hidden local. Recover the
    // original expression so a field projection stays distinct from a bare return.
    fn observedReturnBinding(c: *const Checker, value: typed.NodeId) @FieldType(Observer, "returned") {
        const observer = c.diagnostics.observer orelse return null;
        var current = value;
        var remaining = c.program.nodes.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            current = observer.returnedValue(c.program, current);
            const node = c.program.nodes[@backingInt(current)];
            if (node.data != .local) return observer.returnedBinding(c.program, current);
            const slot = @backingInt(node.data.local);
            if (c.namedBinding(slot)) return observer.returnedBinding(c.program, current);
            current = c.state[slot].view_definition.node orelse c.definitions.get(@intCast(slot)) orelse return null;
        }
        return null;
    }

    fn checkLocal(c: *Checker, slot: usize, access: Access, span: Span) Error!void {
        const local = c.function.scope.locals[slot];
        if (!c.tracked(local.ty)) {
            if (access != .read) try c.checkHeldOwnerWrite(slot, null, span);
            return;
        }
        if (access == .move and c.isExclusiveBinder(slot)) return c.reject(
            span,
            .{ .code = borrow_error, .rule = .X2 },
            "a payload binding of `match mut` is written back into the matched place, so it cannot be moved or stored; store copy(value) instead",
        );
        const root = c.rootOf(slot);
        if (!c.state[slot].available or !c.state[root].available) return c.rejectUnavailable(slot, span);
        // A borrowed collection (RB2) takes element stores only: no other change, no move.
        if (c.collections) |held| if (access != .read and !held.storing and held.table.collectionOf(slot) != null) {
            const held_roots = held.roots[slot].items;
            const lenders: [2]?usize = .{ if (held_roots.len > 0) held_roots[0] else null, if (held_roots.len > 1) held_roots[1] else null };
            const result = c.reject(span, .{ .code = borrow_error, .rule = .B9 }, try c.escapeMessageAmong(span, lenders, c.sink, .fields, local.name));
            c.noteCollectionCause(held.table.collectionOf(slot).?);
            return result;
        };
        if (access == .move and local.ownership.scoped_file) return c.reject(span, .{ .code = "E_WITH_RESOURCE", .rule = .P4 }, file_given_away);
        if (c.state[slot].traits.ambiguous_borrow and access != .read) {
            if (access == .move) return c.rejectLocalCopy(slot, span, .{ .code = borrow_error, .rule = .R6 }, try c.escapeMessageAmong(span, try c.lendersOf(slot), c.sink, .copy, local.name));
            return c.reject(span, .{ .code = borrow_error, .rule = .R6 }, "a borrowed selection is read-only; make an explicit copy(value) before changing it");
        }
        const write = access != .read;
        // A `mut` local stored once from a place borrows it (D4): a write through it is the refusal, at the write.
        if (access == .mutate or access == .update) if (c.borrowedMutOwner(slot)) |holder| {
            if (try c.borrowedOnce(holder)) return c.rejectBorrowedWrite(holder, span);
        };
        // Moving a `const` borrow leaves its owner alone: the move is refused as a borrowed store below. The put-back a
        // `detach` loop generates before an exit ends the loop's loans on its collection (`detachExit`).
        if (!(access == .move and std.mem.startsWith(u8, local.name, typed.detach_owner) and try c.detachExit(slot)))
            try c.checkLoans(slot, root, write and !c.movesConstBorrow(slot, access), access, span);
        if (access == .move) {
            // A view binding is readable, never movable: storing it would outlive
            // its source. The repair copies at the binding, so the value is the
            // request the inline slice's repair makes (W3). A return is judged by
            // the declared borrow sources instead, with `sliceReturn` checking escapes.
            if (c.sliceMoveRefused(slot)) return c.rejectSliceView(slot, span, .{ .code = view_escape, .rule = .V2 }, try c.escapeMessage(span, c.rootOf(slot), .copy, local.name));
            if (c.state[slot].traits.borrowed) {
                // A lowering temporary that holds a slice is the view itself, so
                // moving it into owning storage is the slice escape and carries
                // the copy repair, not the generic borrowed-value advice.
                if (c.temporarySliceSpan(slot)) |slice| return c.rejectCopy(slice, local.ty, .{ .code = view_escape, .rule = .V2 }, try c.escapeMessage(slice, c.rootOf(slot), .copy, local.name));
                if (!c.state[slot].traits.transferable or c.state[root].traits.borrowed) {
                    if (c.state[slot].traits.rule == .B9) return c.rejectConstEscape(slot, span, access);
                    const refusal = c.rejectLocalCopy(slot, span, .{ .code = borrow_error, .rule = c.state[slot].traits.rule }, try c.borrowedStoreMessage(slot, span));
                    c.offerOwnParameter(slot);
                    try c.narrowedOwnRepair(slot, span);
                    return refusal;
                }
                c.state[root].available = false;
            }
            try c.observeMove(slot, span);
            c.invalidateViews(root, span, .move);
            c.state[slot].available = false;
            c.state[slot].traits.field_opened = false;
            c.state[slot].moved_span = span;
            c.state[root].moved_span = span;
        } else if (access == .mutate or access == .update) {
            if (c.state[slot].traits.borrowed and c.state[slot].traits.rule == .B9) return c.rejectConstEscape(slot, span, access);
            // A `with`-bound resource is lent whole to a `mut` argument (an exclusive borrow); a field or element of it is not a case.
            const scoped = c.state[slot].traits.scoped_resource and root == slot;
            const writable = c.state[slot].traits.writable or c.exclusiveAccess(slot) or scoped;
            const root_writable = scoped or c.state[root].traits.writable;
            if (!writable or !root_writable) return c.reject(span, .{ .code = borrow_error, .rule = .M4 }, "mutation requires an exclusive mut parameter or a mutable owning local");
            c.invalidateViews(root, span, access);
        }
    }

    /// The argument a call's result borrows, when the callee returns a view of
    /// one of its parameters.
    fn callViewSource(c: *const Checker, call: anytype) ?usize {
        const index = @backingInt(call.function);
        if (index >= c.program.functions.len) return null;
        const positions = return_borrow.effectiveSources(c.program.records, c.program.functions[index].signature);
        if (positions.len != 1) return null;
        const position = positions[0];
        if (position >= call.arguments.len) return null;
        return @intCast(position);
    }

    /// The argument a node's view-returning call borrows, when `id` is such a call.
    fn viewCallSource(c: *const Checker, id: typed.NodeId) ?typed.NodeId {
        const node = c.program.nodes[@backingInt(id)];
        if (node.data != .call) return null;
        const position = c.callViewSource(node.data.call) orelse return null;
        return node.data.call.arguments[position];
    }

    fn origin(c: *Checker, id: typed.NodeId) ?usize {
        const node = c.program.nodes[@backingInt(id)];
        return switch (node.data) {
            .local => |slot| c.rootOf(@backingInt(slot)),
            .field => |field| c.origin(field.base),
            .variant => null,
            .record => |fields| if (c.borrowedItem(fields)) |owner| c.rootOf(@backingInt(owner)) else null,
            .index => |index| if (c.freshCharacter(index.base)) null else c.origin(index.base),
            .cast => |value| if (c.program.nodes[@backingInt(value)].ty != node.ty) null else c.origin(value),
            .wrap, .unwrap => |value| c.origin(value),
            .block_value => |block| c.origin(block.value),
            .buffer_operation => |operation| switch (operation.kind) {
                .read => if (c.program.records[c.function.scope.locals[@backingInt(operation.owner)].ty.recordIndex()].collection.kind == .string) null else c.rootOf(@backingInt(operation.owner)),
                .get, .key_at, .value_at, .setdefault, .borrow_view => c.rootOf(@backingInt(operation.owner)),
                .slice, .slice_bytes, .text_tail => if (node.view and c.slicesIntoOwning(node.ty)) c.rootOf(@backingInt(operation.owner)) else null,
                .strip, .lstrip, .rstrip => if (c.textTrimBorrow(operation)) c.rootOf(@backingInt(operation.owner)) else null,
                else => null,
            },
            .call => |call| blk: {
                // A call whose result is a view of one argument borrows that
                // argument exactly as a slice does (X1, DECISIONS F6).
                if (c.callViewSource(call)) |position| break :blk c.origin(call.arguments[position]);
                break :blk null;
            },
            else => null,
        };
    }

    /// Only the exact projection reconstructed by its parent may write in place.
    fn sameFieldWriteback(c: *const Checker, base: typed.NodeId, field: typed.FieldInit) bool {
        const nested = c.program.nodes[@backingInt(field.value)];
        const nested_base = switch (nested.data) {
            .update => |update| update.base,
            .replace => |replace| replace.base,
            else => return false,
        };
        return switch (c.program.nodes[@backingInt(nested_base)].data) {
            .field => |projection| projection.base == base and projection.index == field.index,
            else => false,
        };
    }

    fn freshCharacter(c: *const Checker, base: typed.NodeId) bool {
        const ty = c.program.nodes[@backingInt(base)].ty;
        return ty.isAggregate() and c.program.records[ty.recordIndex()].collection.kind == .string;
    }

    /// A dictionary default can borrow either the dictionary or its fallback.
    /// Receiver temporaries may read/copy it, but cannot anchor a stored view.
    fn ambiguousBorrow(c: *const Checker, id: typed.NodeId) bool {
        return switch (c.program.nodes[@backingInt(id)].data) {
            .local => |slot| c.state[@backingInt(slot)].traits.ambiguous_borrow,
            .borrow_selection => true,
            .field => |field| c.ambiguousBorrow(field.base),
            .index => |index| c.ambiguousBorrow(index.base),
            .wrap, .unwrap, .cast => |value| c.ambiguousBorrow(value),
            .block_value => |block| c.ambiguousBorrow(block.value),
            .buffer_operation => |operation| switch (operation.kind) {
                .get => true,
                .read, .key_at, .value_at, .borrow_view, .slice => c.state[@backingInt(operation.owner)].traits.ambiguous_borrow,
                else => false,
            },
            else => false,
        };
    }

    /// Preserve all possible roots of a generated default-selection receiver.
    /// Only provenance edges are visited; ordinary calls produce independent owners.
    fn loanExpression(c: *Checker, id: typed.NodeId, write: bool) Error!void {
        if (!c.ambiguousBorrow(id)) {
            const node = c.program.nodes[@backingInt(id)];
            // A borrowed record (1A) holds the loans of each of its borrowed fields.
            if (node.data == .record and try c.borrowedRecord(id)) {
                for (node.data.record) |field| if (c.owns(c.program.nodes[@backingInt(field.value)].ty) and !staticText(c.program, field.value))
                    try c.loanExpression(field.value, write);
                return;
            }
            if (node.data == .local and c.state[@backingInt(node.data.local)].traits.borrowed) {
                const roots = try c.localRoots(@backingInt(node.data.local), 0);
                for (roots.items) |root| try c.loans.append(c.a, .{ .root = root, .write = write });
                return;
            }
            if (c.origin(id)) |root| try c.loans.append(c.a, .{ .root = root, .write = write });
            // A borrowed call result holds read loans on each of its owners (R3b).
            if (try c.borrowedCallRoots(id, 0)) |roots| for (roots.slice()) |root| try c.loans.append(c.a, .{ .root = root, .write = write });
            return;
        }
        var pending: std.ArrayList(typed.NodeId) = .empty;
        var seen: std.AutoHashMapUnmanaged(typed.NodeId, void) = .empty;
        try pending.append(c.a, id);
        while (pending.pop()) |current| {
            const visited = try seen.getOrPut(c.a, current);
            if (visited.found_existing) continue;
            if (c.origin(current)) |root| try c.loans.append(c.a, .{ .root = root, .write = write });
            try c.borrowParents(current, &pending);
        }
    }

    fn borrowLocal(c: *Checker, slot: usize, pending: *std.ArrayList(typed.NodeId)) Error!void {
        const state = c.state[slot];
        if (!state.traits.ambiguous_borrow) return;
        if (state.view_definition.node) |definition| try pending.append(c.a, definition);
    }

    fn borrowParents(c: *Checker, id: typed.NodeId, pending: *std.ArrayList(typed.NodeId)) Error!void {
        switch (c.program.nodes[@backingInt(id)].data) {
            .local => |slot| try c.borrowLocal(@backingInt(slot), pending),
            .field => |field| try pending.append(c.a, field.base),
            .index => |index| try pending.append(c.a, index.base),
            .wrap, .unwrap, .cast => |value| try pending.append(c.a, value),
            .block_value => |block| try pending.append(c.a, block.value),
            .borrow_selection => |selection| {
                try pending.append(c.a, selection.first);
                try pending.append(c.a, selection.second);
            },
            .buffer_operation => |operation| {
                try c.borrowLocal(@backingInt(operation.owner), pending);
                if (operation.kind == .get and operation.arguments.len == 2)
                    try pending.append(c.a, operation.arguments[1]);
            },
            else => {},
        }
    }

    fn loanReceiver(c: *Checker, slot: usize, span: Span) Error!void {
        const first = c.loans.items.len;
        // The loan names the receiver's place, so an operand that writes a disjoint field of the same owner passes it
        // (`append(mut e.stack, exchange(mut e.block, B()))`); the lowering reads the receiver's place again after it.
        try c.loans.append(c.a, .{ .root = c.rootOf(slot), .write = false, .path = try c.capturedReceiverPath(slot) });
        if (c.state[slot].traits.ambiguous_borrow) {
            if (c.state[slot].view_definition.node) |definition| try c.loanExpression(definition, false);
        }
        for (c.loans.items[first..]) |*loan| loan.hold = .{ .receiver = span };
    }

    /// An element update can read only the exact element being rebuilt. Keep
    /// the containing operation's loan active for all replacement operands.
    fn sameIndexWriteback(c: *const Checker, base: typed.NodeId, index: typed.NodeId, value: typed.NodeId) bool {
        const nested_base = switch (c.program.nodes[@backingInt(value)].data) {
            .update => |update| update.base,
            .replace => |replace| replace.base,
            else => return false,
        };
        return switch (c.program.nodes[@backingInt(nested_base)].data) {
            .index => |projection| projection.base == base and projection.index == index,
            else => false,
        };
    }

    /// The front end's field destination captures a slot in a synthetic local
    /// and later writes the rebuilt value to that same collection and key.
    /// Ordinary extracted values and unrelated keys cannot take this path.
    fn sameSlotWriteback(c: *const Checker, owner: typed.LocalId, index: typed.NodeId, value: typed.NodeId) bool {
        const slot = @backingInt(slotWritebackLocal(c.program, c.function, value) orelse return false);
        const definition = if (c.owns(c.function.scope.locals[slot].ty)) managed: {
            if (!c.state[slot].traits.borrowed) return false;
            break :managed c.state[slot].view_definition.node orelse return false;
        } else c.temporary_definitions.get(@intCast(slot)) orelse return false;
        return switch (c.program.nodes[@backingInt(definition)].data) {
            .buffer_operation => |read| read.kind == .read and read.owner == owner and read.arguments.len == 1 and read.arguments[0] == index,
            else => false,
        };
    }

    fn wholeOwner(c: *const Checker, id: typed.NodeId) bool {
        return switch (c.program.nodes[@backingInt(id)].data) {
            .local => |slot| c.state[@backingInt(slot)].root == none or c.state[@backingInt(slot)].traits.transferable,
            .block_value => |block| c.wholeOwner(block.value),
            else => false,
        };
    }

    /// The innermost block being checked: its statements and the index of the statement now checked. A `const`
    /// binding's borrow ends at the last statement of this block that reads it (B7).
    const BlockContext = struct { items: []const typed.StatementId, index: usize = 0, id: typed.StatementId, span: Span, parent: ?*const BlockContext = null };

    /// Bind a `const` local to a read-only borrow of its owner when its initializer is such a place (B7): the initializer
    /// is read in place, the binding holds its owner, and a loan holds the owner until the binding's last use. False
    /// for every other initializer, which keeps its move, copy or refusal.
    fn initializeConstBorrow(c: *Checker, store: typed.Store, span: Span) Error!bool {
        const owner = (try c.constBorrow(store, span)) orelse return false;
        const slot = @backingInt(store.slot);
        try c.expression(store.value, .read);
        const origins = try c.a.dupe(ConstOrigin, &.{.{ .definition = store.value, .roots = try c.localRoots(owner, 0), .borrowed = true }});
        c.state[slot] = .{ .available = true, .root = owner, .view_definition = .{ .node = store.value, .const_origins = origins }, .dependency = c.state[owner].dependency, .traits = .{ .borrowed = true, .rule = .B9 } };
        try c.holdConstOrigins(slot, .initialize);
        return true;
    }

    /// A store to a `mut` local that holds a borrow (4f): the place is read in place, the local now borrows its owner, and
    /// the owner is held to the local's last use in its declaring block. The loans of earlier assignments stay held, so the
    /// local's loans are the union of every assignment's roots.
    fn storeBorrowedMut(c: *Checker, store: typed.Store) Error!void {
        const slot = @backingInt(store.slot);
        const span = c.program.nodes[@backingInt(store.value)].span;
        if (c.program.nodes[@backingInt(store.value)].data == .record) return c.storeBorrowedMutRecord(store, span);
        if (staticText(c.program, store.value)) return c.storeBorrowedMutLiteral(store);
        if (borrowedCallStore(c.program, store.value)) return c.storeBorrowedMutCall(store, span);
        // A slice of a place (H4) borrows the place, as the place itself would.
        const place = constBorrowPlace(c.program, c.function, store.value) orelse slicePlace(c.program, c.function, store.value) orelse
            return c.rejectInternal(span, "E_INTERNAL_BORROW_SOURCE", "compiler bug: a borrowed mut local's store is not a place");
        try c.expression(store.value, .read);
        const owner = c.ownerLocal(@backingInt(place)) orelse return c.rejectInternal(span, "E_INTERNAL_BORROW_SOURCE", "compiler bug: a borrowed mut local's place has no owner");
        try c.borrowedMutLifetime(slot, owner, span);
        const origins = try c.a.dupe(ConstOrigin, &.{.{ .definition = store.value, .roots = try c.localRoots(owner, 0), .borrowed = true }});
        c.state[slot] = .{ .available = true, .root = owner, .view_definition = .{ .node = store.value, .const_origins = origins }, .dependency = c.state[owner].dependency, .traits = .{ .borrowed = true, .rule = .B9 } };
        try c.holdConstOrigins(slot, .initialize);
    }

    /// A store of a text or bytes literal to a `mut` local that holds a borrow (4f): static storage, so the local borrows
    /// nothing from this assignment; the loans of its earlier assignments stay held to its last use (F-RA-303).
    fn storeBorrowedMutLiteral(c: *Checker, store: typed.Store) Error!void {
        const slot = @backingInt(store.slot);
        try c.expression(store.value, .read);
        // An origin with no roots: the literal joins a branch that borrows like any other assignment of the local.
        const origins = try c.a.dupe(ConstOrigin, &.{.{ .definition = store.value, .roots = .{}, .borrowed = true }});
        c.state[slot] = .{ .available = true, .view_definition = .{ .node = store.value, .const_origins = origins }, .traits = .{ .borrowed = true, .rule = .B9 } };
        try c.holdConstOrigins(slot, .initialize);
    }

    /// A store of a borrowed call result to a `mut` local that holds a borrow (4f, R3b): the call's owners are held to the
    /// local's last use in its declaring block, as a place store's owner is (F-RA-311).
    fn storeBorrowedMutCall(c: *Checker, store: typed.Store, span: Span) Error!void {
        const slot = @backingInt(store.slot);
        const roots = (try c.bindingBorrowRoots(store.value, 0)) orelse return c.rejectInternal(span, "E_INTERNAL_BORROW_SOURCE", "compiler bug: a borrowed mut local's call store has no owner");
        if (roots.unknown) return c.rejectInternal(span, "E_INTERNAL_BORROW_SOURCE", "compiler bug: a borrowed mut local's call store has an unknown owner");
        try c.expression(store.value, .read);
        for (roots.slice()) |root| try c.borrowedMutLifetime(slot, root, span);
        const origins = try c.a.dupe(ConstOrigin, &.{.{ .definition = store.value, .roots = roots, .borrowed = true }});
        c.state[slot] = .{ .available = true, .root = if (roots.items.len == 1 and !roots.temp) roots.items[0] else none, .view_definition = .{ .node = store.value, .const_origins = origins }, .traits = .{ .borrowed = true, .rule = .B9 } };
        try c.holdConstOrigins(slot, .initialize);
    }

    /// A store of a borrowed record to a `mut` local that holds a borrow (4f, 1A): the record's fields are read in place, and the
    /// local borrows the owners of every field, held to its last use as a place store's owner is.
    fn storeBorrowedMutRecord(c: *Checker, store: typed.Store, span: Span) Error!void {
        const slot = @backingInt(store.slot);
        if (!(try c.recordTable()).constructor(store.value)) return c.rejectInternal(span, "E_INTERNAL_BORROW_SOURCE", "compiler bug: a borrowed mut local's store is not a borrowed record");
        const previous = c.record_permit;
        c.record_permit = store.value;
        defer c.record_permit = previous;
        const fields = c.program.nodes[@backingInt(store.value)].data.record;
        try c.borrowedRecordFields(fields);
        const roots = try c.recordRoots(fields, 0);
        if (roots.unknown) return c.rejectInternal(span, "E_INTERNAL_BORROW_SOURCE", "compiler bug: a borrowed record has an unknown owner");
        for (roots.items) |root| try c.borrowedMutLifetime(slot, root, span);
        const origins = try c.a.dupe(ConstOrigin, &.{.{ .definition = store.value, .roots = roots, .borrowed = true }});
        c.state[slot] = .{ .available = true, .view_definition = .{ .node = store.value, .const_origins = origins }, .traits = .{ .borrowed = true, .rule = .B9 } };
        try c.holdConstOrigins(slot, .initialize);
    }

    /// A `mut` local that holds a borrow (4f) may not borrow an owner that a loop makes again in each iteration while the
    /// local is declared outside that loop: the next iteration would destroy what the local still holds.
    fn borrowedMutLifetime(c: *Checker, slot: usize, owner: usize, span: Span) Error!void {
        const declared = c.function.scope.locals[slot].declaration.start;
        var roots = try c.localRoots(owner, 0);
        try roots.add(c.a, owner);
        for (roots.items) |root| {
            if (root >= c.state.len or root < c.function.signature.parameter_count) continue;
            const made = c.function.scope.locals[root].declaration.start;
            for (c.loops.items) |frame| {
                const inside = frame.body.start <= declared and declared < frame.body.end;
                if (inside or made < frame.body.start or made >= frame.body.end) continue;
                const name = c.function.scope.locals[slot].name;
                const message = try c.escapeMessageTo(span, root, .{ .binding = .{ .name = name, .mutable = c.function.scope.locals[slot].mutable, .outlives = true } }, .copy, name);
                const result = c.reject(span, .{ .code = borrow_error, .rule = .B9 }, message);
                c.notePlainCause(slot);
                return result;
            }
        }
    }

    /// Record that the refusal just raised is caused by borrowed `mut` local `slot` (4f): a change, move or escape of it, a
    /// change of an owner it holds, or a borrow that would outlive its owner. `finishFunction` replaces it if it is the final one.
    fn notePlainCause(c: *Checker, slot: usize) void {
        if (c.probing.active or slot >= c.borrowed_mut.len or !c.borrowed_mut[slot]) return;
        c.plain_cause = .{ .slot = slot, .span = c.failure.span, .code = c.failure.code };
    }

    /// The function's final refusal, replaced by the refusal it gets when the borrowed `mut` local that caused it owns its
    /// value: the store that needs `copy(...)` or `own`, with its certain repair, as before 4f. Done once, after the walk, so
    /// no handler on the way out rewrites the replacement. The refusal stays when that re-check finds nothing.
    /// The replaced refusal keeps the first one's position as its cause note (W2).
    fn finishFunction(c: *Checker, result: Error!void) Error!void {
        result catch |err| {
            if (err != error.Rejected) return err;
            const original = c.failure.*;
            // A refusal in a function with borrowed collections (RB2) is reported as the function gets it when they own their
            // elements, as before RB2: each such collection stores a borrow, which an owning collection refuses.
            if (c.collections) |held| {
                try c.plainCollectionRefusal(held.table);
                if (c.collection_cause) |cause| if (std.meta.eql(cause.span, original.span) and std.mem.eql(u8, cause.code, original.code))
                    try c.noteReplacedCause(original, c.function.scope.locals[cause.slot].name, "elements");
                return err;
            }
            if (c.plain_cause) |cause| {
                const same = std.meta.eql(cause.span, c.failure.span) and std.mem.eql(u8, cause.code, c.failure.code);
                if (same) {
                    try c.plainMutRefusal(cause.slot);
                    try c.noteReplacedCause(original, c.function.scope.locals[cause.slot].name, "value");
                    return err;
                }
            }
            if (c.record_cause) |cause| {
                const same = std.meta.eql(cause.span, c.failure.span) and std.mem.eql(u8, cause.code, c.failure.code);
                if (same) {
                    try c.plainRecordRefusal(cause.node);
                    try c.noteReplacedCause(original, try c.recordName(cause.node), "fields");
                    return err;
                }
            }
            try c.noteOwningCause();
            return err;
        };
    }

    /// Record that the refusal just raised is caused by borrowed collection `slot` (RB2, W2): a use of it other than an element
    /// store, a change of an owner it borrows from, or a task it is lent to. `finishFunction` notes it on the replacement.
    fn noteCollectionCause(c: *Checker, slot: usize) void {
        const held = c.collections orelse return;
        if (c.probing.active or !held.table.holds(slot)) return;
        c.collection_cause = .{ .slot = slot, .span = c.failure.span, .code = c.failure.code };
    }

    /// Note on the replacement refusal where `original`, the refusal the walk raised, was (W2): that statement needs `subject`
    /// to own its `part` (its elements, fields or value), which is why the refused line needs `copy(...)` or `own`. Nothing
    /// when the re-check refused the same place or found nothing.
    fn noteReplacedCause(c: *Checker, original: Failure, subject: []const u8, part: []const u8) Error!void {
        if (c.probing.active or std.meta.eql(original.span, c.failure.span)) return;
        // What the statement does is the first refusal's own account of it, without its advice.
        const said = original.message[0 .. std.mem.indexOf(u8, original.message, "; ") orelse original.message.len];
        const message = try std.fmt.allocPrint(c.diagnostics.allocator, "`{s}` must own its {s} because of this line ({s}), so the {s} line needs `copy(...)` or `own`", .{ subject, part, said, c.relativeLine(original.span) });
        c.failure.notes.cause = .{ .span = original.span, .message = message };
    }

    /// Whether the refused line is before or after the cause at `cause`, as the note words it.
    fn relativeLine(c: *const Checker, cause: Span) []const u8 {
        return if (c.failure.span.start < cause.start) "earlier" else "later";
    }

    /// The name a borrowed record goes by in a note: the `const` it initializes, else its record type.
    fn recordName(c: *Checker, node: typed.NodeId) Error![]const u8 {
        if (try c.initializerOf(node)) |slot| if (namedLocal(c.function.scope.locals[slot])) return c.function.scope.locals[slot].name;
        return typed.surfaceTypeName(c.diagnostics.allocator, c.program.nodes[@backingInt(node)].ty, c.program.records);
    }

    /// The local of this function a statement initializes with `value`, or null.
    fn initializerOf(c: *Checker, value: typed.NodeId) Error!?usize {
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item != .statement) continue;
            const data = c.program.statements[@backingInt(item.statement)].data;
            if (data == .initialize and data.initialize.value == value) return @backingInt(data.initialize.slot);
        }
        return null;
    }

    /// Note why a refused borrowed value had to be copied when the place it is stored into owns for a reason elsewhere (W2):
    /// a local collection that a later statement keeps from lending, or a record whose field default is a new value.
    fn noteOwningCause(c: *Checker) Error!void {
        if (c.probing.active or c.failure.notes.cause != null or c.failure.code.len == 0) return;
        if (try c.noteCollectionOwner()) return;
        if (try c.noteMutOwner()) return;
        try c.noteDefaultOwner();
    }

    /// The cause note of a place stored into a `mut` local that owns its value because another store of it is a new value
    /// (4f): a local whose stores all read places borrows them, and one fresh store makes every store an owning one.
    fn noteMutOwner(c: *Checker) Error!bool {
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        var stores: std.ArrayList(struct { store: typed.Store, span: Span }) = .empty;
        var aliases: std.AutoHashMapUnmanaged(u32, typed.NodeId) = .empty;
        defer aliases.deinit(c.a);
        var refused: ?usize = null;
        while (try walker.next()) |item| {
            if (item != .statement) continue;
            const statement = c.program.statements[@backingInt(item.statement)];
            const store = switch (statement.data) {
                .initialize => |store| store,
                .assign => |store| store,
                else => continue,
            };
            if (statement.data == .initialize and store.unpack == null) try aliases.put(c.a, @intCast(@backingInt(store.slot)), store.value);
            try stores.append(c.a, .{ .store = store, .span = statement.span });
            if (std.meta.eql(c.program.nodes[@backingInt(store.value)].span, c.failure.span)) refused = @backingInt(store.slot);
        }
        const slot = refused orelse return false;
        const local = c.function.scope.locals[slot];
        if (slot < c.function.signature.parameter_count or !local.mutable) return false;
        if (!namedLocal(local) or !c.owns(local.ty)) return false;
        var count: usize = 0;
        var fresh: ?Span = null;
        var records: ?BorrowedRecords = null;
        for (stores.items) |entry| {
            if (@backingInt(entry.store.slot) != slot or writeThrough(c.program, &aliases, entry.store, slot)) continue;
            count += 1;
            const value = c.program.nodes[@backingInt(entry.store.value)];
            if (std.meta.eql(value.span, c.failure.span)) {
                if (!borrowStore(c.program, c.function, entry.store)) return false;
                continue;
            }
            const plain = entry.store.unpack == null and !entry.store.element and !entry.store.transfer and !value.own;
            if (plain and staticText(c.program, entry.store.value)) continue;
            if (plain and value.data == .record) {
                if (records == null) records = try BorrowedRecords.init(c.a, c.program, c.linear, c.function, c.case_payloads);
                if (records.?.constructor(entry.store.value)) continue;
            } else if (borrowStore(c.program, c.function, entry.store) or c.repairedCopy(entry.store.value)) continue;
            if (fresh == null) fresh = entry.span;
        }
        const cause = fresh orelse return false;
        if (count < 2) return false;
        const message = try std.fmt.allocPrint(c.diagnostics.allocator, "`{s}` owns its value because this line stores a new value in it, so the {s} line needs `copy(...)` or `own`", .{ local.name, c.relativeLine(cause) });
        c.failure.notes.cause = .{ .span = cause, .message = message };
        return true;
    }

    /// Whether `id` is the `copy(...)` an earlier certain repair of this check wrote (`rewriteCopy`), not a value of the source.
    fn repairedCopy(c: *const Checker, id: typed.NodeId) bool {
        const node = c.program.nodes[@backingInt(id)];
        if (node.data != .block_value) return false;
        const value = c.program.nodes[@backingInt(node.data.block_value.value)];
        if (value.data != .buffer_operation or value.data.buffer_operation.kind != .copy) return false;
        const owner = @backingInt(value.data.buffer_operation.owner);
        return owner < c.function.scope.locals.len and std.mem.eql(u8, c.function.scope.locals[owner].name, "<copy-repair>");
    }

    /// The cause note of a borrowed value appended to a local list that owns its elements because of one later use.
    fn noteCollectionOwner(c: *Checker) Error!bool {
        const target = try c.appendTarget(c.failure.span) orelse return false;
        if (c.collections) |held| if (held.table.holds(target)) return false;
        const plain = if (c.plain_mut.len == c.function.scope.locals.len) c.plain_mut else &.{};
        const table = try BorrowedCollections.init(c.a, c.program, c.linear, c.function, c.case_payloads, plain);
        const why = table.why[target];
        const does = switch (why.kind) {
            .none => return false,
            .initialized => "starts it from a value other than `[]`",
            .assigned => "assigns it again",
            .returned => "returns it",
            .moved => "gives it away with `own`",
            .fresh => "stores a new value in it",
            .changed => "changes it other than by `append`",
        };
        const name = c.function.scope.locals[target].name;
        const message = try std.fmt.allocPrint(c.diagnostics.allocator, "`{s}` owns its elements because this line {s}, so the {s} line needs `copy(...)` or `own`", .{ name, does, c.relativeLine(why.span) });
        c.failure.notes.cause = .{ .span = why.span, .message = message };
        return true;
    }

    /// The named local list an `append` of this function stores the value at `span` into, read through the receiver
    /// temporary that stages it.
    fn appendTarget(c: *Checker, span: Span) Error!?usize {
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        // The value each lowering temporary is initialized with; a receiver is initialized before its operation.
        var staged: std.AutoHashMapUnmanaged(usize, typed.NodeId) = .empty;
        defer staged.deinit(c.a);
        while (try walker.next()) |item| switch (item) {
            .statement => |id| {
                const data = c.program.statements[@backingInt(id)].data;
                if (data == .initialize) try staged.put(c.a, @backingInt(data.initialize.slot), data.initialize.value);
            },
            .expression => |id| {
                const node = c.program.nodes[@backingInt(id)];
                if (node.data != .buffer_operation) continue;
                const operation = node.data.buffer_operation;
                if (operation.kind != .append or operation.arguments.len != 1) continue;
                if (!std.meta.eql(c.program.nodes[@backingInt(operation.arguments[0])].span, span)) continue;
                const owner = @backingInt(operation.owner);
                if (owner >= c.function.scope.locals.len) return null;
                if (namedLocal(c.function.scope.locals[owner])) return owner;
                const read = c.program.nodes[@backingInt(staged.get(owner) orelse return null)];
                if (read.data != .local or read.own or @backingInt(read.data.local) >= c.function.scope.locals.len) return null;
                return @backingInt(read.data.local);
            },
        };
        return null;
    }

    /// The cause note of a borrowed field value refused because its record owns: a managed field the constructor leaves out
    /// takes its declared default, a new value, so the record cannot borrow. A field the constructor writes is noted where
    /// the constructor is walked (`noteOwnedField`).
    fn noteDefaultOwner(c: *Checker) Error!void {
        var table: ?BorrowedRecords = null;
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item != .expression) continue;
            const node = c.program.nodes[@backingInt(item.expression)];
            if (node.data != .record) continue;
            const refused = for (node.data.record) |field| {
                if (std.meta.eql(c.program.nodes[@backingInt(field.value)].span, c.failure.span)) break field;
            } else continue;
            if (table == null) table = try BorrowedRecords.init(c.a, c.program, c.linear, c.function, c.case_payloads);
            if (!table.?.borrowedField(refused.value)) return;
            const owning = table.?.owningField(item.expression) orelse return;
            const given = c.program.nodes[@backingInt(owning.value)].span;
            const declared = c.program.records[node.ty.recordIndex()];
            if (given.start >= node.span.start and given.end <= node.span.end) return;
            if (owning.index >= declared.fields.len or declared.fields[owning.index].default_value == null) return;
            const field = declared.fields[owning.index];
            const record = try typed.surfaceTypeName(c.diagnostics.allocator, node.ty, c.program.records);
            const format = "field `{s}` of `{s}` defaults to a new value, so `{s}(...)` without `{s}` owns its fields instead of " ++
                "borrowing them; that is why the refused field needs `copy(...)` or `own`";
            const message = try std.fmt.allocPrint(c.diagnostics.allocator, format, .{ field.name, record, record, field.name });
            c.failure.notes.cause = .{ .span = field.declaration, .message = message };
            return;
        }
    }

    /// Record that the refusal just raised is caused by borrowed record `node` (1A): a store, move or change of a binding of
    /// it, a change of an owner it holds while it is live, or a refusal while its fields are read. `finishFunction` replaces
    /// the refusal if it is the final one.
    fn noteRecordCause(c: *Checker, node: typed.NodeId) void {
        if (c.probing.active) return;
        c.record_cause = .{ .node = node, .span = c.failure.span, .code = c.failure.code };
    }

    /// The borrowed record a `const` or a lowering temporary `slot` holds (1A), if any.
    fn heldRecord(c: *const Checker, slot: usize) ?typed.NodeId {
        if (slot >= c.state.len) return null;
        const state = c.state[slot];
        if (!state.traits.borrowed or state.traits.rule != .B9) return null;
        for (state.view_definition.const_origins) |origin_value| {
            if (c.program.nodes[@backingInt(origin_value.definition)].data == .record) return origin_value.definition;
        }
        return null;
    }

    /// Note the borrowed record a refused local or field read `id` reaches through its base, if it names a binding of one.
    fn noteHeldRecord(c: *Checker, id: typed.NodeId) void {
        var current = id;
        var remaining = c.program.nodes.len + 1;
        while (remaining != 0) : (remaining -= 1) switch (c.program.nodes[@backingInt(current)].data) {
            .field => |field| current = field.base,
            .local => |slot| {
                const record = c.heldRecord(@backingInt(slot)) orelse return;
                const noted = if (c.record_cause) |cause| std.meta.eql(cause.span, c.failure.span) else false;
                if (!noted) c.noteRecordCause(record);
                return;
            },
            else => return,
        };
    }

    /// Note the borrowed record argument whose loan `loan` is, as the cause of the refusal just raised.
    fn noteArgumentRecord(c: *Checker, loan: Loan) void {
        if (loan.hold != .argument) return;
        for (c.record_arguments.items) |argument| {
            if (!std.meta.eql(argument.span, loan.hold.argument)) continue;
            c.noteRecordCause(argument.node);
            return;
        }
    }

    /// Note a borrowed record returned under `from` as the cause of a return refusal (a missing source or a mixed return).
    fn noteReturnedRecord(c: *Checker) Error!void {
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item != .statement) continue;
            const data = c.program.statements[@backingInt(item.statement)].data;
            if (data != .ret) continue;
            const payload = c.returnedPayload(data.ret);
            const node = c.program.nodes[@backingInt(payload)];
            if (node.data != .record or !try c.borrowedRecord(payload)) continue;
            for (c.returns.borrowed.items) |seen| if (std.meta.eql(seen, node.span)) {
                c.noteRecordCause(payload);
                return;
            };
        }
    }

    /// Replace the refusal with the one the function gets when borrowed record `node` is built as an owner (`finishFunction`):
    /// the field that needs `own` or `copy(...)`, with its certain repair, as before 1A.
    fn plainRecordRefusal(c: *Checker, node: typed.NodeId) Error!void {
        if (c.probing.active) return;
        const plain = try c.a.alloc(bool, c.program.nodes.len);
        @memset(plain, false);
        for (c.plain_records, 0..) |masked, index| if (index < plain.len) {
            plain[index] = masked;
        };
        var shared = c.probeShared(c.program);
        // Each nested re-check masks one more record or one more `mut` local, so the nesting ends: a record that is already
        // masked is still the cause only when a borrowed `mut` local stores it, which the mask of the record does not reach
        // (`storeBorrowedMutRecord`), so the re-check masks that local too; with no such local the refusal stays.
        if (plain[@backingInt(node)]) shared.plain_mut = (try c.plainMutHolding(node)) orelse return;
        plain[@backingInt(node)] = true;
        shared.plain_records = plain;
        shared.observer = c.diagnostics.observer;
        var owned: Failure = .{};
        checkFunction(c.diagnostics.allocator, shared, c.function, &owned, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Rejected => c.failure.* = owned,
        };
    }

    /// Replace the refusal with the one the function gets when its borrowed collections own their elements (`finishFunction`).
    fn plainCollectionRefusal(c: *Checker, table: BorrowedCollections) Error!void {
        if (c.probing.active) return;
        const plain = try c.a.alloc(bool, table.slots.len);
        for (plain, table.slots, 0..) |*out, lent, slot| out.* = lent or (slot < c.plain_mut.len and c.plain_mut[slot]);
        var shared = c.probeShared(c.program);
        shared.plain_mut = plain;
        shared.observer = c.diagnostics.observer;
        var owned: Failure = .{};
        checkFunction(c.diagnostics.allocator, shared, c.function, &owned, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Rejected => c.failure.* = owned,
        };
    }

    /// `plain_mut` with the borrowed `mut` locals that store constructor `node` added (1A, 4f), or null when it adds none.
    fn plainMutHolding(c: *Checker, node: typed.NodeId) Error!?[]const bool {
        const plain = try c.a.alloc(bool, c.function.scope.locals.len);
        @memset(plain, false);
        for (c.plain_mut, 0..) |masked, slot| if (slot < plain.len) {
            plain[slot] = masked;
        };
        var added = false;
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item != .statement) continue;
            const store = switch (c.program.statements[@backingInt(item.statement)].data) {
                .initialize => |store| store,
                .assign => |store| store,
                else => continue,
            };
            const slot = @backingInt(store.slot);
            if (store.value != node or slot >= c.borrowed_mut.len or !c.borrowed_mut[slot]) continue;
            plain[slot] = true;
            added = true;
        }
        return if (added) plain else null;
    }

    /// Replace the refusal with the one the function gets when borrowed `mut` local `slot` owns its value (`finishFunction`).
    fn plainMutRefusal(c: *Checker, slot: usize) Error!void {
        if (c.probing.active or slot >= c.borrowed_mut.len or !c.borrowed_mut[slot]) return;
        const eligible = try borrowedMutLocals(c.a, c.program, c.linear, c.function, c.case_payloads);
        const plain = try c.a.alloc(bool, eligible.len);
        for (plain, eligible, c.borrowed_mut, 0..) |*out, candidate, kept, index| out.* = (candidate and !kept) or index == slot;
        var shared = c.probeShared(c.program);
        shared.plain_mut = plain;
        shared.observer = c.diagnostics.observer;
        var owned: Failure = .{};
        checkFunction(c.diagnostics.allocator, shared, c.function, &owned, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Rejected => c.failure.* = owned,
        };
    }

    /// Bind a `const` initializer as a borrow: a place (B7) or a borrowed call result (R3b). False for every other form.
    fn initializeBinding(c: *Checker, store: typed.Store, span: Span, initializing: bool) Error!bool {
        if (!initializing) return false;
        if (try c.initializeConstBorrow(store, span)) return true;
        if (try c.initializeBorrowedRecord(store, span)) return true;
        if (try c.initializeBorrowedOption(store, span)) return true;
        return c.initializeBorrowedCall(store, span);
    }

    /// Bind a `const` local to a borrowed option (H2, `BorrowedRecords.lentLocalOption`): `Some(place)` reads its payload in
    /// place, and the binding holds the payload's owner until its last use, as a `const` of the place itself does (B9).
    /// False for any other initializer.
    fn initializeBorrowedOption(c: *Checker, store: typed.Store, span: Span) Error!bool {
        const slot = @backingInt(store.slot);
        const local = c.function.scope.locals[slot];
        if (local.mutable or c.temporary(slot) or c.sliceView(slot)) return false;
        if (store.unpack != null or !c.owns(local.ty)) return false;
        if (!(try c.recordTable()).lentLocalOption(store.value)) return false;
        const block = c.block orelse return false;
        if (block.index >= block.items.len) return false;
        const current = c.program.statements[@backingInt(block.items[block.index])];
        if (current.data != .initialize or current.data.initialize.slot != store.slot) return false;
        if (current.span.start != span.start or current.span.end != span.end) return false;
        const payload = c.program.nodes[@backingInt(store.value)].data.variant.value.?;
        try c.expression(payload, .read);
        const roots = try c.placeRoots(payload, 0);
        if (roots.unknown) return c.rejectInternal(span, "E_INTERNAL_BORROW_SOURCE", "compiler bug: a borrowed option has an unknown owner");
        const origins = try c.a.dupe(ConstOrigin, &.{.{ .definition = store.value, .roots = roots, .borrowed = true }});
        c.state[slot] = .{ .available = true, .view_definition = .{ .node = store.value, .const_origins = origins }, .traits = .{ .borrowed = true, .rule = .B9 } };
        try c.holdConstOrigins(slot, .initialize);
        return true;
    }

    /// Bind a `const` local to a borrowed record (1A): its fields are read in place, the binding holds the owners of every
    /// field, and loans hold them until the binding's last use, as a `const` of a place holds its owner (B9). False for any
    /// other initializer.
    fn initializeBorrowedRecord(c: *Checker, store: typed.Store, span: Span) Error!bool {
        const slot = @backingInt(store.slot);
        const local = c.function.scope.locals[slot];
        if (local.mutable or c.temporary(slot) or c.sliceView(slot)) return false;
        if (store.unpack != null or !c.owns(local.ty)) return false;
        if (!try c.borrowedRecord(store.value)) return false;
        const block = c.block orelse return false;
        if (block.index >= block.items.len) return false;
        const current = c.program.statements[@backingInt(block.items[block.index])];
        if (current.data != .initialize or current.data.initialize.slot != store.slot) return false;
        if (current.span.start != span.start or current.span.end != span.end) return false;
        try c.permittedRecord(store.value, .read);
        const roots = try c.placeRoots(store.value, 0);
        if (roots.unknown) return c.rejectInternal(span, "E_INTERNAL_BORROW_SOURCE", "compiler bug: a borrowed record has an unknown owner");
        const origins = try c.a.dupe(ConstOrigin, &.{.{ .definition = store.value, .roots = roots, .borrowed = true }});
        c.state[slot] = .{ .available = true, .view_definition = .{ .node = store.value, .const_origins = origins }, .traits = .{ .borrowed = true, .rule = .B9 } };
        try c.holdConstOrigins(slot, .initialize);
        return true;
    }

    /// The owner a read-only borrow of a `const` initializer lies in (B7), with the statement after which the borrow
    /// ends (the binding's last use in its block). Null for every other initializer, which keeps its move, copy or
    /// refusal. A written own marker instead makes the initializer transfer ownership.
    fn constBorrow(c: *Checker, store: typed.Store, span: Span) Error!?usize {
        const slot = @backingInt(store.slot);
        const local = c.function.scope.locals[slot];
        if (local.mutable or c.temporary(slot) or c.sliceView(slot)) return null;
        if (c.program.nodes[@backingInt(store.value)].own) return null;
        if (store.unpack != null or !c.owns(local.ty)) return null;
        // The initializer must be the statement now checked, directly in the innermost block.
        const block = c.block orelse return null;
        if (block.index >= block.items.len) return null;
        const current = c.program.statements[@backingInt(block.items[block.index])];
        if (current.data != .initialize or current.data.initialize.slot != store.slot) return null;
        if (current.span.start != span.start or current.span.end != span.end) return null;
        const source = constBorrowPlace(c.program, c.function, store.value) orelse return null;
        const owner = c.ownerLocal(@backingInt(source)) orelse return null;
        return owner;
    }

    /// A deferred initializer keeps the destination's declaring block lifetime,
    /// including reads after the conditional arm that supplies its value.
    fn bindingBlock(c: *const Checker, slot: usize) ?BlockContext {
        const declaration = c.function.scope.locals[slot].declaration;
        var current = c.block;
        while (current) |block| {
            if (block.span.start <= declaration.start and block.span.end >= declaration.end) return block;
            current = if (block.parent) |parent| parent.* else null;
        }
        return null;
    }

    fn holdConstOrigins(c: *Checker, slot: usize, mode: enum { initialize, restore }) Error!void {
        const state = c.state[slot];
        if (!state.available) return;
        if (!state.traits.borrowed or state.traits.rule != .B9) return;
        const block = c.bindingBlock(slot) orelse return;
        const release = try c.lastUse(block, slot);
        if (mode == .restore and release == block.index) {
            if (!try c.mentions(block.items[block.index], slot)) return;
        }
        const roots = try c.localRoots(slot, 0);
        const path = try c.constBorrowPath(slot, roots);
        for (roots.items) |root| {
            const held = for (c.loans.items) |loan| {
                if (loan.binding == slot and loan.root == root) break true;
            } else false;
            if (!held) try c.loans.append(c.a, .{ .root = root, .binding = slot, .release = release, .write = false, .hold = .{ .constant = block.id }, .path = path });
        }
    }

    /// The part of its owner a `const` binding borrows (R2): the owner and the plain record fields down to the container the
    /// borrowed value lies in. `const item = self.items[i]` holds `self.items`, so another field of `self` may change while
    /// `item` is live and the list itself, its prefix `self` and anything inside it may not. The path stops at the first element
    /// step (a list element, a dictionary value): elements are not told apart, so a write to any part of that container still
    /// overlaps. Null (the whole owner) when the borrow has several origins or its place cannot be named.
    fn constBorrowPath(c: *Checker, slot: usize, roots: Roots) Error!?PlacePath {
        const origins = c.state[slot].view_definition.const_origins;
        if (origins.len != 1 or roots.items.len != 1 or roots.temp or roots.unknown) return null;
        const named = (try c.sourcePath(origins[0].definition, none, false)) orelse return null;
        if (named.root != roots.items[0]) return null;
        const steps = named.steps.items;
        var kept: usize = 0;
        while (kept < steps.len and steps[steps.len - 1 - kept] == .field) kept += 1;
        var path: PlacePath = .{ .root = named.root };
        try path.steps.appendSlice(c.a, steps[steps.len - kept ..]);
        return path;
    }

    fn restoreConstLoans(c: *Checker) Error!void {
        for (c.state, 0..) |_, slot| try c.holdConstOrigins(slot, .restore);
        try c.restoreCollectionLoans();
    }

    /// Check a value stored into a borrowed collection (RB2): it is read in place, as a borrowed record's field is, and its
    /// roots are what the collection now borrows. A borrowed record constructor is read as one.
    fn lendIntoCollection(c: *Checker, value: typed.NodeId) Error!Roots {
        const node = c.program.nodes[@backingInt(value)];
        if (staticText(c.program, value) or (try c.recordTable()).emptyOption(value)) {
            try c.expression(value, .read);
            return .{};
        }
        const previous = c.record_permit;
        if (node.data == .record) c.record_permit = value;
        defer c.record_permit = previous;
        // `Some(record)` of a borrowed record: the record is read in place, as an element of borrows.
        if (BorrowedCollections.someRecord(try c.recordTable(), value)) |payload| {
            c.record_permit = payload;
            try c.expression(payload, .read);
            return c.placeRoots(payload, 0);
        }
        if (node.data == .variant) {
            const place = (try c.recordTable()).lentOption(value) orelse return c.rejectInternal(node.span, "E_INTERNAL_BORROW_SOURCE", "compiler bug: a lent element is not a lent option");
            try c.expression(node.data.variant.value.?, .read);
            return c.localRoots(@backingInt(place), 0);
        }
        try c.expression(value, .read);
        const roots = try c.placeRoots(value, 0);
        // The table admits no slice or bare view (a framed parameter is held through a record's frame block); `view` here
        // only says a text or list local was read whole.
        if (roots.unknown or roots.frame) return c.reject(node.span, .{ .code = borrow_error, .rule = .B9 }, borrowed_record_escape);
        return roots;
    }

    /// Hold what borrowed collection `slot` borrows (RB2): `roots` join the union its stores have borrowed so far, and the
    /// collection holds each root until its last use in its declaring block. A root that a loop makes again in each iteration
    /// while the collection lives past it is refused, as for a borrowed `mut` local (4f).
    fn holdCollection(c: *Checker, slot: usize, roots: Roots) Error!void {
        const held = c.collections orelse return;
        const span = c.function.scope.locals[slot].declaration;
        for (roots.items) |root| {
            if (root == slot) continue;
            try c.borrowedMutLifetime(slot, root, span);
            try held.roots[slot].add(c.a, root);
        }
        try c.holdCollectionLoans(slot);
    }

    fn holdCollectionLoans(c: *Checker, slot: usize) Error!void {
        const held = c.collections orelse return;
        if (!c.state[slot].available) return;
        const block = c.bindingBlock(slot) orelse return;
        const release = try c.lastUse(block, slot);
        for (held.roots[slot].items) |root| {
            const already = for (c.loans.items) |loan| {
                if (loan.binding == slot and loan.root == root) break true;
            } else false;
            if (!already) try c.loans.append(c.a, .{ .root = root, .binding = slot, .release = release, .write = false, .hold = .{ .constant = block.id } });
        }
    }

    /// Hold again the roots of every borrowed collection (RB2) after a branch or a loop dropped the loans its body added.
    fn restoreCollectionLoans(c: *Checker) Error!void {
        const held = c.collections orelse return;
        for (held.roots, 0..) |roots, slot| if (roots.items.len != 0) try c.holdCollectionLoans(slot);
    }

    /// The iteration loan (R7) of the collection `owner` holds: on the place that is iterated, not on its whole owner, so a
    /// sibling path may change while the loop reads it. A place the checker cannot name keeps the whole owner.
    fn holdIteration(c: *Checker, owner: usize, written: Span) Error!void {
        const root = c.rootOf(owner);
        var place = try c.sourcePath(null, owner, false);
        if (place) |known| if (known.root != root) {
            place = null;
        };
        // The hold of a running `match mut` arm covers the whole owner, but it is the arm's own write loan: it lets the arm
        // change what its binding names, and the loop over that binding needs the iteration loan beside it (FR26, R7).
        for (c.loans.items) |loan| if (loan.hold != .matched and c.coversIteration(loan, root, place)) return;
        try c.loans.append(c.a, .{ .root = root, .write = false, .rule = .R7, .path = place });
        const ty = c.function.scope.locals[owner].ty;
        if (!ty.isAggregate() or ty.recordIndex() >= c.program.records.len) return;
        const list = c.program.records[ty.recordIndex()];
        if (list.collection.kind != .list) return;
        if (list.shape.buffer) |element| try c.iterated.append(c.a, .{ .loan = c.loans.items.len - 1, .span = written, .element = element });
    }

    /// Whether `loan` already holds the iterated place `place` of `root`: a loan on the whole owner covers any place, and
    /// an iteration loan of the same place is the one to keep.
    fn coversIteration(c: *const Checker, loan: Loan, root: usize, place: ?PlacePath) bool {
        if (loan.root != root) return false;
        const held = loan.path orelse return true;
        const wanted = place orelse return false;
        return loan.rule == .R7 and c.samePath(held, wanted);
    }

    fn persistentIterationLoan(loan: Loan) bool {
        if (loan.rule != .R7 or loan.hold != .none) return false;
        return loan.binding == none and loan.release == none and !loan.write;
    }

    /// Whether two paths name the same place: one owner, the same fields, and at each list step the same literal or the
    /// same index expression.
    fn samePath(c: *const Checker, left: PlacePath, right: PlacePath) bool {
        if (left.root != right.root or left.steps.items.len != right.steps.items.len) return false;
        for (left.steps.items, right.steps.items) |first, second| switch (first) {
            .field => |field| if (second != .field or second.field != field) return false,
            .index => |index| {
                if (second != .index) return false;
                if (index == second.index) continue;
                const x = c.literalIndex(index) orelse return false;
                const y = c.literalIndex(second.index) orelse return false;
                if (x != y) return false;
            },
        };
        return true;
    }

    /// Arm-local const holds are rebuilt from joined provenance. Persistent
    /// iteration holds survive the branch; scoped evaluation holds do not.
    fn mergeBranchLoans(c: *Checker, saved: usize, first: []const Loan) Error!void {
        var position = c.loans.items.len;
        while (position > saved) {
            position -= 1;
            if (!persistentIterationLoan(c.loans.items[position])) _ = c.loans.orderedRemove(position);
        }
        for (first) |loan| {
            if (!persistentIterationLoan(loan)) continue;
            const held = for (c.loans.items) |existing| {
                if (existing.root != loan.root or !persistentIterationLoan(existing)) continue;
                if (existing.path == null and loan.path == null) break true;
                if (existing.path != null and loan.path != null and c.samePath(existing.path.?, loan.path.?)) break true;
            } else false;
            if (!held) try c.loans.append(c.a, loan);
        }
        try c.restoreConstLoans();
    }

    /// Every named place, including an owner and an `own` parameter, can be read through a `const` alias.
    fn ownerLocal(c: *const Checker, slot: usize) ?usize {
        if (slot >= c.state.len) return null;
        return if (c.namedBinding(slot)) c.rootOf(slot) else null;
    }

    /// A source payload binding of a consuming match (2A, or a matched temporary): it owns its payload outright, so a field
    /// may leave it by consuming it, as from an owned local record (B8).
    fn ownedPayload(c: *const Checker, slot: usize) bool {
        const local = c.function.scope.locals[slot];
        if (local.origin != .pattern or std.mem.startsWith(u8, local.name, "<")) return false;
        return c.state[slot].available and !c.state[slot].traits.borrowed and c.state[slot].root == none and !c.isExclusiveBinder(slot);
    }

    /// Whether a local is an owner a borrow may lie in: a named or lowering owner that is not itself a borrow.
    fn ownedLocal(c: *const Checker, slot: usize) bool {
        if (c.temporary(slot) or c.sliceView(slot)) return false;
        return !c.state[slot].traits.borrowed and c.state[slot].root == none;
    }

    /// The index in `block` of the last statement, at or after the one now checked, that reads local `slot`.
    fn lastUse(c: *const Checker, block: BlockContext, slot: usize) Error!usize {
        var last = block.index;
        var index = block.index + 1;
        while (index < block.items.len) : (index += 1) {
            if (try c.mentions(block.items[index], slot)) last = index;
        }
        return last;
    }

    /// Whether a statement reads local `slot` anywhere in its body, nested blocks included.
    fn mentions(c: *const Checker, statement: typed.StatementId, slot: usize) Error!bool {
        var walker = try typed_walk.Walker.init(c.a, c.program, statement);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .expression => |id| switch (c.program.nodes[@backingInt(id)].data) {
                .local => |read| if (@backingInt(read) == slot) return true,
                // `copy(x)`, `x.contains(..)` and the other collection operations name their owner as a local id, not a child node.
                .buffer_operation => |operation| if (@backingInt(operation.owner) == slot) return true,
                else => {},
            },
            .statement => {},
        };
        return false;
    }

    /// Remove the borrows of `const` bindings whose last use is statement `index` of the block whose loans begin at
    /// `saved`; with no index, every such borrow the block still holds (its end).
    fn releaseBindings(c: *Checker, saved: usize, index: ?usize) void {
        var position = c.loans.items.len;
        while (position > saved) {
            position -= 1;
            const loan = c.loans.items[position];
            if (loan.hold == .constant and loan.hold.constant != c.block.?.id) continue;
            // A `const` borrow (B7) and an arm hold (C3) both end at a release index; any other loan has none.
            if (loan.binding == none and loan.release == none) continue;
            if (index) |ended| if (loan.release != ended) continue;
            _ = c.loans.orderedRemove(position);
        }
    }

    /// Whether an access moves a `const` binding that borrows its owner (B7), which changes nothing the owner holds.
    fn movesConstBorrow(c: *const Checker, slot: usize, access: Access) bool {
        if (access != .move) return false;
        const state = c.state[slot];
        return state.traits.borrowed and state.root != none and state.view_definition.node != null and !c.temporary(slot) and !c.viewLike(slot);
    }

    /// Refuse an access to `slot` through its owner `root` while a live loan forbids it: an overlap with a `const`
    /// binding, a borrow, or a live view of the owner.
    fn checkLoans(c: *Checker, slot: usize, root: usize, write: bool, access: Access, span: Span) Error!void {
        if (write) for (c.tasks.loans.items) |loan| {
            if (loan.root != root) continue;
            const refusal = c.reject(span, .{ .code = "E_TASK_LOAN", .rule = .K1 }, "this value is lent to a task of an open task group; a task reads its arguments until the group's block ends, so write or give it away after the block");
            c.failure.notes.related = .{ .span = loan.span, .message = "lent to this task until its group ends" };
            return refusal;
        };
        for (c.loans.items, 0..) |loan, index| if (loan.binding != slot and loan.root == root and (loan.write or write)) {
            // A field move consumes its carrier, so sibling paths cannot exempt any move.
            if (access != .move and try c.exemptible(loan) and try c.disjointArgument(loan)) continue;
            if (c.deferOwnValueRead(loan, index, write, access, .{ .slot = slot, .span = span, .argument = c.argument })) continue;
            c.loanConflict(loan, slot, write, access, span) catch |err| {
                // Preserve the selected refusal, including a live view's V3 copy repair.
                if (err != error.Rejected) return err;
                c.noteArgumentRecord(loan);
                if (c.failure.rule != .R2 or loan.hold != .receiver) return err;
                if (access != .mutate and access != .update) return err;
                // Receiver staging may already have invalidated an independent view.
                // Hoisting the call would still leave that view invalidated.
                if (c.sourceView(root, true) != null) return err;
                if (try c.receiverCall(span)) |call| c.failure.repair = .{
                    .receiver = .{ .receiver = loan.hold.receiver, .call = call },
                };
                return err;
            };
        };
    }

    /// LOOPDETACH (`src/loop_detach.zig`): whether the move of `slot`, the hidden owner of a `detach` loop's collection
    /// (named `typed.detach_owner` and its place), is the put-back the front end generates before an exit, which ends the loops' loans on the
    /// collection at the move. False when no loan holds it (the put-back after the loop, judged as any move) and for any
    /// other shape, which keeps the overlap refusal; a hand-written move has a name a source can spell and never comes here.
    /// The conditions, on the one path from the move:
    /// 1. nothing that borrows from the collection (the loop variable, a `const` alias, a match binding, a view) is read
    ///    after the move: the statements after it are scanned;
    /// 2. the value that leaves was held before the move (`<return>`) and borrows nothing of it: refused here, by name;
    /// 3. the path leaves at once: after the move come only the put-back's trap check, the put-backs of the enclosing
    ///    `detach` loops and the exit, which is a `return` (or a postcondition's block that ends in one);
    /// 4. no loan on the collection writes (a `match mut` hold);
    /// 5. no `with` scope or task group holds it, whose close or join would run after the move.
    fn detachExit(c: *Checker, slot: usize) Error!bool {
        var held = false;
        for (c.loans.items) |loan| if (loan.root == slot) {
            if (loan.write or loan.hold == .scope) return false;
            held = true;
        };
        if (!held) return false;
        for (c.tasks.loans.items) |loan| if (loan.root == slot) return false;
        const inner = c.block orelse return false;
        const outer = inner.parent orelse return false;
        const rest = inner.items[inner.index + 1 ..];
        for (rest) |item| if (c.program.statements[@backingInt(item)].data != .assertion) return false;
        const after = outer.items[outer.index + 1 ..];
        if (after.len == 0 or !c.leavesAtOnce(after[after.len - 1])) return false;
        for (after[0 .. after.len - 1]) |item| if (!c.putBackShape(item)) return false;
        const borrowers = try c.borrowersOf(slot);
        for (rest) |item| if (try c.mentionsAny(item, borrowers)) return false;
        for (after[0 .. after.len - 1]) |item| if (try c.mentionsAny(item, borrowers)) return false;
        const exit = after[after.len - 1];
        if (try c.mentionsAny(exit, borrowers)) return c.reject(c.program.statements[@backingInt(exit)].span, .{ .code = overlap_error, .rule = .R7 }, detach_exit_borrow);
        return true;
    }

    /// Whether a statement is an exit with nothing after it on its path: a `return`, or a block that ends in one and
    /// holds nothing else that leaves or loops (a postcondition's staging).
    fn leavesAtOnce(c: *const Checker, id: typed.StatementId) bool {
        const statement = c.program.statements[@backingInt(id)];
        return switch (statement.data) {
            .ret => true,
            .block => |items| items.len != 0 and c.program.statements[@backingInt(items[items.len - 1])].data == .ret and for (items[0 .. items.len - 1]) |item| {
                switch (c.program.statements[@backingInt(item)].data) {
                    .initialize, .assertion, .match, .block => {},
                    else => break false,
                }
            } else true,
            else => false,
        };
    }

    /// Whether a statement has the shape of a generated put-back: a block of the `exchange` into a hidden local and its
    /// trap check.
    fn putBackShape(c: *const Checker, id: typed.StatementId) bool {
        const items = switch (c.program.statements[@backingInt(id)].data) {
            .block => |items| items,
            else => return false,
        };
        return items.len == 2 and c.program.statements[@backingInt(items[0])].data == .initialize and c.program.statements[@backingInt(items[1])].data == .assertion;
    }

    /// The locals that borrow from `owner`, `owner` included: those whose root or dependency chain reaches it, and the
    /// `const` bindings a loan on it names.
    fn borrowersOf(c: *Checker, owner: usize) Error![]const bool {
        const set = try c.a.alloc(bool, c.state.len);
        @memset(set, false);
        set[owner] = true;
        for (c.loans.items) |loan| if (loan.root == owner and loan.binding < set.len) {
            set[loan.binding] = true;
        };
        var changed = true;
        while (changed) {
            changed = false;
            for (c.state, 0..) |state, local| {
                if (set[local]) continue;
                const through_root = state.root != none and state.root < set.len and set[state.root];
                const through_dependency = state.dependency != none and state.dependency < set.len and set[state.dependency];
                if (!through_root and !through_dependency) continue;
                set[local] = true;
                changed = true;
            }
        }
        return set;
    }

    /// Whether a statement reads any local `set` marks, nested blocks included.
    fn mentionsAny(c: *const Checker, statement: typed.StatementId, set: []const bool) Error!bool {
        var walker = try typed_walk.Walker.init(c.a, c.program, statement);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .expression => |id| switch (c.program.nodes[@backingInt(id)].data) {
                .local => |read| if (@backingInt(read) < set.len and set[@backingInt(read)]) return true,
                .buffer_operation => |operation| if (@backingInt(operation.owner) < set.len and set[@backingInt(operation.owner)]) return true,
                else => {},
            },
            .statement => {},
        };
        return false;
    }

    /// Whether a loan on another field may be passed by a write: an argument or iteration loan always (C3, R7), a staged
    /// receiver's, and a `const` binding's only when it names a record place the lowering reads again after the write
    /// (`alias_places`). A `const` binding the lowering does not re-read keeps its borrow across the write.
    fn exemptible(c: *Checker, loan: Loan) Error!bool {
        if (loan.binding == none or c.temporary(loan.binding)) return true;
        return (try c.bindingFlags(loan.binding)).bound;
    }

    /// What the body does to the record of `const` binding `slot` after the binding is made (`alias_places.compute`).
    fn bindingFlags(c: *Checker, slot: usize) Error!alias_places.Flags {
        if (c.place_bindings == null) c.place_bindings = try alias_places.compute(c.a, c.program, c.function);
        const flags = c.place_bindings.?;
        return if (slot < flags.len) flags[slot] else .{};
    }

    /// A store into a local the check does not track: its value is read, and a write to an owner a running `match mut`
    /// arm holds is judged as for a tracked one (FX9).
    fn storeUntracked(c: *Checker, store: typed.Store, initializing: bool, span: Span) Error!void {
        try c.expression(store.value, .read);
        if (!initializing) try c.checkHeldOwnerWrite(@backingInt(store.slot), store.value, span);
    }

    /// Whether a write to `slot` under the `match mut` hold `loan` goes through that arm's own binding (C1): a binding of
    /// the arm or a receiver of its scrutinee, never the held owner itself, nor, for a write, an enclosing arm's binding
    /// the inner match matches (FX9).
    fn writesThroughBinding(c: *const Checker, loan: Loan, slot: usize, write: bool, matched: Span) bool {
        if (slot == loan.root or !c.exclusiveAccess(slot)) return false;
        return !write or !c.heldBinderFor(slot, matched);
    }

    /// Whether `slot` is a read-only borrow of a payload binding of the running `match mut` arm that `loan` holds, through
    /// a chain of definitions that ends at the binding or at the temporary of its receiver (`for e in value:` over a
    /// dictionary or a list of text binds `e` to an element of the binding). A read of such a borrow is a read of the
    /// binding, which the arm may always do; a change of the binding while the borrow is live is judged by the borrow's
    /// own loans, as for a `mut` local.
    fn borrowsFromBinding(c: *const Checker, loan: Loan, slot: usize) bool {
        if (slot == loan.root or !c.state[slot].traits.borrowed) return false;
        var current = slot;
        for (0..8) |_| {
            const definition = c.state[current].view_definition.node orelse c.definitions.get(@intCast(current)) orelse
                c.temporary_definitions.get(@intCast(current)) orelse return false;
            const lender = c.lenderLocal(definition, 0) orelse return false;
            if (c.exclusiveAccess(lender)) return true;
            current = lender;
        }
        return false;
    }

    /// Refuse a change through a `match mut` binding while a named borrow of its contents is still used: a loop variable
    /// over the binding, or a local bound to a part of it. A read of such a borrow is accepted (`borrowsFromBinding`), so the
    /// change that would invalidate it is the refusal, as for a `mut` local. The borrow is used when the statement the
    /// change lies in, or a later one of the block that declares the borrow, names it (a `const` alias has its own loan
    /// and is refused there).
    fn refuseWriteUnderBorrow(c: *Checker, loan: Loan, slot: usize, span: Span) Error!void {
        for (c.state, 0..) |state, other| {
            if (other == slot or !state.available or state.root != loan.root) continue;
            if (!c.namedBorrowOfBinding(loan, other) or !try c.usedFromHere(other)) continue;
            const names = c.function.scope.locals;
            const message = try std.fmt.allocPrint(
                c.diagnostics.allocator,
                "'{s}' is changed here while '{s}', a borrow of its contents, is still used; use '{s}' before this change, or take copy({s}) first",
                .{ names[loan.root].name, names[other].name, names[other].name, names[other].name },
            );
            c.failure.notes.related = .{ .span = names[other].declaration, .message = "borrowed here" };
            return c.reject(span, .{ .code = overlap_error, .rule = loan.rule }, message);
        }
    }

    /// Whether `slot` is a named local that borrows from the binding `loan` holds and has no loan of its own (a `const`
    /// alias has one, and is judged by it).
    fn namedBorrowOfBinding(c: *const Checker, loan: Loan, slot: usize) bool {
        const name = c.function.scope.locals[slot].name;
        if (name.len == 0 or name[0] == '<') return false;
        if (c.exclusiveAccess(slot) or !c.borrowsFromBinding(loan, slot)) return false;
        for (c.loans.items) |held| {
            if (held.binding == slot) return false;
        }
        return true;
    }

    /// Whether the statement now checked, or a later one of the block that declares `slot`, names it.
    fn usedFromHere(c: *Checker, slot: usize) Error!bool {
        const block = c.bindingBlock(slot) orelse return false;
        var index = block.index;
        while (index < block.items.len) : (index += 1) {
            if (try c.mentions(block.items[index], slot)) return true;
        }
        return false;
    }

    /// The local a place expression reads from, through fields, elements, block values and the owner of a collection
    /// operation, or null.
    fn lenderLocal(c: *const Checker, id: typed.NodeId, depth: usize) ?usize {
        if (depth > 32) return null;
        return switch (c.program.nodes[@backingInt(id)].data) {
            .local => |slot| @backingInt(slot),
            .field => |field| c.lenderLocal(field.base, depth + 1),
            .index => |index| c.lenderLocal(index.base, depth + 1),
            .block_value => |block| c.lenderLocal(block.value, depth + 1),
            .buffer_operation => |operation| @backingInt(operation.owner),
            else => null,
        };
    }

    /// Refuse a write to `slot`, an owner the check does not track (its type holds no managed value), while a running
    /// `match mut` arm holds it: the hold X2 keeps for every owner, until the arm's last use of a payload binding (FX9, the
    /// user's decision HOLD of 13 November). Reads of such an owner are not judged, as before.
    fn checkHeldOwnerWrite(c: *Checker, slot: usize, written: ?typed.NodeId, span: Span) Error!void {
        for (c.loans.items) |loan| {
            if (!loan.write or loan.hold != .matched) continue;
            if (loan.root != slot and !c.heldBinderFor(slot, loan.hold.matched)) continue;
            // A field write beside the matched place was accepted for such an owner and stays accepted.
            if (written) |value| if (c.heldPlace(loan.hold.matched)) |place| if (c.besidePlace(place, value)) continue;
            return c.loanConflict(loan, slot, true, .mutate, span);
        }
    }

    /// Select the existing refusal for one overlapping loan before preparing any source repair.
    fn loanConflict(c: *Checker, loan: Loan, slot: usize, write: bool, access: Access, span: Span) Error!void {
        const local = c.function.scope.locals[slot];
        const root = loan.root;
        const matched: ?Span = if (loan.hold == .matched) loan.hold.matched else null;
        // A `match mut` binding writes through to its container while its own arm's hold is live (C1). The held owner itself
        // is never written through: when it is the binding of an enclosing `match mut` (`match mut sh:` in a `boxed(inner=sh)`
        // arm), a write to it replaces the place the inner arm's bindings write into (FX9).
        if (matched != null and loan.write and c.writesThroughBinding(loan, slot, write, matched.?)) {
            if (write) try c.refuseWriteUnderBorrow(loan, slot, span);
            return;
        }
        if (matched != null and loan.write and access == .read and c.borrowsFromBinding(loan, slot)) return;
        if (matched != null and loan.write) {
            const owner = c.ownerName(loan.root, c.spanText(matched.?) orelse "the matched value");
            const advice = if (write) "move this write after that use, or write through the binding" else "move this access after that use";
            const message = try std.fmt.allocPrint(c.diagnostics.allocator, "'{s}' is written by a `match mut` arm that is running, until that arm's last use of a payload binding; {s}", .{ owner, advice });
            c.failure.notes.related = .{ .span = matched.?, .message = "written by this `match mut`" };
            return c.reject(span, .{ .code = overlap_error, .rule = loan.rule }, message);
        }
        if (loan.binding != none) return c.bindingOverlap(loan, span, access);
        // A change that overlaps a borrow of a source a live slice view of
        // which exists is the view's escape, whatever the collection family:
        // the reader gets the copy repair on the view's binding (W4). With no
        // live view the borrow conflict keeps its own message.
        // A move or change of a view binding itself is judged below; this is a
        // change to a *source* that a view of it would not survive.
        if (write and !c.sliceView(slot)) try c.escapeLiveView(root, span, access);
        const source = c.function.scope.locals[loan.root].name;
        if (loan.root != slot and !loan.write) {
            // A view whose root is the function's single borrowable parameter
            // returns even while a `match` on that parameter borrows it: the
            // payload is part of the parameter (REGRESSION-R5).
            if (access == .move and c.partOfBorrowableParameter(slot, loan.root)) return;
            if (!std.mem.startsWith(u8, local.name, "<") and !std.mem.startsWith(u8, source, "<")) {
                const advice = if (access == .move) try escape_message.movedBorrowAdvice(c.diagnostics.allocator, local.name, c.sink) else "copy it with copy(value)";
                const message = try std.fmt.allocPrint(c.diagnostics.allocator, "'{s}' borrows from '{s}'; {s} or finish the borrow first", .{ local.name, source, advice });
                if (access == .move) return c.rejectLocalCopy(slot, span, .{ .code = overlap_error, .rule = loan.rule }, message);
                return c.reject(span, .{ .code = overlap_error, .rule = loan.rule }, message);
            }
        }
        if (matched) |match_span| {
            // The place changed, as the source wrote it: never a lowering temporary's name (`<collection>`, FR80).
            const written = c.writtenPlace(loan, slot, span);
            const held = if (c.lendingCallSubject(match_span)) |subject| try std.fmt.allocPrint(
                c.diagnostics.allocator,
                "'{s}' lends the value that `match {s}:` is matching, and the running arm cannot change '{s}' while the " ++
                    "match borrows it; copy the matched value first (`match copy({s}):`) so the arm's payload is its own, " ++
                    "and assign that payload with `own`",
                .{ written, subject, written, subject },
            ) else if (if (write and access != .move) c.matchedPlaceWritten(loan, match_span, span) else null) |place| try std.fmt.allocPrint(
                c.diagnostics.allocator,
                "'{s}' is the value of a `match` whose arm is running, and a match on a named value keeps borrowing it; " ++
                    "`match mut {s}:` lets the arm change it: write through the payload binding, which names its place in {s}, " ++
                    "and an arm that binds nothing may assign {s} (docs/match-expressions.md, Mutable element matches)",
                .{ written, place, place, place },
            ) else try c.namedMatchMessage(loan, access, match_span, written);
            const result = if (access == .move and !loan.write) c.rejectLocalCopy(slot, span, .{ .code = overlap_error, .rule = loan.rule }, held) else c.reject(span, .{ .code = overlap_error, .rule = loan.rule }, held);
            c.failure.notes.related = .{ .span = match_span, .message = "borrowed by this match" };
            return result;
        }
        if (loan.hold == .scope) return c.scopeConflict(loan, slot, access, span);
        if (loan.rule == .M5 and loan.hold == .argument and c.argument.write)
            return c.mutArgumentConflict(loan, slot, span);
        if (loan.rule == .M5 and loan.hold == .argument and c.elementOverlap(loan)) return c.elementArgumentConflict(loan, slot, span);
        // A change of the owner of a list that a `for` loop is iterating: the repair is the loop over positions, not a copy. A move keeps
        // the copy repair below.
        if (iterationOf(loan, slot, access)) {
            if (try c.iterationLoopMessage(loan)) |loop_message| return c.reject(span, .{ .code = overlap_error, .rule = loan.rule }, loop_message);
        }
        const message = if (loan.rule == .M5 and loan.hold == .argument and local.ty.isAggregate() and c.program.records[local.ty.recordIndex()].isRecord())
            try c.recordArgumentMessage(loan, slot, span)
        else
            generic_overlap;
        if (access == .move and !loan.write) return c.rejectLocalCopy(slot, span, .{ .code = overlap_error, .rule = loan.rule }, message);
        return c.reject(span, .{ .code = overlap_error, .rule = loan.rule }, message);
    }

    /// Refuse a move or change of `slot` while a `with` scope opened from a provider it owns is open (F-37): name the
    /// scope's provider, and when that provider is a field (`holder.net`), the copy that gives a handle outside the record.
    fn scopeConflict(c: *Checker, loan: Loan, slot: usize, access: Access, span: Span) Error {
        const capability_field = c.scopeCapabilityField(loan.hold.scope);
        const owner = c.function.scope.locals[slot].name;
        const provider_span = loan.hold.scope;
        const src = c.source orelse return c.reject(span, .{ .code = overlap_error, .rule = loan.rule }, generic_overlap);
        if (provider_span.end > src.bytes.len or provider_span.start >= provider_span.end) return c.reject(span, .{ .code = overlap_error, .rule = loan.rule }, generic_overlap);
        const provider = src.text(provider_span);
        const verb = if (access == .move) "moved" else "changed";
        const held = try std.fmt.allocPrint(
            c.diagnostics.allocator,
            "'{s}' cannot be {s} while the `with` scope opened from `{s}` is open: the scope and every resource made from it " ++
                "borrow '{s}' until the `with` ends",
            .{ owner, verb, provider, owner },
        );
        const message = if (capability_field)
            try std.fmt.allocPrint(
                c.diagnostics.allocator,
                "{s}; `{s}` is a field of '{s}', so write `const handle = copy({s})` before the `with` and open the scope " ++
                    "from `handle`, a copy of the capability that is not part of '{s}' and reaches the same provider",
                .{ held, provider, owner, provider, owner },
            )
        else
            try std.fmt.allocPrint(c.diagnostics.allocator, "{s}; finish with the scope first", .{held});
        const result = c.reject(span, .{ .code = overlap_error, .rule = loan.rule }, message);
        c.failure.notes.related = .{ .span = provider_span, .message = "the scope's provider" };
        return result;
    }

    /// Whether the provider of a `with` scope, at `span`, is a capability read from a field: a copy of it is a shareable
    /// handle that is not part of the record (F-37).
    fn scopeCapabilityField(c: *const Checker, span: Span) bool {
        for (c.program.nodes) |node| {
            if (node.span.start != span.start or node.span.end != span.end) continue;
            if (node.data == .field and node.ty.capabilityIndex() != null) return true;
        }
        return false;
    }

    /// The source text of a `match` subject at `span` when it is a call (`json.get(here, key)`), whose result lends from
    /// its arguments, rather than a named place; null otherwise (F-47).
    /// The matched place `PLACE` of `match PLACE:` when `match mut PLACE:` is the spelling that lets the running arm change
    /// it (F-49): PLACE is a local, a field path of one, or an element `xs[...]` of a local list `xs`, and the write at
    /// `written` assigns PLACE or a part of it (its text begins with PLACE followed by ` =`, `.` or `[`). Null otherwise.
    fn matchedPlaceWritten(c: *const Checker, loan: Loan, matched: Span, written: Span) ?[]const u8 {
        const src = c.source orelse return null;
        if (matched.end > src.bytes.len or matched.start >= matched.end) return null;
        if (written.end > src.bytes.len or written.start >= src.bytes.len) return null;
        const place = src.text(matched);
        const root_end = std.mem.indexOfAny(u8, place, ".[") orelse place.len;
        if (!std.mem.eql(u8, place[0..root_end], c.function.scope.locals[loan.root].name)) return null;
        var index: usize = 0;
        var element = false;
        while (index < place.len) : (index += 1) {
            const byte = place[index];
            if (std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '.') continue;
            // One element step, `xs[...]` directly on the root, whose subscript is a name or a number.
            if (byte != '[' or index != root_end or place[place.len - 1] != ']') return null;
            for (place[index + 1 .. place.len - 1]) |inner| if (!std.ascii.isAlphanumeric(inner) and inner != '_') return null;
            element = true;
            break;
        }
        if (element) {
            const ty = c.function.scope.locals[loan.root].ty;
            if (!ty.isAggregate() or ty.recordIndex() >= c.program.records.len) return null;
            const record = c.program.records[ty.recordIndex()];
            if (!record.isCollection() or record.collection.kind != .list) return null;
        }
        const target = src.bytes[written.start..];
        if (!std.mem.startsWith(u8, target, place) or target.len == place.len) return null;
        const after = target[place.len..];
        if (after[0] == '.' or after[0] == '[') return place;
        if (!std.mem.startsWith(u8, after, " = ")) return null;
        // A whole replacement fits `match mut` when the arm binds nothing, or when it builds the case the arm matched,
        // which a write through the binding does in place; another case would replace what the binding names.
        const arm = armPattern(src.bytes, written.start) orelse return null;
        const open = std.mem.indexOfScalar(u8, arm, '(') orelse return place;
        const value = after[" = ".len..];
        const head_end = std.mem.indexOfScalar(u8, value, '(') orelse return null;
        const head = value[0..head_end];
        const case_name = if (std.mem.lastIndexOfScalar(u8, head, '.')) |dot| head[dot + 1 ..] else head;
        const arm_head = arm[0..open];
        const arm_case = if (std.mem.lastIndexOfScalar(u8, arm_head, '.')) |dot| arm_head[dot + 1 ..] else arm_head;
        return if (case_name.len != 0 and std.mem.eql(u8, case_name, arm_case)) place else null;
    }

    /// The pattern of the `case` line that opens the arm holding offset `at`: the text after `case ` on the nearest earlier
    /// line that begins, after its indentation, with `case ` and is indented less than the line at `at`; null when none is.
    fn armPattern(bytes: []const u8, at: usize) ?[]const u8 {
        const line_start = if (std.mem.lastIndexOfScalar(u8, bytes[0..at], '\n')) |nl| nl + 1 else 0;
        var limit = at - line_start;
        var end = line_start;
        while (end > 0) {
            const start = if (std.mem.lastIndexOfScalar(u8, bytes[0 .. end - 1], '\n')) |nl| nl + 1 else 0;
            const line = bytes[start .. end - 1];
            end = start;
            const text = std.mem.trimStart(u8, line, " ");
            const indent = line.len - text.len;
            if (text.len == 0 or indent >= limit) continue;
            limit = indent;
            if (std.mem.startsWith(u8, text, "case ")) return std.mem.trimEnd(u8, text["case ".len..], " :\r");
            if (std.mem.startsWith(u8, text, "match ")) return null;
        }
        return null;
    }

    /// The refusal of a change of `written` (as the source wrote it) while the plain `match` hold `loan` on a named place is
    /// live: it names the matched place and the place written, says why, and offers the repairs that apply (FR80).
    fn namedMatchMessage(c: *const Checker, loan: Loan, access: Access, match_span: Span, written: []const u8) Error![]const u8 {
        const subject = c.spanText(match_span) orelse written;
        // A local a call initialized (`const tried = attempt(src)`): matching the call transfers the payload.
        const definition = c.definitions.get(@intCast(loan.root));
        const from_call = if (definition) |value| c.program.nodes[@backingInt(value)].data == .call else false;
        if (from_call and std.mem.eql(u8, subject, c.function.scope.locals[loan.root].name)) return std.fmt.allocPrint(
            c.diagnostics.allocator,
            "'{s}' is the value of a `match` whose arm is running, and a match on a named value keeps borrowing it; " ++
                "a copy(value) here runs on every call or iteration, so match on the call that produces it (`match f(x):`) " ++
                "so the payload transfers, or test a bool or option before the match and make the call after it returns",
            .{written},
        );
        const verb = if (access == .move) "move" else "change";
        // A payload of no storage (numbers, flags) is copied when bound and holds nothing (`armHold`), so what stays refused
        // is a payload binding that reads the place it holds.
        const why = ", because the payload binding reads what it holds there";
        return std.fmt.allocPrint(
            c.diagnostics.allocator,
            "`match {s}:` borrows '{s}' until its running arm's last use of a payload binding, so this {s} of " ++
                "'{s}' is refused{s}; match a copy (`match copy({s}):`, cheap when the payload is numbers) " ++
                "or read what the arm needs into a local before the match and {s} '{s}' after it",
            .{ subject, c.ownerName(loan.root, subject), verb, written, why, subject, verb, written },
        );
    }

    /// The source text at `span`, or null when there is no source or the span is empty.
    fn spanText(c: *const Checker, span: Span) ?[]const u8 {
        const src = c.source orelse return null;
        if (span.end > src.bytes.len or span.start >= span.end) return null;
        return src.text(span);
    }

    /// The name of local `slot` for a message: `fallback` when it is a compiler temporary (`<collection>`).
    fn ownerName(c: *const Checker, slot: usize, fallback: []const u8) []const u8 {
        const name = c.function.scope.locals[slot].name;
        return if (name.len == 0 or name[0] == '<') fallback else name;
    }

    /// The place an access at `span` changes, as the source wrote it: the target of an assignment (`t.ints[n]` of
    /// `t.ints[n] = at`), the `mut` argument of a call (`t.seen` of `append(mut t.seen, n)`), else the name of the local
    /// accessed, or of its owner when that local is a compiler temporary.
    fn writtenPlace(c: *const Checker, loan: Loan, slot: usize, span: Span) []const u8 {
        const owner = c.ownerName(slot, c.ownerName(loan.root, "this value"));
        const text = c.spanText(span) orelse return owner;
        const line = text[0 .. std.mem.indexOfScalar(u8, text, '\n') orelse text.len];
        if (placeEnd(line)) |end| if (end != 0 and std.ascii.isAlphabetic(line[0])) {
            // `PLACE = value` or `PLACE += value`, never `PLACE == value`.
            const rest = std.mem.trimStart(u8, line[end..], " ");
            const operator = std.mem.indexOfNone(u8, rest, "+-*/%|&^<>") orelse rest.len;
            const assigns = operator < rest.len and rest[operator] == '=';
            if (assigns and !std.mem.startsWith(u8, rest[operator..], "==")) return line[0..end];
        };
        const marker = std.mem.indexOf(u8, line, "mut ") orelse return owner;
        if (marker == 0 or (line[marker - 1] != '(' and line[marker - 1] != ' ')) return owner;
        const argument = line[marker + "mut ".len ..];
        var depth: usize = 0;
        for (argument, 0..) |byte, index| switch (byte) {
            '(', '[' => depth += 1,
            ')', ']', ',' => {
                if (depth == 0) return if (index == 0) owner else argument[0..index];
                if (byte != ',') depth -= 1;
            },
            else => {},
        };
        return owner;
    }

    /// The offset of the first byte of `text` that cannot be part of a place (`t.ints[n]`), or null when every byte can.
    fn placeEnd(text: []const u8) ?usize {
        var depth: usize = 0;
        for (text, 0..) |byte, index| switch (byte) {
            '[' => depth += 1,
            ']' => depth -|= 1,
            else => {
                const name = std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '.';
                if (depth == 0 and !name) return index;
            },
        };
        return null;
    }

    fn lendingCallSubject(c: *const Checker, span: Span) ?[]const u8 {
        const src = c.source orelse return null;
        if (span.end > src.bytes.len or span.start >= span.end) return null;
        const text = src.text(span);
        const open = std.mem.indexOfScalar(u8, text, '(') orelse return null;
        if (open == 0 or text[text.len - 1] != ')') return null;
        // `copy(...)` makes a value of its own, which borrows nothing.
        if (std.mem.eql(u8, text[0..open], "copy")) return null;
        return text;
    }

    /// Why two arguments of one call cannot name overlapping parts of a record (M5): one passes the record, or a part that holds the
    /// other, and the callee can reach the second through the first. Different fields of one record are disjoint and never come here.
    fn recordArgumentMessage(c: *Checker, loan: Loan, slot: usize, span: Span) Error![]const u8 {
        const current = if (c.argument.value) |value| c.program.nodes[@backingInt(value)].span else span;
        const owner = c.function.scope.locals[loan.root].name;
        const earlier = try c.argumentText(loan.hold.argument, owner);
        const later = try c.argumentText(current, c.function.scope.locals[slot].name);
        if (loan.write) return std.fmt.allocPrint(
            c.diagnostics.allocator,
            "'{s}' reads '{s}', which the earlier argument '{s}' passes `mut`: the callee may change it, so the same call cannot also read it. " ++
                "Bind the value to a local before the call (`const value = {s}`), or pass the record itself `mut` and read it inside the callee",
            .{ later, owner, earlier, later },
        );
        return std.fmt.allocPrint(
            c.diagnostics.allocator,
            "'{s}' passes '{s}' whole, and the earlier argument '{s}' reads a part of it: the callee could change that part through the record. " ++
                "Pass the record itself `mut` and use both fields inside the callee, or pass a copy of the part (`copy({s})`)",
            .{ later, owner, earlier, earlier },
        );
    }

    /// Whether `loan` is the iteration loan (R7) of a `for` loop over a place inside `slot`, and the access changes `slot` in place:
    /// a move keeps the copy repair.
    fn iterationOf(loan: Loan, slot: usize, access: Access) bool {
        if (loan.rule != .R7 or loan.hold != .none or loan.binding != none) return false;
        return !loan.write and access != .move and loan.root == slot;
    }

    /// The loop variable and the iterable of the `for` loop that holds `loan`, as the loop writes them (`for name in st.names:`,
    /// `for dep in st.mf.nodes[n].deps:`), and the list's element type; null for a header of another form or a loop whose loan is gone.
    fn iteratedList(c: *Checker, loan: Loan) ?struct { name: []const u8, text: []const u8, element: ?typed.Type } {
        const src = c.source orelse return null;
        const place = loan.path orelse return null;
        var at = c.iterated.items.len;
        while (at != 0) {
            at -= 1;
            const entry = c.iterated.items[at];
            if (entry.loan >= c.loans.items.len or entry.span.start >= entry.span.end or entry.span.end > src.bytes.len) continue;
            const held = c.loans.items[entry.loan];
            if (held.root != loan.root or held.rule != .R7 or held.hold != .none or held.binding != none) continue;
            if (held.path == null or !c.samePath(held.path.?, place)) continue;
            const header = std.mem.trim(u8, std.mem.sliceTo(src.text(entry.span), '\n'), " \t");
            if (!std.mem.startsWith(u8, header, "for ") or !std.mem.endsWith(u8, header, ":")) return null;
            const inside = header["for ".len .. header.len - 1];
            const split = std.mem.indexOf(u8, inside, " in ") orelse return null;
            const name = std.mem.trim(u8, inside[0..split], " ");
            const text = std.mem.trim(u8, inside[split + " in ".len ..], " ");
            if (!writtenAs(name, "_") or !writtenAs(text, "_.[]")) return null;
            // A loan on a prefix of the written place (an element's field: `st.mf.nodes[n].deps`) was made on the type of that prefix.
            var steps: usize = 0;
            for (text) |byte| steps += @intFromBool(byte == '.' or byte == '[');
            return .{ .name = name, .text = text, .element = if (steps == place.steps.items.len) entry.element else null };
        }
        return null;
    }

    /// Whether `text` is not empty and holds only letters, digits and the characters of `extra`: a name or a place with no call in it.
    fn writtenAs(text: []const u8, extra: []const u8) bool {
        for (text) |byte| if (!std.ascii.isAlphanumeric(byte) and std.mem.indexOfScalar(u8, extra, byte) == null) return false;
        return text.len != 0;
    }

    /// The refusal of a change to `loan`'s owner while a `for` loop iterates a list inside it (W3-F-7, W4-F-6): the loop borrows the
    /// list until it ends. The repairs, in order: pass only the field the call changes; the `detach` loop (LOOPDETACH), which sets
    /// the list aside and puts it back at every exit; a loop over positions, which holds no borrow between its visits, where a scalar
    /// element is read as it is and any other is copied, one element at a time, not the list. Null when the iterable cannot be written out.
    fn iterationLoopMessage(c: *Checker, loan: Loan) Error!?[]const u8 {
        const list = c.iteratedList(loan) orelse return null;
        const owner = c.function.scope.locals[loan.root].name;
        const element = if (list.element) |known| (if (c.owns(known))
            try std.fmt.allocPrint(c.diagnostics.allocator, "`const {s} = copy({s}[k])`, which copies the one element, not the list", .{ list.name, list.text })
        else
            try std.fmt.allocPrint(c.diagnostics.allocator, "`const {s} = {s}[k]`", .{ list.name, list.text })) else try std.fmt.allocPrint(
            c.diagnostics.allocator,
            "`const {s} = {s}[k]`, written `copy({s}[k])` for a text, list or record element: it copies the one element, not the list",
            .{ list.name, list.text, list.text },
        );
        const message = try std.fmt.allocPrint(
            c.diagnostics.allocator,
            "'{s}' cannot be changed here while a `for` loop iterates `{s}`: the loop borrows it until it ends. If the call changes only " ++
                "another field of '{s}', pass that field (`mut {s}.field`). Or write `for {s} in detach {s}:`, which sets the list aside for " ++
                "the loop and puts it back at every exit; inside the loop `{s}` is empty. Or walk the list by position, which holds no " ++
                "borrow between visits: `mut k = 0`, `while k < len({s}):`, as its first line {s}, and `k += 1` as its last",
            .{ owner, list.text, owner, owner, list.name, list.text, list.text, list.text, element },
        );
        return message;
    }

    /// Whether the arguments in conflict reach their places through an element of a list: the earlier loan or the
    /// argument now checked has a list step in its path.
    fn elementOverlap(c: *const Checker, loan: Loan) bool {
        for ([_]?PlacePath{ loan.path, c.argument.path }) |maybe| if (maybe) |path| {
            for (path.steps.items) |step| if (step == .index) return true;
        };
        return false;
    }

    /// A read argument and an earlier mutable one that may name the same list element. Records and their fields have
    /// another message: two elements of a list, unlike two fields, are separate storage only when both indices are
    /// distinct literals, and the remedies are not the record's.
    fn elementArgumentConflict(c: *Checker, loan: Loan, slot: usize, span: Span) Error {
        const current = if (c.argument.value) |value| c.program.nodes[@backingInt(value)].span else span;
        const first = try c.argumentText(loan.hold.argument, c.function.scope.locals[loan.root].name);
        const second = try c.argumentText(current, c.function.scope.locals[slot].name);
        // The copy the remedy asks for is already written: it must be bound before the call, not inside it.
        const copied = std.mem.startsWith(u8, second, "copy(");
        const message = try std.fmt.allocPrint(
            c.diagnostics.allocator,
            "'{s}' may be the same list element as the mutable argument '{s}': two elements of one list are separate storage only " ++
                "when both indices are distinct literals. Bind a copy first (`const part = {s}{s}{s}`) and pass `part`, " ++
                "or pass the list `mut` and index both elements inside the callee",
            .{ second, first, if (copied) "" else "copy(", second, if (copied) "" else ")" },
        );
        const result = c.reject(current, .{ .code = overlap_error, .rule = .M5 }, message);
        c.failure.notes.related = .{ .span = loan.hold.argument, .message = "earlier mutable argument" };
        return result;
    }

    /// Keep mut advice at a statement boundary: an argument copy is not writable storage.
    fn mutArgumentConflict(c: *Checker, loan: Loan, slot: usize, span: Span) Error {
        const current = if (c.argument.value) |value| c.program.nodes[@backingInt(value)].span else span;
        const first = try c.argumentText(loan.hold.argument, c.function.scope.locals[loan.root].name);
        const second = try c.argumentText(current, c.function.scope.locals[slot].name);
        const ty = if (c.argument.value) |value| c.program.nodes[@backingInt(value)].ty else c.function.scope.locals[slot].ty;
        const independent = !resources.dependent(c.program, ty);
        const marker = if (c.owns(ty)) "own " else "";
        const message = if (independent) try std.fmt.allocPrint(
            c.diagnostics.allocator,
            "mutable argument '{s}' overlaps earlier argument '{s}'; mutable arguments must name disjoint storage. " ++
                "For a separate writable value, write `mut part = copy({s})`, pass `mut part` in this position, " ++
                "then write `{s} = {s}part` after the call",
            .{ second, first, second, second, marker },
        ) else try std.fmt.allocPrint(
            c.diagnostics.allocator,
            "mutable argument '{s}' overlaps earlier argument '{s}'; this value cannot be copied. " ++
                "Pass the owner once and perform both operations inside the callee, or use distinct owners",
            .{ second, first },
        );
        const result = c.reject(current, .{ .code = overlap_error, .rule = .M5 }, message);
        c.failure.notes.related = .{ .span = loan.hold.argument, .message = "earlier argument overlaps this mutable argument" };
        return result;
    }

    /// Render an argument place without its written mut prefix, retaining grouping.
    fn argumentText(c: *Checker, span: Span, fallback: []const u8) Error![]const u8 {
        const src = c.source orelse return fallback;
        if (span.start >= span.end or span.end > src.bytes.len) return fallback;
        const text = src.text(span);
        var start: usize = 0;
        while (start < text.len) {
            if (text[start] == '(' or std.ascii.isWhitespace(text[start])) {
                start += 1;
            } else if (text[start] == '#') {
                while (start < text.len and text[start] != '\n') : (start += 1) {}
            } else break;
        }
        if (!std.mem.startsWith(u8, text[start..], "mut")) return text;
        const end = start + 3;
        if (end == text.len) return text;
        if (!std.ascii.isWhitespace(text[end]) and text[end] != '(') return text;
        const suffix = std.mem.trimStart(u8, text[end..], " \t");
        return std.mem.concat(c.a, u8, &.{ text[0..start], suffix });
    }

    /// Select the smallest scalar source call enclosing the access that actually conflicts.
    fn receiverCall(c: *Checker, access: Span) Error!?Span {
        var selected: ?Span = null;
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .statement => {},
            .expression => |id| {
                const node = c.program.nodes[@backingInt(id)];
                if (node.data != .call and node.data != .invoke) continue;
                if (!node.ty.isInteger() and node.ty != .bool) continue;
                if (node.span.start > access.start or node.span.end < access.end) continue;
                if (selected == null or node.span.end - node.span.start < selected.?.end - selected.?.start) selected = node.span;
            },
        };
        return selected;
    }

    /// A change or move of an owner while a `const` binding borrows it (B7): refused until the binding's last use.
    fn bindingOverlap(c: *Checker, loan: Loan, span: Span, access: Access) Error {
        const binding = c.function.scope.locals[loan.binding];
        const owner = c.function.scope.locals[loan.root].name;
        const held = try std.fmt.allocPrint(c.diagnostics.allocator, "'{s}' cannot be changed or moved while '{s}' borrows it; use '{s}' before this change, or bind copy(value)", .{ owner, binding.name, binding.name });
        const copy = try c.bindingCopySource(loan, access);
        const result = if (copy) |initializer|
            c.rejectCopy(initializer, binding.ty, .{ .code = overlap_error, .rule = .R2 }, held)
        else if (access == .move and !loan.write)
            c.rejectLocalCopy(loan.root, span, .{ .code = overlap_error, .rule = .R2 }, held)
        else
            c.reject(span, .{ .code = overlap_error, .rule = .R2 }, held);
        // The owner access remains the conflict; only the repair targets its borrow's initializer.
        c.failure.span = span;
        c.failure.notes.related = .{ .span = binding.declaration, .message = "borrowed by this binding" };
        c.noteCollectionCause(loan.binding);
        c.notePlainCause(loan.binding);
        if (c.heldRecord(loan.binding)) |record| c.noteRecordCause(record);
        return result;
    }

    /// A named result's initializer can become independent before its known owners change.
    /// Temporary or writing loans have no such source repair.
    fn bindingCopySource(c: *Checker, loan: Loan, access: Access) Error!?Span {
        if (c.probing.active) return null;
        if (access != .mutate and access != .update) return null;
        if (loan.write) return null;
        const slot = loan.binding;
        const local = c.function.scope.locals[slot];
        if (local.mutable or local.usage.temporary or !c.namedBinding(slot)) return null;
        const state = c.state[slot];
        if (!state.available) return null;
        if (!state.traits.borrowed or state.traits.rule != .R3) return null;
        const definition = state.view_definition.node orelse return null;
        const roots = try c.localRoots(slot, 0);
        if (roots.temp or roots.unknown or roots.items.len == 0) return null;
        for (roots.items) |root| {
            if (root >= c.state.len) return null;
            if (!c.state[root].available or c.temporary(root)) return null;
            if (c.function.scope.locals[root].usage.temporary) return null;
        }
        if (!c.probeBindingCopy(slot, definition)) return null;
        return c.program.nodes[@backingInt(definition)].span;
    }

    /// Prove the exact copy's ownership effect against the complete function,
    /// including later aliases, wrapper returns and its written `from` contract.
    fn probeBindingCopy(c: *Checker, slot: usize, definition: typed.NodeId) bool {
        if (!c.copyRepairAvailable(definition)) return false;
        const patched = c.scratchMark();
        defer c.scratchRollback(patched);
        const rewritten = (c.bindingCopyProgram(slot, definition) catch return false) orelse return false;
        return c.proveRepair(rewritten, definition);
    }

    /// Whether `slot` is a borrowed `mut` local (4f) stored exactly once (D4, lane OC's H1): `mut c = place` with no other
    /// assignment. A local assigned more than once keeps its refusal at the store that needs `copy(...)` (`plainMutRefusal`).
    fn borrowedOnce(c: *Checker, slot: usize) Error!bool {
        if (slot >= c.borrowed_mut.len or !c.borrowed_mut[slot]) return false;
        var stores: usize = 0;
        var aliases: std.AutoHashMapUnmanaged(u32, typed.NodeId) = .empty;
        defer aliases.deinit(c.a);
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item != .statement) continue;
            const statement = c.program.statements[@backingInt(item.statement)].data;
            const store = switch (statement) {
                .initialize => |store| store,
                .assign => |store| store,
                else => continue,
            };
            if (statement == .initialize and store.unpack == null) try aliases.put(c.a, @intCast(@backingInt(store.slot)), store.value);
            if (@backingInt(store.slot) == slot and !writeThrough(c.program, &aliases, store, slot)) stores += 1;
        }
        return stores == 1;
    }

    /// Whether assignment `store` of local `slot` writes a field or an element of it in place (`writeThrough`), reading the
    /// receiver temporaries' initializers the checker recorded.
    fn writtenThrough(c: *Checker, store: typed.Store, slot: usize) bool {
        const base = switch (c.program.nodes[@backingInt(store.value)].data) {
            .update => |update| update.base,
            .replace => |replace| replace.base,
            else => return false,
        };
        var current = base;
        var depth: usize = 0;
        while (depth < 4) : (depth += 1) {
            const node = c.program.nodes[@backingInt(current)];
            if (node.data != .local) return false;
            const read = @backingInt(node.data.local);
            if (read == slot) return true;
            current = c.temporary_definitions.get(@intCast(read)) orelse c.definitions.get(@intCast(read)) orelse return false;
        }
        return false;
    }

    /// A write through a `mut` local that borrows the place it was stored from once (D4): refused at the write, naming the
    /// binding, its lender and both repairs at the binding (`own` when the place is a bare owner, `copy(...)`), with the copy
    /// as the structured fix when the copied function checks.
    fn rejectBorrowedWrite(c: *Checker, slot: usize, span: Span) Error {
        const local = c.function.scope.locals[slot];
        const definition = c.constBorrowedDefinition(slot) orelse
            return c.reject(span, .{ .code = borrow_error, .rule = .B9 }, "a `mut` local that borrows its place cannot be written; write `own` or `copy(...)` in its initializer");
        const initializer = c.program.nodes[@backingInt(definition)];
        const place = if (c.source) |src| if (initializer.span.start < initializer.span.end and initializer.span.end <= src.bytes.len) src.text(initializer.span) else local.name else local.name;
        const lenders = try c.lendersOf(slot);
        const lender = c.lenderOf(lenders[0]);
        const owner = lender == .local or lender == .own_parameter;
        // An element of an owner the function may change (W2): a copy would keep this write out of the element.
        const element = elementRead(c.program, definition) and (owner or lender == .mut_parameter);
        // The hidden owner of `for x in own SOURCE:` (F-16): its source lends the list, so the loop cannot take it. The
        // message names the loop's source, not the hidden owner, and offers no edit at a binding the source never wrote.
        if (std.mem.eql(u8, local.name, "consumed list")) {
            const lent_by = try escape_message.lenderText(c.diagnostics.allocator, lender);
            const returned = if (initializer.data == .call) " the call returns" else "";
            const consumed = try std.fmt.allocPrint(c.diagnostics.allocator, "a consuming loop cannot own `{s}`: the list{s} is lent by {s}, so taking it " ++
                "would leave its owner without it; write `for x in own copy({s}):` to own a copy, or `for x in {s}:` to read each element", .{ place, returned, lent_by, place, place });
            return c.reject(span, .{ .code = borrow_error, .rule = .B9 }, consumed);
        }
        const message = try escape_message.composeWrite(c.diagnostics.allocator, .{ .binding = local.name, .place = place, .lender = lender, .can_give = owner and initializer.data == .local, .element = element });
        const result = c.reject(span, .{ .code = borrow_error, .rule = .B9 }, message);
        if (c.probing.active) return result;
        // A binding written and then stored back into its own place (`mut item = items[i]`, `item.v = ...`, `items[i] = item`)
        // keeps the certain write-back repair the owning check finds (C6 (b)): the writes go to the element place itself.
        const written = c.failure.*;
        try c.plainMutRefusal(slot);
        if (c.failure.repair == .write_back) return result;
        // The code, rule and certain repair at the binding are the ones the binding gets as an owner, as before D4 (B2 for a
        // bare owner, R1, B7, B8, M1 or R3 for a lent place); only the place and the message move to the write.
        if (c.failure.code.len != 0 and c.failure.span.start != written.span.start) {
            // A refusal of the owning re-check elsewhere (a loop's hold, a later overlap) is the function's refusal, as it was.
            const at_binding = c.failure.span.start >= local.declaration.start and c.failure.span.end <= initializer.span.end;
            if (!at_binding) return result;
            c.failure.span = written.span;
            c.failure.message = written.message;
            c.failure.notes.related = null;
            // The copy is one of two meanings of the write, so it is no certain repair (W2).
            if (element) c.failure.copy = .{};
            return result;
        }
        c.failure.* = written;
        if (!element and c.probeBindingCopy(slot, definition)) c.failure.copy = .{ .span = initializer.span };
        return result;
    }

    /// A const alias cannot become an owner at its later use. Prefer moving
    /// its original bare initializer only when the function remains sound.
    fn rejectConstEscape(c: *Checker, slot: usize, span: Span, access: Access) Error!void {
        const name = c.function.scope.locals[slot].name;
        const lenders = try c.lendersOf(slot);
        if (c.borrowedMutOwner(slot) == null) if (c.heldRecord(slot)) |record| {
            const result = c.reject(span, .{ .code = "E_OWN_MARKER", .rule = .B9 }, try c.escapeMessageAmong(span, lenders, c.sink, .fields, name));
            c.noteRecordCause(record);
            return result;
        };
        if (c.borrowedMutOwner(slot)) |local| {
            const holder = c.function.scope.locals[local].name;
            const result = c.reject(span, .{ .code = "E_OWN_MARKER", .rule = .B9 }, try c.escapeMessageAmong(span, try c.lendersOf(local), c.sink, .{ .binding = .{ .each_assignment = holder } }, name));
            c.notePlainCause(local);
            return result;
        }
        // A binding of a nested pattern has no initializer to give or copy, and no edit that is local to its use is proved here:
        // the message names the pattern the author wrote and how to match its layers, and offers no fix.
        if (access == .move) if (try c.nestedPatternRepair(slot, lenders[0])) |repair| {
            return c.reject(span, .{ .code = "E_OWN_MARKER", .rule = .B9 }, try c.escapeMessageAmong(span, lenders, c.sink, .{ .binding = .{ .pattern = repair } }, name));
        };
        const give: escape_message.Repairs = .{ .binding = .{ .initializer = .{ .binding = name, .give = true } } };
        const result = c.reject(span, .{ .code = "E_OWN_MARKER", .rule = .B9 }, try c.escapeMessageAmong(span, lenders, c.sink, give, name));
        const definition = c.constBorrowedDefinition(slot) orelse return result;
        if (c.probing.active) {
            if (c.probing.needed_own) |needed| {
                needed.* = .{ .slot = slot, .definition = definition };
            }
            return result;
        }
        const node = c.program.nodes[@backingInt(definition)];
        if (c.typeDependentRepair(node)) return result;
        if (node.data == .local and c.probeOwn(definition, slot, null)) {
            if (c.source) |src| if (try own_marker.insert(c.diagnostics.allocator, src, node.span)) |edit| try c.markerFix(node, edit, .{ .id = definition, .slot = slot });
        } else {
            const ty = c.function.scope.locals[slot].ty;
            if (resources.dependent(c.program, ty)) return result;
            if (c.probeBindingCopy(slot, definition)) {
                c.failure.copy = .{ .span = node.span };
                c.failure.message = try c.escapeMessageAmong(span, lenders, c.sink, .{ .binding = .{ .initializer = .{ .binding = name, .give = false } } }, name);
                c.recoverAt(.{ .id = definition, .slot = slot }, .copy);
            }
        }
        return result;
    }

    /// The facts of the refusal of binding `slot` when the source binds it in a pattern that looks through more than one layer
    /// (`case Ok(Some(v)):`): the pattern as written, where the binding lies in it, and who can give the matched value's payloads.
    /// Null for any other binding.
    fn nestedPatternRepair(c: *Checker, slot: usize, lender: ?usize) Error!?escape_message.PatternBinding {
        const local = c.function.scope.locals[slot];
        if (!local.written()) return null;
        const src = c.source orelse return null;
        if (local.declaration.start >= local.declaration.end) return null;
        const found = pattern_message.casePattern(src.bytes, local.declaration.start) orelse return null;
        if (!try pattern_message.nested(c.diagnostics.allocator, found.text, found.at)) return null;
        const matched: pattern_message.Matched = switch (c.lenderOf(lender)) {
            .local, .own_parameter => |owner| if (pattern_message.hidden(owner)) .fresh else .{ .owner = owner },
            .plain_parameter, .mut_parameter => .lent,
            .matched, .unnamed, .fresh_record => .fresh,
        };
        return .{ .binding = local.name, .pattern = found.text, .at = found.at, .matched = matched };
    }

    /// The `mut` local holding a borrow (4f) whose borrow `slot` holds: the local itself, or a lowering temporary (a staged
    /// receiver) that took one of its assignments' borrows.
    fn borrowedMutOwner(c: *const Checker, slot: usize) ?usize {
        if (slot < c.borrowed_mut.len and c.borrowed_mut[slot]) return slot;
        const definition = c.constBorrowedDefinition(slot) orelse return null;
        switch (c.program.nodes[@backingInt(definition)].data) {
            .local => |read| if (c.borrowed_mut[@backingInt(read)]) return @backingInt(read),
            else => {},
        }
        for (c.borrowed_mut, 0..) |borrowed, local| if (borrowed) {
            for (c.state[local].view_definition.const_origins) |alternative| if (alternative.definition == definition) return local;
        };
        return null;
    }

    fn constBorrowedDefinition(c: *const Checker, slot: usize) ?typed.NodeId {
        const source = c.state[slot].view_definition;
        for (source.const_origins) |alternative| if (alternative.borrowed) return alternative.definition;
        return source.node;
    }

    /// Rechecking permits missing move markers and normalizes other escaping
    /// const aliases in the clone. Only a complete joint ownership proof offers
    /// the requested edit; availability, loans and return contracts still apply.
    /// `blocked`, when given, receives the refusal that stopped a failed proof (`proveRepairBlocked`).
    fn probeOwn(c: *Checker, definition: typed.NodeId, borrowed_slot: ?usize, blocked: ?*?Blocked) bool {
        return c.probeMarked(definition, borrowed_slot, true, blocked);
    }

    /// The proof of `probeOwn` with the marker flag of `definition` set to `own`: false proves the function as written, with the
    /// missing marker permitted as every re-check permits it.
    fn probeMarked(c: *Checker, definition: typed.NodeId, borrowed_slot: ?usize, own: bool, blocked: ?*?Blocked) bool {
        const patched = c.scratchMark();
        defer c.scratchRollback(patched);
        const program = c.withOwn(definition, own) catch return false;
        const locals = c.a.dupe(typed.Local, c.function.scope.locals) catch return false;
        if (borrowed_slot) |slot| locals[slot].ownership.view = false;
        var function = c.function;
        function.scope.locals = locals;
        return c.proveRepairBlocked(.{ .program = program, .function = function }, definition, blocked);
    }

    /// The refusal a failed repair proof stopped at and could not normalise: what `ownBeside` compares (FR61).
    const Blocked = struct { code: []const u8, rule: ?Rule, span: Span };

    /// FR61: the `own` marker at node `id` whose proof failed at refusal `marked`, written after the marker, is certain beside
    /// that refusal when the function as written (the marker missing, as a re-check permits) stops at the same refusal, so the marker did not cause
    /// it, and the moved local is used nowhere else and moved once per declaration (`movedOnce`), so nothing the re-check
    /// does not reach can read what the marker moves. `waits` when only the use test fails: the repair waits for that refusal.
    fn ownBeside(c: *Checker, id: typed.NodeId, marked: Blocked) Error!enum { proven, waits, caused } {
        const span = c.program.nodes[@backingInt(id)].span;
        // A refusal written before the marker, or at it, may be one the re-check meets before the marker's own checks.
        if (marked.span.start < span.end) return .caused;
        var unmarked: ?Blocked = null;
        if (c.probeMarked(id, null, false, &unmarked)) return .caused;
        const found = unmarked orelse return .caused;
        if (!std.mem.eql(u8, found.code, marked.code) or found.rule != marked.rule) return .caused;
        if (found.span.start != marked.span.start or found.span.end != marked.span.end) return .caused;
        return if (try c.movedOnce(id)) .proven else .waits;
    }

    /// Whether node `id` is a local that no other node of the function reads or assigns, and that no loop holding `id` but not
    /// the local's declaration moves twice: what `own` there moves is then never wanted again, wherever a re-check stops.
    fn movedOnce(c: *Checker, id: typed.NodeId) Error!bool {
        const node = c.program.nodes[@backingInt(id)];
        if (node.data != .local) return false;
        const slot = node.data.local;
        const declaration = c.function.scope.locals[@backingInt(slot)].declaration;
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .expression => |other| {
                const data = c.program.nodes[@backingInt(other)].data;
                if (other != id and data == .local and data.local == slot) return false;
            },
            .statement => |at| {
                const statement = c.program.statements[@backingInt(at)];
                switch (statement.data) {
                    .assign => |store| if (store.slot == slot) return false,
                    .loop, .range_loop => {
                        const holds = statement.span.start <= node.span.start and node.span.end <= statement.span.end;
                        const declares = statement.span.start <= declaration.start and declaration.end <= statement.span.end;
                        if (holds and !declares) return false;
                    },
                    else => {},
                }
            },
        };
        return true;
    }

    /// Compose exact existing repairs identified by an ownership refusal.
    /// The requested edit stays fixed, and every retry changes a distinct source
    /// occurrence before the whole function is checked again.
    fn proveRepair(c: *Checker, initial: BindingCopyProgram, requested: typed.NodeId) bool {
        return c.proveRepairBlocked(initial, requested, null);
    }

    /// `proveRepair` that writes to `blocked` the refusal it stops at when that refusal is not one it can normalise.
    fn proveRepairBlocked(c: *Checker, initial: BindingCopyProgram, requested: typed.NodeId, blocked: ?*?Blocked) bool {
        var rewritten = initial;
        var provisional: std.ArrayList(BindingOwn) = .empty;
        while (true) {
            var observed: RepairObservations = .{};
            const shared = c.probeShared(rewritten.program);
            checkFunction(c.a, shared, rewritten.function, &observed.failure, .{
                .active = true,
                .needed_own = &observed.needed_own,
                .needed_copy = &observed.needed_copy,
                .needed_removal = &observed.needed_removal,
                .moves = &observed.moves,
            }) catch |err| {
                if (err != error.Rejected) return false;
                if (observed.needed_removal) |definition| {
                    if (definition == requested) return false;
                    c.writeOwn(rewritten.program, definition, false) catch return false;
                    continue;
                }
                if (observed.needed_copy) |site| if (site.definition == requested) return false;
                if (!c.normalizeRepair(&rewritten, observed, &provisional)) {
                    const failure = observed.failure;
                    if (blocked) |out| out.* = .{ .code = failure.code, .rule = failure.rule, .span = failure.span };
                    return false;
                }
                continue;
            };
            return true;
        }
    }

    /// A refusal names either an existing borrow-copy repair or an unmarked
    /// transfer invalidated later. Successful written transfers remain fixed;
    /// dependent types and resources are never copy candidates.
    fn normalizeRepair(c: *Checker, rewritten: *BindingCopyProgram, observed: RepairObservations, provisional: *std.ArrayList(BindingOwn)) bool {
        var next = c.*;
        next.program = rewritten.program;
        next.function = rewritten.function;
        const failure = observed.failure;
        if (failure.rule == .B9) {
            const binding = observed.needed_own orelse return false;
            const value = rewritten.program.nodes[@backingInt(binding.definition)];
            if (value.own or value.type_dependent) return false;
            if (value.data != .local) {
                if (!next.copyRepairAvailable(binding.definition)) return false;
                rewritten.* = next.copyProgram(binding.definition, binding.slot) catch return false;
                return true;
            }
            provisional.append(c.a, binding) catch return false;
            c.writeOwn(rewritten.program, binding.definition, true) catch return false;
            @constCast(rewritten.function.scope.locals)[binding.slot].ownership.view = false;
            return true;
        }
        if (observed.needed_copy) |site| {
            if (!next.copyRepairAvailable(site.definition)) return false;
            rewritten.* = next.copyProgram(site.definition, site.borrowed_slot) catch return false;
            return true;
        }
        const unavailable = failure.rule == .B3 or failure.rule == .B6;
        const moved = if (unavailable) (failure.notes.related orelse return false).span else failure.span;
        var definition: ?typed.NodeId = null;
        if (unavailable) for (observed.moves.items) |candidate| {
            if (candidate.moved.start != moved.start or candidate.moved.end != moved.end) continue;
            if (definition != null and definition.? != candidate.definition) return false;
            definition = candidate.definition;
        };
        // A B9 initializer marked only by this proof may still need a copy.
        // Its attempted ownership can fail immediately when the source borrows.
        // Source-written markers and the requested edit never enter this list.
        for (provisional.items) |candidate| {
            const node = rewritten.program.nodes[@backingInt(candidate.definition)];
            if (!node.own or node.data != .local) continue;
            if (node.span.start != moved.start or node.span.end != moved.end) continue;
            if (definition != null and definition.? != candidate.definition) return false;
            definition = candidate.definition;
        }
        const target = definition orelse return false;
        if (!next.copyRepairAvailable(target)) return false;
        rewritten.* = next.copyProgram(target, null) catch return false;
        return true;
    }

    /// A rewritten program and function; `owned` when its node and statement tables were allocated for it (`rewriteCopy`).
    const BindingCopyProgram = struct { program: typed.Program, function: typed.Function, owned: bool = false };

    /// Model `copy(initializer)` with one evaluation, the same temporary and
    /// collection copy operation as source lowering. The checked tree stays untouched.
    fn bindingCopyProgram(c: *Checker, slot: usize, definition: typed.NodeId) Error!?BindingCopyProgram {
        const target = for (c.program.statements) |statement| {
            if (statement.data != .initialize) continue;
            if (statement.data.initialize.slot != @as(typed.LocalId, @fromBackingInt(slot))) continue;
            if (statement.data.initialize.value == definition) break true;
        } else false;
        if (!target) return null;
        const copied = try c.copyProgram(definition, slot);
        return copied;
    }

    /// Model a copy at one source occurrence without changing the checked tree.
    /// Its receiver is read once; the fresh result keeps later owner reads valid. With a scratch copy the rewrite is a patch of it,
    /// which the caller undoes (`scratchMark`, `scratchRollback`) when the proof it serves is done.
    fn copyProgram(c: *Checker, definition: typed.NodeId, borrowed_slot: ?usize) Error!BindingCopyProgram {
        return rewriteCopy(c.a, c.a, c.scratch, .{ .program = c.program, .function = c.function }, definition, borrowed_slot);
    }

    /// The program and function of `from` with the node `definition` replaced by a block that copies it into a new temporary local.
    /// The tables are a patch of `scratch` when it can take one (nothing is allocated for them), else a copy of `from`'s allocated
    /// from `tables`, which whoever owns `tables` frees (`BindingCopyProgram.owned`, `Tables.release`). The rest is allocated from `a`.
    fn rewriteCopy(a: std.mem.Allocator, tables: std.mem.Allocator, scratch: ?*Scratch, from: BindingCopyProgram, definition: typed.NodeId, borrowed_slot: ?usize) error{OutOfMemory}!BindingCopyProgram {
        const old = from.function.scope.locals;
        const source = from.program;
        const original = source.nodes[@backingInt(definition)];
        const ty = original.ty;
        const span = original.span;
        const locals = try a.alloc(typed.Local, old.len + 1);
        @memcpy(locals[0..old.len], old);
        if (borrowed_slot) |slot| locals[slot].ownership.view = false;
        const temporary_slot: typed.LocalId = @fromBackingInt(old.len);
        locals[old.len] = .{ .name = "<copy-repair>", .ty = ty, .declaration = span, .mutable = false, .usage = .{ .temporary = true } };
        const initialize: typed.StatementId = @fromBackingInt(source.statements.len);
        const body = try a.dupe(typed.StatementId, &.{initialize});
        const patched = if (scratch) |shared| try shared.extend(source, definition) else null;
        const pair: Scratch.TablePair = patched orelse try copyTables(tables, source);
        const nodes = pair.nodes;
        const statements = pair.statements;
        const receiver: typed.NodeId = @fromBackingInt(source.nodes.len);
        nodes[@backingInt(receiver)] = original;
        nodes[@backingInt(receiver)].own = false;
        const copied: typed.NodeId = @fromBackingInt(source.nodes.len + 1);
        nodes[@backingInt(copied)] = .{ .ty = ty, .span = span, .data = .{ .buffer_operation = .{ .kind = .copy, .owner = temporary_slot, .arguments = &.{} } } };
        statements[@backingInt(initialize)] = .{ .span = span, .terminates = false, .data = .{ .initialize = .{ .slot = temporary_slot, .value = receiver } } };
        const block: typed.StatementId = @fromBackingInt(source.statements.len + 1);
        statements[@backingInt(block)] = .{ .span = span, .terminates = false, .data = .{ .block = body } };
        nodes[@backingInt(definition)] = .{ .ty = ty, .span = span, .data = .{ .block_value = .{ .body = block, .value = copied } } };
        var program = source;
        program.nodes = nodes;
        program.statements = statements;
        var function = from.function;
        function.scope.locals = locals;
        return .{ .program = program, .function = function, .owned = patched == null };
    }

    /// Copies of `program`'s node and statement tables with two entries more each, allocated from `tables`. The two are the last
    /// allocations, so a failed second one releases the first and nothing else is held.
    fn copyTables(tables: std.mem.Allocator, program: typed.Program) error{OutOfMemory}!Scratch.TablePair {
        const nodes = try tables.alloc(typed.Node, program.nodes.len + 2);
        const statements = tables.alloc(typed.Statement, program.statements.len + 2) catch |err| {
            tables.free(nodes);
            return err;
        };
        @memcpy(nodes[0..program.nodes.len], program.nodes);
        @memcpy(statements[0..program.statements.len], program.statements);
        return .{ .nodes = nodes, .statements = statements };
    }

    /// Where the scratch copy stands now, for `scratchRollback` to return to when the rewrites a probe made are not needed any more.
    fn scratchMark(c: *const Checker) ?Scratch.Extent {
        return if (c.scratch) |scratch| scratch.mark() else null;
    }

    /// Undo the patches made to the scratch copy since `at`.
    fn scratchRollback(c: *const Checker, at: ?Scratch.Extent) void {
        if (c.scratch) |scratch| scratch.rollback(at.?);
    }

    /// The program with the marker flag of node `id` set to `own`: a patch of the scratch copy when it can take one (the caller
    /// undoes it with `scratchRollback`), else a private copy of the nodes allocated from `c.a`.
    fn withOwn(c: *Checker, id: typed.NodeId, own: bool) error{OutOfMemory}!typed.Program {
        if (c.scratch) |scratch| if (scratch.adopt(c.program, 0, 0)) |view| {
            try scratch.setOwn(@backingInt(id), own);
            return view;
        };
        const nodes = try c.a.dupe(typed.Node, c.program.nodes);
        nodes[@backingInt(id)].own = own;
        var program = c.program;
        program.nodes = nodes;
        return program;
    }

    /// A node and the id it replaces, for `withNodes`.
    const NodePatch = struct { id: typed.NodeId, node: typed.Node };

    /// The program with two nodes replaced: a patch of the scratch copy when it can take one (the caller undoes it with
    /// `scratchRollback`), else a private copy of the nodes allocated from `c.a`.
    fn withNodes(c: *Checker, first: NodePatch, second: NodePatch) error{OutOfMemory}!typed.Program {
        if (c.scratch) |scratch| if (scratch.adopt(c.program, 0, 0)) |view| {
            try scratch.setNode(@backingInt(first.id), first.node);
            try scratch.setNode(@backingInt(second.id), second.node);
            return view;
        };
        const nodes = try c.a.dupe(typed.Node, c.program.nodes);
        nodes[@backingInt(first.id)] = first.node;
        nodes[@backingInt(second.id)] = second.node;
        var program = c.program;
        program.nodes = nodes;
        return program;
    }

    /// Write the marker flag of node `id` of a rewritten program: in the scratch copy (journaled) when the program's tables are
    /// its, else in the program's own tables, which are private to the probe.
    fn writeOwn(c: *const Checker, program: typed.Program, id: typed.NodeId, own: bool) error{OutOfMemory}!void {
        if (c.scratch) |scratch| if (scratch.holds(program)) return scratch.setOwn(@backingInt(id), own);
        @constCast(program.nodes)[@backingInt(id)].own = own;
    }

    /// Copy repairs remain explicit and must preserve the complete ownership
    /// contract, including later carrier reads, loops and borrowed returns.
    fn probeMoveCopy(c: *Checker, definition: typed.NodeId) bool {
        if (!c.copyRepairAvailable(definition)) return false;
        const patched = c.scratchMark();
        defer c.scratchRollback(patched);
        const rewritten = c.copyProgram(definition, null) catch return false;
        return c.proveRepair(rewritten, definition);
    }

    /// A modeled builtin copy must have the same meaning when written in source.
    /// Requirement uses of `copy` do not claim the name; declarations and bindings do.
    fn copyRepairAvailable(c: *Checker, definition: typed.NodeId) bool {
        const node = c.program.nodes[@backingInt(definition)];
        if (c.typeDependentRepair(node) or resources.dependent(c.program, node.ty)) return false;
        const src = c.source orelse return false;
        if (c.copy_claim) |known| return !known.claimed(c.a, src.bytes);
        return !(language.lexer.claimsName(c.a, src.bytes, "copy") catch return false);
    }

    /// Compose existing borrow-copy repairs only at the exact failed move.
    /// Successful written transfers remain fixed; a marker already refused as
    /// a borrow can use its existing copy replacement during the joint proof.
    fn noteBorrowCopy(c: *Checker, id: typed.NodeId, access: Access) void {
        if (!c.probing.active or access != .move) return;
        const needed = c.probing.needed_copy orelse return;
        const copy = c.failure.copy.span orelse return;
        switch (c.failure.rule orelse return) {
            .R1, .M1, .B7, .X1 => {},
            else => return,
        }
        const node = c.program.nodes[@backingInt(id)];
        if (node.span.start != c.failure.span.start or node.span.end != c.failure.span.end) return;
        if (node.data == .local and !c.namedBinding(@backingInt(node.data.local))) return;
        if (node.own) {
            const src = c.source orelse return;
            _ = own_marker.remove(src, node.span) orelse return;
            if (node.data == .local) {
                if (copy.start >= copy.end or copy.end > src.bytes.len) return;
                if (!std.mem.eql(u8, src.text(copy), c.function.scope.locals[@backingInt(node.data.local)].name)) return;
            } else if (copy.start != node.span.start or copy.end != node.span.end) return;
        } else if (copy.start != node.span.start or copy.end != node.span.end) return;
        needed.* = .{ .definition = id };
    }

    /// Recognize a complete source subscript, separating an element from a
    /// contiguous slice. Calls and generated operations with call spans fail closed.
    fn sourceSubscript(c: *Checker, span: Span, slice: bool) bool {
        const src = c.source orelse return false;
        if (span.start >= span.end or span.end > src.bytes.len) return false;
        var sink: language.diagnostic.Sink = .{ .allocator = c.a };
        const tokens = language.lexer.lexRange(c.a, src.bytes, span, &sink) catch return false;
        if (tokens.len < 4 or (tokens[0].tag != .ident and tokens[0].tag != .lparen)) return false;
        var depth: usize = 0;
        var bracket = false;
        var colons: usize = 0;
        var closed: ?usize = null;
        for (tokens, 0..) |token, index| switch (token.tag) {
            .lparen, .lbrace => depth += 1,
            .lbracket => {
                if (depth == 0) {
                    bracket = true;
                    colons = 0;
                }
                depth += 1;
            },
            .rparen, .rbrace, .rbracket => {
                if (depth == 0) return false;
                depth -= 1;
                if (depth == 0 and token.tag == .rbracket) {
                    closed = index;
                    bracket = false;
                }
            },
            .colon => {
                if (bracket and depth == 1) colons += 1 else if (depth == 0) return false;
            },
            .ident, .dot, .eof => {},
            else => if (depth == 0) return false,
        };
        return depth == 0 and closed != null and closed.? + 2 == tokens.len and colons == @as(usize, if (slice) 1 else 0);
    }

    /// The scalar helper has the same view-copy repair as a subscript. Require
    /// its complete source call and canonical receiver setup plus slice result.
    fn sourceScalarSlice(c: *Checker, id: typed.NodeId) bool {
        const node = c.program.nodes[@backingInt(id)];
        if (node.data != .block_value) return false;
        const result = c.program.nodes[@backingInt(node.data.block_value.value)];
        if (!result.view or result.data != .buffer_operation) return false;
        if (!std.meta.eql(result.span, node.span) or result.ty != node.ty) return false;
        const operation = result.data.buffer_operation;
        if (operation.kind != .slice and operation.kind != .text_tail) return false;
        const body = c.program.statements[@backingInt(node.data.block_value.body)].data;
        if (body != .block or body.block.len != 1 or !c.temporary(@backingInt(operation.owner))) return false;
        const setup = c.program.statements[@backingInt(body.block[0])].data;
        if (setup != .initialize or setup.initialize.slot != operation.owner) return false;
        const src = c.source orelse return false;
        if (node.span.start >= node.span.end or node.span.end > src.bytes.len) return false;
        var sink: language.diagnostic.Sink = .{ .allocator = c.a };
        const tokens = language.lexer.lexRange(c.a, src.bytes, node.span, &sink) catch return false;
        if (tokens.len < 7) return false;
        if (tokens[0].tag != .ident or tokens[1].tag != .dot or tokens[2].tag != .ident or tokens[3].tag != .lparen) return false;
        if (!std.mem.eql(u8, src.text(tokens[0].span), "strings") or !std.mem.eql(u8, src.text(tokens[2].span), "char_slice")) return false;
        var depth: usize = 0;
        for (tokens[3 .. tokens.len - 1], 3..) |token, index| switch (token.tag) {
            .lparen => depth += 1,
            .rparen => {
                if (depth == 0) return false;
                depth -= 1;
                if (depth == 0 and index + 2 != tokens.len) return false;
            },
            else => {},
        };
        return depth == 0 and tokens[tokens.len - 2].tag == .rparen;
    }

    /// A source element copy wraps the whole subscript, including its setup.
    /// A hidden read in that setup is not repaired by copying the final result.
    fn noteReadCopy(c: *Checker, id: typed.NodeId, access: Access) void {
        if (!c.probing.active or access != .move or c.failure.rule != .B7) return;
        const boundary = c.copy_boundary orelse return;
        if (!boundary.result) return;
        const root = c.program.nodes[@backingInt(boundary.definition)];
        if (typed.requiresHandling(root.ty, c.program.records) or !c.sourceSubscript(root.span, false)) return;
        var current = boundary.definition;
        var remaining = c.program.nodes.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            const node = c.program.nodes[@backingInt(current)];
            if (node.own or node.type_dependent) return;
            if (node.ty != root.ty or !std.meta.eql(node.span, root.span)) return;
            if (current == id) break;
            if (node.data != .block_value) return;
            current = node.data.block_value.value;
        } else return;
        const value = c.program.nodes[@backingInt(id)];
        if (value.data != .index and (value.data != .buffer_operation or value.data.buffer_operation.kind != .read)) return;
        c.noteBorrowCopy(boundary.definition, access);
    }

    /// Compose direct slices and the canonical scalar helper's owning-store
    /// copy. Named views, other calls, Results and ambiguous spans stay manual.
    fn noteSliceCopy(c: *Checker, slot: usize, value: typed.NodeId) void {
        if (!c.probing.active or c.failure.rule != .V2) return;
        const needed = c.probing.needed_copy orelse return;
        const copy = c.failure.copy.span orelse return;
        const node = c.program.nodes[@backingInt(value)];
        if (c.copy_boundary) |boundary| {
            if (!boundary.result) return;
            const outer = c.program.nodes[@backingInt(boundary.definition)];
            if (std.meta.eql(outer.span, node.span) and boundary.definition != value) return;
        }
        if (node.own or node.type_dependent or typed.requiresHandling(node.ty, c.program.records)) return;
        if (!std.meta.eql(node.span, copy) or !std.meta.eql(node.span, c.failure.span)) return;
        if (!c.sourceSubscript(node.span, true) and !c.sourceScalarSlice(value)) return;
        if (c.sliceNodeFamily(value, 0, .any) == null and c.listSliceSource(value) == null) return;
        needed.* = .{ .definition = value, .borrowed_slot = slot };
    }

    /// Compose one existing mixed-return copy only for a bare source local.
    /// Contracts, wrappers and shared generated occurrences retain their refusal.
    fn noteMixedCopy(c: *Checker) void {
        if (!c.probing.active or c.failure.rule != .R5) return;
        const needed = c.probing.needed_copy orelse return;
        if (return_borrow.effectiveSources(c.program.records, c.function.signature).len != 0) return;
        if (c.failure.copy.borrowed.len == 0) return;
        const span = c.failure.copy.borrowed[0];
        const src = c.source orelse return;
        var candidate: ?typed.NodeId = null;
        for (c.returns.borrowed_values.items) |value| {
            const node = c.program.nodes[@backingInt(value)];
            if (!std.meta.eql(node.span, span)) continue;
            if (node.data != .local or node.own or node.type_dependent or typed.requiresHandling(node.ty, c.program.records)) return;
            const slot = @backingInt(node.data.local);
            if (!c.namedBinding(slot) or !std.mem.eql(u8, src.text(span), c.function.scope.locals[slot].name)) return;
            if (candidate != null and candidate.? != value) return;
            candidate = value;
        }
        const definition = candidate orelse return;
        var walker = typed_walk.Walker.init(c.a, c.program, c.function.scope.body) catch return;
        defer walker.deinit();
        var occurrences: usize = 0;
        while (walker.next() catch return) |item| switch (item) {
            .expression => |id| if (std.meta.eql(c.program.nodes[@backingInt(id)].span, span)) {
                if (id != definition) return;
                occurrences += 1;
                if (occurrences != 1) return;
            },
            else => {},
        };
        if (occurrences == 1) needed.* = .{ .definition = definition };
    }

    /// The refusal text for a borrowed value that is stored or returned: the Escape message (`escape_message.zig`). The lent value
    /// is the use the source spells at `span`; a borrowed binding is lent by the root it borrows from, and a parameter by itself.
    /// A borrowed binding cannot be given away, so the copy is the only repair.
    fn borrowedStoreMessage(c: *Checker, slot: usize, span: Span) Error![]const u8 {
        return escape_message.compose(c.diagnostics.allocator, try c.borrowedStoreFacts(slot, span));
    }

    /// NARROW-OWN: a bare read of an owner narrowed to `Some` that a store refused (`slot` holds the payload the read in place
    /// binds, `span` is the written name). `own NAME` moves the payload out of an owner the function owns, so the message offers
    /// it before the copy; its edit is the repair where no later line reads the owner and no loop the owner was declared outside
    /// of runs the read again, as the repairs of a missing `own` decide.
    fn narrowedOwnRepair(c: *Checker, slot: usize, span: Span) Error!void {
        if (c.probing.active) return;
        const src = c.source orelse return;
        const owner = (try c.narrowedOwner(slot, span)) orelse return;
        var lenders = try c.lendersOf(slot);
        if (lenders[0] == null) lenders[0] = owner;
        const facts = try c.escapeFacts(span, lenders, c.sink, .{ .give_or_copy = .{} }, c.function.scope.locals[slot].name);
        c.failure.message = try escape_message.compose(c.diagnostics.allocator, facts);
        if (try c.readAfter(owner, span) or try c.loopAround(owner, span)) return;
        const edit = (try own_marker.insert(c.diagnostics.allocator, src, span)) orelse return;
        c.failure.copy = .{};
        c.failure.repair = .{ .explicit_fix = try c.diagnostics.allocator.dupe(language.diagnostic.Edit, &.{edit}) };
    }

    /// The owner a refused payload `slot` was narrowed from, when the source writes that owner bare at `span` and the function
    /// owns it (a local or an `own` parameter); null for any other slot.
    fn narrowedOwner(c: *Checker, slot: usize, span: Span) Error!?usize {
        if (!std.mem.startsWith(u8, c.function.scope.locals[slot].name, "<")) return null;
        const owner = c.rootOf(slot);
        if (owner == slot) return null;
        const local = c.function.scope.locals[owner];
        const own_parameter = owner < c.function.scope.own_parameters.len and c.function.scope.own_parameters[owner];
        const parameter = owner < c.function.signature.parameter_count;
        if (parameter and !own_parameter) return null;
        if (!parameter and local.origin != .local) return null;
        const src = c.source orelse return null;
        if (span.end > src.bytes.len or !std.mem.eql(u8, src.text(span), local.name)) return null;
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item != .expression) continue;
            const node = c.program.nodes[@backingInt(item.expression)];
            if (node.span.start != span.start or node.span.end != span.end) continue;
            const read = language.option_flow.narrowedRead(c.program.nodes, c.program.statements, item.expression) orelse continue;
            const value = c.program.nodes[@backingInt(node.data.block_value.value)];
            if (@backingInt(read) == owner and value.data == .local and @backingInt(value.data.local) == slot) return owner;
        }
        return null;
    }

    /// Whether the function reads local `owner` after `span`.
    fn readAfter(c: *Checker, owner: usize, span: Span) Error!bool {
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item != .expression) continue;
            const node = c.program.nodes[@backingInt(item.expression)];
            if (node.data == .local and @backingInt(node.data.local) == owner and node.span.start >= span.end) return true;
        }
        return false;
    }

    /// Whether a loop that starts after local `owner` is declared holds `span`, so it could run the read again.
    fn loopAround(c: *Checker, owner: usize, span: Span) Error!bool {
        const declared = c.function.scope.locals[owner].declaration.start;
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item != .statement) continue;
            const statement = c.program.statements[@backingInt(item.statement)];
            if (statement.data != .loop and statement.data != .range_loop) continue;
            if (statement.span.start > declared and statement.span.start <= span.start and span.end <= statement.span.end) return true;
        }
        return false;
    }

    fn borrowedStoreFacts(c: *Checker, slot: usize, span: Span) Error!escape_message.Facts {
        var lenders = try c.lendersOf(slot);
        if (lenders[0] == null) lenders[0] = c.rootOf(slot);
        return c.escapeFacts(span, lenders, c.sink, .copy, c.function.scope.locals[slot].name);
    }

    /// COPY-B1: a bare plain parameter, or a field of one, that a store refused and told to copy: when the function checks with the
    /// parameter taken `own` and the value written `own`, the message names that form first and the copy second. The text is the only
    /// change: the verdict, the code, the span and the structured copy repair stay as the refusal set them.
    fn takeParameterMessage(c: *Checker, id: typed.NodeId) Error!void {
        if (c.probing.active or c.failure.copy.span == null) return;
        const node = c.program.nodes[@backingInt(id)];
        if (node.own or node.type_dependent or resources.dependent(c.program, node.ty)) return;
        const src = c.source orelse return;
        const slot = c.plainParameterOf(id) orelse return;
        var facts = switch (node.data) {
            .local => try c.borrowedStoreFacts(slot, node.span),
            .field => |field| try c.escapeFacts(node.span, .{ c.origin(field.base), null }, c.sink, .copy, ""),
            else => return,
        };
        const plain = try escape_message.compose(c.diagnostics.allocator, facts);
        if (!std.mem.eql(u8, plain, c.failure.message) or !c.probeTakeParameter(id, slot)) return;
        facts.form = .{ .take_parameter = .{ .parameter = c.function.scope.locals[slot].name, .declared = c.ownDeclaration(src, slot) } };
        c.failure.message = try escape_message.compose(c.diagnostics.allocator, facts);
    }

    /// The plain parameter a whole local or a chain of fields reads, or null for any other lender.
    fn plainParameterOf(c: *Checker, id: typed.NodeId) ?usize {
        var current = id;
        while (true) switch (c.program.nodes[@backingInt(current)].data) {
            .field => |field| current = field.base,
            .local => |slot| {
                const index: usize = @backingInt(slot);
                if (index >= c.function.signature.parameter_count) return null;
                return switch (c.lenderOf(index)) {
                    .plain_parameter => index,
                    else => null,
                };
            },
            else => return null,
        };
    }

    /// The declaration of parameter `slot` as the source spells it with `own` before it (`own name: str`): its name and the type up to
    /// the `,`, `)` or `=` that ends it outside any brackets. Null when the source is not at hand or does not spell it so.
    fn ownDeclaration(c: *Checker, src: language.source.Source, slot: usize) ?[]const u8 {
        const local = c.function.scope.locals[slot];
        const start: usize = local.declaration.start;
        if (start >= src.bytes.len or !std.mem.startsWith(u8, src.bytes[start..], local.name)) return null;
        var at = start + local.name.len;
        while (at < src.bytes.len and src.bytes[at] == ' ') at += 1;
        if (at >= src.bytes.len or src.bytes[at] != ':') return null;
        const colon = at;
        var depth: usize = 0;
        at += 1;
        while (at < src.bytes.len) : (at += 1) switch (src.bytes[at]) {
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => {
                if (depth == 0) break;
                depth -= 1;
            },
            ',', '=', '\n' => if (depth == 0) break,
            else => {},
        };
        const type_text = std.mem.trim(u8, src.bytes[colon + 1 .. at], " \t\r");
        if (type_text.len == 0) return null;
        return std.fmt.allocPrint(c.diagnostics.allocator, "own {s}: {s}", .{ local.name, type_text }) catch null;
    }

    /// Whether the function checks with parameter `slot` taken `own` and the value `id` written `own`, as the repairs a message
    /// names are proven: a refusal of another store that has a copy repair of its own is repaired with it, and nothing else is.
    fn probeTakeParameter(c: *Checker, id: typed.NodeId, slot: usize) bool {
        const patched = c.scratchMark();
        defer c.scratchRollback(patched);
        const program = c.withOwn(id, true) catch return false;
        const locals = c.a.dupe(typed.Local, c.function.scope.locals) catch return false;
        locals[slot].ownership.view = false;
        const own = c.a.alloc(bool, @max(c.function.signature.parameter_count, c.function.scope.own_parameters.len)) catch return false;
        @memset(own, false);
        @memcpy(own[0..c.function.scope.own_parameters.len], c.function.scope.own_parameters);
        own[slot] = true;
        var function = c.function;
        function.scope.locals = locals;
        function.scope.own_parameters = own;
        return c.proveRepair(.{ .program = program, .function = function }, id);
    }

    /// The named local that lends: a temporary the lowering made stands for the value it was initialized with, so the lender is
    /// what that value reads. Null when no named local does.
    fn namedLender(c: *Checker, slot: ?usize) ?usize {
        var current = slot orelse return null;
        var remaining: usize = 8;
        while (std.mem.startsWith(u8, c.function.scope.locals[current].name, "<")) {
            if (remaining == 0) return null;
            remaining -= 1;
            const definition = c.temporary_definitions.get(@intCast(current)) orelse c.definitions.get(@intCast(current)) orelse return null;
            current = c.origin(definition) orelse return null;
        }
        return current;
    }

    /// Whether `slot` is the hidden owner the lowering makes for a fresh record whose field a slice or a length reads: a
    /// compiler temporary of a record type that is not a text, bytes or list.
    fn hiddenRecord(c: *const Checker, slot: usize) bool {
        const local = c.function.scope.locals[slot];
        if (!std.mem.startsWith(u8, local.name, "<") or !local.ty.isAggregate()) return false;
        if (local.ty.recordIndex() >= c.program.records.len) return false;
        return !c.program.records[local.ty.recordIndex()].isCollection();
    }

    /// Who lends the storage of local `slot`: a parameter by its mode, a local by its name, a temporary by none.
    /// A hidden record whose value a named local lends (a call's result declared `from` a parameter) is that local's loan,
    /// not a fresh record (FX14): the message names the lender, as it did before the record had a hidden owner.
    fn lenderOf(c: *Checker, slot: ?usize) escape_message.Lender {
        const fresh: escape_message.Lender = if (slot != null and c.hiddenRecord(slot.?)) .fresh_record else .unnamed;
        const index = c.namedLender(slot) orelse return fresh;
        const local = c.function.scope.locals[index];
        if (std.mem.startsWith(u8, local.name, "<")) return fresh;
        // The compiler's own local for a layer of a nested pattern has no name the author wrote: name the pattern instead.
        if (pattern_message.hidden(local.name)) {
            const src = c.source orelse return fresh;
            const found = pattern_message.casePattern(src.bytes, local.declaration.start) orelse return fresh;
            return .{ .matched = found.text };
        }
        if (index >= c.function.signature.parameter_count) return .{ .local = local.name };
        if (index < c.function.scope.own_parameters.len and c.function.scope.own_parameters[index]) return .{ .own_parameter = local.name };
        return if (local.mutable) .{ .mut_parameter = local.name } else .{ .plain_parameter = local.name };
    }

    /// The one message of an Escape refusal: the value the source spells at `span` (`fallback` when the check has no source),
    /// its lender, the store that is `c.sink`, and the repairs.
    fn escapeMessage(c: *Checker, span: Span, lender: ?usize, repairs: escape_message.Repairs, fallback: []const u8) Error![]const u8 {
        return c.escapeMessageTo(span, lender, c.sink, repairs, fallback);
    }

    /// `escapeMessage` for a destination the caller knows better than `c.sink`.
    fn escapeMessageTo(c: *Checker, span: Span, lender: ?usize, destination: escape_message.Destination, repairs: escape_message.Repairs, fallback: []const u8) Error![]const u8 {
        return c.escapeMessageAmong(span, .{ lender, null }, destination, repairs, fallback);
    }

    /// The Escape message of a value that reads up to two places: a selection between two owners, a join of two branches, or
    /// a binding that borrows from several.
    fn escapeMessageAmong(c: *Checker, span: Span, lenders: [2]?usize, destination: escape_message.Destination, repairs: escape_message.Repairs, fallback: []const u8) Error![]const u8 {
        return escape_message.compose(c.diagnostics.allocator, try c.escapeFacts(span, lenders, destination, repairs, fallback));
    }

    /// The facts `escapeMessageAmong` composes its message from.
    fn escapeFacts(c: *Checker, span: Span, lenders: [2]?usize, destination: escape_message.Destination, repairs: escape_message.Repairs, fallback: []const u8) Error!escape_message.Facts {
        const lent = if (c.source) |src| if (span.start < span.end and span.end <= src.bytes.len) src.text(span) else fallback else fallback;
        const first = c.lenderOf(lenders[0]);
        const second: ?escape_message.Lender = if (lenders[1]) |slot| c.lenderOf(slot) else null;
        const same = if (second) |other| if (first.name()) |name| if (other.name()) |other_name| std.mem.eql(u8, name, other_name) else false else false else false;
        const take_or = if (c.source) |src| c.takeOrRepair(src, lent) else null;
        return .{ .lent = lent, .lender = first, .other = if (same) null else second, .destination = destination, .repairs = repairs, .take_or = take_or };
    }

    /// F-71: when `lent` names (with or without `own`) a binding of `o.unwrap_or(d)` whose option `o` is a local or an
    /// `own` parameter this function owns, the `options.take_or(own o, d)` that moves the value instead; null otherwise,
    /// and for a default that is a place (`take_or` would take it) or an option that is a field, an element or lent.
    fn takeOrRepair(c: *Checker, src: language.source.Source, lent: []const u8) ?escape_message.TakeOr {
        const trimmed = std.mem.trim(u8, lent, " \t");
        const name = if (std.mem.startsWith(u8, trimmed, "own ")) std.mem.trimStart(u8, trimmed[4..], " \t") else trimmed;
        for (c.function.scope.locals, 0..) |local, slot| {
            if (!namedLocal(local) or !std.mem.eql(u8, local.name, name)) continue;
            const value = c.definitions.get(@intCast(slot)) orelse continue;
            const node = c.program.nodes[@backingInt(value)];
            if (node.data != .borrow_selection or node.data.borrow_selection.kind != .optional_default) continue;
            const option = c.program.nodes[@backingInt(node.data.borrow_selection.first)];
            const fallback = c.program.nodes[@backingInt(node.data.borrow_selection.second)];
            if (option.data != .local or fallback.own) return null;
            switch (fallback.data) {
                .local, .field, .index, .buffer_operation => return null,
                else => {},
            }
            const owner = @backingInt(option.data.local);
            if (owner >= c.state.len or c.state[owner].traits.borrowed) return null;
            switch (c.lenderOf(owner)) {
                .local, .own_parameter => {},
                else => return null,
            }
            for ([_]Span{ option.span, fallback.span, node.span }) |span| if (span.start >= span.end or span.end > src.bytes.len) return null;
            const a = c.diagnostics.allocator;
            const call = std.fmt.allocPrint(a, "options.take_or(own {s}, {s})", .{ src.text(option.span), src.text(fallback.span) }) catch return null;
            return .{ .call = call, .replaced = src.text(node.span) };
        }
        return null;
    }

    /// The first two places a borrowing local holds.
    fn lendersOf(c: *Checker, slot: usize) Error![2]?usize {
        const roots = try c.localRoots(slot, 0);
        if (roots.items.len == 0) return .{ if (c.rootOf(slot) != slot) c.rootOf(slot) else null, null };
        return .{ roots.items[0], if (roots.items.len > 1) roots.items[1] else null };
    }

    /// Whether the place a value is being moved into outlives the call: the record or collection the innermost store fills
    /// is returned, or is the caller's storage.
    fn sinkLeaves(c: *const Checker) bool {
        return switch (c.sink) {
            .returned => true,
            .field => |field| field.leaves,
            .element => |element| element.leaves,
            else => false,
        };
    }

    /// Start checking a value stored as an element of collection local `owner`: its destination is that collection, and a slice
    /// of a lent value is refused first.
    fn enterElementStore(c: *Checker, owner: usize, argument: typed.NodeId) Error!void {
        c.sink = c.containerSink(owner);
        try c.sliceEscape(argument);
    }

    /// The destination of a value stored into collection local `owner`: the named list, dictionary or set the lowering's alias
    /// stands for, which outlives the call when it is the caller's `mut` storage.
    fn containerSink(c: *Checker, owner: usize) escape_message.Destination {
        const named = c.namedLender(owner);
        const record = c.program.records[c.function.scope.locals[owner].ty.recordIndex()];
        const noun: []const u8 = switch (record.collection.kind) {
            .list => "list",
            .dictionary => if (record.collection.set) "set" else "dictionary",
            .bytes => "byte buffer",
            .string => "text",
        };
        const leaves = if (named) |slot| c.callerMut(slot) else false;
        // The lender is named only when it is the collection itself: `h.seen` is lent by `h`, which is no set (W2).
        const own_name = if (named) |slot| std.meta.eql(c.function.scope.locals[slot].ty, c.function.scope.locals[owner].ty) else false;
        return .{ .element = .{ .noun = noun, .name = if (own_name) c.function.scope.locals[named.?].name else "", .leaves = leaves } };
    }

    /// The destination of a field assigned through record update `base` at `index`: it outlives the call when the record is
    /// the caller's `mut` storage.
    fn updateSink(c: *Checker, base: typed.NodeId, index: usize) escape_message.Destination {
        const ty = c.program.nodes[@backingInt(base)].ty;
        if (!ty.isAggregate() or ty.recordIndex() >= c.program.records.len) return .elsewhere;
        const record = c.program.records[ty.recordIndex()];
        if (index >= record.fields.len) return .elsewhere;
        const leaves = if (c.origin(base)) |root| c.callerMut(root) else false;
        return .{ .field = .{ .record = record.name, .name = record.fields[index].name, .leaves = leaves } };
    }

    /// The destination a compiler temporary that stages an owning store will be stored into: the lowering initializes it before
    /// the collection operation or record update that reads it, so the store's own destination is found there.
    fn stagedSink(c: *Checker, slot: usize) Error!?escape_message.Destination {
        if (c.staged == null) {
            var table: std.AutoHashMapUnmanaged(u32, Staged) = .empty;
            var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
            defer walker.deinit();
            while (try walker.next()) |item| {
                if (item != .expression) continue;
                switch (c.program.nodes[@backingInt(item.expression)].data) {
                    .buffer_operation => |operation| for (operation.arguments) |argument| {
                        const read = c.program.nodes[@backingInt(argument)];
                        if (read.data == .local) try table.put(c.a, @intCast(@backingInt(read.data.local)), .{ .collection = @backingInt(operation.owner) });
                    },
                    .update => |update| for (update.fields) |field| {
                        const read = c.program.nodes[@backingInt(field.value)];
                        if (read.data == .local) try table.put(c.a, @intCast(@backingInt(read.data.local)), .{ .update = .{ .base = update.base, .index = field.index } });
                    },
                    else => {},
                }
            }
            c.staged = table;
        }
        const found = c.staged.?.get(@intCast(slot)) orelse return null;
        return switch (found) {
            .collection => |owner| c.containerSink(owner),
            .update => |update| c.updateSink(update.base, update.index),
        };
    }

    /// Whether `slot` is a `mut` parameter: the caller's storage, held exclusively.
    fn callerMut(c: *const Checker, slot: usize) bool {
        if (slot >= c.function.signature.parameter_count) return false;
        if (slot < c.function.scope.own_parameters.len and c.function.scope.own_parameters[slot]) return false;
        return c.function.scope.locals[slot].mutable;
    }

    /// The `from` clause sources a return needs, in parameter order: every declared source and every one in `extra`.
    fn fromNames(c: *Checker, extra: []const usize) Error![]const u8 {
        const a = c.diagnostics.allocator;
        var slots: std.ArrayList(usize) = .empty;
        for (return_borrow.sources(c.function.signature)) |position| try slots.append(a, position);
        for (extra) |slot| if (std.mem.indexOfScalar(usize, slots.items, slot) == null) try slots.append(a, slot);
        std.mem.sort(usize, slots.items, {}, std.sort.asc(usize));
        var names: std.ArrayList(u8) = .empty;
        for (slots.items, 0..) |slot, index| {
            if (index != 0) try names.appendSlice(a, ", ");
            try names.appendSlice(a, c.function.scope.locals[slot].name);
        }
        return names.items;
    }

    fn temporary(c: *const Checker, slot: usize) bool {
        return temporaryLocal(c.function.scope.locals[slot]);
    }

    /// Name the local that a rejected element read was initializing. The
    /// generic collection message cannot see the destination slot.
    fn annotateElementBinding(c: *Checker, slot: usize, value: typed.NodeId, initializing: bool) void {
        if (!initializing or !c.owns(c.function.scope.locals[slot].ty)) return;
        const read = c.element_read orelse return;
        if (!std.mem.eql(u8, c.failure.code, borrow_error) or !std.meta.eql(c.failure.span, read)) return;
        var node = c.program.nodes[@backingInt(value)];
        while (node.data == .block_value) node = c.program.nodes[@backingInt(node.data.block_value.value)];
        if (node.data != .buffer_operation) return;
        const operation = node.data.buffer_operation;
        if (operation.kind != .read and operation.kind != .get) return;
        const name = c.function.scope.locals[slot].name;
        if (std.mem.startsWith(u8, name, "<")) return;
        if (operation.arguments.len == 1) c.offerBorrowRepair(slot, node, @backingInt(operation.owner), operation.arguments[0]);
        // A binding a later line writes through, with no proven write-back, gets no copy repair (W2): the copy would take
        // that write and leave the element unchanged, so the author has to say which of the two was meant.
        const lost = if (c.failure.repair == .none) c.lostWriteLine(slot, @backingInt(operation.owner)) else null;
        if (lost != null) c.failure.copy = .{};
        const repairs: escape_message.Repairs = if (lost) |line| .{ .binding = .{ .lost_write = .{ .binding = name, .line = line } } } else switch (c.failure.repair) {
            .const_binding => .{ .binding = .{ .constant = name } },
            .write_back => .{ .binding = .{ .write_back = name } },
            else => .copy,
        };
        const destination: escape_message.Destination = .{ .binding = .{ .name = name, .mutable = c.function.scope.locals[slot].mutable } };
        c.failure.message = c.escapeMessageTo(c.program.nodes[@backingInt(value)].span, c.rootOf(@backingInt(operation.owner)), destination, repairs, name) catch return;
    }

    /// The line of the first write through `mut` binding `slot` of an element of `owner`, when that owner is one the function
    /// may change (a local, an `own` or a `mut` parameter) and the source is known; null otherwise (W2).
    fn lostWriteLine(c: *Checker, slot: usize, owner: usize) ?usize {
        if (c.probing.active or !c.function.scope.locals[slot].mutable) return null;
        const src = c.source orelse return null;
        const lender = c.lenderOf(c.rootOf(owner));
        if (lender != .local and lender != .own_parameter and lender != .mut_parameter) return null;
        const span = (c.laterWrite(slot) catch return null) orelse return null;
        return src.locate(span.start).line;
    }

    /// The first statement or expression of this function that writes through local `slot` or passes it to be changed (W2):
    /// a field or element assignment, a changing list operation, or an argument the callee declares it changes. A whole
    /// reassignment is no write through it.
    fn laterWrite(c: *Checker, slot: usize) Error!?Span {
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        var aliases: std.AutoHashMapUnmanaged(u32, typed.NodeId) = .empty;
        defer aliases.deinit(c.a);
        while (try walker.next()) |item| switch (item) {
            .statement => |id| {
                const statement = c.program.statements[@backingInt(id)];
                switch (statement.data) {
                    .initialize => |store| if (store.unpack == null) try aliases.put(c.a, @intCast(@backingInt(store.slot)), store.value),
                    .assign => |store| if (@backingInt(store.slot) == slot and writeThrough(c.program, &aliases, store, slot)) return statement.span,
                    else => {},
                }
            },
            .expression => |id| {
                var written: std.AutoHashMapUnmanaged(u32, void) = .empty;
                defer written.deinit(c.a);
                try language.call_views.noteWrites(c.a, c.program, id, &written);
                var targets = written.keyIterator();
                while (targets.next()) |target| {
                    if (target.* == slot) return c.program.nodes[@backingInt(id)].span;
                    // A changing list operation names the lowering temporary that stages its receiver.
                    const staged = c.program.nodes[@backingInt(aliases.get(target.*) orelse continue)];
                    if (staged.data == .local and !staged.own and @backingInt(staged.data.local) == slot) return c.program.nodes[@backingInt(id)].span;
                }
            },
        };
        return null;
    }

    /// Offers a certain borrow repair for the refused `mut slot = owner[index]` (C6): `const` when the
    /// whole function checks with the binding const (a), else the write-back through the element place
    /// when its lines prove it (b). Otherwise the copy repair stays, as it always did.
    fn offerBorrowRepair(c: *Checker, slot: usize, element: typed.Node, owner: usize, index: typed.NodeId) void {
        const local = c.function.scope.locals[slot];
        // An element read's binding is labelled `collection_copy` (sema_statements.zig): the copy of an index.
        if (c.probing.active or !local.mutable) return;
        if (local.origin != .local and local.origin != .collection_copy) return;
        if (c.probeConstBinding(slot)) {
            c.failure.repair = .{ .const_binding = local.declaration };
            return;
        }
        c.offerWriteBack(slot, element, owner, index);
    }

    /// Whether the function checks with `slot` read as a `const` borrow. The whole function is re-checked
    /// with that binding's `mut` removed, so a write to it, or a change to its owner while it is live,
    /// fails the probe exactly as it would fail the repaired program.
    fn probeConstBinding(c: *Checker, slot: usize) bool {
        const locals = c.a.dupe(typed.Local, c.function.scope.locals) catch return false;
        locals[slot].mutable = false;
        var function = c.function;
        function.scope.locals = locals;
        var probe: Failure = .{};
        const shared = c.probeShared(c.program);
        checkFunction(c.a, shared, function, &probe, .{ .active = true }) catch return false;
        return true;
    }

    /// Offers the write-back repair for `mut slot = owner[index]` when the source lines prove the
    /// rewrite (`borrow_repair.proveWriteBack`). The element's record fields come from the typed program.
    fn offerWriteBack(c: *Checker, slot: usize, element: typed.Node, owner: usize, index: typed.NodeId) void {
        const source = c.source orelse return;
        // The element read's owner is often a compiler alias of the named list (`<collection>`); its root is the list.
        const root = c.rootOf(owner);
        const owner_name = c.function.scope.locals[root].name;
        if (std.mem.startsWith(u8, owner_name, "<")) return;
        const local = c.function.scope.locals[slot];
        const fields: []const typed.Field = if (element.ty.isAggregate() and c.program.records[element.ty.recordIndex()].isRecord())
            c.program.records[element.ty.recordIndex()].fields
        else
            &.{};
        const names: borrow_repair.Names = .{
            .binding = local.name,
            .owner = owner_name,
            .index = source.text(c.program.nodes[@backingInt(index)].span),
            .declaration = local.declaration,
        };
        const edits = (borrow_repair.proveWriteBack(c.diagnostics.allocator, source, names, fields) catch return) orelse return;
        c.failure.repair = .{ .write_back = edits };
    }

    /// Contracts stage the source return before checking its postconditions.
    fn storedReturnValue(c: *const Checker, store: typed.Store, initializing: bool) ?typed.NodeId {
        if (!initializing) return null;
        const local = c.function.scope.locals[@backingInt(store.slot)];
        if (local.origin != .contract_value) return null;
        if (!std.mem.eql(u8, local.name, "result") and !std.mem.eql(u8, local.name, "<return>")) return null;
        return store.value;
    }

    fn observeStoredReturn(c: *Checker, store: typed.Store, initializing: bool) void {
        const observer = c.diagnostics.observer orelse return;
        const value = c.storedReturnValue(store, initializing) orelse return;
        observer.returned = c.observedReturnBinding(value);
    }

    fn checkStore(c: *Checker, store: typed.Store, initializing: bool, span: Span) Error!void {
        if (store.unpack != null) return c.checkUnpack(store, initializing, span);
        const slot = @backingInt(store.slot);
        const local = c.function.scope.locals[slot];
        // A generated invariant check after a write through a `match mut` binding reads the container the arm holds into
        // this hidden local (FX7b): a borrowed read that ends with the check, so it takes no loan and meets no hold. No
        // other read of a held place, a hand-written one in the same position included, comes here.
        if (initializing and generatedHoldRead(local)) {
            c.state[slot] = .{ .available = true, .traits = .{ .borrowed = true } };
            return;
        }
        if (initializing and std.mem.startsWith(u8, local.name, "\x00literal") and c.constantText(local.ty) and c.projectedLiteral(store.value))
            return c.reject(c.program.nodes[@backingInt(store.value)].span, .{ .code = "E_LITERAL_ARM", .rule = .C1 }, "a literal match on a str or bytes element or field would copy it; bind the value first with `const value = copy(...)`");
        if (initializing and c.temporary(slot)) try c.temporary_definitions.put(c.a, @intCast(slot), store.value);
        try c.noteExclusiveReceiver(slot, store, initializing);
        const observer = c.diagnostics.observer;
        const previous_return = if (observer) |seen| seen.returned else null;
        c.observeStoredReturn(store, initializing);
        defer if (observer) |seen| {
            seen.returned = previous_return;
        };
        const previous_marker = c.marker.returned;
        if (c.storedReturnValue(store, initializing)) |value| c.marker.returned = c.bareReturnedLocal(value, span);
        defer c.marker.returned = previous_marker;
        if (c.borrowed_mut[slot]) {
            if (!initializing and c.writtenThrough(store, slot)) return c.rejectBorrowedWrite(slot, span);
            return c.storeBorrowedMut(store);
        }
        if (c.literalCollection(slot)) |made| return c.storeLiteralCollection(store, slot, made, initializing, span);
        if (c.stagedCollection(slot)) return c.storeStagedValue(store, slot);
        return c.checkStoredValue(store, initializing, span);
    }

    /// Whether local `slot` stages the value of an element write into a borrowed collection (RB2).
    fn stagedCollection(c: *const Checker, slot: usize) bool {
        const held = c.collections orelse return false;
        return slot < held.table.staged.len and held.table.staged[slot] != none;
    }

    /// The value an element write into a borrowed collection stages (RB2) is read in place, as an appended value is; the
    /// write then lends it to the collection.
    fn storeStagedValue(c: *Checker, store: typed.Store, slot: usize) Error!void {
        const roots = try c.lendIntoCollection(store.value);
        const origins = try c.a.dupe(ConstOrigin, &.{.{ .definition = store.value, .roots = roots, .borrowed = true }});
        c.state[slot] = .{ .available = true, .view_definition = .{ .node = store.value, .const_origins = origins }, .traits = .{ .borrowed = true, .rule = .B9 } };
    }

    /// The literal a borrowed collection (RB2) is initialized with, the lowering temporary that builds it, or null.
    fn literalCollection(c: *const Checker, slot: usize) ?usize {
        const held = c.collections orelse return null;
        if (!held.table.holds(slot) or held.table.literal[slot] == none) return null;
        return held.table.literal[slot];
    }

    /// A borrowed collection (RB2) initialized with a list literal of borrows takes the literal's temporary, the one move it
    /// may take, and with it what the literal borrows.
    fn storeLiteralCollection(c: *Checker, store: typed.Store, slot: usize, made: usize, initializing: bool, span: Span) Error!void {
        const held = c.collections.?;
        {
            const was = held.storing;
            held.storing = true;
            defer held.storing = was;
            try c.checkStoredValue(store, initializing, span);
        }
        try held.roots[slot].merge(c.a, held.roots[made]);
        try c.holdCollectionLoans(slot);
    }

    /// Literal-match lowering retains the projected scrutinee inside its hidden initializer.
    fn projectedLiteral(c: *const Checker, value: typed.NodeId) bool {
        return switch (c.program.nodes[@backingInt(value)].data) {
            .field, .index => true,
            .buffer_operation => |operation| operation.kind == .read or operation.kind == .get,
            .block_value => |block| c.projectedLiteral(block.value),
            else => false,
        };
    }

    /// F-56: stage a field of a temporary (`parse(x).problem`) into the `<membership>` operand of `in` as a read in
    /// place, borrowing the call's result for the statement. Whether it applied.
    fn membershipFieldRead(c: *Checker, slot: usize, store: typed.Store) Error!bool {
        if (!c.temporary(slot) or store.transfer) return false;
        if (!std.mem.eql(u8, c.function.scope.locals[slot].name, membership_operand)) return false;
        if (c.program.nodes[@backingInt(store.value)].data != .field) return false;
        if (c.origin(store.value) != null or c.ambiguousBorrow(store.value)) return false;
        try c.expression(store.value, .read);
        c.state[slot] = .{ .available = true, .root = none, .view_definition = .{ .node = store.value }, .traits = .{ .borrowed = true, .rule = .B8 } };
        return true;
    }

    /// An initializer that borrows for its statement: a `<membership>` field read (F-56) or a borrowed call result.
    fn initializeBorrowed(c: *Checker, store: typed.Store, span: Span) Error!bool {
        if (try c.membershipFieldRead(@backingInt(store.slot), store)) return true;
        return c.initializeBorrowedCall(store, span);
    }

    fn checkStoredValue(c: *Checker, store: typed.Store, initializing: bool, span: Span) Error!void {
        const slot = @backingInt(store.slot);
        const local = c.function.scope.locals[slot];
        const previous_sink = c.sink;
        defer c.sink = previous_sink;
        if (!c.temporary(slot)) {
            c.sink = .{ .binding = .{ .name = local.name, .mutable = local.mutable } };
        } else if (store.transfer) if (try c.stagedSink(slot)) |staged| {
            c.sink = staged;
        };
        const transferring = c.temporary(slot) and store.transfer;
        if (transferring) {
            try c.writtenMarker(store.value, .move);
            try c.sliceEscape(store.value);
        }
        if (try c.initializeBorrowed(store, span)) return;
        if (c.sliceView(slot)) {
            try c.expression(store.value, .read);
            // The slice itself names its source: a text or byte slice through its
            // operation, a list slice through the source binding its copy loop
            // starts from (the stores of all three are the escape rule's).
            const source = if (c.sliceNodeFamily(store.value, 0, .any)) |slice|
                c.rootOf(@backingInt(slice.data.buffer_operation.owner))
            else if (c.viewCallSource(store.value)) |argument|
                c.origin(argument) orelse return c.reject(span, .{ .code = view_escape, .rule = .V3 }, "a view result must borrow from a known local owner")
            else
                c.listSliceSource(store.value) orelse return c.reject(span, .{ .code = view_escape, .rule = .V3 }, "a slice view must borrow from a known local owner");
            // A move of the binding materializes its own copy, so it is not
            // borrowed; only its source's integrity keeps it alive.
            c.state[slot] = .{ .available = true, .root = if (source == slot) none else source, .view_definition = .{ .node = store.value }, .traits = .{ .borrowed = false } };
            return;
        }
        // Every unmarked const place initializer is a read-only borrow (B9).
        if (try c.initializeBinding(store, span, initializing)) return;
        if (!c.owns(local.ty)) return c.storeUntracked(store, initializing, span);
        // F-56: `in` and `not in` stage an operand that is not a local in a `<membership>` temporary that only the probe
        // reads. A field of a temporary (`parse(x).problem`) is read there as `==` reads it in place: the probe keeps
        // nothing, and the call's result lives to the end of the statement.
        // Receiver/iteration staging reads a place. An owning RHS staged
        // before its destination instead transfers now, preserving source order.
        if (c.temporary(slot) and !store.transfer) {
            // Even two fresh inputs produce a borrow. Lack of a named root
            // cannot turn a generated selection receiver into a new owner.
            if (c.ambiguousBorrow(store.value)) {
                try c.expression(store.value, .read);
                const source = c.origin(store.value);
                c.state[slot] = .{
                    .available = true,
                    .root = if (source) |root| if (root == slot) none else root else none,
                    .view_definition = .{ .node = store.value },
                    .traits = .{ .borrowed = true, .ambiguous_borrow = true, .rule = .R6 },
                };
                return;
            }
            if (c.origin(store.value)) |source| {
                try c.expression(store.value, .read);
                if (source == slot) return;
                c.state[slot] = .{
                    .available = true,
                    .root = source,
                    .view_definition = .{ .node = store.value },
                    .dependency = c.state[source].dependency,
                    .traits = .{
                        .borrowed = true,
                        .writable = local.origin != .iteration and c.state[source].traits.writable,
                        .transferable = c.wholeOwner(store.value),
                        .ambiguous_borrow = c.ambiguousBorrow(store.value),
                        .rule = if (local.origin == .iteration or local.origin == .pattern or !c.state[source].traits.borrowed) .B7 else c.state[source].traits.rule,
                    },
                };
                try c.holdStagedReceiver(slot, source);
                return;
            }
        }
        const node = c.program.nodes[@backingInt(store.value)];
        const optional = if (!initializing) c.optionalWriteback(store) else null;
        const updating = !initializing and (store.element or node.data == .update or node.data == .replace or optional != null);
        if (updating) {
            try c.checkUpdatedLocal(slot, store.value, span);
            try c.expression(optional orelse store.value, .update);
        } else {
            if (!initializing and c.state[slot].available) try c.checkLocal(slot, .mutate, span);
            const previous_store = c.local_store;
            c.local_store = !transferring;
            defer c.local_store = previous_store;
            c.expression(store.value, .move) catch |err| {
                if (err == error.Rejected) c.annotateElementBinding(slot, store.value, initializing);
                return err;
            };
            // Judged after the value is checked, so the temporaries its slice
            // lowers through have their roots and the source has a name.
            try c.ownedViewStore(slot, store.value);
        }
        const parameter = slot < c.function.signature.parameter_count;
        const affine = resources.affine(c.program, local.ty);
        // A rewritten `own` parameter holds the callee's own value, so it is
        // owned again; only a plain or `mut` parameter stays the caller's storage.
        const owned = parameter and slot < c.function.scope.own_parameters.len and c.function.scope.own_parameters[slot];
        const dependency = if (resources.dependent(c.program, local.ty)) try c.resourceOrigin(store.value) else null;
        c.state[slot] = .{ .available = true, .dependency = dependency orelse none, .traits = .{ .borrowed = parameter and !affine and !owned, .writable = local.mutable, .rule = if (local.mutable) .M1 else .R1 } };
        if (!local.mutable and c.namedBinding(slot)) c.state[slot].view_definition.const_origins = try c.a.dupe(ConstOrigin, &.{.{ .definition = store.value, .roots = .{ .temp = true }, .borrowed = false }});
    }

    /// A writable receiver captured before separate index setup must survive that setup.
    /// The write statement takes its own receiver loan; end this hold just before it.
    fn holdStagedReceiver(c: *Checker, slot: usize, source: usize) Error!void {
        if (!c.written.contains(@intCast(slot))) return;
        const block = c.block orelse return;
        const ty = c.function.scope.locals[slot].ty;
        if (!ty.isAggregate() or !c.program.records[ty.recordIndex()].isCollection()) return;
        var index = block.index + 1;
        while (index < block.items.len) : (index += 1) {
            if (!try c.writesReceiver(block.items[index], slot)) continue;
            if (index > block.index + 1) try c.loans.append(c.a, .{
                .root = c.rootOf(source),
                .write = false,
                .binding = slot,
                .release = index - 1,
                .path = try c.sourcePath(null, slot, true),
                .hold = .{ .receiver = c.function.scope.locals[slot].declaration },
                .rule = .R2,
            });
            return;
        }
    }

    fn writesReceiver(c: *const Checker, statement: typed.StatementId, slot: usize) Error!bool {
        var walker = try typed_walk.Walker.init(c.a, c.program, statement);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .statement => {},
            .expression => |id| switch (c.program.nodes[@backingInt(id)].data) {
                .buffer_operation => |operation| if (@backingInt(operation.owner) == slot and operation.kind.writesReceiver()) return true,
                else => {},
            },
        };
        return false;
    }

    /// The owners a value reads from (R3b): a place's parameter or owned local, the loans of a `const` borrow, and the
    /// owners of a borrowed call's arguments. A temporary contributes no owner and sets `temp`.
    fn placeRoots(c: *Checker, id: typed.NodeId, depth: usize) Error!Roots {
        var roots: Roots = .{};
        if (depth > c.program.nodes.len + c.state.len) {
            roots.unknown = true;
            return roots;
        }
        if (c.listSliceSource(id)) |root| {
            try roots.add(c.a, root);
            roots.view = true;
            return roots;
        }
        const node = c.program.nodes[@backingInt(id)];
        switch (node.data) {
            .local => |slot| {
                var found = try c.localRoots(@backingInt(slot), depth);
                found.view = c.viewedSlot(@backingInt(slot));
                return found;
            },
            .buffer_operation => |operation| switch (operation.kind) {
                .slice, .slice_bytes, .text_tail => {
                    var found = try c.localRoots(@backingInt(operation.owner), depth);
                    found.view = true;
                    return found;
                },
                .strip, .lstrip, .rstrip => if (c.textTrimBorrow(operation)) {
                    var found = try c.localRoots(@backingInt(operation.owner), depth);
                    found.view = true;
                    return found;
                },
                // An element, dictionary value or key is a part of its owner (a list view's element is a managed block of
                // the caller's storage), so it is not a whole view. A char read of text is a scalar and owns nothing.
                .get, .key_at, .value_at, .setdefault, .borrow_view => {
                    var found = try c.localRoots(@backingInt(operation.owner), depth);
                    // A dictionary read with a default answers the default when the key is absent, so the default is an owner too.
                    // A literal default (4c) is a static constant and owns nothing.
                    const defaulted = operation.kind == .get and operation.arguments.len == 2;
                    if (defaulted and !c.staticValue(operation.arguments[1])) try found.merge(c.a, try c.placeRoots(operation.arguments[1], depth + 1));
                    found.view = false;
                    return found;
                },
                .read => if (!c.textOwner(@backingInt(operation.owner))) {
                    var found = try c.localRoots(@backingInt(operation.owner), depth);
                    found.view = false;
                    return found;
                },
                else => {},
            },
            .field => |field| return c.placeRoots(field.base, depth + 1),
            .index => |index| return c.placeRoots(index.base, depth + 1),
            // A borrowed record (1A) reads the owners of its fields.
            .record => |fields| if (try c.borrowedRecord(id)) return c.recordRoots(fields, depth),
            .cast => |value| if (c.program.nodes[@backingInt(value)].ty == node.ty) return c.placeRoots(value, depth + 1),
            .wrap, .unwrap => |value| return c.placeRoots(value, depth + 1),
            .block_value => |block| return c.placeRoots(block.value, depth + 1),
            .variant => |variant| {
                if (return_borrow.step(c.program.records, node.ty)) |step| {
                    if (variant.tag == step.tag) if (variant.value) |value| return c.placeRoots(value, depth + 1);
                    return roots;
                }
            },
            .call => if (try c.borrowedCallRoots(id, depth + 1)) |found| return found,
            // `try call(...)`: the success of a borrowed call keeps the call's roots.
            .propagate => |propagated| if (c.program.nodes[@backingInt(propagated.value)].data == .call) return c.placeRoots(propagated.value, depth + 1),
            .borrow_selection => |selection| {
                try roots.merge(c.a, try c.placeRoots(selection.first, depth + 1));
                // A literal default (4c) is a static constant: it has no owner to hold, so `unwrap_or(b"")` borrows only its option.
                if (!c.staticValue(selection.second)) try roots.merge(c.a, try c.placeRoots(selection.second, depth + 1));
                return roots;
            },
            else => {},
        }
        roots.temp = true;
        return roots;
    }

    /// The owners of a local's value: through its initializer when it is a compiler temporary nothing writes; else the
    /// owners of its `const` loans, or its own root. A parameter or an owned local is its own owner; a borrowed binding
    /// with no loan and no root borrows a temporary.
    fn localRoots(c: *Checker, slot: usize, depth: usize) Error!Roots {
        var roots: Roots = .{};
        if (slot >= c.state.len) {
            roots.unknown = true;
            return roots;
        }
        if (c.temporaryValue(slot)) |definition| return c.placeRoots(definition, depth + 1);
        // A borrowed collection (RB2) is its own buffer and lends what its stores borrow.
        if (c.collections) |held| if (held.table.holds(slot)) {
            try roots.add(c.a, slot);
            try roots.merge(c.a, held.roots[slot]);
            return roots;
        };
        const state = c.state[slot];
        if (state.traits.borrowed and state.traits.rule == .B9 and state.view_definition.const_origins.len != 0) {
            for (state.view_definition.const_origins) |alternative| try roots.merge(c.a, alternative.roots);
            return roots;
        }
        for (c.loans.items) |loan| if (loan.binding == slot) try roots.add(c.a, loan.root);
        // Loans retain named owners, while the initializer also records temporary
        // or unknown sources. An alias must preserve both kinds of provenance.
        if (state.traits.borrowed and state.traits.rule == .R3) {
            const definition = state.view_definition.node orelse {
                roots.unknown = true;
                return roots;
            };
            if (try c.bindingBorrowRoots(definition, depth + 1)) |origin_roots| {
                try roots.merge(c.a, origin_roots);
            } else roots.unknown = true;
        }
        if (roots.items.len != 0 or roots.unknown or roots.temp) return roots;
        if (state.traits.borrowed) if (state.view_definition.node) |definition| return c.placeRoots(definition, depth + 1);
        if (slot < c.function.signature.parameter_count or !state.traits.borrowed or state.root != none) {
            try roots.add(c.a, c.rootOf(slot));
            return roots;
        }
        roots.temp = true;
        return roots;
    }

    /// The initializer of a compiler temporary that nothing in the function writes, or null.
    fn temporaryValue(c: *const Checker, slot: usize) ?typed.NodeId {
        if (!c.function.scope.locals[slot].usage.temporary or c.written.contains(@intCast(slot))) return null;
        return c.definitions.get(@intCast(slot));
    }

    /// Whether a local holds text, so that a read of it is a scalar (a character), not a borrowed block.
    fn textOwner(c: *const Checker, slot: usize) bool {
        const ty = c.function.scope.locals[slot].ty;
        if (!ty.isAggregate() or ty.recordIndex() >= c.program.records.len) return false;
        return c.program.records[ty.recordIndex()].collection.kind == .string;
    }

    /// Only a no-argument str trim borrows its kept octets. Bytes trims and
    /// trims with a character set build independent storage.
    fn textTrimBorrow(c: *const Checker, operation: @FieldType(@FieldType(typed.Node, "data"), "buffer_operation")) bool {
        if (operation.arguments.len != 0 or !c.textOwner(@backingInt(operation.owner))) return false;
        return switch (operation.kind) {
            .strip, .lstrip, .rstrip => true,
            else => false,
        };
    }

    /// Whether a local is a whole value Core holds as a view rather than as an owned block: a plain text, bytes or list
    /// parameter, a view binding, or a binding that aliases a local. Borrowed returns retain this representation and
    /// map every owner through the declaration's sources, including when the caller supplies a slice.
    fn viewedSlot(c: *const Checker, slot: usize) bool {
        const ty = c.function.scope.locals[slot].ty;
        if (!ty.isAggregate() or ty.recordIndex() >= c.program.records.len) return false;
        const record = c.program.records[ty.recordIndex()];
        if (!record.isCollection()) return false;
        if (record.collection.kind != .string and record.collection.kind != .bytes and record.collection.kind != .list) return false;
        if (slot < c.function.signature.parameter_count or c.viewLike(slot)) return true;
        const definition = c.state[slot].view_definition.node orelse return false;
        return c.program.nodes[@backingInt(definition)].data == .local;
    }

    /// Map every declared source through its actual argument. No body facts or
    /// fixed owner budget participate in the call's borrowing contract.
    fn borrowedCallRoots(c: *Checker, id: typed.NodeId, depth: usize) Error!?Roots {
        const node = c.program.nodes[@backingInt(id)];
        if (node.data != .call) return null;
        const call = node.data.call;
        if (!c.owns(node.ty)) return null;
        if (@backingInt(call.function) >= c.program.functions.len) return null;
        const signature = c.program.functions[@backingInt(call.function)].signature;
        const positions = return_borrow.effectiveSources(c.program.records, signature);
        if (positions.len == 0) return null;
        var roots: Roots = .{};
        for (positions) |position| {
            if (position >= call.arguments.len) {
                roots.unknown = true;
                continue;
            }
            try roots.merge(c.a, try c.placeRoots(call.arguments[position], depth + 1));
        }
        return roots;
    }

    fn ownedParameterSlot(c: *const Checker, slot: usize) bool {
        return slot < c.function.scope.own_parameters.len and c.function.scope.own_parameters[slot];
    }

    /// A borrowed result may be read with every owner held; storing, moving or
    /// changing it needs an explicit copy.
    fn borrowedResultUse(c: *Checker, id: typed.NodeId, roots: Roots, access: Access) Error!void {
        const node = c.program.nodes[@backingInt(id)];
        if (roots.unknown) return c.reject(node.span, .{ .code = borrow_error, .rule = .R3 }, "this call has an invalid declared borrow source");
        if (access == .read) return;
        const lender: ?usize = if (roots.items.len != 0) roots.items[0] else null;
        return c.rejectCopy(node.span, node.ty, .{ .code = borrow_error, .rule = .R3 }, try c.escapeMessage(node.span, lender, .copy, ""));
    }

    /// Recognize borrowed results and their read-only aliases. Intrinsic accessors
    /// retain their borrowing after lowering replaces a call with an operation.
    fn bindingBorrowRoots(c: *Checker, value: typed.NodeId, depth: usize) Error!?Roots {
        if (depth > c.program.nodes.len) return null;
        return switch (c.program.nodes[@backingInt(value)].data) {
            .local => |local| if (@backingInt(local) < c.state.len and c.state[@backingInt(local)].traits.borrowed and c.state[@backingInt(local)].traits.rule == .R3)
                try c.localRoots(@backingInt(local), depth + 1)
            else
                null,
            .call => c.borrowedCallRoots(value, depth),
            // `try call(...)`: the success is a borrow with the call's roots.
            .propagate => |propagated| c.borrowedCallRoots(propagated.value, depth),
            .block_value => |block| c.bindingBorrowRoots(block.value, depth + 1),
            .borrow_selection => try c.placeRoots(value, depth),
            .buffer_operation => |operation| switch (operation.kind) {
                .get, .setdefault => try c.placeRoots(value, depth),
                .strip, .lstrip, .rstrip => if (c.textTrimBorrow(operation)) try c.placeRoots(value, depth) else null,
                else => null,
            },
            else => null,
        };
    }

    /// Bind a `const` local to a borrowed result (R3b/R6), including an existing
    /// result binding or lowered intrinsic call. A loan holds each owner until the binding's
    /// last use; a source `mut` binding still needs an independent value.
    fn initializeBorrowedCall(c: *Checker, store: typed.Store, span: Span) Error!bool {
        const value = store.value;
        const slot = @backingInt(store.slot);
        const local = c.function.scope.locals[slot];
        // A lowering temporary of the call (an argument or a receiver) is bound the same way: it lives for its statement.
        // A `mut` local is a compiler temporary that nothing writes (the lowering declares some `mut`), or it is not bound.
        if (local.mutable and (!local.usage.temporary or c.written.contains(@intCast(slot)))) return false;
        if (store.unpack != null or !c.owns(local.ty)) return false;
        if (resources.affine(c.program, local.ty) or resources.dependent(c.program, local.ty)) return false;
        const roots = (try c.bindingBorrowRoots(value, 0)) orelse return false;
        if (roots.unknown) return false;
        // The initializer must be the statement now checked, directly in the innermost block (as for a place borrow).
        const block = c.block orelse return false;
        if (block.index >= block.items.len) return false;
        const current = c.program.statements[@backingInt(block.items[block.index])];
        if (current.data != .initialize or current.data.initialize.slot != store.slot) return false;
        if (current.span.start != span.start or current.span.end != span.end) return false;
        try c.expression(value, .read);
        const release = try c.lastUse(block, slot);
        for (roots.slice()) |root| try c.loans.append(c.a, .{ .root = root, .write = false, .binding = slot, .release = release });
        c.state[slot] = .{ .available = true, .root = if (roots.items.len == 1 and !roots.temp) roots.items[0] else none, .view_definition = .{ .node = value }, .traits = .{ .borrowed = true, .rule = .R3 } };
        return true;
    }

    /// Record every local this function's body writes: an assignment, a mutating operation on an owner, or a call that takes a
    /// local at a position the callee writes (the rule `markCallViews` uses for its temporaries).
    fn collectWrites(c: *Checker) Error!void {
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .statement => |id| {
                const data = c.program.statements[@backingInt(id)].data;
                if (data == .assign) try c.written.put(c.a, @intCast(@backingInt(data.assign.slot)), {});
                if (data == .initialize and data.initialize.unpack == null) try c.definitions.put(c.a, @intCast(@backingInt(data.initialize.slot)), data.initialize.value);
            },
            .expression => |id| try language.call_views.noteWrites(c.a, c.program, id, &c.written),
        };
    }

    /// A `return` of a value that is not a view (R3b, R3a): an accepted borrowed return is read in place and recorded by
    /// `acceptBorrowedReturn`; any other value keeps its check. A refused place is recorded for the mixed-return rule, and
    /// the path ends so the check goes on. A place that checks as a read (a view or a scalar) is not recorded: the
    /// baseline accepted those returns beside a new value.
    fn returnValue(c: *Checker, value: typed.NodeId, span: Span) Error!void {
        const previous = c.marker.returned;
        c.marker.returned = c.bareReturnedLocal(value, span);
        defer c.marker.returned = previous;
        const previous_sink = c.sink;
        defer c.sink = previous_sink;
        c.sink = .returned;
        if (c.neutralWrapper(value)) {
            c.returning = true;
            defer c.returning = false;
            return c.expression(value, .move);
        }
        if (try c.borrowedReturn(value)) |roots| return c.acceptBorrowedReturn(value, roots);
        c.returning = true;
        defer c.returning = false;
        // The value is classified after its check: a slice's temporaries are recorded while it is checked, and the roots do
        // not change.
        c.checkReturn(value, span) catch |err| {
            if (err != error.Rejected) return err;
            const kind = c.returnKind(value);
            try c.noteReturn(kind, value);
            if (kind != .place) return err;
            if (c.returns.refused == null) c.returns.refused = c.failure.*;
            return;
        };
        const kind = c.returnKind(value);
        if (kind != .place) try c.noteReturn(kind, value);
    }

    /// Only an exact source local is implicitly transferred by return or fail.
    /// Generated outcome/error injections span the statement; written
    /// constructors span only their expression and keep their child markers.
    fn bareReturnedLocal(c: *const Checker, value: typed.NodeId, statement: Span) ?typed.NodeId {
        var current = value;
        var remaining = c.program.nodes.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            const node = c.program.nodes[@backingInt(current)];
            if (node.data == .local) {
                const slot = @backingInt(node.data.local);
                if (c.namedBinding(slot)) return current;
                current = c.definitions.get(@intCast(slot)) orelse return null;
                continue;
            }
            const same_statement = node.span.start == statement.start and node.span.end == statement.end;
            const child = switch (node.data) {
                .variant => |variant| variant.value orelse return null,
                .record => |fields| if (same_statement and fields.len == 1) fields[0].value else return null,
                .wrap, .cast => |inner| inner,
                .block_value => |block| block.value,
                else => return null,
            };
            const inner = c.program.nodes[@backingInt(child)].span;
            const implicit_wrapper = same_statement and (node.data == .variant or node.data == .record);
            if (!implicit_wrapper and (node.span.start != inner.start or node.span.end != inner.end)) return null;
            current = child;
        }
        return null;
    }

    /// The value a `return` yields, inside its `Some` wrapper.
    fn returnedValue(c: *const Checker, value: typed.NodeId) typed.NodeId {
        return c.returnedPayload(value);
    }

    /// Eligible parameter places, regardless of whether the declaration already
    /// names them. Missing names are collected for one declaration repair.
    fn borrowedReturn(c: *Checker, value: typed.NodeId) Error!?Roots {
        const leaf = return_borrow.shape(c.program.records, c.function.signature).leaf;
        if (!return_borrow.managed(c.program.records, leaf)) return null;
        const payload = c.returnedValue(value);
        // A marked projection requests ownership, so it must pass the ordinary
        // move checks rather than silently becoming a declared borrowed return.
        if (c.program.nodes[@backingInt(payload)].own and c.marker.returned != payload) return null;
        if (!c.owns(c.program.nodes[@backingInt(payload)].ty)) return null;
        // A borrowed record (1A) is returned only under a declared `from` contract; without one it keeps its owning
        // construction and that refusal (a missing marker or a copy).
        if (c.program.nodes[@backingInt(payload)].data == .record and return_borrow.sources(c.function.signature).len == 0) return null;
        const roots = try c.placeRoots(payload, 0);
        if (roots.temp or roots.unknown or roots.items.len == 0) return null;
        for (roots.slice()) |root| {
            if (root >= c.function.signature.parameter_count) return null;
            if (!c.state[root].traits.borrowed) return null;
        }
        // A box this call made for `Some(p)` (O4) is a slot of its frame: it dies with the call, even under `from`.
        if (roots.frame) return c.reject(c.program.nodes[@backingInt(payload)].span, .{ .code = borrow_error, .rule = .R4 }, frame_return);
        // A frame block (RB1) dies with the call too. The return keeps the owning construction, so it is refused as it
        // was before frame blocks: the bare parameter read is a move of a borrow (R1).
        if (roots.block_frame) return null;
        return roots;
    }

    /// Read a parameter place and record every owner and undeclared source.
    fn acceptBorrowedReturn(c: *Checker, value: typed.NodeId, roots: Roots) Error!void {
        try c.borrowedReturnMarkers(value);
        try c.permittedRecord(c.returnedValue(value), .read);
        try c.returns.roots.merge(c.a, roots);
        const declared = return_borrow.sources(c.function.signature);
        for (roots.items) |root| {
            const position = std.math.cast(u16, root) orelse return c.rejectInternal(c.program.nodes[@backingInt(value)].span, "E_INTERNAL_BORROW_SOURCE", "compiler bug: invalid borrowed parameter position");
            if (std.mem.indexOfScalar(u16, declared, position) == null) {
                try c.returns.missing.add(c.a, root);
                if (c.returns.first_missing == null) c.returns.first_missing = c.program.nodes[@backingInt(c.returnedPayload(value))].span;
            }
        }
        try c.noteReturn(.place, value);
    }

    /// Borrowed-success analysis peels wrappers without moving their payload.
    /// Every written wrapper marker still needs its ordinary placement check.
    fn borrowedReturnMarkers(c: *Checker, value: typed.NodeId) Error!void {
        const payload = c.returnedValue(value);
        var current = value;
        var remaining = c.program.nodes.len + 1;
        while (current != payload and remaining != 0) : (remaining -= 1) {
            try c.writtenMarker(current, .read);
            current = switch (c.program.nodes[@backingInt(current)].data) {
                .variant => |variant| variant.value orelse return,
                .wrap => |inner| inner,
                else => return,
            };
        }
    }

    /// Complete same-owner reconstruction is a writeback, never a borrowed move.
    fn optionalWriteback(c: *const Checker, store: typed.Store) ?typed.NodeId {
        const contract = @import("optional_writeback.zig");
        const found = contract.shape(c.program, c.function, store) orelse return null;
        const receiver = @backingInt(found.receiver);
        if (!c.state[receiver].traits.borrowed or c.rootOf(receiver) != @backingInt(store.slot)) return null;
        const definition = c.state[receiver].view_definition.node orelse return null;
        if (!contract.projection(c.program, c.function, store, found, definition)) return null;
        return found.payload;
    }

    /// The entire tuple transfers once, before any destination expression runs.
    fn checkUnpack(c: *Checker, store: typed.Store, initializing: bool, span: Span) Error!void {
        const fields = @import("tuple_unpack.zig").fields(c.a, c.program, c.function, store, initializing) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Invalid => return c.rejectInternal(span, "E_INTERNAL_TUPLE_STAGING", "compiler bug: invalid complete tuple staging"),
        };
        try c.expression(store.value, .move);
        const dependency = try c.resourceOrigin(store.value);
        if (dependency) |provider| if (!c.state[provider].available)
            return c.reject(span, .{ .code = resource_escape, .rule = .P2 }, "tuple fields cannot outlive their dependent provider");
        c.state[@backingInt(store.slot)] = .{};
        for (fields, store.unpack.?) |field, optional| {
            const slot = @backingInt(optional orelse continue);
            c.state[slot] = .{ .available = true, .dependency = if (resources.dependent(c.program, field.ty)) dependency orelse none else none, .traits = .{ .writable = c.function.scope.locals[slot].mutable } };
        }
    }

    /// `take(mut place)` and `exchange(mut place, value)`: the replacement moves in and the place is written (its root
    /// must be exclusive, the same check as an update); the moved-out value is the owned result of the call. Lowering
    /// builds the replacement before it reads the place, so the replacement is checked first: a replacement that moves
    /// the place's own owner (`exchange(mut xs, own xs)`) leaves the place unavailable and the write is refused.
    fn placeExchange(c: *Checker, exchange: @FieldType(@FieldType(typed.Node, "data"), "place_exchange")) Error!void {
        if (exchange.value) |value| try c.expression(value, .move);
        // The write is judged against live loans by the place it names, as a `mut` argument is.
        const previous = c.argument;
        defer c.argument = previous;
        const place = c.program.nodes[@backingInt(exchange.place)];
        const path = if (place.data == .local and c.temporary(@backingInt(place.data.local))) try c.capturedReceiverPath(@backingInt(place.data.local)) else try c.argumentPath(exchange.place);
        c.argument = .{ .value = exchange.place, .path = path, .write = true };
        try c.expression(exchange.place, .update);
    }

    fn fieldExpression(c: *Checker, id: typed.NodeId, access: Access) Error!void {
        const node = c.program.nodes[@backingInt(id)];
        const field = node.data.field;
        // FR91: a later move of a group takes its field from the record the group's first move consumed. The group was formed
        // while the record was whole (`carriesField`), so a payload binding (`match own`, `own x else:`), which owns its
        // payload only while it is available (`ownedPayload`), is still the group's record at the later moves.
        const grouped = if (access == .move) c.field_moves.find(id) else null;
        const follows = if (grouped) |move| c.followsGroup(move) else false;
        if (follows or (access == .move and c.canMoveAffineField(field.base, field.index))) {
            if (!follows) {
                try c.moveCarrierBase(field.base);
                if (grouped) |move| c.state[move.root].traits.field_opened = true;
            }
            if (c.diagnostics.observer) |observer| try observer.record("carrier", node.span, .{ .function = c.function.name, .field = field.index });
            return;
        }
        const writes = access == .mutate or access == .update;
        // A write to a part of an owner the check does not track is judged here against the running `match mut`s, with
        // the written path (FX9); its base is then only read, so the owner's write check does not run twice.
        if (writes) if (c.untrackedRoot(field.base)) |root| {
            try c.checkHeldPartWrite(root, node, node.span);
            return c.expression(field.base, .read);
        };
        try c.expression(field.base, if (writes) .mutate else .read);
        if (access != .move or !c.owns(node.ty)) return;
        const rule = c.projectedBorrowRule(field.base) orelse .B8;
        const message = try c.lentParameterFields(id, try c.escapeMessage(node.span, c.origin(field.base), .copy, ""));
        return c.rejectCopy(node.span, node.ty, .{ .code = borrow_error, .rule = rule }, message);
    }

    /// FR91B: the refusal of `own p.lo` where the statement moves several fields of `p` and `p` is a plain or `mut` parameter,
    /// whose storage is the caller's: the message names the parameter to declare `own` before the copy.
    fn lentParameterFields(c: *Checker, id: typed.NodeId, message: []const u8) Error![]const u8 {
        const move = c.field_moves.attempt(id) orelse return message;
        if (move.root >= c.function.signature.parameter_count) return message;
        const own = c.function.scope.own_parameters;
        if (move.root < own.len and own[move.root]) return message;
        const copy_at = std.mem.indexOf(u8, message, "; write `copy(") orelse return message;
        const name = c.function.scope.locals[move.root].name;
        return std.fmt.allocPrint(c.diagnostics.allocator, "{s}; declare the parameter `own {s}` of `{s}` to move several of its fields out, or{s}", .{
            message[0..copy_at], name, c.function.name, message[copy_at + 1 ..],
        });
    }

    /// FR91: whether a move of a group follows the group's first move on this path: the record is gone, consumed there
    /// (`field_opened`, at a root of the statement's group), so the move takes its field from what the lowering opened.
    fn followsGroup(c: *const Checker, move: field_moves.Move) bool {
        const state = c.state[move.root];
        return !state.available and state.traits.field_opened and c.field_moves.consumedAt(c.program, move.root, state.moved_span);
    }

    /// Whether a field node moves out of its record: the checker's test for `field_moves.of`.
    fn carriesField(c: *const Checker, id: typed.NodeId) error{}!bool {
        const field = c.program.nodes[@backingInt(id)].data.field;
        return c.canMoveAffineField(field.base, field.index);
    }

    /// A field leaves an owned plain record by consuming the complete carrier.
    /// Lowering destroys every sibling at that point, including conditional paths.
    fn canMoveAffineField(c: *const Checker, base: typed.NodeId, field: usize) bool {
        const ty = c.program.nodes[@backingInt(base)].ty;
        if (!ty.isAggregate()) return false;
        const record = c.program.records[ty.recordIndex()];
        if (!ordinaryRecord(record) or field >= record.fields.len) return false;
        const moved = record.fields[field].ty;
        if (!c.owns(moved) and !resources.affine(c.program, moved)) return false;
        return c.ownedRecordPlace(base);
    }

    /// Whether a record place is a field path from an owned root: an owned parameter (`own`) or an owned local, never a
    /// fresh value, an element, a temporary, or a borrowed or `mut` parameter.
    fn ownedRecordPlace(c: *const Checker, id: typed.NodeId) bool {
        var node = id;
        while (true) switch (c.program.nodes[@backingInt(node)].data) {
            .local => |slot| {
                const binding = @backingInt(slot);
                if (c.ownedPayload(binding)) return true;
                if (c.temporary(binding)) return false;
                if (binding < c.function.signature.parameter_count) {
                    const own = binding < c.function.scope.own_parameters.len and c.function.scope.own_parameters[binding];
                    return own;
                }
                return c.ownedLocal(binding);
            },
            .field => |field| node = field.base,
            else => return false,
        };
    }

    /// Preserve the actual source of a borrowed projection through lowering.
    /// This selects a refusal, never permission to move the borrowed value.
    fn projectedBorrowRule(c: *const Checker, value: typed.NodeId) ?Rule {
        var current = value;
        var remaining = c.program.nodes.len + c.state.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            const node = c.program.nodes[@backingInt(current)];
            switch (node.data) {
                .field => |field| current = field.base,
                .block_value => |block| current = block.value,
                .wrap, .unwrap, .cast => |inner| current = inner,
                .index => return .B7,
                .buffer_operation => |operation| return switch (operation.kind) {
                    .read, .get, .key_at, .value_at, .setdefault, .borrow_view => .B7,
                    else => null,
                },
                .call => |call| {
                    const signature = c.program.functions[@backingInt(call.function)].signature;
                    return if (return_borrow.effectiveSources(c.program.records, signature).len != 0) .R3 else null;
                },
                .local => |local| {
                    const slot = @backingInt(local);
                    if (c.temporaryValue(slot)) |definition| {
                        current = definition;
                        continue;
                    }
                    if (!c.state[slot].traits.borrowed) return null;
                    const rule = c.state[slot].traits.rule;
                    if (rule == .R3 or rule == .M1) return rule;
                    const root = c.rootOf(slot);
                    return if (c.state[root].traits.borrowed and c.state[root].traits.rule == .M1) .M1 else null;
                },
                else => return null,
            }
        }
        return null;
    }

    /// Transparent lowering preserves the one place a written marker names.
    fn markerPlace(c: *const Checker, value: typed.NodeId) ?typed.NodeId {
        var current = value;
        var projection: ?typed.NodeId = null;
        var remaining = c.program.nodes.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            const node = c.program.nodes[@backingInt(current)];
            switch (node.data) {
                .local => |slot| return if (c.namedBinding(@backingInt(slot))) projection orelse current else null,
                .field => |field| {
                    if (projection == null) projection = current;
                    current = field.base;
                },
                .block_value => |block| current = block.value,
                .wrap, .unwrap, .cast => |inner| current = inner,
                else => return null,
            }
        }
        return null;
    }

    /// A shared template can be edited only when this occurrence has a fixed type.
    /// `mark`, when given, is the node the edit writes or removes the marker of, so `checkEvery` can read on past the refusal.
    fn markerFix(c: *Checker, node: typed.Node, edit: language.diagnostic.Edit, mark: ?Mark) Error!void {
        if (c.probing.active or c.typeDependentRepair(node)) return;
        if (c.source == null) return;
        c.failure.copy = .{};
        c.failure.repair = .{ .explicit_fix = try c.diagnostics.allocator.dupe(language.diagnostic.Edit, &.{edit}) };
        if (mark) |at| c.recoverAt(at, if (edit.text.len == 0) .unmark else .own);
    }

    fn misplacedMarker(c: *Checker, id: ?typed.NodeId, node: typed.Node, refusal: Refusal, message: []const u8) Error!void {
        const result = c.reject(node.span, refusal, message);
        if (c.source) |src| if (own_marker.remove(src, node.span)) |edit| try c.markerFix(node, edit, if (id) |at| .{ .id = at } else null);
        return result;
    }

    /// Whether an `own` marker sits on a `@linear` value or on a field read of one (D-FFI-11).
    fn linearMarker(program: typed.Program, node: typed.Node) bool {
        if (typed.linear(node.ty, program.records)) return true;
        if (node.data != .field) return false;
        return typed.linear(program.nodes[@backingInt(node.data.field.base)].ty, program.records);
    }

    /// Symbolic typing preserves type dependency at this source occurrence;
    /// no concrete type equality guesses whether a scalar is generic.
    fn genericScalarPlace(c: *const Checker, id: typed.NodeId) bool {
        if (c.function.type_arguments.len == 0) return false;
        if (!c.program.nodes[@backingInt(id)].type_dependent) return false;
        return c.markerPlace(id) != null;
    }

    /// A marker may only transfer a named managed place. Bare return/fail names
    /// transfer implicitly, and a generic scalar instance ignores the marker.
    fn writtenMarker(c: *Checker, id: typed.NodeId, access: Access) Error!void {
        const node = c.program.nodes[@backingInt(id)];
        if (!node.own) return;
        if (c.marker.returned == id and node.data == .local) return c.returnedMarker(id, node);
        if (!c.owns(node.ty)) {
            if (c.genericScalarPlace(id)) return;
            // A `@linear` owner, or a field read that consumes one, is written `own` though Core sees scalars: the
            // front end's linear rules count the marker (D-FFI-11), and here it is a plain read.
            if (linearMarker(c.program, node)) return;
            // A capability, or a value that held one, owned its provider before 5C, so `own` was required on it: the
            // marker still checks, and the front end's `W_CAPABILITY_OWN` warning removes it.
            if (language.provider_types.holdsFormerLeaf(c.program.records, node.ty)) return;
            return c.misplacedMarker(id, node, .{ .code = "E_OWN_MARKER", .rule = .B2 }, "a scalar has no managed storage to transfer; remove own");
        }
        const borrowed_field = node.data == .field and c.projectedBorrowRule(node.data.field.base) != null;
        if (c.markerPlace(id) == null and !borrowed_field) return c.unplacedMarker(id, node, access);
        if (access != .move) {
            // `own owner.field` of a `@linear` owner is what ends the owner (the front end counts the marker), so removing it
            // would leave the owner unconsumed: the refusal says so and offers no removal.
            if (c.linearOwner(id)) |owner| return c.reject(node.span, .{ .code = "E_OWN_MARKER", .rule = .W2 }, try c.linearReadMarkerMessage(node, owner));
            // A source-written marker in a read position already has an exact
            // removal repair. Synthetic and dependent markers stay untouched.
            if (c.probing.active and !node.type_dependent) if (c.probing.needed_removal) |needed| {
                if (c.source) |src| if (own_marker.remove(src, node.span) != null) {
                    needed.* = id;
                };
            };
            return c.misplacedMarker(id, node, .{ .code = "E_OWN_MARKER", .rule = .W2 }, try c.readMarkerMessage(id, node));
        }
    }

    /// The refusal of an `own` on a value that is not a named place: a fresh value is already owned, so the marker adds nothing;
    /// a lent value (an element, a slice, a `from` result) cannot be given, which is the Escape rule's, unless the position
    /// only reads it.
    fn unplacedMarker(c: *Checker, id: typed.NodeId, node: typed.Node, access: Access) Error!void {
        const refusal: Refusal = .{ .code = "E_OWN_MARKER", .rule = .B2 };
        // `own NAME` of an owner narrowed to `Some` that the function does not own (a plain or `mut` parameter, a loop
        // variable, a match binding) is lent by that owner's root, not by the read's hidden payload (NARROW-OWN).
        const narrowed = if (language.option_flow.narrowedRead(c.program.nodes, c.program.statements, id)) |owner| c.rootOf(@backingInt(owner)) else null;
        const lender = narrowed orelse try c.lentRoot(id) orelse
            return c.misplacedMarker(id, node, refusal, "a fresh value is already owned, so `own` adds nothing; remove `own`");
        if (access != .move and c.argument.value != null and c.argument.value.? == id) return c.misplacedMarker(id, node, refusal, try c.readMarkerMessage(id, node));
        const repairs: escape_message.Repairs = if (!c.probing.active and c.probeMarkerRemoval(id)) .{ .written_own = .lend } else .{ .written_own = .then_copy };
        if (narrowed != null and repairs.written_own == .then_copy) return c.narrowedMarker(node, refusal, try c.escapeMessage(node.span, lender, repairs, ""));
        return c.misplacedMarker(id, node, refusal, try c.escapeMessage(node.span, lender, repairs, ""));
    }

    /// The refusal of `own NAME` over a narrowed owner the function does not own, where removing the marker leaves a bare read the
    /// store refuses again: the edit writes the copy in its place (`copy(NAME)`), which the message names after the removal.
    fn narrowedMarker(c: *Checker, node: typed.Node, refusal: Refusal, message: []const u8) Error!void {
        const result = c.reject(node.span, refusal, message);
        if (c.probing.active or node.type_dependent) return result;
        const src = c.source orelse return result;
        const edit = own_marker.remove(src, node.span) orelse return result;
        const name = std.mem.trim(u8, src.text(.{ .start = edit.span.end, .end = node.span.end }), " ");
        c.failure.copy = .{};
        const copy: language.diagnostic.Edit = .{ .span = node.span, .text = try std.fmt.allocPrint(c.diagnostics.allocator, "copy({s})", .{name}) };
        c.failure.repair = .{ .explicit_fix = try c.diagnostics.allocator.dupe(language.diagnostic.Edit, &.{copy}) };
        return result;
    }

    /// The refusal of `return own x`: a return gives its value without the marker. When `x` is lent, the value would leave
    /// the call, so the message is the Escape rule's and names the repair the fix makes (removing `own`) and what follows.
    fn returnedMarker(c: *Checker, id: typed.NodeId, node: typed.Node) Error!void {
        const refusal: Refusal = .{ .code = "E_OWN_MARKER", .rule = .B2 };
        const slot = @backingInt(node.data.local);
        if (!c.state[slot].traits.borrowed) return c.misplacedMarker(id, node, refusal, "a return gives its value without `own`; remove `own`");
        const root = c.rootOf(slot);
        const parameter = root < c.function.signature.parameter_count;
        const declared = parameter and std.mem.indexOfScalar(u16, return_borrow.sources(c.function.signature), @intCast(root)) != null;
        const repairs: escape_message.Repairs = if (declared)
            .{ .written_own = .borrow }
        else if (parameter)
            .{ .written_own = .{ .declare = try c.fromNames(&.{root}) } }
        else
            .{ .written_own = .then_copy };
        return c.misplacedMarker(id, node, refusal, try c.escapeMessageTo(node.span, root, .returned, repairs, ""));
    }

    /// The `@linear` local a field read `own owner.a.b` is rooted at, or null for any other place.
    fn linearOwner(c: *const Checker, id: typed.NodeId) ?typed.Node {
        var current = c.program.nodes[@backingInt(id)];
        if (current.data != .field) return null;
        while (current.data == .field) current = c.program.nodes[@backingInt(current.data.field.base)];
        if (current.data != .local or !typed.linear(current.ty, c.program.records)) return null;
        return current;
    }

    /// The marker wording for `own owner.field` in a position that only reads: it would end the `@linear` owner if the value
    /// were taken, and removing it leaves the owner unconsumed, so the repair is to take the field where it is kept.
    fn linearReadMarkerMessage(c: *Checker, node: typed.Node, owner: typed.Node) Error![]const u8 {
        const a = c.diagnostics.allocator;
        const generic = "`own` of a `@linear` owner's field ends the owner only where the field is taken, and this position only reads it";
        const src = c.source orelse return generic;
        if (node.span.end > src.bytes.len or owner.span.end > src.bytes.len) return generic;
        const value = try escape_message.quote(a, src.text(node.span));
        const name = try escape_message.quote(a, src.text(owner.span));
        return std.fmt.allocPrint(a, "`own {s}` gives `{s}`, but this position only reads it, so it does not end the `@linear` owner `{s}`, and " ++
            "removing `own` would leave `{s}` unconsumed; take the field where its value is kept (`const kept = own {s}`, " ++
            "`return own {s}`) or give `{s}` to an `own` parameter", .{ value, value, name, name, value, value, name });
    }

    /// The marker wording for an `own` in a position that only reads its value: `own` gives, and this position takes nothing.
    fn readMarkerMessage(c: *Checker, id: typed.NodeId, node: typed.Node) Error![]const u8 {
        const a = c.diagnostics.allocator;
        const spelled = if (c.source) |src| if (node.span.start < node.span.end and node.span.end <= src.bytes.len) src.text(node.span) else "this value" else "this value";
        const value = try escape_message.quote(a, spelled);
        const position: []const u8 = if (c.argument.value != null and c.argument.value.? == id) "this argument is only read" else "this position only reads it";
        return std.fmt.allocPrint(a, "`own {s}` gives `{s}`, but {s}; remove `own`", .{ value, value, position });
    }

    /// The root that lends the value `id` reads when the value is lent and no named place: an element, a slice, a view or a
    /// `from` result. Null for a fresh value.
    fn lentRoot(c: *Checker, id: typed.NodeId) Error!?usize {
        if (c.viewSourceSlot(id) orelse c.sliceRoot(id) orelse c.origin(id)) |root| return root;
        // A slice written with `own` is not flagged as a view, but it still slices its owner: look through the blocks, wrappers
        // and casts the lowering puts around it.
        var current = id;
        var remaining: usize = 8;
        while (remaining != 0) : (remaining -= 1) {
            const node = c.program.nodes[@backingInt(current)];
            switch (node.data) {
                .block_value => |block| current = block.value,
                .wrap, .cast, .unwrap => |inner| current = inner,
                .buffer_operation => |operation| switch (operation.kind) {
                    .slice, .slice_bytes, .text_tail => return if (c.slicesIntoOwning(node.ty)) c.rootOf(@backingInt(operation.owner)) else null,
                    else => break,
                },
                else => break,
            }
        }
        if (c.program.nodes[@backingInt(id)].data != .call) return null;
        const roots = (try c.borrowedCallRoots(id, 0)) orelse return null;
        return if (roots.items.len != 0) roots.items[0] else null;
    }

    /// The `own` marker's edit at node `id`, published with the recovery that checks the rest of the function with it written.
    fn ownFix(c: *Checker, node: typed.Node, id: typed.NodeId) Error!void {
        const src = c.source orelse return;
        if (try own_marker.insert(c.diagnostics.allocator, src, node.span)) |edit| try c.markerFix(node, edit, .{ .id = id });
    }

    /// Requiring a marker follows successful ownership checking, so existing
    /// unavailable-value, borrow, resource and overlap refusals keep priority.
    fn moveMarker(c: *Checker, id: typed.NodeId) Error!void {
        if (c.marker.permitted == id or c.marker.returned == id) return;
        const node = c.program.nodes[@backingInt(id)];
        if (node.own or !c.owns(node.ty)) return;
        if (node.data != .local and node.data != .field) return;
        if (node.data == .local and !c.namedBinding(@backingInt(node.data.local))) return;
        if (c.probing.active) {
            if (c.probing.moves) |moves| {
                if (node.type_dependent or resources.dependent(c.program, node.ty)) return;
                const root = c.origin(id) orelse return;
                const moved = c.state[root].moved_span;
                if (moved.start < moved.end) try moves.append(c.diagnostics.allocator, .{ .definition = id, .moved = moved });
            }
            return;
        }
        const rule: Rule = if (c.argument.value == id) .W2 else .B2;
        const lender = c.origin(id);
        const result = c.reject(node.span, .{ .code = "E_OWN_MARKER", .rule = rule }, try c.escapeMessage(node.span, lender, .{ .give_or_copy = .{} }, ""));
        if (c.typeDependentRepair(node)) return result;
        // Rechecking the whole function includes later reads of the binding or
        // any sibling of a consumed record. A transfer is certain only when
        // that check succeeds; otherwise prove an explicit copy instead.
        var blocked: ?Blocked = null;
        if (c.probeOwn(id, null, &blocked)) {
            try c.ownFix(node, id);
        } else if (c.probeMoveCopy(id)) {
            c.failure.copy = .{ .span = node.span };
            c.failure.message = try c.escapeMessage(node.span, lender, .copy, "");
            try c.readFirstRepair(id, lender);
            c.recoverAt(.{ .id = id }, .copy);
        } else if (blocked) |other| switch (try c.ownBeside(id, other)) {
            .proven => try c.ownFix(node, id),
            .waits => if (c.source) |src| {
                const at = src.locate(other.span.start);
                const waits: escape_message.Repairs = .{ .give_or_copy = .{ .waits = .{ .line = at.line, .column = at.column } } };
                c.failure.message = try c.escapeMessage(node.span, lender, waits, "");
            },
            .caused => {},
        };
        return result;
    }

    /// The call or constructor that holds a moved argument, and the argument.
    const MovedArgument = struct { container: typed.NodeId, moved: typed.NodeId };

    /// The argument of a call or constructor that gives a local away: node `id` when it is given, else the argument written `own`
    /// whose span is `span`. Null when the function has none.
    fn movedArgument(c: *Checker, span: Span, id: ?typed.NodeId) Error!?MovedArgument {
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item != .expression) continue;
            switch (c.program.nodes[@backingInt(item.expression)].data) {
                .record => |fields| for (fields) |field| {
                    if (c.givesLocal(field.value, span, id)) return .{ .container = item.expression, .moved = field.value };
                },
                .call => |call| for (call.arguments) |value| {
                    if (c.givesLocal(value, span, id)) return .{ .container = item.expression, .moved = value };
                },
                else => {},
            }
        }
        return null;
    }

    /// Whether `value` is the argument written `own` over the local at `span`, or over a field of it (FR63: `own state.lat` moves
    /// the record `state`, whose local is the span the move was recorded at); node `id` itself when it is given.
    fn givesLocal(c: *const Checker, value: typed.NodeId, span: Span, id: ?typed.NodeId) bool {
        if (id) |wanted| return value == wanted;
        const node = c.program.nodes[@backingInt(value)];
        if (!node.own or (node.data != .local and node.data != .field)) return false;
        const root = c.program.nodes[@backingInt(read_first.rootLocal(c.program, value) orelse return false)].span;
        return root.start == span.start and root.end == span.end;
    }

    /// FR41: the repair that writes the call with the reads first, for a moved local that a later argument of the same call only
    /// reads (`read_first.zig`), and the argument that gives it, once the function checks with the call so written.
    fn readFirstRepair(c: *Checker, id: typed.NodeId, lender: ?usize) Error!void {
        const node = c.program.nodes[@backingInt(id)];
        if (c.probing.active or node.data != .local or node.type_dependent or resources.dependent(c.program, node.ty)) return;
        const found = (try c.readFirstPlan(node.span, id)) orelse return;
        if (!c.probeReadFirst(found.plan, found.moved)) return;
        var facts = try c.escapeFacts(node.span, .{ lender, null }, c.sink, .copy, "");
        facts.form = .{ .read_first = .{ .moved = found.plan.moved, .reads = found.plan.reads } };
        c.failure.message = try escape_message.compose(c.diagnostics.allocator, facts);
        c.failure.copy = .{};
        c.failure.repair = .{ .explicit_fix = try c.diagnostics.allocator.dupe(language.diagnostic.Edit, &.{found.plan.edit}) };
    }

    /// FR41: a read of a local after the call or constructor that gives it away, in an argument after the one that gives it: the
    /// message names the call written with the read first, and the repair writes it so.
    fn readBeforeMove(c: *Checker, slot: usize, moved: Span, read: Span) Error!bool {
        if (c.probing.active or !c.namedBinding(slot)) return false;
        const found = (try c.readFirstPlan(moved, null)) orelse return false;
        if (read.start < found.plan.reads_span.start or read.end > found.plan.reads_span.end) return false;
        if (!c.probeReadFirst(found.plan, found.moved)) return false;
        c.failure.message = try read_first.movedMessage(c.diagnostics.allocator, c.function.scope.locals[slot].name, found.plan);
        c.failure.repair = .{ .explicit_fix = try c.diagnostics.allocator.dupe(language.diagnostic.Edit, &.{found.plan.edit}) };
        return true;
    }

    /// FR63: a field moved out of a record that the move of another field consumed. The message names the first move and says what
    /// moving several fields needs; where the record is a `mut` local the function owns and nothing uses it after the statement
    /// (`take_fields.zig`), the repair writes each move as `take(mut place)`, once the function checks with them. A read that follows
    /// a group of moves in its statement (FR91, `grouped`) keeps the plain refusal unless that repair is offered. FR91B: two moves
    /// written as two `const` locals that the next statement's call or constructor takes are joined into it instead
    /// (`take_fields.Join`), which wins over `take` as it leaves no default behind; else the message names the way out that fits
    /// where the refused move stands (`take_fields.Found.shape`). Whether it wrote the message.
    fn takeFieldsRepair(c: *Checker, slot: usize, moved: Span, refused: Span, grouped: bool) Error!bool {
        if (c.probing.active or !c.namedBinding(slot)) return false;
        const src = c.source orelse return false;
        const allocator = c.diagnostics.allocator;
        const found = (try take_fields.find(allocator, src, c.program, c.function, .{ .slot = slot, .moved = moved, .refused = refused })) orelse return false;
        var takes: []const []const u8 = &.{};
        var together: []const u8 = try std.fmt.allocPrint(allocator, "f(own {s}, own {s})", .{
            take_fields.placeText(src.bytes, c.program.nodes[@backingInt(found.first)].span),
            take_fields.placeText(src.bytes, c.program.nodes[@backingInt(found.refused)].span),
        });
        if (found.join != null and c.probeJoin(found.join.?)) {
            together = found.join.?.text;
            c.failure.repair = .{ .explicit_fix = try allocator.dupe(language.diagnostic.Edit, found.join.?.edits) };
        } else if (found.repair) |repair| if (c.probeTakeFields(found.moves)) {
            takes = repair.places;
            c.failure.repair = .{ .explicit_fix = try allocator.dupe(language.diagnostic.Edit, repair.edits) };
        };
        if (grouped and takes.len == 0) return false;
        if (found.shape == .operand and found.holder.len != 0) together = found.holder;
        const at = src.locate(moved.start);
        const line = src.locate(refused.start).line;
        c.failure.message = try escape_message.consumedMessage(allocator, .{
            .record = c.function.scope.locals[slot].name,
            .first = src.text(c.program.nodes[@backingInt(found.first)].span),
            .at = .{ .line = at.line, .column = at.column },
            .same_line = at.line == line,
            .takes = takes,
            .shape = found.shape,
            .together = together,
        });
        return true;
    }

    /// FR91B: a read of a field of a record that `own p.field` consumed, in the statement of the moves or after it. The message
    /// says to read it into a local before the statement that moves (`const n = p.n`; `copy(p.tag)` for a value that owns
    /// storage, which a `const` alias would keep borrowed from the record the move then consumes).
    fn readAfterFieldMove(c: *Checker, slot: usize, moved: Span, read: Span, grouped: bool) Error!void {
        if (c.probing.active or !c.namedBinding(slot)) return;
        const src = c.source orelse return;
        const bytes = src.bytes;
        if (moved.end >= bytes.len or bytes[moved.end] != '.' or read.end >= bytes.len or bytes[read.end] != '.') return;
        var before = moved.start;
        while (before > 0 and (bytes[before - 1] == ' ' or bytes[before - 1] == '\t')) before -= 1;
        if (before < 3 or !std.mem.eql(u8, bytes[before - 3 .. before], "own")) return;
        const place = placeChain(bytes, read.start);
        const name = place[(std.mem.lastIndexOfScalar(u8, place, '.') orelse return) + 1 ..];
        if (name.len == 0 or !std.ascii.isAlphabetic(name[0])) return;
        const owning = for (c.program.nodes) |node| {
            if (node.data == .field and node.span.start == read.start and node.span.end == read.start + place.len) break c.owns(node.ty);
        } else return;
        const allocator = c.diagnostics.allocator;
        const at = src.locate(moved.start);
        const same_line = at.line == src.locate(read.start).line;
        const where = if (grouped or same_line)
            try std.fmt.allocPrint(allocator, "at column {d} consumed `{s}` and destroyed its other fields; read `{s}` into a local before this statement", .{ at.column, c.function.scope.locals[slot].name, place })
        else
            try std.fmt.allocPrint(allocator, "at line {d}, column {d} consumed `{s}` and destroyed its other fields; read `{s}` into a local before that statement", .{ at.line, at.column, c.function.scope.locals[slot].name, place });
        const value = if (owning) try std.fmt.allocPrint(allocator, "copy({s})", .{place}) else place;
        c.failure.message = try std.fmt.allocPrint(allocator, "'{s}' was moved or is unavailable on this path; `own {s}` {s} (`const {s} = {s}`) and use that, or write copy(...) to keep both", .{
            c.function.scope.locals[slot].name, placeChain(bytes, moved.start), where, name, value,
        });
    }

    /// FR91B: whether the function checks with the two statements of `join` emptied and its two uses moving the fields their
    /// locals were initialized with: the ownership checker's verdict on the joined statement.
    fn probeJoin(c: *Checker, join: take_fields.Join) bool {
        const nodes = c.a.dupe(typed.Node, c.program.nodes) catch return false;
        const statements = c.a.dupe(typed.Statement, c.program.statements) catch return false;
        for (join.uses, join.cleared) |use, cleared| {
            const store = statements[@backingInt(cleared)].data.initialize;
            nodes[@backingInt(use)] = nodes[@backingInt(store.value)];
            statements[@backingInt(cleared)].data = .{ .block = &.{} };
        }
        var program = c.program;
        program.nodes = nodes;
        program.statements = statements;
        return c.proveRepair(.{ .program = program, .function = c.function }, join.uses[0]);
    }

    /// Whether the function checks with each of `moves` written as `take(mut place)`: the ownership checker's verdict.
    fn probeTakeFields(c: *Checker, moves: []const typed.NodeId) bool {
        const patched = c.scratchMark();
        defer c.scratchRollback(patched);
        const program = c.withExchanges(moves) catch return false;
        return c.proveRepair(.{ .program = program, .function = c.function }, moves[0]);
    }

    /// The program with each of `moves` replaced by `take(mut place)` of the same field: a patch of the scratch copy when it can take
    /// one (the caller undoes it with `scratchRollback`), else a private copy of the nodes allocated from `c.a`.
    fn withExchanges(c: *Checker, moves: []const typed.NodeId) error{OutOfMemory}!typed.Program {
        if (c.scratch) |scratch| if (try scratch.exchange(c.program, moves)) |view| return view;
        const nodes = try c.a.alloc(typed.Node, c.program.nodes.len + moves.len);
        @memcpy(nodes[0..c.program.nodes.len], c.program.nodes);
        for (moves, c.program.nodes.len..) |move, at| {
            nodes[at] = nodes[@backingInt(move)];
            nodes[at].own = false;
            nodes[@backingInt(move)] = taking(nodes[@backingInt(move)], @fromBackingInt(at));
        }
        var program = c.program;
        program.nodes = nodes;
        return program;
    }

    const ReadFirstPlan = struct { plan: read_first.Plan, moved: typed.NodeId };

    /// The plan of the call that holds the moved argument at `span` (node `id` when known), before it is proved.
    fn readFirstPlan(c: *Checker, span: Span, id: ?typed.NodeId) Error!?ReadFirstPlan {
        const src = c.source orelse return null;
        const held = (try c.movedArgument(span, id)) orelse return null;
        const node = c.program.nodes[@backingInt(held.moved)];
        if (node.type_dependent or resources.dependent(c.program, node.ty)) return null;
        const found = (try read_first.plan(c.diagnostics.allocator, src, c.program, held.container, held.moved)) orelse return null;
        return .{ .plan = found, .moved = held.moved };
    }

    /// Whether the function checks with the call written as `plan` writes it: the moved argument marked `own` and evaluated after the
    /// arguments that follow it. The ownership checker's own verdict, so no read after the move, no view of the value kept, and no
    /// other use of it is left.
    fn probeReadFirst(c: *Checker, found: read_first.Plan, moved: typed.NodeId) bool {
        const patched = c.scratchMark();
        defer c.scratchRollback(patched);
        var marked = c.program.nodes[@backingInt(moved)];
        marked.own = true;
        const program = c.withNodes(.{ .id = moved, .node = marked }, .{ .id = found.container, .node = found.rewritten }) catch return false;
        return c.proveRepair(.{ .program = program, .function = c.function }, moved);
    }

    /// The parent field transfer consumes this base internally; its own marker
    /// belongs to the complete source projection, not each carrier prefix.
    fn moveCarrierBase(c: *Checker, base: typed.NodeId) Error!void {
        const previous = c.marker.permitted;
        c.marker.permitted = base;
        defer c.marker.permitted = previous;
        try c.expression(base, .move);
    }

    /// Prove a marker removal against the complete declared return contract.
    /// The source edit leaves every expression and wrapper in place.
    fn probeMarkerRemoval(c: *Checker, id: typed.NodeId) bool {
        const patched = c.scratchMark();
        defer c.scratchRollback(patched);
        const program = c.withOwn(id, false) catch return false;
        var probe: Failure = .{};
        const shared = c.probeShared(program);
        checkFunction(c.a, shared, c.function, &probe, .{ .active = true }) catch return false;
        return true;
    }

    /// A declared borrowed return can lose its marker when the whole contract
    /// still checks. Other marked borrows need a proved independent copy.
    fn borrowedMarkerRepair(c: *Checker, id: typed.NodeId) Error!void {
        const node = c.program.nodes[@backingInt(id)];
        if (!node.own) return;
        if (node.type_dependent) {
            c.failure.copy = .{};
            c.failure.repair = .none;
            return;
        }
        if (c.failure.copy.span == null) return;
        if (c.failure.rule == .B9) return;
        if (c.probing.active) return;
        // A raw copy repair would wrap the still-written marker. Offer only an
        // exact prefix replacement, and withhold it when source is unavailable.
        c.failure.copy = .{};
        c.failure.repair = .none;
        const src = c.source orelse return;
        const removal = own_marker.remove(src, node.span) orelse return;
        if (c.returning and return_borrow.effectiveSources(c.program.records, c.function.signature).len != 0 and c.probeMarkerRemoval(id)) {
            try c.markerFix(node, removal, .{ .id = id });
            c.failure.message = try c.escapeMessageTo(node.span, c.origin(id), .returned, .{ .written_own = .borrow }, "");
            return;
        }
        if (!c.probeMoveCopy(id)) return;
        c.failure.repair = .{ .explicit_fix = try c.diagnostics.allocator.dupe(language.diagnostic.Edit, &.{
            .{ .span = removal.span, .text = "copy(" },
            .{ .span = .{ .start = node.span.end, .end = node.span.end }, .text = ")" },
        }) };
        c.failure.copy = .{};
        c.recoverAt(.{ .id = id }, .copy);
    }

    /// A different source expression starts a new copy result boundary. Nodes
    /// sharing their outer expression's span retain its setup/result distinction.
    /// Setup remains ineligible through nested expressions with different spans.
    fn enterCopyBoundary(c: *Checker, id: typed.NodeId) void {
        if (!c.probing.active) return;
        const previous = c.copy_boundary orelse {
            c.copy_boundary = .{ .definition = id };
            return;
        };
        if (!std.meta.eql(c.program.nodes[@backingInt(previous.definition)].span, c.program.nodes[@backingInt(id)].span))
            c.copy_boundary = .{ .definition = id, .result = previous.result };
    }

    fn expression(c: *Checker, id: typed.NodeId, access: Access) Error!void {
        const node = c.program.nodes[@backingInt(id)];
        const previous_boundary = c.copy_boundary;
        c.enterCopyBoundary(id);
        defer c.copy_boundary = previous_boundary;
        try c.writtenMarker(id, access);
        const previous_marker = c.marker.permitted;
        if (node.own) c.marker.permitted = c.markerPlace(id);
        defer c.marker.permitted = previous_marker;
        switch (node.data) {
            .integer, .boolean, .unit, .blob, .hole => {},
            .function_value => |function| try c.functionValue(node.span, function),
            .local => |slot| c.checkLocal(@backingInt(slot), access, node.span) catch |err| {
                if (err == error.Rejected) {
                    c.noteBorrowCopy(id, access);
                    try c.borrowedMarkerRepair(id);
                    c.noteHeldRecord(id);
                    try c.takeParameterMessage(id);
                }
                return err;
            },
            .borrow_selection => |selection| {
                if (!@import("build_borrow_selection.zig").valid(c.program, selection, node.ty)) return c.rejectInternal(node.span, "E_INTERNAL_BORROW_SELECTION", "compiler bug: invalid borrowed selection type contract");
                if (access != .read and access != .move and c.owns(node.ty)) return c.reject(node.span, .{ .code = borrow_error, .rule = .R6 }, "a borrowed selection cannot be mutated; make an explicit copy(value) first");
                const saved = c.loans.items.len;
                defer c.loans.shrinkRetainingCapacity(saved);
                try c.expression(selection.first, .read);
                try c.loanExpression(selection.first, false);
                try c.expression(selection.second, .read);
                if (access == .move and c.owns(node.ty)) {
                    const lenders: [2]?usize = .{ c.origin(selection.first), c.origin(selection.second) };
                    return c.rejectCopy(node.span, node.ty, .{ .code = borrow_error, .rule = .R6 }, try c.escapeMessageAmong(node.span, lenders, c.sink, .copy, ""));
                }
            },
            .block_value => |block| {
                const boundary = c.copy_boundary;
                if (c.copy_boundary) |*active| active.result = false;
                _ = try c.checkStatement(block.body);
                c.copy_boundary = boundary;
                try c.expression(block.value, access);
            },
            .cast => |value| {
                const from = c.program.nodes[@backingInt(value)].ty;
                try c.expression(value, if (from != node.ty) .read else access);
            },
            .wrap, .unwrap, .arena_escape => |value| try c.expression(value, access),
            .length => |value| try c.expression(value, .read),
            .unary => |unary| try c.expression(unary.operand, .read),
            .vector_binary => |vector| {
                try c.expression(vector.left, .read);
                try c.expression(vector.right, .read);
            },
            .vector_neg => |vector| try c.expression(vector.operand, .read),
            .vector_sqrt => |vector| try c.expression(vector.operand, .read),
            .vector_convert => |vector| try c.expression(vector.operand, .read),
            .vector_select => |selection| {
                try c.expression(selection.mask, .read);
                try c.expression(selection.a, .read);
                try c.expression(selection.b, .read);
            },
            .float_fma => |fused| {
                try c.expression(fused.a, .read);
                try c.expression(fused.b, .read);
                try c.expression(fused.c, .read);
            },
            .byte_load => |load| {
                try c.expression(load.bytes, .read);
                try c.expression(load.offset, .read);
            },
            .binary => try c.binaryExpression(id),
            .field => c.fieldExpression(id, access) catch |err| {
                if (err == error.Rejected) {
                    c.noteBorrowCopy(id, access);
                    try c.borrowedMarkerRepair(id);
                    c.noteHeldRecord(id);
                    try c.takeParameterMessage(id);
                }
                return err;
            },
            .index => |index| {
                const base = c.program.nodes[@backingInt(index.base)].ty;
                const fresh_character = base.isAggregate() and c.program.records[base.recordIndex()].collection.kind == .string;
                try c.expression(index.base, .read);
                const saved = c.loans.items.len;
                defer c.loans.shrinkRetainingCapacity(saved);
                try c.loanExpression(index.base, false);
                try c.expression(index.index, .read);
                if (!fresh_character and access == .move and c.owns(node.ty)) {
                    const refusal = c.rejectCopy(node.span, node.ty, .{ .code = borrow_error, .rule = .B7 }, try c.escapeMessage(node.span, c.origin(index.base), .copy, ""));
                    c.noteReadCopy(id, access);
                    return refusal;
                }
            },
            .array => |items| {
                const previous_sink = c.sink;
                defer c.sink = previous_sink;
                c.sink = .{ .element = .{ .noun = "list", .name = "", .leaves = c.sinkLeaves() } };
                for (items) |item| {
                    try c.sliceEscape(item);
                    try c.expression(item, .move);
                }
            },
            .record => |fields| try c.recordExpression(id, fields, access),
            .update => |update| {
                try c.checkUpdateBase(update, writebackBase(access));
                const previous_sink = c.sink;
                defer c.sink = previous_sink;
                for (update.fields) |field| {
                    c.sink = c.updateSink(update.base, field.index);
                    try c.sliceEscape(field.value);
                    try c.expression(field.value, if ((access == .update or access == .writeback) and c.sameFieldWriteback(update.base, field)) access else .move);
                }
            },
            .replace => |replace| {
                try c.expression(replace.base, writebackBase(access));
                try c.expression(replace.index, .read);
                try c.sliceEscape(replace.value);
                try c.expression(replace.value, if ((access == .update or access == .writeback) and c.sameIndexWriteback(replace.base, replace.index, replace.value)) access else .move);
            },
            // `take(mut place)` and `exchange(mut place, value)`: the place is written (its root must be exclusive, the
            // same check as an update) and the replacement moves in; the moved-out value is the owned result.
            .place_exchange => |exchange| try c.placeExchange(exchange),
            .acquire_buffer => |buffer| try c.expression(buffer.capacity, .read),
            .buffer_operation => c.collection(node, access) catch |err| {
                if (err == error.Rejected) c.noteReadCopy(id, access);
                return err;
            },
            .task_group_open => {},
            .task_submit => |submit| try c.taskSubmit(submit.group, submit.call),
            .task_result => |slot| try c.checkLocal(@backingInt(slot), .read, node.span),
            .call => |call| {
                const function = c.program.functions[@backingInt(call.function)];
                // A task's arguments outlive the submitting statement, so a submitted call takes no borrowed record (1A).
                const submitted = c.task_call != null and c.task_call.? == id;
                const previous_callee = c.callee;
                defer c.callee = previous_callee;
                c.callee = @backingInt(call.function);
                try c.arguments(call.arguments, call.evaluation_order, function.signature.declared_mutates, function.scope.own_parameters, !submitted);
                if (try c.borrowedCallRoots(id, 0)) |roots| try c.borrowedResultUse(id, roots, access);
            },
            .invoke => |call| {
                try c.expression(call.callee, .read);
                const callback = c.program.records[c.program.nodes[@backingInt(call.callee)].ty.recordIndex()].contract.callback.?;
                const previous_callee = c.callee;
                defer c.callee = previous_callee;
                c.callee = null;
                try c.arguments(call.arguments, call.evaluation_order, callback.mutates, callback.own, false);
            },
            .print => |print| {
                if (print.stream) |stream| try c.expression(stream, .read);
                var values: std.ArrayList(typed.NodeId) = .empty;
                const delayed_formats = print.sink != .error_report or print.debug or print.separator != null or print.terminator != null;
                for (print.arguments) |argument| {
                    const value = c.program.nodes[@backingInt(argument)];
                    // The direct print path delays rendering until all arguments,
                    // separators and terminators have been evaluated.
                    if (value.data == .format and delayed_formats) {
                        try c.writtenMarker(argument, .read);
                        try c.formatValues(&values, value.data.format);
                    } else try values.append(c.a, argument);
                }
                if (print.separator) |separator| try values.append(c.a, separator);
                if (print.terminator) |terminator| try values.append(c.a, terminator);
                try c.arguments(values.items, &.{}, &.{}, &.{}, false);
            },
            .stream_write => |write| {
                try c.expression(write.stream, .read);
                try c.expression(write.text, .read);
            },
            .stream_flush => |flush| try c.expression(flush.stream, .read),
            .format => |format| try c.formatExpression(format),
            .stand_in,
            .external_read,
            .environment_get,
            .environment_names,
            .dir_resource,
            .host_resource,
            .restrict_resource,
            .environment_only,
            .file_access,
            .file_method,
            .acquire_resource,
            .accept_resource,
            .complete_resource,
            .resource_io,
            => try c.resourceExpression(node),
            .propagate => |value| try c.propagateResource(value.value, node.span, access),
            .variant => |variant| try c.variantExpression(variant.value),
        }
        if (access == .move) try c.moveMarker(id);
    }

    /// Each printable hole is read in source order, and earlier managed holes
    /// remain borrowed until the last hole finishes evaluation.
    fn formatExpression(c: *Checker, format: typed.Format) Error!void {
        var values: std.ArrayList(typed.NodeId) = .empty;
        try c.formatValues(&values, format);
        try c.arguments(values.items, &.{}, &.{}, &.{}, false);
    }

    /// Flatten only holes that will be rendered together. A materialized nested
    /// format remains its own expression and owns its independent result text.
    fn formatValues(c: *Checker, values: *std.ArrayList(typed.NodeId), format: typed.Format) Error!void {
        for (format.pieces) |piece| switch (piece) {
            .literal => {},
            .hole => |hole| try values.append(c.a, hole.value),
        };
    }

    /// Function values carry owned signatures, so a borrowing result needs a copying wrapper.
    fn functionValue(c: *Checker, span: Span, id: typed.FunctionId) Error!void {
        const function = c.program.functions[@backingInt(id)];
        const values = @import("view_function_value.zig");
        if (!values.borrowsResult(c.program.records, function)) return;
        const src = c.source orelse return c.reject(span, .{ .code = "E_VIEW_FUNCTION_VALUE", .rule = .V4 }, "a borrowing function cannot be used as an owned function value; pass a function that copies its result");
        const item = try values.diagnosticForUse(c.diagnostics.allocator, src, c.program.records, function, span);
        c.failure.* = .{ .code = item.code, .span = item.span, .message = item.message, .rule = .V4 };
        if (item.provenance.fix) |fix| {
            const edits = try c.diagnostics.allocator.alloc(language.diagnostic.Edit, fix.count());
            for (edits, 0..) |*edit, index| edit.* = fix.at(index);
            c.failure.repair = .{ .explicit_fix = edits };
        }
        return error.Rejected;
    }

    fn taskSubmit(c: *Checker, group: typed.LocalId, id: typed.NodeId) Error!void {
        const node = c.program.nodes[@backingInt(id)];
        const call = node.data.call;
        try c.functionValue(node.span, call.function);
        const previous = c.task_call;
        c.task_call = id;
        defer c.task_call = previous;
        try c.expression(id, .read);
        const function = c.program.functions[@backingInt(call.function)];
        for (call.arguments, 0..) |argument, index| {
            if (index < function.scope.own_parameters.len and function.scope.own_parameters[index]) continue;
            if (!@import("task_lending.zig").isPlace(c.program, argument)) continue;
            const value = c.program.nodes[@backingInt(argument)];
            if (!c.tracked(value.ty)) continue;
            const roots = try c.placeRoots(argument, 0);
            // A task takes no borrowed collection (RB2): its refusal is the one the collection gets as an owner.
            if (c.collections) |held| for (roots.items) |root| if (held.table.holds(root)) {
                const result = c.reject(value.span, .{ .code = borrow_error, .rule = .B9 }, borrowed_record_escape);
                c.noteCollectionCause(root);
                return result;
            };
            for (roots.items) |root| try c.tasks.add(c.a, .{ .root = root, .group = group, .span = value.span });
        }
    }

    /// Walk binary spines without consuming the host stack. An explicit restore
    /// action keeps each left operand's loan live only while its RHS is checked.
    /// The constructor of `operand` when it is a case or a record built as a direct operand of an `==` or `!=` in the
    /// binary tree rooted at `root`, for the message that says the value is built for the comparison (F-11).
    fn comparedOperand(c: *Checker, root: typed.NodeId, operand: typed.NodeId) ?escape_message.Compared {
        const node = c.program.nodes[@backingInt(operand)];
        const case = switch (node.data) {
            .variant => true,
            .record => false,
            else => return null,
        };
        if (!c.comparedIn(root, operand)) return null;
        const src = c.source orelse return null;
        if (node.span.end > src.bytes.len or node.span.start >= node.span.end) return null;
        const text = src.text(node.span);
        const open = std.mem.indexOfScalar(u8, text, '(') orelse return null;
        return .{ .constructor = text[0..open], .case = case };
    }

    /// Whether `operand` is the left or right side of an `==` or `!=` somewhere in the binary tree rooted at `root`.
    fn comparedIn(c: *Checker, root: typed.NodeId, operand: typed.NodeId) bool {
        var stack: [32]typed.NodeId = undefined;
        var depth: usize = 1;
        stack[0] = root;
        while (depth != 0) {
            depth -= 1;
            const node = c.program.nodes[@backingInt(stack[depth])];
            if (node.data != .binary) continue;
            const binary = node.data.binary;
            const equality = binary.op == .eq or binary.op == .ne;
            if (equality and (binary.left == operand or binary.right == operand)) return true;
            if (depth + 2 > stack.len) return false;
            stack[depth] = binary.left;
            stack[depth + 1] = binary.right;
            depth += 2;
        }
        return false;
    }

    fn binaryExpression(c: *Checker, id: typed.NodeId) Error!void {
        const Action = union(enum) { visit: typed.NodeId, after_left: typed.NodeId, restore: usize };
        var pending: std.ArrayList(Action) = .empty;
        defer pending.deinit(c.a);
        const initial = c.loans.items.len;
        defer c.loans.shrinkRetainingCapacity(initial);
        try pending.append(c.a, .{ .visit = id });
        while (pending.pop()) |action| switch (action) {
            .restore => |saved| c.loans.shrinkRetainingCapacity(saved),
            .after_left => |parent| {
                const binary = c.program.nodes[@backingInt(parent)].data.binary;
                const saved = c.loans.items.len;
                if (c.tracked(c.program.nodes[@backingInt(binary.left)].ty)) try c.loanExpression(binary.left, false);
                try pending.append(c.a, .{ .restore = saved });
                try pending.append(c.a, .{ .visit = binary.right });
            },
            .visit => |value| {
                const node = c.program.nodes[@backingInt(value)];
                if (node.data != .binary) {
                    // A comparison's operand that is built for it keeps nothing after the comparison (F-11).
                    const previous_sink = c.sink;
                    defer c.sink = previous_sink;
                    if (c.comparedOperand(id, value)) |built| c.sink = .{ .compared = built };
                    try c.expression(value, .read);
                    continue;
                }
                try c.writtenMarker(value, .read);
                const binary = node.data.binary;
                // As before, visit short-circuit RHSs conservatively: a move on
                // that path makes its source unavailable after the expression.
                try pending.append(c.a, .{ .after_left = value });
                try pending.append(c.a, .{ .visit = binary.left });
            },
        };
    }

    fn variantExpression(c: *Checker, payload: ?typed.NodeId) Error!void {
        const value = payload orelse return;
        // A misplaced marker keeps its exact removal before a slice copy repair.
        try c.writtenMarker(value, .move);
        try c.sliceEscape(value);
        return c.expression(value, .move);
    }

    /// A generated dictionary item is a pair of borrows from one entry. Source
    /// record constructors cannot spell these internal projections, and copying
    /// an item still follows the ordinary explicit deep-copy path.
    fn borrowedItem(c: *const Checker, fields: []const typed.FieldInit) ?typed.LocalId {
        if (fields.len != 2) return null;
        if (fields[0].index != 0 or fields[1].index != 1) return null;
        const key = switch (c.program.nodes[@backingInt(fields[0].value)].data) {
            .buffer_operation => |operation| operation,
            else => return null,
        };
        const value = switch (c.program.nodes[@backingInt(fields[1].value)].data) {
            .buffer_operation => |operation| operation,
            else => return null,
        };
        if (key.kind != .key_at or value.kind != .value_at or key.owner != value.owner) return null;
        if (key.arguments.len != 1 or value.arguments.len != 1) return null;
        return if (key.arguments[0] == value.arguments[0]) key.owner else null;
    }

    /// A record constructor: a dictionary item or a borrowed record read in place (1A), else an owner of its moved fields.
    fn recordExpression(c: *Checker, id: typed.NodeId, fields: []const typed.FieldInit, access: Access) Error!void {
        if (access == .read and c.borrowedItem(fields) != null) {
            for (fields) |field| try c.expression(field.value, .read);
            return;
        }
        if (access != .read or !try c.permitsBorrowedRecord(id)) return c.recordFields(id, fields);
        c.borrowedRecordFields(fields) catch |err| {
            // An inner record that already noted this refusal stays its cause.
            const inner = if (c.record_cause) |cause| std.meta.eql(cause.span, c.failure.span) else false;
            if (err == error.Rejected and !inner) c.noteRecordCause(id);
            return err;
        };
    }

    /// Whether constructor `id` is built as a borrowed record (1A): it is one (`BorrowedRecords.constructor`) and no re-check
    /// builds it as an owner (`Shared.plain_records`).
    fn borrowedRecord(c: *Checker, id: typed.NodeId) Error!bool {
        const index = @backingInt(id);
        if (c.program.nodes[index].data != .record) return false;
        if (index < c.plain_records.len and c.plain_records[index]) return false;
        return (try c.recordTable()).constructor(id);
    }

    /// The borrowed-record table of this function, built on first use: a function with no record constructor pays nothing.
    fn recordTable(c: *Checker) error{OutOfMemory}!BorrowedRecords {
        if (c.records == null) c.records = try BorrowedRecords.init(c.a, c.program, c.linear, c.function, c.case_payloads);
        return c.records.?;
    }

    /// Whether a record constructor read here is a borrowed value: a read-only argument of a direct call, or the constructor
    /// that a `const` initializer, a borrowed `mut` store, a `from` return or an enclosing borrowed record reads.
    fn permitsBorrowedRecord(c: *Checker, id: typed.NodeId) Error!bool {
        const argument = c.argument.call and c.argument.value != null and c.argument.value.? == id;
        const permitted = c.record_permit != null and c.record_permit.? == id;
        return (argument or permitted) and try c.borrowedRecord(id);
    }

    /// Read a borrowed record's fields in place (1A): each borrow is a read of its place, and a nested borrowed record is
    /// read the same way. Nothing moves, so the record owns nothing and is never dropped.
    fn borrowedRecordFields(c: *Checker, fields: []const typed.FieldInit) Error!void {
        for (fields) |field| {
            const previous = c.record_permit;
            defer c.record_permit = previous;
            if (c.program.nodes[@backingInt(field.value)].data == .record) c.record_permit = field.value;
            // A lent option (O4) reads its parameter in place; `Some(p)` moves nothing.
            if ((try c.recordTable()).lentOption(field.value) != null) {
                try c.writtenMarker(field.value, .read);
                try c.expression(c.program.nodes[@backingInt(field.value)].data.variant.value.?, .read);
                continue;
            }
            try c.expression(field.value, .read);
        }
    }

    /// Check a constructor in a position that may hold a borrowed record (`record_permit`), as a read when it is one.
    fn permittedRecord(c: *Checker, value: typed.NodeId, access: Access) Error!void {
        const previous = c.record_permit;
        defer c.record_permit = previous;
        c.record_permit = value;
        try c.expression(value, if (try c.borrowedRecord(value)) .read else access);
    }

    /// The owners a borrowed record reads (1A): the roots of each borrowed field, a static field adding none.
    fn recordRoots(c: *Checker, fields: []const typed.FieldInit, depth: usize) Error!Roots {
        var roots: Roots = .{};
        const table = try c.recordTable();
        for (fields) |field| {
            const value = c.program.nodes[@backingInt(field.value)];
            if (!c.owns(value.ty) or staticText(c.program, field.value) or table.emptyOption(field.value)) continue;
            try roots.merge(c.a, try c.placeRoots(field.value, depth + 1));
            if (table.frameOption(field.value)) roots.frame = true;
            if (table.framedRead(field.value)) roots.block_frame = true;
        }
        return roots;
    }

    /// The cause note of a borrowed field of constructor `id` refused where a record of borrows would be read in place
    /// (F-44): another field the constructor writes holds an owned value, so the record owns all its fields.
    fn noteOwnedField(c: *Checker, id: typed.NodeId, refused: typed.FieldInit) Error!void {
        const table = try c.recordTable();
        if (!table.borrowedField(refused.value)) return;
        const owning = table.owningField(id) orelse return;
        const node = c.program.nodes[@backingInt(id)];
        const given = c.program.nodes[@backingInt(owning.value)].span;
        // A field the constructor leaves to its default is `noteDefaultOwner`'s note.
        if (given.start < node.span.start or given.end > node.span.end) return;
        const declared = c.program.records[node.ty.recordIndex()];
        if (owning.index >= declared.fields.len) return;
        const record = try typed.surfaceTypeName(c.diagnostics.allocator, node.ty, c.program.records);
        const name = declared.fields[owning.index].name;
        const format = "field `{s}` holds an owned value, so `{s}(...)` owns its fields instead of borrowing them: a " ++
            "record whose managed fields are all borrowed is a view, and one owned field makes it an owner; copy the " ++
            "borrowed fields, or build the record without `{s}` holding an owned value";
        const message = try std.fmt.allocPrint(c.diagnostics.allocator, format, .{ name, record, name });
        c.failure.notes.cause = .{ .span = given, .message = message };
    }

    fn recordFields(c: *Checker, id: typed.NodeId, fields: []const typed.FieldInit) Error!void {
        const saved = c.loans.items.len;
        defer c.loans.shrinkRetainingCapacity(saved);
        const previous_sink = c.sink;
        defer c.sink = previous_sink;
        const ty = c.program.nodes[@backingInt(id)].ty;
        const record: ?typed.Record = if (ty.isAggregate() and ty.recordIndex() < c.program.records.len) c.program.records[ty.recordIndex()] else null;
        const leaves = c.sinkLeaves();
        // A record built to be compared keeps its fields only for the comparison: the message names that (F-11).
        const compared = previous_sink == .compared;
        // A position that would read a record of borrows in place: a read-only argument of a direct call, or the
        // initializer of a local (`const` or a `mut` local that holds a borrow).
        const viewable = (c.argument.call and c.argument.value != null and c.argument.value.? == id) or
            (c.record_permit != null and c.record_permit.? == id) or previous_sink == .binding;
        for (fields) |field| {
            if (record) |named| if (field.index < named.fields.len and !compared) {
                c.sink = .{ .field = .{ .record = named.name, .name = named.fields[field.index].name, .leaves = leaves } };
            };
            try c.sliceEscape(field.value);
            c.expression(field.value, .move) catch |err| {
                if (err == error.Rejected and viewable) try c.noteOwnedField(id, field);
                return err;
            };
            if (try c.resourceOrigin(field.value)) |anchor|
                try c.loans.append(c.a, .{ .root = anchor, .write = false });
        }
    }

    fn resourceExpression(c: *Checker, node: typed.Node) Error!void {
        switch (node.data) {
            .stand_in => |stand| {
                try c.expression(stand.first, .read);
                if (stand.second) |second| try c.expression(second, .read);
            },
            .external_read => |read| try c.expression(read.capability, .read),
            .environment_get => |get| {
                try c.expression(get.capability, .read);
                try c.expression(get.name, .read);
            },
            .environment_names => |cap| try c.expression(cap, .read),
            // A narrowing answers a new capability handle (5C), an ordinary value that a `with` scope may also bind.
            .dir_resource => |dir| {
                try c.expression(dir.capability, .read);
                try c.expression(dir.path, .read);
            },
            .host_resource => |host| {
                try c.expression(host.capability, .read);
                try c.expression(host.name, .read);
            },
            .restrict_resource => |restrict| try c.expression(restrict.value, .read),
            .environment_only => |only| {
                try c.expression(only.capability, .read);
                try c.expression(only.names, .read);
            },
            .file_access => |file| try c.arguments(file.arguments, &.{}, &.{}, &.{}, false),
            .file_method => |file| {
                try c.checkLocal(@backingInt(file.owner), .read, node.span);
                if (file.argument) |argument| try c.expression(argument, .read);
            },
            .acquire_resource => |acquire| {
                try c.arguments(&.{ acquire.capability, acquire.request }, &.{}, &.{}, &.{}, false);
                _ = c.origin(acquire.capability) orelse return c.reject(node.span, .{ .code = resource_origin, .rule = .P1 }, "bind the provider to a named local before acquiring a resource");
            },
            .accept_resource => |owner| try c.checkLocal(@backingInt(owner), .read, node.span),
            .complete_resource => |owner| {
                try c.expression(owner, .move);
            },
            .resource_io => |io| {
                try c.checkLocal(@backingInt(io.owner), .read, node.span);
                if (io.value) |input| try c.expression(input, .read);
            },
            else => unreachable,
        }
    }

    /// `try value`: the result is consumed, its error returned and its success taken out. When the result is a borrowed
    /// call and the success is only read (`access` is `.read`: a `const` binding that holds a loan, R3), the call is read
    /// in place too, so the success keeps the call's roots; any other use of the success moves it, and a borrowed call
    /// result is refused as it is anywhere else.
    fn propagateResource(c: *Checker, value: typed.NodeId, span: Span, access: Access) Error!void {
        try c.expression(value, if (access == .read) .read else .move);
        const shape = typed.resultShape(c.program.nodes[@backingInt(value)].ty, c.program.records) orelse return;
        if (resources.dependent(c.program, shape.error_type)) try c.resourceReturn(value, span);
    }

    fn resourceReturn(c: *Checker, value: typed.NodeId, span: Span) Error!void {
        const anchor = try c.resourceParameter(c.function, span);
        if (try c.resourceOrigin(value)) |actual| if (actual != anchor)
            return c.reject(span, .{ .code = resource_escape, .rule = .P3 }, "a returned resource must depend on this function's single provider or resource input");
    }

    fn resourceParameter(c: *Checker, function: typed.Function, span: Span) Error!usize {
        return resources.parameter(c.program, function) orelse return c.reject(span, .{ .code = resource_origin, .rule = .P3 }, try c.resourceInputsMessage(function));
    }

    /// What a function that returns a resource is told when `resources.parameter` finds no single input (R3-RESORIGIN, RES-ORIGIN-2):
    /// the inputs `resources.counted` counts, in source order, with the type as the source spells it, and what to write. A `Clock`,
    /// an `Entropy`, an `Environment`, a `Process` and a provider of the other kind are not counted, so they are not named. When the
    /// one input of the result's type is not `own` and only providers sit beside it, taking it `own` makes it the origin. Otherwise
    /// the work that needs them together goes in a function that returns a `bool` or an `int`, which takes a file as `mut` and any
    /// other resource as `own` (a `Poller`'s operations take it `own`, so `mut` cannot call them, e_mut_own). Words only: the code, rule,
    /// position and fix are the caller's.
    fn resourceInputsMessage(c: *Checker, function: typed.Function) Error![]const u8 {
        const quoted = struct {
            /// `` `a` ``, `` `a` and `b` `` or `` `a`, `b` and `c` ``: parameter names for the message.
            fn names(a: std.mem.Allocator, out: *std.ArrayList(u8), list: []const []const u8) error{OutOfMemory}!void {
                for (list, 0..) |name, index| {
                    const separator = if (index == 0) "" else if (index + 1 == list.len) " and " else ", ";
                    try out.print(a, "{s}`{s}`", .{ separator, name });
                }
            }
        };
        const a = c.diagnostics.allocator;
        var text: std.ArrayList(u8) = .empty;
        var shown: std.ArrayList(u8) = .empty;
        var work: std.ArrayList([]const u8) = .empty;
        var file_names: std.ArrayList([]const u8) = .empty;
        var owned: std.ArrayList([]const u8) = .empty;
        var same: std.ArrayList([]const u8) = .empty;
        var resources_held: usize = 0;
        for (function.scope.locals[0..function.signature.parameter_count], 0..) |local, index| {
            if (!resources.counted(c.program, function, index)) continue;
            const spelled = language.reference_tables.prelude.reservedTypeName(local.ty) orelse try typed.surfaceTypeName(a, local.ty, c.program.records);
            try shown.print(a, "{s}`{s}: {s}`", .{ if (work.items.len == 0) "" else ", ", local.name, spelled });
            try work.append(a, local.name);
            if (resources.provider(local.ty)) continue;
            resources_held += 1;
            try (if (local.ty.isFile()) &file_names else &owned).append(a, local.name);
            if (resources.ofResult(c.program, local.ty, function.signature.return_type)) try same.append(a, local.name);
        }
        const name = try language.display_name.spelled(a, function.name);
        const kinds = resources.kinds(c.program, function.signature.return_type);
        const provider_names = if (kinds.filesystem and kinds.network) "a `Filesystem`, a `Network`" else if (kinds.network) "a `Network`" else "a `Filesystem`";
        try text.print(a, "`{s}` returns a resource, so it takes exactly one input the result can come from ({s} or a resource), and it takes ", .{ name, provider_names });
        if (work.items.len == 0) {
            try text.appendSlice(a, "none: add as its one input the provider the resource is acquired from, or the resource it continues");
            return text.items;
        }
        try text.print(a, "{d}: {s}. ", .{ work.items.len, shown.items });
        if (resources_held == 1 and same.items.len == 1) {
            try text.print(a, "Take `{s}` as `own`: an `own` input of the result's type is the one it comes from, and the providers beside it are not counted.", .{same.items[0]});
            return text.items;
        }
        try text.appendSlice(a, "Keep the one the result comes from and take the others out of the parameters: do the work that needs ");
        try quoted.names(a, &text, work.items);
        try text.appendSlice(a, " together in a function that returns a `bool` or an `int`, which may take any number of inputs");
        if (file_names.items.len != 0) {
            try text.appendSlice(a, " (take ");
            try quoted.names(a, &text, file_names.items);
            try text.appendSlice(a, " as `mut`)");
        }
        if (owned.items.len != 0) {
            try text.appendSlice(a, if (file_names.items.len != 0) "; that function takes " else ": that function takes ");
            try quoted.names(a, &text, owned.items);
            try text.appendSlice(a, " as `own`, which every operation on a resource can use, and keeps the other work there");
        }
        try text.append(a, '.');
        return text.items;
    }

    fn resourceOrigin(c: *Checker, id: typed.NodeId) Error!?usize {
        const node = c.program.nodes[@backingInt(id)];
        if (resources.provider(node.ty)) return c.origin(id);
        if (!resources.dependent(c.program, node.ty)) return null;
        return switch (node.data) {
            .local => |slot| if (c.state[@backingInt(slot)].dependency == none) null else c.state[@backingInt(slot)].dependency,
            .field => |field| c.resourceOrigin(field.base),
            .block_value => |block| c.resourceOrigin(block.value),
            .wrap, .unwrap, .cast, .complete_resource => |value| c.resourceOrigin(value),
            .accept_resource => |owner| if (c.state[@backingInt(owner)].dependency == none) null else c.state[@backingInt(owner)].dependency,
            .propagate => |value| c.resourceOrigin(value.value),
            .variant => |variant| if (variant.value) |value| c.resourceOrigin(value) else null,
            .file_access => |file| c.origin(file.arguments[0]) orelse return c.reject(node.span, .{ .code = resource_origin, .rule = .P1 }, "a file requires a named provider"),
            .acquire_resource => |acquire| c.origin(acquire.capability) orelse return c.reject(node.span, .{ .code = resource_origin, .rule = .P1 }, "a resource requires a named provider"),
            .call => |call| c.resourceOrigin(call.arguments[try c.resourceParameter(c.program.functions[@backingInt(call.function)], node.span)]),
            .record => |fields| result: {
                var anchor: ?usize = null;
                for (fields) |field| if (try c.resourceOrigin(field.value)) |next| {
                    if (anchor != null and anchor != next) return c.reject(node.span, .{ .code = resource_origin, .rule = .P1 }, "one resource carrier cannot combine different provider origins");
                    anchor = next;
                };
                break :result anchor;
            },
            else => c.reject(
                node.span,
                .{ .code = resource_origin, .rule = .P1 },
                try std.fmt.allocPrint(c.diagnostics.allocator, "resource origin `{s}` is unsupported; use a named provider, a resource local, a field, or a call with one provider input", .{@tagName(node.data)}),
            ),
        };
    }

    /// Recover a receiver's local field/index path without assuming distinct
    /// dynamic indices. Hidden aliases follow only their checked borrow source.
    fn collectionPath(c: *Checker, start: ?typed.NodeId, owner: usize) Error!?PlacePath {
        return c.sourcePath(start, owner, false);
    }

    /// Staged argument prefixes can recover a lowering temporary before its initializer runs.
    fn sourcePath(c: *Checker, start: ?typed.NodeId, owner: usize, definitions: bool) Error!?PlacePath {
        var path: PlacePath = .{};
        var node = start;
        var slot: ?usize = if (start == null) owner else null;
        var remaining = c.program.nodes.len + c.state.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            if (slot) |binding| {
                const state = c.state[binding];
                if (c.temporary(binding)) {
                    const value = if (state.traits.borrowed) state.view_definition.node else if (definitions) c.definitions.get(@intCast(binding)) else null;
                    if (value) |definition| {
                        node = definition;
                        slot = null;
                        continue;
                    }
                }
                if (state.root != none) return null;
                path.root = binding;
                return path;
            }
            switch (c.program.nodes[@backingInt(node.?)].data) {
                .local => |binding| slot = @backingInt(binding),
                .field => |field| {
                    try path.steps.append(c.a, .{ .field = field.index });
                    node = field.base;
                },
                .index => |index| {
                    try path.steps.append(c.a, .{ .index = index.index });
                    node = index.base;
                },
                .block_value => |block| node = block.value,
                .wrap, .unwrap, .cast => |value| node = value,
                .buffer_operation => |operation| {
                    if (operation.kind != .read or operation.arguments.len != 1) return null;
                    try path.steps.append(c.a, .{ .index = operation.arguments[0] });
                    slot = @backingInt(operation.owner);
                },
                else => return null,
            }
        }
        return null;
    }

    /// Same-depth list paths are either the same block or distinct siblings;
    /// runtime identity selects self-extension. Prefix overlap needs an explicit copy.
    fn independentExtension(c: *Checker, owner: usize, source: typed.NodeId, span: Span) Error!void {
        const message = "extend cannot read an overlapping ancestor or ambiguous source; make an explicit copy(value) before extending";
        if (c.ambiguousBorrow(source)) return c.reject(span, .{ .code = overlap_error, .rule = .M6 }, message);
        const root = c.origin(source) orelse return;
        if (root != c.rootOf(owner)) return;
        const destination = (try c.collectionPath(null, owner)) orelse return c.reject(span, .{ .code = overlap_error, .rule = .M6 }, message);
        const input = (try c.collectionPath(source, none)) orelse return c.reject(span, .{ .code = overlap_error, .rule = .M6 }, message);
        if (destination.root != input.root) return;
        const shared = @min(destination.steps.items.len, input.steps.items.len);
        for (0..shared) |offset| {
            const left = destination.steps.items[destination.steps.items.len - 1 - offset];
            const right = input.steps.items[input.steps.items.len - 1 - offset];
            switch (left) {
                .field => |field| switch (right) {
                    .field => |other| if (field != other) return,
                    .index => return c.reject(span, .{ .code = overlap_error, .rule = .M6 }, message),
                },
                .index => switch (right) {
                    .index => {}, // Unknown indices can coincide, never imply a prefix is safe.
                    .field => return c.reject(span, .{ .code = overlap_error, .rule = .M6 }, message),
                },
            }
        }
        if (destination.steps.items.len != input.steps.items.len) return c.reject(span, .{ .code = overlap_error, .rule = .M6 }, message);
    }

    fn collection(c: *Checker, node: typed.Node, access: Access) Error!void {
        const operation = node.data.buffer_operation;
        if (operation.kind == .get and access != .read and access != .move and c.owns(node.ty)) return c.reject(
            node.span,
            .{ .code = borrow_error, .rule = .R6 },
            "a borrowed selection is read-only; make an explicit copy(value) before changing it",
        );
        const owner = @backingInt(operation.owner);
        if (operation.kind == .copy) {
            return c.checkLocal(owner, .read, node.span);
        }
        try c.trimUse(node, access);
        // An element store into a borrowed collection (RB2) lends its value: the collection then holds what the value borrows.
        if (c.lentStoreValue(operation)) |stored| return c.lentStore(owner, operation, stored, node.span);
        const linear = c.tracked(c.function.scope.locals[owner].ty);
        if (linear and operation.kind == .iteration_check) {
            try c.checkLocal(owner, .read, node.span);
            try c.holdIteration(owner, node.span);
        } else {
            const write = operation.kind.writesReceiver();
            const writable_projection = c.owns(node.ty) and (access == .mutate or access == .update);
            if (write) try c.checkReceiver(owner, .mutate, node.span) else try c.checkLocal(owner, if (writable_projection) .mutate else .read, node.span);
            const saved = c.loans.items.len;
            defer c.loans.shrinkRetainingCapacity(saved);
            // Operands finish before the operation mutates. Permit reads (including
            // the generated negative-index length check), but forbid invalidation.
            if (linear) try c.loanReceiver(owner, node.span);
            const schema = c.program.records[c.function.scope.locals[owner].ty.recordIndex()];
            const borrowed_read = switch (operation.kind) {
                .read, .get => schema.collection.kind == .list or schema.collection.kind == .dictionary,
                .key_at, .value_at, .setdefault => schema.collection.kind == .dictionary,
                else => false,
            };
            if (linear and access == .move and c.owns(node.ty) and borrowed_read) {
                c.element_read = node.span;
                return c.rejectCopy(node.span, node.ty, .{ .code = borrow_error, .rule = if (operation.kind == .get) .R6 else .B7 }, try c.escapeMessage(node.span, c.rootOf(owner), .copy, ""));
            }
            // Rebuilding an existing slot preserves its key. Only a genuine
            // dictionary insertion takes ownership of a supplied key.
            const slot_writeback = switch (schema.collection.kind) {
                .list, .dictionary => operation.kind == .write and c.sameSlotWriteback(operation.owner, operation.arguments[0], operation.arguments[1]),
                else => false,
            };
            // `d[key] = value` with a key written as a place reads it: the table copies it only when it is new (copy on insert).
            const borrowed_key = operation.borrowed_key and (operation.kind == .write or operation.kind == .setdefault) and
                schema.collection.kind == .dictionary and !slot_writeback and c.owns(c.program.nodes[@backingInt(operation.arguments[0])].ty);
            for (operation.arguments, 0..) |argument, index| {
                // A buffer written from its own octets reads what it changes: `bytes(buf)` spells the snapshot (CX-1),
                // a bare `buf` does not, so the overlap is refused (R-B17).
                if (write and schema.collection.kind == .bytes and c.selfSource(owner, argument)) return c.reject(
                    node.span,
                    .{ .code = overlap_error, .rule = .M6 },
                    "a buffer cannot be written from its own octets; write bytes(buf) for an independent snapshot",
                );
                const reads_key = borrowed_key and index == 0;
                const consumes = if (reads_key) false else if (schema.collection.kind == .dictionary) switch (operation.kind) {
                    .write => !slot_writeback or index != 0,
                    .setdefault => true,
                    .pop_default => index == 1,
                    else => false,
                } else operation.kind == .append or (operation.kind == .write and index == 1) or ((operation.kind == .insert or operation.kind == .exchange) and index == 1);
                const writeback = slot_writeback and index == 1;
                const previous_sink = c.sink;
                defer c.sink = previous_sink;
                if (consumes) try c.enterElementStore(owner, argument);
                const observer = c.diagnostics.observer;
                const previous_audit = if (observer) |seen| seen.argument else null;
                if (observer) |seen| seen.argument = if (seen.sourceCall(node.span)) c.observedBindingSpan(argument) else null;
                defer if (observer) |seen| {
                    seen.argument = previous_audit;
                };
                try c.expression(argument, if (writeback) .writeback else if (consumes) .move else .read);
                // The borrowed key stays read until the store, so the value it is stored with cannot invalidate it.
                if (reads_key) try c.loanExpression(argument, false);
                if (schema.collection.kind == .list and operation.kind == .extend)
                    try c.independentExtension(owner, argument, node.span);
            }
        }
    }

    /// A text trim lends its text, as `strings.strip(text) -> str from text` declares: it may be read with its text held,
    /// and any other use needs a copy, exactly as `borrowedResultUse` judges a call with that contract (W13, slice 3: the
    /// trims are `builtin func` homes, so their call is this operation, not a call).
    fn trimUse(c: *Checker, node: typed.Node, access: Access) Error!void {
        const operation = node.data.buffer_operation;
        if (access == .read or !c.textTrimBorrow(operation)) return;
        const owner = @backingInt(operation.owner);
        try c.checkLocal(owner, .read, node.span);
        return c.rejectCopy(node.span, node.ty, .{ .code = borrow_error, .rule = .R3 }, try c.escapeMessage(node.span, c.rootOf(owner), .copy, ""));
    }

    /// The value an element store into a borrowed collection (RB2) stores, or null.
    fn lentStoreValue(c: *const Checker, operation: @FieldType(@FieldType(typed.Node, "data"), "buffer_operation")) ?typed.NodeId {
        const held = c.collections orelse return null;
        return held.table.storedValue(operation);
    }

    /// An element store into a borrowed collection (RB2): the receiver takes the one change it may, the stored value is read
    /// in place while the receiver is held, and the collection then holds what the value borrows.
    fn lentStore(c: *Checker, owner: usize, operation: @FieldType(@FieldType(typed.Node, "data"), "buffer_operation"), stored: typed.NodeId, span: Span) Error!void {
        const held = c.collections.?;
        {
            const was = held.storing;
            held.storing = true;
            defer held.storing = was;
            try c.checkReceiver(owner, .mutate, span);
        }
        const roots = roots: {
            const saved = c.loans.items.len;
            defer c.loans.shrinkRetainingCapacity(saved);
            try c.loanReceiver(owner, span);
            // An element write's index or key: a dictionary takes a fresh key, and reads one written as a place, copying it
            // when the entry is new.
            if (operation.kind == .write) {
                const key = operation.arguments[0];
                // A borrowed collection lends its values, not its keys: a key the store consumes is owned storage, so a slice
                // of a lent value cannot be one (`by_head[line[:at]] = line`), as for any other dictionary (V2).
                if (!operation.borrowed_key) try c.sliceEscape(key);
                try c.expression(key, if (operation.borrowed_key) .read else .move);
                if (operation.borrowed_key) try c.loanExpression(key, false);
            }
            break :roots try c.lendIntoCollection(stored);
        };
        try c.holdCollection(held.table.collectionOf(owner).?, roots);
    }

    /// Recover the place captured by a receiver before its separate setup statements.
    fn capturedReceiverPath(c: *Checker, slot: usize) Error!?PlacePath {
        if (c.state[slot].view_definition.node) |value| return c.argumentPath(value);
        if (!c.temporary(slot) and c.state[slot].root == none) return .{ .root = slot };
        return null;
    }

    /// A lowered mutation checks the receiver's own place, independently of an enclosing argument.
    fn checkReceiver(c: *Checker, slot: usize, access: Access, span: Span) Error!void {
        const previous = c.argument;
        defer c.argument = previous;
        if (access == .mutate or access == .update) c.argument = .{ .value = c.state[slot].view_definition.node, .path = try c.capturedReceiverPath(slot), .write = true };
        return c.checkLocal(slot, access, span);
    }

    /// The place a record expression names: its named owner and the plain record fields below it, following a borrowed alias
    /// the lowering staged for it. Null for an element, a provider or anything else the checker cannot name.
    fn recordPlace(c: *Checker, id: typed.NodeId) Error!?PlacePath {
        switch (c.program.nodes[@backingInt(id)].data) {
            .local => |local| {
                const binding = @backingInt(local);
                if (c.temporary(binding)) {
                    const state = c.state[binding];
                    if (!state.available or !state.traits.borrowed) return null;
                    return c.recordPlace(state.view_definition.node orelse return null);
                }
                if (c.state[binding].root != none) return null;
                return .{ .root = binding };
            },
            .field => |field| {
                if (!c.plainRecordType(c.program.nodes[@backingInt(field.base)].ty)) return null;
                var path = (try c.recordPlace(field.base)) orelse return null;
                try path.steps.insert(c.a, 0, .{ .field = field.index });
                return path;
            },
            else => return null,
        }
    }

    /// Whether `ty` is an ordinary record whose fields are disjoint storage.
    fn plainRecordType(c: *const Checker, ty: typed.Type) bool {
        if (!ty.isAggregate()) return false;
        return ordinaryRecord(c.program.records[ty.recordIndex()]);
    }

    /// Every record place an update writes: one path per field it sets, going down into a field that is itself rebuilt by an
    /// update of that same field (`self.inner.n = 3`). Null when any of them cannot be named, or the update sets nothing.
    fn updatePaths(c: *Checker, update: @FieldType(@FieldType(typed.Node, "data"), "update")) Error!?[]const PlacePath {
        var paths: std.ArrayList(PlacePath) = .empty;
        if (!try c.collectUpdatePaths(update.base, update.fields, &paths) or paths.items.len == 0) return null;
        return paths.items;
    }

    fn collectUpdatePaths(c: *Checker, base: typed.NodeId, fields: []const typed.FieldInit, paths: *std.ArrayList(PlacePath)) Error!bool {
        const owner = (try c.recordPlace(base)) orelse return false;
        if (!c.plainRecordType(c.program.nodes[@backingInt(base)].ty)) return false;
        for (fields) |field| {
            const nested = c.program.nodes[@backingInt(field.value)];
            if (nested.data == .update and c.sameFieldWriteback(base, field)) {
                if (!try c.collectUpdatePaths(nested.data.update.base, nested.data.update.fields, paths)) return false;
                continue;
            }
            var path: PlacePath = .{ .root = owner.root };
            try path.steps.append(c.a, .{ .field = field.index });
            try path.steps.appendSlice(c.a, owner.steps.items);
            try paths.append(c.a, path);
        }
        return true;
    }

    /// Check the destination of an update as written at the fields the update sets, not as the whole record: a loan on another
    /// field of the same owner does not conflict (R2). An update whose fields cannot all be named checks the whole destination.
    fn checkUpdatedLocal(c: *Checker, slot: usize, value: typed.NodeId, span: Span) Error!void {
        const node = c.program.nodes[@backingInt(value)];
        const paths = if (node.data == .update) try c.updatePaths(node.data.update) else null;
        const written = paths orelse return c.checkLocal(slot, .mutate, span);
        const previous = c.argument;
        defer c.argument = previous;
        for (written) |path| {
            c.argument = .{ .value = null, .path = path, .write = true };
            try c.checkLocal(slot, .mutate, span);
        }
    }

    /// The base of an update, checked as written at the fields the update sets when it is written in place (`self.n = 1`).
    fn checkUpdateBase(c: *Checker, update: @FieldType(@FieldType(typed.Node, "data"), "update"), access: Access) Error!void {
        if (access != .mutate) return c.expression(update.base, access);
        const paths = (try c.updatePaths(update)) orelse return c.expression(update.base, access);
        const previous = c.argument;
        defer c.argument = previous;
        for (paths) |path| {
            c.argument = .{ .value = null, .path = path, .write = true };
            try c.expression(update.base, access);
        }
    }

    /// Whether `argument` is the owner itself, read bare (not through a conversion).
    fn selfSource(c: *const Checker, owner: usize, argument: typed.NodeId) bool {
        const node = c.program.nodes[@backingInt(argument)];
        return node.data == .local and @backingInt(node.data.local) == owner;
    }

    /// Recover only effect-free list argument paths, including the exact
    /// temporary receiver block generated for a list read. Record, array and
    /// dictionary projections keep root loans until their lowering is qualified.
    fn argumentPath(c: *Checker, id: typed.NodeId) Error!?PlacePath {
        const node = c.program.nodes[@backingInt(id)];
        switch (node.data) {
            .local => |slot| {
                const binding = @backingInt(slot);
                if (c.isExclusiveBinder(binding)) return c.payloadBindingPath(binding);
                if (c.temporary(binding)) return c.iterationPath(binding);
                if (c.state[binding].root != none) return c.aliasPath(binding);
                return .{ .root = binding };
            },
            .index => |index| return c.indexedArgumentPath(index.base, index.index),
            .field => |field| return c.fieldArgumentPath(field.base, field.index),
            .block_value => |block| {
                const body = c.program.statements[@backingInt(block.body)];
                if (body.data != .block or body.data.block.len != 1) return null;
                const statement = c.program.statements[@backingInt(body.data.block[0])];
                if (statement.data != .initialize) return null;
                const init = statement.data.initialize;
                if (!c.temporary(@backingInt(init.slot)) or init.unpack != null) return null;
                const value = c.program.nodes[@backingInt(block.value)];
                if (value.data != .buffer_operation) return null;
                const read = value.data.buffer_operation;
                // `copy(place)` reads its place while the arguments are evaluated: the place's path (F-RC-204).
                if (read.kind == .copy and read.owner == init.slot and read.arguments.len == 0) return c.argumentPath(init.value);
                if (read.kind != .read or read.owner != init.slot or read.arguments.len != 1) return null;
                return c.indexedArgumentPath(init.value, read.arguments[0]);
            },
            else => return null,
        }
    }

    /// The place a loop variable names, for an argument that reads it: an element of the iterated place (`for pn in
    /// ledger.pins` names `ledger.pins[?]`), so a `mut` argument naming another field of the same owner is disjoint from it
    /// (zero-copy part 1, F-RA-610). The element step is unknown, so it never separates two elements. Null for a loop over
    /// anything but a named place, and for every other temporary.
    fn iterationPath(c: *Checker, binding: usize) Error!?PlacePath {
        if (c.function.scope.locals[binding].origin != .iteration or c.written.contains(@intCast(binding))) return null;
        const definition = c.definitions.get(@intCast(binding)) orelse return null;
        const value = c.program.nodes[@backingInt(definition)];
        if (value.data != .buffer_operation) return null;
        const read = value.data.buffer_operation;
        if (read.kind != .read or read.arguments.len != 1) return null;
        const iterated = @backingInt(read.owner);
        // The loop's collection temporary: its iteration loan (R7) keeps the iterated place unchanged while the loop runs.
        if (!c.temporary(iterated)) return null;
        const source = c.definitions.get(@intCast(iterated)) orelse return null;
        return c.indexedArgumentPath(source, read.arguments[0]);
    }

    /// The place a `const` binding of a record place names, for an argument that passes the binding: the fields from its owner
    /// down to the container it was read from. Null for any other borrow.
    fn aliasPath(c: *Checker, slot: usize) Error!?PlacePath {
        const state = c.state[slot];
        const borrowing = state.available and state.traits.borrowed and state.traits.rule == .B9;
        if (!borrowing) return null;
        if (!(try c.bindingFlags(slot)).bound) return null;
        return c.constBorrowPath(slot, try c.localRoots(slot, 0));
    }

    /// The place a `match mut` payload binding names, for an argument that passes it (M5, X2): the running arm's payload
    /// slot names the matched place itself, and a field binding (initialized by the arm's prologue as a field of that
    /// slot) the field of the payload inside it. Two field bindings of one arm are then two fields of one place, disjoint
    /// exactly as two record fields of it are; a place inside a list element stays refused by `disjointArgument`. Null
    /// for a binding whose place is not known, and for a read argument: the build takes the whole payload out of its
    /// case for a `mut` argument (`union_take`), so a read of a sibling binding beside it would borrow a taken value.
    /// A matched place under an enclosing arm's binding (`match mut x:` in `case both(x, y):`) is named the same way: the
    /// build tests the inner case where it takes the inner payload (FR77), so bindings of two nested arms separate too.
    fn payloadBindingPath(c: *Checker, slot: usize) Error!?PlacePath {
        if (!c.argument.write) return null;
        for (c.held_places.items) |held| if (held.payload == slot) return c.argumentPath(held.place);
        const definition = c.definitions.get(@intCast(slot)) orelse return null;
        const field = switch (c.program.nodes[@backingInt(definition)].data) {
            .field => |field| field,
            else => return null,
        };
        const base = switch (c.program.nodes[@backingInt(field.base)].data) {
            .local => |base| @backingInt(base),
            else => return null,
        };
        if (base == slot or !c.isExclusiveBinder(base)) return null;
        return c.fieldArgumentPath(field.base, field.index);
    }

    fn indexedArgumentPath(c: *Checker, base: typed.NodeId, index: typed.NodeId) Error!?PlacePath {
        const ty = c.program.nodes[@backingInt(base)].ty;
        if (!ty.isAggregate()) return null;
        const schema = c.program.records[ty.recordIndex()];
        if (!schema.isCollection() or schema.collection.kind != .list) return null;
        // A dynamic index stays in the path as an unknown element: it never separates two elements, but the steps
        // before it still can (`tree.nodes[at]` and `tree.roots` split at the field).
        var path = (try c.argumentPath(base)) orelse return null;
        try path.steps.insert(c.a, 0, .{ .index = index });
        return path;
    }

    /// The path of one field of a plain record (C3): the path of the record with the field step appended. Two
    /// different fields of one owner are separate storage, so their arguments do not overlap.
    fn fieldArgumentPath(c: *Checker, base: typed.NodeId, index: usize) Error!?PlacePath {
        const ty = c.program.nodes[@backingInt(base)].ty;
        if (!ty.isAggregate()) return null;
        if (!ordinaryRecord(c.program.records[ty.recordIndex()])) return null;
        var path = (try c.argumentPath(base)) orelse return null;
        try path.steps.insert(c.a, 0, .{ .field = index });
        return path;
    }

    fn literalIndex(c: *const Checker, id: typed.NodeId) ?i128 {
        return switch (c.program.nodes[@backingInt(id)].data) {
            .integer => |value| if (value >= 0) value else null,
            else => null,
        };
    }

    /// Whether the access of the argument now being checked and the live loan name disjoint parts of one owner (C3).
    /// Both paths must be known. They are compared from the owner outward. Outside any list element, two different
    /// fields of a record are disjoint storage, whatever the accesses and whatever follows them, and equal fields lead
    /// on. A list step separates the paths only when both indices are literals and differ (a read element and a
    /// mutable one separate as well as two mutable ones). Two equal literals are the same element and lead on; two
    /// indices that may be equal, a field against an index, and a path that ends first (a prefix) never separate. A
    /// record field inside an element stays refused (OWNERSHIP-CONTRACT-1): once a path has entered an element, a
    /// field step in either path ends the comparison.
    fn disjointArgument(c: *Checker, loan: Loan) Error!bool {
        const left = loan.path orelse return false;
        const staged = loan.rule == .R2 and loan.binding != none and loan.release != none and c.temporary(loan.binding);
        if (staged) {
            const path = if (c.argument.value) |value| try c.sourcePath(value, none, true) else c.argument.path;
            if (path) |right| if (left.root == right.root and differentOuterFields(left, right)) return true;
        }
        const right = c.argument.path orelse return false;
        if (left.root != right.root) return false;
        // A writer's receiver is read again after its operands only across distinct outer record fields (the lowering's
        // `writableReceiverReusing` makes the same test), never across list elements.
        if (loan.hold == .receiver) return differentOuterFields(left, right);
        const a = left.steps.items;
        const b = right.steps.items;
        var inside = false;
        for (0..@min(a.len, b.len)) |offset| {
            const first = a[a.len - 1 - offset];
            const second = b[b.len - 1 - offset];
            switch (first) {
                .field => |field| switch (second) {
                    .field => |other| {
                        if (inside) return false;
                        if (field != other) return true;
                    },
                    .index => return false,
                },
                .index => switch (second) {
                    .index => {
                        const x = c.literalIndex(first.index) orelse return false;
                        const y = c.literalIndex(second.index) orelse return false;
                        if (x != y) return !(fieldBelow(a[0 .. a.len - 1 - offset]) or fieldBelow(b[0 .. b.len - 1 - offset]));
                        inside = true;
                    },
                    .field => return false,
                },
            }
        }
        return false;
    }

    /// Whether any of `steps` (the steps inside an element, innermost first) is a record field.
    fn fieldBelow(steps: []const PlaceStep) bool {
        for (steps) |step| if (step == .field) return true;
        return false;
    }

    fn loanArgument(c: *Checker, id: typed.NodeId, write: bool, path: ?PlacePath) Error!void {
        const begin = c.loans.items.len;
        try c.loanExpression(id, write);
        for (c.loans.items[begin..]) |*loan| {
            loan.rule = .M5;
            loan.hold = .{ .argument = c.program.nodes[@backingInt(id)].span };
        }
        if (path == null or c.loans.items.len != begin + 1) return;
        c.loans.items[begin].path = path;
    }

    /// Readonly scalar arguments finish before the callee can mutate an earlier argument.
    /// Retain read loans during evaluation to forbid nested moves and mutations.
    /// A managed read argument beside a record an earlier argument passes `mut` may read that record too (F-24), when the
    /// value it makes borrows nothing from it: the arguments are evaluated in order before the call, and the `mut`
    /// argument is the record's value, so the callee changes the record only after this argument is a value of its own.
    /// A read that would conflict with such an argument is deferred (`deferOwnValueRead`) and judged once the value is
    /// known; an argument with no such read is checked exactly as before.
    /// An argument an `own` parameter takes is judged the same way (FR67): its reads of the record are deferred as a
    /// read argument's are, so a value it makes (`copy(state.name)`, `"a" + state.name`, a call, a record literal) moves
    /// into the callee sharing nothing with the record. A move of a part of the record (`own state.name`) is a move, not
    /// a read, so it is never deferred; a resource keeps the earlier rule.
    fn argumentExpression(c: *Checker, arg: typed.NodeId, access: Access, begin: usize) Error!void {
        const ty = c.program.nodes[@backingInt(arg)].ty;
        const owned = access == .move and !resources.affine(c.program, ty);
        if (access != .read and !owned) return c.expression(arg, access);
        if (access == .read and !c.tracked(ty)) return c.readBesideEarlierLoans(arg, begin);
        if (!c.fieldPathMutBefore(begin)) return c.expression(arg, access);
        var deferral: OwnValueRead = .{ .begin = begin, .end = c.loans.items.len };
        const outer = c.own_value_read;
        c.own_value_read = &deferral;
        defer c.own_value_read = outer;
        const judged = c.expression(arg, access);
        c.own_value_read = outer;
        if (owned) return c.takenValueBesideMut(arg, &deferral, judged);
        try judged;
        if (deferral.conflict != null) try c.requireOwnValueBesideMut(arg, &deferral);
    }

    /// Evaluate a scalar read argument with the earlier arguments' loans held as reads: it may read what they lend, and
    /// may not change or move it.
    fn readBesideEarlierLoans(c: *Checker, arg: typed.NodeId, begin: usize) Error!void {
        const saved = try c.a.dupe(Loan, c.loans.items[begin..]);
        defer @memcpy(c.loans.items[begin..][0..saved.len], saved);
        for (c.loans.items[begin..]) |*loan| loan.write = false;
        try c.expression(arg, .read);
    }

    /// Whether an earlier argument of this call passes a record `mut` and every such argument is a local or a path of
    /// fields of one (F-24). A list element's address is the list's, so a `mut` element keeps the earlier rule.
    fn fieldPathMutBefore(c: *const Checker, begin: usize) bool {
        var held = false;
        for (c.loans.items[begin..]) |loan| {
            if (!loan.write or loan.rule != .M5 or loan.hold != .argument) continue;
            const path = loan.path orelse return false;
            for (path.steps.items) |step| if (step == .index) return false;
            held = true;
        }
        return held;
    }

    /// Whether the conflict of a read with the loan at `index` waits for the value of the argument being evaluated
    /// (F-24): a plain read, of a record a `mut` argument of the same call holds, while that call's argument is evaluated.
    /// The first such loan is kept for the judgement, with the read that met it.
    fn deferOwnValueRead(c: *Checker, loan: Loan, index: usize, write: bool, access: Access, read: DeferredRead) bool {
        const deferral = c.own_value_read orelse return false;
        if (write or access != .read) return false;
        if (!loan.write or loan.rule != .M5 or loan.hold != .argument) return false;
        if (index < deferral.begin or index >= deferral.end) return false;
        if (deferral.conflict == null) {
            deferral.conflict = loan;
            deferral.read = read;
        }
        return true;
    }

    /// An `own` argument whose evaluation met a deferred read is refused, when its evaluation or its value is refused, with
    /// the refusal that read meets without the deferral (FR67): the deferral accepts a value of its own and changes no
    /// refusal of an `own` argument.
    fn takenValueBesideMut(c: *Checker, arg: typed.NodeId, deferral: *const OwnValueRead, judged: Error!void) Error!void {
        const loan = deferral.conflict orelse return judged;
        judged catch |err| return if (err == error.Rejected) c.deferredConflict(loan, deferral.read, err) else err;
        c.requireOwnValueBesideMut(arg, deferral) catch |err| {
            return if (err == error.Rejected) c.deferredConflict(loan, deferral.read, err) else err;
        };
    }

    /// The refusal of the deferred `read` of a record the `mut` argument's `loan` holds, as `checkLoans` raises it;
    /// `otherwise` when that read is not refused.
    fn deferredConflict(c: *Checker, loan: Loan, read: DeferredRead, otherwise: Error) Error {
        const current = c.argument;
        defer c.argument = current;
        c.argument = read.argument;
        c.loanConflict(loan, read.slot, false, .read, read.span) catch |err| {
            if (err == error.Rejected) c.noteArgumentRecord(loan);
            return err;
        };
        return otherwise;
    }

    /// Refuse a read argument whose value borrows from any record an earlier argument of the call holds `mut` (F-24):
    /// the callee could change that record while it reads the argument. Every `mut` loan of the call's earlier arguments
    /// is compared, not only the one whose read was deferred first: a value may borrow from a second `mut` record. The
    /// message names the argument and the copy that frees it.
    fn requireOwnValueBesideMut(c: *Checker, arg: typed.NodeId, deferral: *const OwnValueRead) Error!void {
        const mark = c.loans.items.len;
        defer c.loans.shrinkRetainingCapacity(mark);
        try c.loanExpression(arg, false);
        for (c.loans.items[mark..]) |lent| for (c.loans.items[deferral.begin..deferral.end]) |loan| {
            if (!loan.write or loan.rule != .M5 or loan.hold != .argument) continue;
            if (loan.root != lent.root) continue;
            const span = c.program.nodes[@backingInt(arg)].span;
            const owner = c.function.scope.locals[loan.root].name;
            const earlier = try c.argumentText(loan.hold.argument, owner);
            const later = try c.argumentText(span, owner);
            const message = try std.fmt.allocPrint(
                c.diagnostics.allocator,
                "'{s}' lends a part of '{s}' to the call, and the earlier argument '{s}' passes '{s}' `mut`: the callee may change it while it reads '{s}'. " ++
                    "Pass a value of its own (`copy({s})`), or pass the record itself `mut` and read it inside the callee",
                .{ later, owner, earlier, owner, later, later },
            );
            const result = c.reject(span, .{ .code = overlap_error, .rule = .M5 }, message);
            c.failure.notes.related = .{ .span = loan.hold.argument, .message = "earlier mutable argument" };
            return result;
        };
    }

    fn arguments(c: *Checker, args: []const typed.NodeId, order: []const usize, mutates: []const u16, own: []const bool, call: bool) Error!void {
        const saved = c.loans.items.len;
        defer c.loans.shrinkRetainingCapacity(saved);
        for (0..args.len) |position| {
            const index = if (order.len == 0) position else order[position];
            const write = std.mem.indexOfScalar(u16, mutates, @intCast(index)) != null;
            const arg = args[index];
            const affine = resources.affine(c.program, c.program.nodes[@backingInt(arg)].ty);
            // An `own` position takes its argument, so the argument moves even
            // when its type is copyable: the caller's binding is unusable after
            // the line, and the callee may store, return or move the value.
            const taken = index < own.len and own[index];
            // A slice is a view of its source, so an owned position would copy it silently (R-B4, W4): the copy is written as
            // `copy(...)`. A text or bytes slice is refused as a list slice is (D8, the user's decision of 10 November 2026); one
            // written with `own` keeps the marker's own refusal (B2), which names the same copy.
            const text_slice = if (c.program.nodes[@backingInt(arg)].own) null else c.sliceSpan(arg);
            if (taken) if (c.listSliceSpan(arg) orelse text_slice) |span| return c.rejectCopy(
                span,
                c.program.nodes[@backingInt(arg)].ty,
                .{ .code = view_escape, .rule = .W4 },
                try c.escapeMessageTo(span, c.viewSourceSlot(arg) orelse c.sliceRoot(arg) orelse c.origin(arg), c.argumentSink(index), .copy, ""),
            );
            const previous_sink = c.sink;
            defer c.sink = previous_sink;
            c.sink = if (taken) c.argumentSink(index) else .call_argument;
            const previous_argument = c.argument;
            c.argument = .{ .value = arg, .write = write, .call = call };
            const observer = c.diagnostics.observer;
            const previous_audit = if (observer) |seen| seen.argument else null;
            if (observer) |seen| seen.argument = c.observedBindingSpan(arg);
            defer if (observer) |seen| {
                seen.argument = previous_audit;
            };
            const access: Access = if (write) .mutate else if (affine or taken) .move else .read;
            // A moved argument can move its whole owner (a record of scalar siblings is taken as one carrier), so only a
            // read or a mutable argument carries the place it names (C3).
            // A `copy(place)` given to an `own` parameter moves the fresh copy and only reads its place, so it carries the
            // place's path too (F-RC-204).
            if (access != .move or copiedPlace(c.program, arg)) c.argument.path = try c.argumentPath(arg);
            const path = c.argument.path;
            try c.argumentExpression(arg, access, saved);
            if (call and access == .read and try c.borrowedRecord(arg))
                try c.record_arguments.append(c.a, .{ .span = c.program.nodes[@backingInt(arg)].span, .node = arg });
            c.argument = previous_argument;
            if (affine) if (try c.resourceOrigin(arg)) |provider| try c.loans.append(c.a, .{ .root = provider, .write = false });
            if (c.tracked(c.program.nodes[@backingInt(arg)].ty)) {
                try c.loanArgument(arg, write, path);
            }
        }
    }

    /// The `own` parameter that argument `index` of the call being checked is given to, as a destination.
    fn argumentSink(c: *const Checker, index: usize) escape_message.Destination {
        const callee = c.callee orelse return .elsewhere;
        const function = c.program.functions[callee];
        if (index >= function.signature.parameter_count or index >= function.scope.locals.len) return .elsewhere;
        return .{ .argument = .{ .callee = function.name, .parameter = function.scope.locals[index].name } };
    }

    /// Const alternatives retain their actual initializers and lender sets.
    /// An owned fresh arm adds temporary storage, not an invented named lender.
    fn mergeConst(c: *Checker, slot: usize, left: State, right: State) Error!bool {
        if (!left.available or !right.available) return false;
        if (left.dependency != right.dependency) return false;
        const first = left.view_definition.const_origins;
        const second = right.view_definition.const_origins;
        if (first.len == 0 or second.len == 0) return false;
        const left_borrows = left.traits.borrowed and left.traits.rule == .B9;
        const right_borrows = right.traits.borrowed and right.traits.rule == .B9;
        if (!left_borrows and !right_borrows) return false;
        var origins: std.ArrayList(ConstOrigin) = .empty;
        for ([_][]const ConstOrigin{ first, second }) |alternatives| for (alternatives) |alternative| {
            const existing = for (origins.items) |*item| {
                if (item.definition == alternative.definition and item.borrowed == alternative.borrowed) break item;
            } else null;
            if (existing) |item| {
                try item.roots.merge(c.a, alternative.roots);
            } else {
                var roots: Roots = .{};
                try roots.merge(c.a, alternative.roots);
                try origins.append(c.a, .{ .definition = alternative.definition, .roots = roots, .borrowed = alternative.borrowed });
            }
        };
        c.state[slot] = .{ .available = true, .dependency = left.dependency, .view_definition = .{ .const_origins = origins.items }, .traits = .{ .borrowed = true, .rule = .B9 } };
        return true;
    }

    fn merge(c: *Checker, first: []const State, second: []const State) Error!void {
        for (c.state, first, second, 0..) |*out, left, right, slot| {
            if (try c.mergeConst(slot, left, right)) continue;
            out.* = left;
            out.available = left.available and right.available;
            if (left.available and !right.available) out.moved_span = right.moved_span;
            if (!out.available) out.view_definition.invalidated = left.view_definition.invalidated orelse right.view_definition.invalidated;
            if (!left.available) out.view_rule = left.view_rule else if (!right.available) out.view_rule = right.view_rule;
            out.traits.ambiguous_borrow = left.traits.ambiguous_borrow or right.traits.ambiguous_borrow;
            // FR91: the record is open after the join only when both paths opened it at the same move.
            out.traits.field_opened = left.traits.field_opened and right.traits.field_opened and left.moved_span.start == right.moved_span.start;
            // Only compiler-created loans have roots. A differing root cannot
            // describe one definite borrowed value after this join.
            const same_ownership = left.root == right.root and left.traits.borrowed == right.traits.borrowed and left.traits.transferable == right.traits.transferable;
            // Two views of the same source merge as one view: a phi keeps the
            // union of the incoming parents (DECISIONS F3, wave 3's D23), so the
            // different slice definitions do not invalidate it. REFUSAL-R3.
            const same_view = left.root == right.root and left.root != none and slot < c.function.scope.locals.len and c.viewLike(slot);
            if (!same_ownership or left.dependency != right.dependency) out.available = false;
            // A binding borrows one source: two views of that source merge as one
            // view, while different sources are refused with the copy repair and
            // the fix makes the binding owned (DECISIONS F7).
            const incompatible_view = !same_ownership or (left.view_definition.node != right.view_definition.node and !same_view);
            if (left.view_definition.node != right.view_definition.node and !same_view) out.available = false;
            if (left.available and right.available and incompatible_view and c.sliceView(slot)) {
                out.view_rule = .V5;
                if (left.root != none and right.root != none) try c.joined.put(c.a, @intCast(slot), .{ left.root, right.root });
            }
        }
    }

    fn loopBack(c: *Checker, before: []const State, span: Span) Error!void {
        for (before, c.state, c.function.scope.locals, 0..) |old, now, local, slot| {
            // A slice view is not an owner: invalidating a dead one is harmless,
            // and a live one is refused at its use with the copy repair (the
            // merge below keeps it unavailable). REFUSAL-R4.
            const lost_owner = old.available and !old.traits.borrowed and !now.available and !c.sliceView(slot);
            if (lost_owner and c.owns(local.ty)) {
                const message = try std.fmt.allocPrint(c.diagnostics.allocator, "'{s}' is moved inside a loop and is unavailable at the next iteration or loop exit; reinitialize it before continuing", .{local.name});
                c.failure.* = .{ .code = "E_SINGLE_OWNER_LOOP", .rule = .B6, .message = message, .span = span };
                if (now.moved_span.start < now.moved_span.end) {
                    c.failure.notes.related = .{ .span = now.moved_span, .message = try std.fmt.allocPrint(c.diagnostics.allocator, "'{s}' is moved here", .{local.name}) };
                }
                return error.Rejected;
            }
        }
    }

    fn loop(c: *Checker, value: typed.Loop, span: Span) Error!void {
        const entry = try c.a.dupe(State, c.state);
        try c.expression(value.condition, .read);
        try c.loopBack(entry, span);
        const before = try c.a.dupe(State, c.state);
        const saved = c.loans.items.len;
        const task_mark = c.tasks.loans.items.len;
        const exit_mark = c.tasks.exits.items.len;
        defer c.loans.shrinkRetainingCapacity(saved);
        const body_span = c.program.statements[@backingInt(value.body)].span;
        try c.loops.append(c.a, .{ .id = value.id, .before = before, .body = body_span });
        defer _ = c.loops.pop();
        const falls = try c.checkStatement(value.body);
        if (falls) {
            if (value.step) |step| _ = try c.checkStatement(step);
            try c.loopBack(before, span);
        }
        // A loop may execute zero times. Outer owners remain available only
        // when every reachable path preserves them.
        const after = try c.a.dupe(State, c.state);
        try c.merge(before, if (falls) after else before);
        if (falls) try c.borrowedMutLoopBack(value, saved);
        try c.taskLoopBack(value, .{ .before = before, .loans = saved, .tasks = task_mark, .exits = exit_mark, .falls = falls });
    }

    /// A `mut` local that holds a borrow (4f) and is assigned in a loop body carries the borrow of one iteration into the
    /// next. The body is checked again from the joined state, the borrows of every assignment held, until the roots those
    /// locals hold stop growing, so a change of a root before the assignment that re-borrows it is a conflict too.
    fn borrowedMutLoopBack(c: *Checker, value: typed.Loop, loans: usize) Error!void {
        if (!try c.assignsBorrowedMut(value.body)) return;
        var held = try c.borrowedMutRoots();
        var remaining = c.state.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            var next = c.*;
            next.state = try c.a.dupe(State, c.state);
            next.loans = try std.ArrayList(Loan).initCapacity(c.a, loans);
            try next.loans.appendSlice(c.a, c.loans.items[0..loans]);
            // The walk again grows its own copies of the tables a walk adds to, so this checker's stay intact.
            next.temporary_definitions = try c.temporary_definitions.clone(c.a);
            next.definitions = try c.definitions.clone(c.a);
            next.written = try c.written.clone(c.a);
            next.loops = try c.loops.clone(c.a);
            next.arm_holds = try c.arm_holds.clone(c.a);
            next.exclusive_binders = try c.exclusive_binders.clone(c.a);
            next.exclusive_receivers = try c.exclusive_receivers.clone(c.a);
            next.record_arguments = try c.record_arguments.clone(c.a);
            next.tasks = .{ .loans = try c.tasks.loans.clone(c.a), .exits = try c.tasks.exits.clone(c.a) };
            next.returns = .{};
            next.diagnostics.observer = null;
            try next.restoreConstLoans();
            next.walkLoopAgain(value) catch |err| {
                c.plain_cause = next.plain_cause;
                c.collection_cause = next.collection_cause;
                return err;
            };
            try c.merge(c.state, next.state);
            const grown = try c.borrowedMutRoots();
            if (grown == held) return;
            held = grown;
        }
    }

    /// One more walk of a loop's condition, body and step, from the state this checker holds.
    fn walkLoopAgain(c: *Checker, value: typed.Loop) Error!void {
        try c.expression(value.condition, .read);
        if (try c.checkStatement(value.body)) {
            if (value.step) |step| _ = try c.checkStatement(step);
        }
    }

    /// How many (local, root) pairs the borrowed `mut` locals hold now: a count that only grows as joins add roots.
    fn borrowedMutRoots(c: *Checker) Error!usize {
        var count: usize = 0;
        if (c.collections) |held| for (held.roots) |roots| {
            count += roots.items.len;
        };
        for (c.borrowed_mut, 0..) |borrowed, slot| if (borrowed and c.state[slot].available) {
            count += (try c.localRoots(slot, 0)).items.len;
        };
        return count;
    }

    /// Whether `body` assigns a `mut` local that holds a borrow (4f) and is declared outside it.
    fn assignsBorrowedMut(c: *Checker, body: typed.StatementId) Error!bool {
        const collections = if (c.collections) |held| held.table.any() else false;
        if (std.mem.indexOfScalar(bool, c.borrowed_mut, true) == null and !collections) return false;
        const span = c.program.statements[@backingInt(body)].span;
        var walker = try typed_walk.Walker.init(c.a, c.program, body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            // An element store into a borrowed collection declared outside the body (RB2) carries its borrow into the next
            // iteration, as an assignment of a borrowed `mut` local does.
            if (item == .expression and collections) {
                const node = c.program.nodes[@backingInt(item.expression)];
                if (node.data != .buffer_operation) continue;
                const held = c.collections.?;
                if (held.table.storedValue(node.data.buffer_operation) == null) continue;
                const slot = held.table.collectionOf(@backingInt(node.data.buffer_operation.owner)).?;
                const declaration = c.function.scope.locals[slot].declaration;
                if (declaration.start < span.start or declaration.start >= span.end) return true;
                continue;
            }
            if (item != .statement) continue;
            const data = c.program.statements[@backingInt(item.statement)].data;
            if (data != .assign) continue;
            const slot = @backingInt(data.assign.slot);
            if (!c.borrowed_mut[slot]) continue;
            const declaration = c.function.scope.locals[slot].declaration;
            if (declaration.start < span.start or declaration.start >= span.end) return true;
        }
        return false;
    }

    const TaskLoop = struct { before: []const State, loans: usize, tasks: usize, exits: usize, falls: bool };

    /// A task submitted in one iteration still reads its lender in the next.
    /// Breaks preserve loans after the loop; continues also seed its backedge.
    fn taskLoopBack(c: *Checker, value: typed.Loop, entry: TaskLoop) Error!void {
        var back: Tasks = .{};
        // A returning body cannot lend on the zero-iteration continuation.
        // Only explicit loop exits below can contribute its newly held roots.
        if (!entry.falls) c.tasks.loans.shrinkRetainingCapacity(entry.tasks);
        for (c.tasks.loans.items) |loan| try back.add(c.a, loan);
        var position = entry.exits;
        while (position < c.tasks.exits.items.len) {
            const exit = c.tasks.exits.items[position];
            if (exit.target != value.id) {
                position += 1;
                continue;
            }
            try c.tasks.add(c.a, exit.loan);
            if (exit.continuing) try back.add(c.a, exit.loan);
            _ = c.tasks.exits.orderedRemove(position);
        }
        if (back.loans.items.len <= entry.tasks) return;
        // The source walk is repeated only when this loop adds a group loan.
        // Its private state avoids duplicating return tallies and audit events.
        var next = c.*;
        next.state = try c.a.dupe(State, entry.before);
        next.loans = try std.ArrayList(Loan).initCapacity(c.a, entry.loans);
        try next.loans.appendSlice(c.a, c.loans.items[0..entry.loans]);
        next.tasks = back;
        next.returns = .{};
        next.diagnostics.observer = null;
        try next.expression(value.condition, .read);
        if (try next.checkStatement(value.body)) {
            if (value.step) |step| _ = try next.checkStatement(step);
        }
    }

    /// The owners of a borrowed call result that a match reads in place (R3b), or null for any other scrutinee. Its
    /// arms read the payload while the owners are held by loans, so the result is read, not moved into the match.
    fn matchBorrowedRoots(c: *Checker, value: typed.NodeId) Error!?Roots {
        if (!borrowedCallValue(c.program, c.linear, value)) return null;
        return c.borrowedCallRoots(value, 0);
    }

    /// The loan a named scrutinee holds for one arm (C3). An arm that binds nothing holds nothing, so its body may change the
    /// scrutinee's owner. A payload binding holds the owner until the arm body's last statement that reads one of the
    /// bindings, so a change after that point is allowed while a change before it, or a read after it, is refused. A
    /// generated narrowing binding, or a body that is not a block, holds the owner for the whole arm. A payload of no
    /// storage, fielded or not, holds nothing (FR93).
    fn armHold(c: *Checker, arm: typed.MatchArm, root: usize, value: typed.NodeId, mode: MatchMode) Error!void {
        const span = c.program.nodes[@backingInt(value)].span;
        const write = mode.exclusive;
        if (write) try c.registerExclusiveBinders(arm);
        const slot = arm.slot orelse return;
        // A payload that owns no storage (a number, a flag, a record of those) is copied when it is bound, so the arm reads
        // nothing of the scrutinee after that and may change it, the matched place included: `case Some(sec): attach[i] = None`
        // (zero-copy part 1, F-RC-110, F-RA-401), and a fielded `case num(v=n): t.keys[i] = Key.other` the same (the build
        // binds a named payload as a value, `armBody` in build.zig; FR93).
        const payload_type = c.function.scope.locals[@backingInt(slot)].ty;
        const copied = !c.owns(payload_type) and !resources.affine(c.program, payload_type);
        if (!write and copied) return;
        const body = if (arm.unpack) |unpack| unpack.body else arm.body;
        const statement = c.program.statements[@backingInt(body)];
        const narrowing = std.mem.startsWith(u8, c.function.scope.locals[@backingInt(slot)].name, "<");
        if (narrowing or statement.data != .block) return c.loans.append(c.a, .{ .root = root, .write = write, .rule = if (write) .X2 else .X1, .hold = .{ .matched = span } });
        var last: ?usize = null;
        for (statement.data.block, 0..) |item, index| {
            if (try c.mentionsBinding(item, arm)) last = index;
        }
        const release = last orelse return;
        // A bind-or-else holds its place as a `const` alias of it would: the binding is the borrower, and the refusal says so.
        if (mode.continuation) return c.arm_holds.append(c.a, .{ .body = body, .loan = .{ .root = root, .write = false, .binding = @backingInt(slot), .release = release } });
        try c.arm_holds.append(c.a, .{ .body = body, .loan = .{ .root = root, .write = write, .rule = if (write) .X2 else .X1, .hold = .{ .matched = span }, .release = release } });
    }

    /// Record the payload bindings of one `match mut` arm as exclusive binders (C1).
    fn registerExclusiveBinders(c: *Checker, arm: typed.MatchArm) Error!void {
        if (arm.slot) |slot| try c.exclusive_binders.append(c.a, @backingInt(slot));
        if (arm.unpack) |unpack| for (unpack.fields) |field| if (field) |slot| try c.exclusive_binders.append(c.a, @backingInt(slot));
    }

    /// Whether `slot` is a payload binding of a `match mut` arm (C1).
    fn isExclusiveBinder(c: *const Checker, slot: usize) bool {
        return std.mem.indexOfScalar(usize, c.exclusive_binders.items, slot) != null;
    }

    /// Whether `slot` is a `match mut` binding, or a compiler temporary of the scrutinee's receiver or of an expression
    /// that names a binding (registered when it is initialized). Such a temporary exists only for an expression the
    /// binding's own arm contains, so its write reaches the container through that arm's hold (C1).
    fn exclusiveAccess(c: *const Checker, slot: usize) bool {
        return c.isExclusiveBinder(slot) or c.isExclusiveReceiver(slot);
    }

    /// The enclosing arm's `match mut` binding a `match mut` place starts at (`sh` of `match mut sh` or `match mut sh.f`),
    /// or null (FX9).
    fn placeBinder(c: *const Checker, value: typed.NodeId) ?usize {
        var current = value;
        for (0..32) |_| switch (c.program.nodes[@backingInt(current)].data) {
            .local => |slot| return if (c.isExclusiveBinder(@backingInt(slot))) @backingInt(slot) else null,
            .field => |field| current = field.base,
            else => return null,
        };
        return null;
    }

    /// The place of the running `match mut` whose arms' holds carry `span`, or null (FX9).
    fn heldPlace(c: *const Checker, span: Span) ?typed.NodeId {
        for (c.held_places.items) |held| if (std.meta.eql(held.span, span)) return held.place;
        return null;
    }

    /// Whether `slot` is an enclosing arm's binding that the inner `match mut` whose arms' holds carry `span` matches (FX9).
    fn heldBinderFor(c: *const Checker, slot: usize, span: Span) bool {
        const place = c.heldPlace(span) orelse return false;
        return c.placeBinder(place) == slot;
    }

    /// The local a chain of field reads starts at, when its type is one the check does not track (FX9).
    fn untrackedRoot(c: *const Checker, base: typed.NodeId) ?usize {
        var current = base;
        for (0..32) |_| switch (c.program.nodes[@backingInt(current)].data) {
            .field => |field| current = field.base,
            .local => |slot| return if (c.tracked(c.function.scope.locals[@backingInt(slot)].ty)) null else @backingInt(slot),
            else => return null,
        };
        return null;
    }

    /// The field indices from a place's root local to the place, or null when a step is not a field (FX9).
    fn fieldPath(c: *const Checker, start: typed.Node, out: *[32]usize) ?[]const usize {
        var depth: usize = 0;
        var node = start;
        while (true) switch (node.data) {
            .field => |field| {
                if (depth == out.len) return null;
                out[depth] = field.index;
                depth += 1;
                node = c.program.nodes[@backingInt(field.base)];
            },
            .local => break,
            else => return null,
        };
        std.mem.reverse(usize, out[0..depth]);
        return out[0..depth];
    }

    /// A write to the part `written` of the untracked owner `slot`: refused while a running `match mut` arm holds the
    /// owner, unless the part lies beside the matched place (its path leaves the place's path) (FX9).
    fn checkHeldPartWrite(c: *Checker, slot: usize, written: typed.Node, span: Span) Error!void {
        var written_steps: [32]usize = undefined;
        const path = c.fieldPath(written, &written_steps);
        for (c.loans.items) |loan| {
            if (!loan.write or loan.hold != .matched) continue;
            if (loan.root != slot and !c.heldBinderFor(slot, loan.hold.matched)) continue;
            if (path) |steps| if (c.heldPlace(loan.hold.matched)) |place| {
                var held_steps: [32]usize = undefined;
                if (c.fieldPath(c.program.nodes[@backingInt(place)], &held_steps)) |held| {
                    const common = @min(held.len, steps.len);
                    if (!std.mem.eql(usize, held[0..common], steps[0..common])) continue;
                }
            };
            return c.loanConflict(loan, slot, true, .mutate, span);
        }
    }

    /// Whether the stored value `written` changes only fields beside the held `place`: an update of the owner whose
    /// fields leave the place's path (`h.tag = x` beside `match mut h.shape`; `w.h.tag = x` beside `match mut w.h.shape`).
    /// Such a write leaves the matched place as it is (FX9).
    fn besidePlace(c: *const Checker, place: typed.NodeId, written: typed.NodeId) bool {
        var path: [32]usize = undefined;
        var depth: usize = 0;
        var current = place;
        while (true) switch (c.program.nodes[@backingInt(current)].data) {
            .field => |field| {
                if (depth == path.len) return false;
                path[depth] = field.index;
                depth += 1;
                current = field.base;
            },
            .local => break,
            else => return false,
        };
        std.mem.reverse(usize, path[0..depth]);
        var value = written;
        for (path[0..depth]) |step| {
            const update = switch (c.program.nodes[@backingInt(value)].data) {
                .update => |update| update,
                else => return false,
            };
            var next: ?typed.NodeId = null;
            for (update.fields) |field| if (field.index == step) {
                next = field.value;
            };
            value = next orelse return true;
        }
        return false;
    }

    /// Record a compiler temporary whose initializer names a `match mut` binding, so its write reaches the container (C1).
    fn noteExclusiveReceiver(c: *Checker, slot: usize, store: typed.Store, initializing: bool) Error!void {
        if (!initializing or !c.temporary(slot)) return;
        if (c.namesExclusiveBinder(store.value, 0)) try c.exclusive_receivers.append(c.a, slot);
    }

    /// The checks a `match mut` scrutinee passes before its arms run (C1): a named, mutable owner that is not moved or
    /// borrowed here, and the receiver temporary of its place read.
    fn beginExclusive(c: *Checker, value: typed.NodeId, source: ?usize, owned: bool, borrowed: ?Roots) Error!void {
        const span = c.program.nodes[@backingInt(value)].span;
        if (source == null or owned or borrowed != null) return c.reject(span, .{ .code = borrow_error, .rule = .X2 }, "`match mut` writes the payload back into the place it names, " ++
            "so the place must be an owner that is not moved or borrowed here; bind the value to a `mut` local first");
        if (!c.writableOwner(source.?)) return c.reject(span, .{ .code = borrow_error, .rule = .X2 }, "`match mut` writes the payload back into its place, " ++
            "so the owner must be a mutable local or parameter: declare it `mut`");
        if (c.scrutineeReceiver(value)) |temp| try c.exclusive_receivers.append(c.a, temp);
    }

    /// Whether the owner in `slot` may be written: its state says so, or it is a `mut` local of a type that holds no managed
    /// value (a union whose payloads are all scalars), whose state the check never records (FX5: `match mut` on such a local
    /// was refused as if it were `const`, while the same match through a `mut` parameter was accepted).
    fn writableOwner(c: *const Checker, slot: usize) bool {
        if (c.state[slot].traits.writable) return true;
        if (slot >= c.function.scope.locals.len) return false;
        const local = c.function.scope.locals[slot];
        return local.mutable and !c.owns(local.ty);
    }

    /// Whether a scrutinee is a projection of an owner (an element, a field, a list read): only such a match narrows (C3).
    fn scrutineeProjection(c: *const Checker, value: typed.NodeId) bool {
        return switch (c.program.nodes[@backingInt(value)].data) {
            .index, .field, .block_value, .buffer_operation => true,
            else => false,
        };
    }

    /// Whether an initializer names a `match mut` binding, through fields, elements and block values (C1).
    fn namesExclusiveBinder(c: *const Checker, id: typed.NodeId, depth: usize) bool {
        if (depth > 32) return false;
        return switch (c.program.nodes[@backingInt(id)].data) {
            .local => |slot| c.isExclusiveBinder(@backingInt(slot)),
            .field => |field| c.namesExclusiveBinder(field.base, depth + 1),
            .index => |index| c.namesExclusiveBinder(index.base, depth + 1),
            .block_value => |block| c.namesExclusiveBinder(block.value, depth + 1) or c.namesThroughStagedReceiver(block, depth),
            .buffer_operation => |operation| c.isExclusiveBinder(@backingInt(operation.owner)),
            else => false,
        };
    }

    /// Whether a block's value reads through a receiver temporary that the block itself initializes from a place naming a
    /// `match mut` binding (`{ <collection> = items; read(<collection>, 0) }`): the temporary is registered as the block's
    /// statements are checked, which is after the enclosing initializer asks (`exchange(mut items[0], v)` stages the element
    /// in a second temporary, whose writes reach the container as the first one's do).
    fn namesThroughStagedReceiver(c: *const Checker, block: anytype, depth: usize) bool {
        const lender = c.lenderLocal(block.value, 0) orelse return false;
        const body = c.program.statements[@backingInt(block.body)];
        if (body.data != .block) return false;
        for (body.data.block) |id| {
            const statement = c.program.statements[@backingInt(id)];
            if (statement.data != .initialize or @backingInt(statement.data.initialize.slot) != lender) continue;
            if (c.namesExclusiveBinder(statement.data.initialize.value, depth + 1)) return true;
        }
        return false;
    }

    /// Whether `slot` is the receiver temporary of a `match mut` scrutinee (C1).
    fn isExclusiveReceiver(c: *const Checker, slot: usize) bool {
        return std.mem.indexOfScalar(usize, c.exclusive_receivers.items, slot) != null;
    }

    /// The receiver temporary a place read of `value` goes through: a block whose only statement initializes it, and
    /// whose value reads through it (the shape `argumentPath` and `receiverPlaceOwner` recognize).
    fn scrutineeReceiver(c: *const Checker, value: typed.NodeId) ?usize {
        const node = c.program.nodes[@backingInt(value)];
        if (node.data != .block_value) return null;
        const body = c.program.statements[@backingInt(node.data.block_value.body)];
        if (body.data != .block or body.data.block.len != 1) return null;
        const statement = c.program.statements[@backingInt(body.data.block[0])];
        if (statement.data != .initialize) return null;
        const slot = @backingInt(statement.data.initialize.slot);
        return if (c.temporary(slot)) slot else null;
    }

    /// Whether a statement reads one of the payload bindings of a match arm (C3).
    fn mentionsBinding(c: *const Checker, statement: typed.StatementId, arm: typed.MatchArm) Error!bool {
        if (arm.slot) |slot| if (try c.mentions(statement, @backingInt(slot))) return true;
        if (arm.unpack) |unpack| for (unpack.fields) |field| if (field) |slot| {
            if (try c.mentions(statement, @backingInt(slot))) return true;
        };
        return false;
    }

    /// The arm hold whose body is `body`, if one is waiting to be applied when that block is entered (C3).
    fn armHoldFor(c: *const Checker, body: typed.StatementId) ?Loan {
        for (c.arm_holds.items) |hold| if (hold.body == body) return hold.loan;
        return null;
    }

    const MatchBinding = struct { root: usize, dependency: usize, owned: bool, source: ?typed.NodeId, writable: bool, exclusive: bool };

    /// A payload keeps its scrutinee's complete provenance, including the
    /// source set of a borrowed call whose owners cannot fit one root slot.
    fn matchBindingState(c: *const Checker, slot: typed.LocalId, binding: MatchBinding) State {
        const local = c.function.scope.locals[@backingInt(slot)];
        const narrowing = std.mem.startsWith(u8, local.name, "<");
        const local_writable = narrowing and local.mutable;
        return .{
            .available = true,
            .root = if (binding.owned) none else binding.root,
            .view_definition = .{ .node = binding.source },
            .dependency = binding.dependency,
            .traits = .{
                .borrowed = !binding.owned,
                .writable = (local_writable and binding.writable) or binding.exclusive,
            },
        };
    }

    /// Install this arm's payload bindings. An owned destructured payload is
    /// split into independent owners before its source statements run.
    fn enterMatchArm(c: *Checker, arm: typed.MatchArm, binding: MatchBinding) typed.StatementId {
        if (arm.slot) |slot| c.state[@backingInt(slot)] = c.matchBindingState(slot, binding);
        if (!binding.owned or arm.unpack == null) return arm.body;
        if (arm.slot) |slot| c.state[@backingInt(slot)].available = false;
        for (arm.unpack.?.fields) |field| if (field) |slot| {
            c.state[@backingInt(slot)] = .{ .available = true, .dependency = binding.dependency };
        };
        return arm.unpack.?.body;
    }

    /// Source pattern bindings end with the arm's lexical scope. A generated
    /// narrowing binding remains available to its enclosing block value.
    fn leaveMatchArm(c: *Checker, arm: typed.MatchArm) void {
        if (arm.slot) |slot| if (!std.mem.startsWith(u8, c.function.scope.locals[@backingInt(slot)].name, "<")) {
            c.state[@backingInt(slot)].available = false;
        };
        if (arm.unpack) |unpack| for (unpack.fields) |field| if (field) |slot| {
            c.state[@backingInt(slot)].available = false;
        };
    }

    /// How a match holds its scrutinee: `exclusive` is `match mut`; `continuation` is a bind-or-else, whose success arm holds the
    /// rest of the enclosing block, so a named scrutinee is held until the arm's last use of a binding, as a `const` alias is.
    const MatchMode = struct { exclusive: bool = false, continuation: bool = false };

    fn matchArms(c: *Checker, value: typed.NodeId, arms: []const typed.MatchArm, mode: MatchMode) Error!bool {
        const exclusive = mode.exclusive;
        const borrowed = try c.matchBorrowedRoots(value);
        const consumed = try c.matchOwnScrutinee(value, exclusive);
        const owned = borrowed == null and (consumed or matchOwnsTemporary(c.program.nodes, value) or resources.affine(c.program, c.program.nodes[@backingInt(value)].ty));
        try c.expression(value, if (owned) .move else .read);
        const dependency = try c.resourceOrigin(value);
        const before = try c.a.dupe(State, c.state);
        const saved = c.loans.items.len;
        errdefer c.loans.shrinkRetainingCapacity(saved);
        // A consumed owner (2A) is gone once the match starts: nothing holds it, and its payload bindings own their values.
        const source = if (consumed) null else c.origin(value);
        // A named scrutinee is held per arm (C3): see `armHold`. Owned and borrowed-call scrutinees keep the match-wide hold.
        // Only a projection of an owner (an element, a field) narrows: a bare named scrutinee keeps its match-wide hold,
        // so the match refuses a move of the value it is matching (`return tried` in its own arm).
        const projection = c.scrutineeProjection(value);
        const narrow = source != null and !owned and borrowed == null and (projection or exclusive or mode.continuation);
        const scrutinee_span = c.program.nodes[@backingInt(value)].span;
        const holds_saved = c.arm_holds.items.len;
        defer c.arm_holds.shrinkRetainingCapacity(holds_saved);
        if (source) |root| if (!narrow) try c.loans.append(c.a, .{ .root = root, .write = false, .rule = .X1, .hold = .{ .matched = scrutinee_span } });
        const exclusive_base = c.exclusive_binders.items.len;
        defer c.exclusive_binders.shrinkRetainingCapacity(exclusive_base);
        const receiver_base = c.exclusive_receivers.items.len;
        defer c.exclusive_receivers.shrinkRetainingCapacity(receiver_base);
        if (exclusive) try c.beginExclusive(value, source, owned, borrowed);
        const held_base = c.held_places.items.len;
        defer c.held_places.shrinkRetainingCapacity(held_base);
        if (exclusive) try c.held_places.append(c.a, .{ .place = value, .span = scrutinee_span });
        // Every owner of a borrowed result is held while the arms run, so a change to any of them is refused.
        if (borrowed) |roots| for (roots.slice()) |root| try c.loans.append(c.a, .{ .root = root, .write = false, .rule = .X1, .hold = .{ .matched = scrutinee_span } });
        const payload_root: usize = if (borrowed) |roots| if (roots.items.len == 1 and !roots.temp) roots.items[0] else none else none;
        const binding: MatchBinding = .{
            .root = source orelse payload_root,
            .dependency = dependency orelse none,
            .owned = owned,
            .source = if (borrowed != null) value else null,
            .writable = if (source) |root| c.writableOwner(root) else false,
            .exclusive = exclusive,
        };
        var joined: ?[]State = null;
        const task_mark = c.tasks.loans.items.len;
        var joined_tasks: Tasks = .{};
        for (arms) |arm| {
            c.tasks.loans.shrinkRetainingCapacity(task_mark);
            @memcpy(c.state, before);
            const body = c.enterMatchArm(arm, binding);
            if (exclusive) c.held_places.items[held_base].payload = if (arm.slot) |slot| @backingInt(slot) else none;
            const arm_saved = c.loans.items.len;
            if (narrow) try c.armHold(arm, source.?, value, mode);
            const falls = try c.checkStatement(body);
            c.loans.shrinkRetainingCapacity(arm_saved);
            c.arm_holds.shrinkRetainingCapacity(holds_saved);
            if (!falls) continue;
            for (c.tasks.loans.items[task_mark..]) |loan| try joined_tasks.add(c.a, loan);
            c.leaveMatchArm(arm);
            if (joined) |previous| try c.merge(previous, c.state);
            if (joined == null) joined = try c.a.alloc(State, c.state.len);
            @memcpy(joined.?, c.state);
        }
        c.loans.shrinkRetainingCapacity(saved);
        c.tasks.loans.shrinkRetainingCapacity(task_mark);
        for (joined_tasks.loans.items) |loan| try c.tasks.add(c.a, loan);
        if (joined) |after| {
            @memcpy(c.state, after);
            try c.restoreConstLoans();
        }
        return joined != null;
    }

    /// Whether `match own value:` consumes a named owner (2A). Only an owned local or an `own` parameter can be consumed: a
    /// borrowed or `mut` parameter, a borrowed local, and a field or element place are refused here with the repair that
    /// applies, before the ordinary move check could word the refusal as a store. A resource keeps its own consuming path.
    fn matchOwnScrutinee(c: *Checker, value: typed.NodeId, exclusive: bool) Error!bool {
        const node = c.program.nodes[@backingInt(value)];
        if (!node.own or !c.owns(node.ty)) return false;
        if (resources.affine(c.program, node.ty)) return false;
        std.debug.assert(node.data != .local or matchConsumesNamed(c.program, c.linear, value));
        if (exclusive) return c.refuseMatchOwn(node, "`match mut` writes into the place it matches and `match own` would consume it; remove own");
        const slot = switch (node.data) {
            .local => |slot| @backingInt(slot),
            .field, .index, .block_value => return c.refuseMatchOwn(node, place_scrutinee),
            else => return false,
        };
        const parameter = slot < c.function.signature.parameter_count;
        const own_parameter = parameter and slot < c.function.scope.own_parameters.len and c.function.scope.own_parameters[slot];
        const name = c.function.scope.locals[slot].name;
        if (parameter and !own_parameter and c.function.scope.locals[slot].mutable)
            return c.refuseMatchOwn(node, try std.fmt.allocPrint(c.diagnostics.allocator, mut_scrutinee, .{ name, name }));
        if (parameter and !own_parameter)
            return c.refuseMatchOwn(node, try std.fmt.allocPrint(c.diagnostics.allocator, "'{s}' is a borrowed parameter, so `match own` cannot consume it; remove own to borrow its payload, or declare the parameter `own`", .{name}));
        if (c.state[slot].available and c.state[slot].traits.borrowed)
            return c.refuseMatchOwn(node, try std.fmt.allocPrint(c.diagnostics.allocator, "'{s}' borrows another owner, so `match own` cannot consume it; remove own to borrow its payload, or match `own` the owner it borrows", .{name}));
        return true;
    }

    /// Refuse a marked scrutinee `match own` cannot consume, offering the removal of the marker as before 2A.
    /// `message` is made in `c.diagnostics.allocator`, as every formatted refusal is: `c.a` is freed when the function's
    /// check returns, before the refusal is printed (FX8: `check --no-cache` crashed reading it).
    fn refuseMatchOwn(c: *Checker, node: typed.Node, message: []const u8) Error {
        c.misplacedMarker(null, node, own_read, message) catch |err| return err;
        unreachable;
    }

    /// The checks a non-view `return` value passes. The slice's endpoints lower
    /// into temporaries inside the value's block, so the escape is judged after
    /// the value has been checked and those temporaries have their owners.
    fn checkReturn(c: *Checker, value: typed.NodeId, span: Span) Error!void {
        const observer = c.diagnostics.observer;
        const previous_audit = if (observer) |seen| seen.returned else null;
        if (observer) |seen| seen.returned = c.observedReturnBinding(value);
        defer if (observer) |seen| {
            seen.returned = previous_audit;
        };
        try c.expression(value, .move);
        try c.sliceReturn(value);
        if (resources.dependent(c.program, c.function.signature.return_type)) try c.resourceReturn(value, span);
    }

    /// Classify a `return` value before it is checked (R3a). The value is read
    /// through the same origin the checker uses for borrows: a place of a
    /// borrowed parameter is `place`; an owned local or a value built on the path
    /// is `new`; `None`, a literal or a number is `neutral`; any other view of a
    /// local is `other`.
    fn returnKind(c: *Checker, value: typed.NodeId) ReturnKind {
        const payload = c.returnedPayload(value);
        switch (c.program.nodes[@backingInt(payload)].data) {
            .integer, .boolean, .unit, .blob => return .neutral,
            // A text or bytes literal is an array node of its own type: a constant.
            .array => if (c.constantText(c.program.nodes[@backingInt(payload)].ty)) return .neutral,
            .variant => |variant| if (variant.value == null) return .neutral,
            .block_value => if (emptyListLiteral(c.program, payload)) return .neutral,
            else => {},
        }
        const root = c.sliceRoot(payload) orelse c.origin(payload) orelse return .new;
        if (root < c.function.signature.parameter_count) return if (c.state[root].traits.borrowed) .place else .new;
        const node = c.program.nodes[@backingInt(payload)];
        if (node.data == .local and @backingInt(node.data.local) == root and !c.viewLike(root)) return .new;
        return .other;
    }

    /// Whether `ty` is text or bytes, whose array node is a literal constant.
    /// Whether a value is a static constant with no storage to own or free: a number, a bool, a unit, a byte blob, a text or
    /// bytes literal, a case with no payload (`None`), or the empty list literal `[]`.
    fn staticValue(c: *const Checker, id: typed.NodeId) bool {
        // The empty list literal is the runtime's static empty list in these positions (4e; the lowering's `staticEmptyList`).
        if (emptyListLiteral(c.program, id)) return true;
        const node = c.program.nodes[@backingInt(id)];
        return switch (node.data) {
            .integer, .boolean, .unit, .blob => true,
            .array => c.constantText(node.ty),
            .variant => |variant| variant.value == null,
            .block_value => |block| c.staticValue(block.value),
            else => false,
        };
    }

    fn constantText(c: *const Checker, ty: typed.Type) bool {
        if (!ty.isAggregate() or ty.recordIndex() >= c.program.records.len) return false;
        const kind = c.program.records[ty.recordIndex()].collection.kind;
        return kind == .string or kind == .bytes;
    }

    /// The root a checked slice borrows: the root of the local its slice
    /// expression slices, through the temporaries the lowering wraps it in. Null
    /// when `id` is not a slice.
    fn sliceRoot(c: *Checker, id: typed.NodeId) ?usize {
        if (c.sliceNode(id, 0)) |slice| return c.rootOf(@backingInt(slice.data.buffer_operation.owner));
        return c.listSliceSource(id);
    }

    /// Record one return for the mixed-return refusal (R3a): a borrowed return
    /// names the span its copy repair wraps, and the first new value is kept for
    /// the refusal's related span.
    fn noteReturn(c: *Checker, kind: ReturnKind, value: typed.NodeId) Error!void {
        const span = c.program.nodes[@backingInt(c.returnedPayload(value))].span;
        switch (kind) {
            .place => {
                if (c.probing.active) try c.returns.borrowed_values.append(c.a, value);
                for (c.returns.borrowed.items) |seen| if (seen.start == span.start and seen.end == span.end) return;
                try c.returns.borrowed.append(c.a, span);
            },
            // A view of an owned local is judged by the escape rules, and a list literal or a call's fresh value is a new
            // storage: both are new values for the mixed-return rule, so no borrowed return beside them is accepted.
            .new, .other => if (c.returns.new_value == null) {
                c.returns.new_value = span;
            },
            .neutral => {},
        }
    }

    /// The function's outcome once its body is checked (R3a). A refused borrowed
    /// return that no later refusal replaces is raised here, as the mixed-return
    /// refusal when the function also returns a new value.
    fn finishReturns(c: *Checker, body: Error!bool) Error!void {
        _ = body catch |err| {
            if (err != error.Rejected or c.returns.refused == null) return err;
            return c.refuseReturns();
        };
        if (c.returns.missing.items.len != 0 and !c.mixedReturns()) return c.undeclaredReturns();
        if (c.returns.refused == null and !c.mixedReturns()) return;
        return c.refuseReturns();
    }

    /// Whether the function returns a borrow on one path and a new value on another (R3a's test, now also for accepted
    /// borrowed returns, which are refused when the function returns a new value).
    fn mixedReturns(c: *const Checker) bool {
        if (c.returns.new_value == null) return false;
        return c.returns.borrowed.items.len != 0 or return_borrow.effectiveSources(c.program.records, c.function.signature).len != 0;
    }

    /// The refusal of an undeclared borrowed return whose result `caller` keeps (F-8): the copy of every borrowed return
    /// is the repair, since a `from` result would be refused in that caller.
    fn undeclaredCopy(c: *Checker, span: Span, caller: usize) Error {
        const first: ?usize = if (c.returns.missing.items.len != 0) c.returns.missing.items[0] else null;
        const lent = try c.escapeMessageTo(span, first, .returned, .copy, "");
        const name = try language.display_name.spelled(c.diagnostics.allocator, c.program.functions[caller].name);
        const message = try std.fmt.allocPrint(c.diagnostics.allocator, "{s}: `{s}` keeps the result, and a result declared `from` a parameter would be lent to it", .{ lent, name });
        const result = c.reject(span, .{ .code = "E_BORROW_UNDECLARED", .rule = .R4 }, message);
        c.failure.copy = .{ .borrowed = try c.diagnostics.allocator.dupe(Span, c.returns.borrowed.items) };
        c.failure.notes.related = .{ .span = c.program.functions[caller].declaration, .message = "this caller keeps the result" };
        return result;
    }

    /// Whether the function returns a `byte_buffer`, a result that cannot be declared `from` a parameter (FX17).
    fn bufferResult(c: *Checker) bool {
        const ty = c.function.signature.return_type;
        const records = c.program.records;
        if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
        const record = records[ty.recordIndex()];
        return record.managed and record.collection.kind == .bytes and !language.typed.isByteString(record);
    }

    /// A returned borrow of a function whose result is a `byte_buffer` (FX17: `return buf[1:3]`): the result cannot be declared
    /// `from` a parameter, so the repair is a buffer of its own, `copy(...)`, which `selka fix` writes, or the octets,
    /// `bytes(...)`, in a function whose result is `bytes`.
    fn undeclaredBufferCopy(c: *Checker, span: Span) Error {
        const first: ?usize = if (c.returns.missing.items.len != 0) c.returns.missing.items[0] else null;
        const lent = try c.escapeMessageTo(span, first, .returned, .copy, "");
        const text = if (c.source) |src| if (span.start < span.end and span.end <= src.bytes.len) src.text(span) else "" else "";
        const octets = if (text.len == 0 or text.len > 60)
            "`bytes(...)` of it"
        else
            try std.fmt.allocPrint(c.diagnostics.allocator, "`bytes({s})`", .{text});
        const message = try std.fmt.allocPrint(c.diagnostics.allocator, "{s}: a `byte_buffer` result cannot be declared `from` a parameter; for the octets alone, return {s} from a function whose result is `bytes`", .{ lent, octets });
        const result = c.reject(span, .{ .code = "E_BORROW_UNDECLARED", .rule = .R4 }, message);
        c.failure.copy = .{ .borrowed = try c.diagnostics.allocator.dupe(Span, c.returns.borrowed.items) };
        return result;
    }

    /// The first function of the program that keeps the result of the function being checked (F-8, F-15): a caller the
    /// ownership check accepts while the result is new, and refuses once the result is declared `from` the parameters at
    /// `positions`, for any reason but its own undeclared borrowed return (a caller that returns the result passes the
    /// borrow on, and its own `from` clause is the next round's repair). Null when every caller only reads or passes on
    /// the result, or when no function of the program calls it.
    fn keepingCaller(c: *Checker, positions: []const usize) Error!?usize {
        const own = for (c.program.functions, 0..) |function, index| {
            if (std.meta.eql(function.declaration, c.function.declaration) and std.mem.eql(u8, function.name, c.function.name)) break index;
        } else return null;
        const shared: Shared = .{ .program = c.program, .linear = c.linear, .source = c.source, .case_payloads = c.case_payloads };
        return keepingCallerIn(c.a, shared, own, positions);
    }

    /// A missing contract names every source in one declaration edit, while
    /// preserving names already declared even when this body does not use them.
    fn undeclaredReturns(c: *Checker) Error {
        const span = c.returns.first_missing.?;
        var required = c.returns.roots;
        for (return_borrow.sources(c.function.signature)) |position| try required.add(c.a, position);
        // F-8, F-15: with no `from` clause yet, the callers decide the repair. A caller that keeps the result would be
        // refused once the result is declared `from`, so the copy is the repair; with none, the clause is.
        const choosing = return_borrow.sources(c.function.signature).len == 0 and !c.probing.active and c.source != null;
        if (c.bufferResult()) return c.undeclaredBufferCopy(span);
        const keeper = if (choosing) try c.keepingCaller(required.items) else null;
        if (keeper) |caller| return c.undeclaredCopy(span, caller);
        const result = c.reject(span, .{ .code = "E_BORROW_UNDECLARED", .rule = .R4 }, try c.undeclaredMessage(span, required, choosing));
        // A returned `mut` local that holds a borrow (4f) keeps its owning stores' copy repairs rather than a new contract.
        if (try c.returnedBorrowedMut()) |slot| c.notePlainCause(slot);
        // So does a returned borrowed record (1A).
        try c.noteReturnedRecord();
        const src = c.source orelse return result;
        if (try borrow_return_repair.amend(c.diagnostics.allocator, src, c.function.declaration, required.items)) |edit| {
            c.failure.repair = .{ .explicit_fix = try c.diagnostics.allocator.dupe(language.diagnostic.Edit, &.{edit}) };
        }
        return result;
    }

    /// The Escape message of a return that borrows a parameter the signature does not name: the first such return, lent by its
    /// parameter, with the `from` clause that names every source as a repair.
    fn undeclaredMessage(c: *Checker, span: Span, required: Roots, alone: bool) Error![]const u8 {
        const first: ?usize = if (c.returns.missing.items.len != 0) c.returns.missing.items[0] else null;
        return c.escapeMessageTo(span, first, .returned, .{ .declare_from = .{ .sources = try c.fromNames(required.items), .alone = alone } }, "");
    }

    /// A `mut` local holding a borrow (4f) that a borrowed return of this function returns, if any.
    fn returnedBorrowedMut(c: *Checker) Error!?usize {
        if (std.mem.indexOfScalar(bool, c.borrowed_mut, true) == null) return null;
        var walker = try typed_walk.Walker.init(c.a, c.program, c.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item != .statement) continue;
            const data = c.program.statements[@backingInt(item.statement)].data;
            if (data != .ret) continue;
            const payload = c.program.nodes[@backingInt(c.returnedPayload(data.ret))];
            if (payload.data != .local or !c.borrowed_mut[@backingInt(payload.data.local)]) continue;
            for (c.returns.borrowed.items) |seen| if (seen.start == payload.span.start and seen.end == payload.span.end) return @backingInt(payload.data.local);
        }
        return null;
    }

    /// Refuse a generic instance whose `from` sources cannot lend its result (`instance_borrow.zig`): at the call that made
    /// it, with its declaration as the related fact and the clause's removal where that is certain.
    fn refuseUnlendable(c: *Checker) Error {
        const a = c.diagnostics.allocator;
        const call = instance_borrow.firstCall(c.program, c.function.id);
        c.failure.* = .{
            .code = "E_BORROW_SOURCE",
            .rule = .R4,
            .message = try instance_borrow.message(a, c.function),
            .span = call orelse c.function.declaration,
            .notes = .{ .related = if (call != null) .{ .span = c.function.declaration, .message = "the generic declaration and its `from` clause" } else null },
        };
        if (c.source) |src| if (try borrow_return_repair.removeConcreteSources(a, src, c.function.declaration)) |remove| {
            c.failure.repair = .{ .explicit_fix = try a.dupe(language.diagnostic.Edit, &.{remove}) };
        };
        return error.Rejected;
    }

    /// Raise the refusal of a function with a refused borrowed return. A function
    /// that also returns a new value gets one `E_BORROW_MIXED` with a `copy(...)`
    /// repair on every borrowed return; any other keeps its first refusal.
    fn refuseReturns(c: *Checker) Error {
        if (!c.mixedReturns()) {
            c.failure.* = c.returns.refused orelse return error.Rejected;
            return error.Rejected;
        }
        const new_span = c.returns.new_value.?;
        const borrowed = try c.diagnostics.allocator.dupe(Span, c.returns.borrowed.items);
        c.failure.* = .{
            .code = mixed_error,
            .rule = .R5,
            .message = try c.mixedMessage(borrowed, new_span),
            .span = if (borrowed.len == 0) new_span else borrowed[0],
            .copy = .{ .borrowed = borrowed },
            .notes = .{ .related = .{ .span = new_span, .message = "this return is a new value" } },
        };
        if (c.source) |src| if (try borrow_return_repair.remove(c.diagnostics.allocator, src, c.function.declaration)) |remove| {
            const copies = (try copyEdits(c.diagnostics.allocator, src, c.failure.copy)) orelse &.{};
            const edits = try c.diagnostics.allocator.alloc(language.diagnostic.Edit, copies.len + 1);
            edits[0] = remove;
            @memcpy(edits[1..], copies);
            c.failure.repair = .{ .explicit_fix = edits };
        };
        c.noteMixedCopy();
        try c.noteReturnedRecord();
        return error.Rejected;
    }

    /// The message of the mixed-return refusal, naming the lines of its borrowed
    /// returns and of its new value when the source is known: lines of the file
    /// the function is written in, not of the merged program.
    fn mixedMessage(c: *Checker, borrowed: []const Span, new_span: Span) Error![]const u8 {
        const name = c.function.name;
        if (borrowed.len == 0) return std.fmt.allocPrint(c.diagnostics.allocator, "`{s}` declares a borrowed result with `from` but returns new storage; remove `from` for an owned result", .{name});
        const source = c.source orelse return std.fmt.allocPrint(c.diagnostics.allocator, "`{s}` returns a borrow on one path and a new value on another; write copy(...) around each borrowed return", .{name});
        var lines: std.ArrayList(u8) = .empty;
        defer lines.deinit(c.diagnostics.allocator);
        for (borrowed, 0..) |span, index| {
            if (index != 0) try lines.appendSlice(c.diagnostics.allocator, ", ");
            const number = try std.fmt.allocPrint(c.diagnostics.allocator, "{d}", .{source.locate(span.start).line});
            try lines.appendSlice(c.diagnostics.allocator, number);
        }
        return std.fmt.allocPrint(c.diagnostics.allocator, "`{s}` returns a borrow on line {s} and a new value on line {d}; write copy(...) around each borrowed return", .{ name, lines.items, source.locate(new_span.start).line });
    }

    fn checkBranch(c: *Checker, branch: @FieldType(@FieldType(typed.Statement, "data"), "branch")) Error!bool {
        try c.expression(branch.condition, .read);
        const before = try c.a.dupe(State, c.state);
        const loans = c.loans.items.len;
        const tasks = c.tasks.loans.items.len;
        const first_falls = try c.checkStatement(branch.then_body);
        const first_tasks = try c.a.dupe(TaskLoan, c.tasks.loans.items[tasks..]);
        c.tasks.loans.shrinkRetainingCapacity(tasks);
        const first = try c.a.dupe(State, c.state);
        const first_loans = try c.a.dupe(Loan, c.loans.items[loans..]);
        c.loans.shrinkRetainingCapacity(loans);
        @memcpy(c.state, before);
        const second_falls = if (branch.else_body) |body| try c.checkStatement(body) else true;
        if (!second_falls) c.tasks.loans.shrinkRetainingCapacity(tasks);
        if (first_falls) for (first_tasks) |loan| try c.tasks.add(c.a, loan);
        if (!second_falls) c.loans.shrinkRetainingCapacity(loans);
        if (first_falls and second_falls) {
            const second = try c.a.dupe(State, c.state);
            try c.merge(first, second);
        } else if (first_falls) @memcpy(c.state, first);
        try c.mergeBranchLoans(loans, if (first_falls) first_loans else &.{});
        return first_falls or second_falls;
    }

    fn checkStatement(c: *Checker, id: typed.StatementId) Error!bool {
        const statement = c.program.statements[@backingInt(id)];
        const outer_moves = c.field_moves;
        defer c.field_moves = outer_moves;
        c.field_moves = try field_moves.of(c.a, c.program, id, c, carriesField);
        switch (statement.data) {
            .block => |items| {
                const saved = c.loans.items.len;
                const outer = c.block;
                c.block = .{ .items = items, .id = id, .span = statement.span, .parent = if (outer) |*parent| parent else null };
                if (c.armHoldFor(id)) |loan| try c.loans.append(c.a, loan);
                defer {
                    c.releaseBindings(saved, null);
                    c.block = outer;
                }
                for (items, 0..) |item, index| {
                    c.block.?.index = index;
                    if (!try c.checkStatement(item)) return false;
                    c.releaseBindings(saved, index);
                }
            },
            .initialize => |store| try c.checkStore(store, true, statement.span),
            .assign => |store| try c.checkStore(store, false, statement.span),
            .discard => |value| try c.expression(value, if (resources.affine(c.program, c.program.nodes[@backingInt(value)].ty)) .move else .read),
            .ret => |value| {
                try c.returnValue(value, statement.span);
                return false;
            },
            .assertion => |assertion| {
                try c.expression(assertion.condition, .read);
                if (assertion.message_value) |message| try c.expression(message, .read);
                if (c.program.nodes[@backingInt(assertion.condition)].data == .boolean and !c.program.nodes[@backingInt(assertion.condition)].data.boolean) return false;
            },
            .branch => |branch| return c.checkBranch(branch),
            .with_scope => |scope| {
                const source = scope.resource orelse return c.rejectInternal(statement.span, "E_INTERNAL_RESOURCE_SCOPE", "compiler bug: a resource scope has no resource");
                const node = c.program.nodes[@backingInt(source)];
                // A task group's join releases its loans on every exit edge.
                if (node.data == .task_group_open) {
                    defer c.tasks.close(scope.slot);
                    const group = @backingInt(scope.slot);
                    c.state[group] = .{ .available = true, .traits = .{ .borrowed = true } };
                    const falls = try c.checkStatement(scope.body);
                    c.state[group].available = false;
                    return falls;
                }
                const provider = @import("build_cap.zig").scopeProvider(c.program, source) orelse return c.reject(statement.span, .{ .code = resource_origin, .rule = .P1 }, "open a dependent scope directly from a named provider");
                if (providers.root(c.program, provider) == null) return c.reject(statement.span, .{ .code = resource_origin, .rule = .P1 }, "bind the provider or its enclosing record to a local before opening a scope");
                if (node.data == .file_access or node.data == .propagate) {
                    try c.expression(source, .read);
                } else {
                    switch (node.data) {
                        .dir_resource => |dir| try c.arguments(&.{ provider, dir.path }, &.{}, &.{}, &.{}, false),
                        .host_resource => |host| try c.arguments(&.{ provider, host.name }, &.{}, &.{}, &.{}, false),
                        .environment_only => |only| try c.arguments(&.{ provider, only.names }, &.{}, &.{}, &.{}, false),
                        .restrict_resource => try c.expression(provider, .read),
                        else => try c.expression(source, .read),
                    }
                }
                const saved = c.loans.items.len;
                defer c.loans.shrinkRetainingCapacity(saved);
                // The scope holds its provider's owner until the `with` ends; the hold names the provider for the refusal (F-37).
                if (c.origin(provider)) |root| try c.loans.append(c.a, .{ .root = root, .write = false, .hold = .{ .scope = c.program.nodes[@backingInt(provider)].span } });
                const slot = @backingInt(scope.slot);
                c.state[slot] = .{ .available = true, .traits = .{ .borrowed = true, .scoped_resource = true, .rule = .P4 } };
                const falls = try c.checkStatement(scope.body);
                for (c.state, 0..) |*state, other| if (state.available and state.dependency == slot) {
                    if (other < slot) return c.reject(statement.span, .{ .code = resource_escape, .rule = .P2 }, "a resource cannot escape its provider scope");
                    state.available = false;
                };
                c.state[slot].available = false;
                return falls;
            },
            .match => |value| return c.matchArms(value.value, value.arms, .{ .exclusive = value.exclusive, .continuation = value.continuation }),
            .loop => |value| {
                try c.loop(value, statement.span);
                try c.restoreCollectionLoans();
            },
            .range_loop => |range| {
                const plan = range.plan();
                try c.checkStore(plan.start, true, statement.span);
                try c.checkStore(plan.end, true, statement.span);
                for (plan.setup) |setup| _ = try c.checkStatement(setup);
                try c.loop(plan.loop, statement.span);
                try c.restoreCollectionLoans();
            },
            .loop_exit => |exit| {
                for (c.tasks.loans.items) |loan| try c.tasks.exits.append(c.a, .{ .target = exit.target, .continuing = exit.continuing, .loan = loan });
                for (c.loops.items) |frame| if (frame.id == exit.target) try c.loopBack(frame.before, statement.span);
                return false;
            },
        }
        return true;
    }
};

/// Whether an IR value owns managed storage that an explicit copy must duplicate.
pub fn containsList(module: *const ir.Module, ty: ir.Type) bool {
    if (module.isView(ty)) return true;
    if ((ty == .str or ty == .bytes or ty == .byte_buffer)) return true;
    if (!ty.isCompound()) return false;
    return switch (module.compound(ty)) {
        .borrowed => |inner| containsList(module, inner),
        .list => true,
        .dict, .box => true,
        .@"union" => |cases| for (cases) |payload| {
            if (containsList(module, payload)) break true;
        } else false,
        .record => |fields| for (fields) |field| {
            if (containsList(module, field)) break true;
        } else false,
        .array => |array| containsList(module, array.elem),
        else => false,
    };
}

fn copyExpressionSource(a: std.mem.Allocator, src: language.source.Source, span: Span) error{OutOfMemory}!bool {
    var sink: language.diagnostic.Sink = .{ .allocator = a };
    defer sink.deinit();
    const tokens = language.lexer.lexRange(a, src.bytes, span, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return false,
    };
    defer a.free(tokens);
    var depth: usize = 0;
    for (tokens) |token| switch (token.tag) {
        .lparen, .lbracket, .lbrace => depth += 1,
        .rparen, .rbracket, .rbrace => {
            if (depth == 0) return false;
            depth -= 1;
        },
        .equal, .plus_equal, .minus_equal, .star_equal, .slash_equal, .slash_slash_equal, .percent_equal, .colon, .semicolon, .kw_return => if (depth == 0) return false,
        else => {},
    };
    return depth == 0;
}

/// The one edit that stores a lent value into a set with its own copy: `sets.add(mut seen, x)` becomes `sets.include(mut seen, x)`,
/// the text `copy(x)` and the needless-copy rewrite of it reach in two rounds. Null unless the span is the last argument of a call
/// `NAME.add(mut PLACE, SPAN)`, so any other store keeps the `copy(...)` repair.
fn setIncludeEdits(a: std.mem.Allocator, src: language.source.Source, copy: Copy) error{OutOfMemory}!?[]language.diagnostic.Edit {
    const span = copy.span orelse return null;
    if (copy.borrowed.len != 0) return null;
    if (copy.name != null and !std.mem.eql(u8, src.text(span), copy.name.?)) return null;
    const space = " \t\r\n";
    // Only the closing parenthesis follows the value.
    const after = std.mem.trimStart(u8, src.bytes[span.end..], space);
    if (after.len == 0 or after[0] != ')') return null;
    // A comma, then `mut PLACE`, then the opening parenthesis come before it.
    const before = std.mem.trimEnd(u8, src.bytes[0..span.start], space);
    if (before.len == 0 or before[before.len - 1] != ',') return null;
    const first = std.mem.trimEnd(u8, before[0 .. before.len - 1], space);
    var open = first.len;
    while (open > 0 and (std.ascii.isAlphanumeric(first[open - 1]) or std.mem.indexOfScalar(u8, "_. \t", first[open - 1]) != null)) open -= 1;
    if (open == 0 or first[open - 1] != '(') return null;
    const place = std.mem.trim(u8, first[open..], space);
    if (!std.mem.startsWith(u8, place, "mut ")) return null;
    // `NAME.add` is the callee.
    const callee = std.mem.trimEnd(u8, first[0 .. open - 1], space);
    if (!std.mem.endsWith(u8, callee, ".add")) return null;
    const dot = callee.len - ".add".len;
    if (dot == 0 or !(std.ascii.isAlphanumeric(callee[dot - 1]) or callee[dot - 1] == '_')) return null;
    const edits = try a.alloc(language.diagnostic.Edit, 1);
    edits[0] = .{ .span = .{ .start = @intCast(dot + 1), .end = @intCast(dot + 1 + "add".len) }, .text = "include" };
    return edits;
}

/// The edits of a copy repair: `copy(` before and `)` after each repaired span,
/// in source order. Null when no span is repairable: a name check fails, or a
/// span is not a whole expression, so the diagnostic offers no fix at all.
/// The function of `program` that keeps the result of function `callee` (F-8): a caller the ownership check accepts
/// while the result is new and refuses once it is declared `from` the parameters at `positions`, for any reason but its
/// own undeclared borrowed return. Null when every caller only reads the result or passes it on. `check` asks it before
/// printing `W_COPY_MOVE`, whose `from` advice such a caller would refuse.
pub fn keepingCallerOf(a: std.mem.Allocator, program: typed.Program, source: ?language.source.Source, callee: usize, positions: []const usize) Error!?usize {
    if (callee >= program.functions.len) return null;
    try markCallViews(a, program);
    const linear = try ownedTypes(a, program);
    const payloads = try BorrowedRecords.casePayloads(a, program);
    return keepingCallerIn(a, .{ .program = program, .linear = linear, .source = source, .case_payloads = payloads }, callee, positions);
}

/// `keepingCallerOf` over a check's own shared tables.
fn keepingCallerIn(a: std.mem.Allocator, before: Shared, own: usize, positions: []const usize) Error!?usize {
    const functions = before.program.functions;
    const sources = try a.alloc(u16, positions.len);
    for (positions, sources) |position, *slot| slot.* = std.math.cast(u16, position) orelse return null;
    std.mem.sort(u16, sources, {}, std.sort.asc(u16));
    const declared = try a.dupe(typed.Function, functions);
    declared[own].signature.return_origin = .{ .params = sources };
    // A caller that returns the result passes the borrow on: its own `from` clause is its repair.
    return firstRefusedCaller(a, before, declared, own, "E_BORROW_UNDECLARED");
}

/// For each `W_COPY_MOVE` hint `check` judges against the callers (FR14b), every function with a checked body that calls the
/// hint's function, and whether it keeps what the hint's advice would take: the result once it is declared `from` the
/// parameter (refused for any reason but its own undeclared borrowed return, or for any reason at all for a `strict` target),
/// or the argument once the parameter is `own`.
/// These are the answers `keepingCallerOf` and `keepingArgumentCallerOf` give, for every caller rather than the first that
/// keeps, with the shared tables built once. A caller the check refuses as written keeps nothing.
pub fn callerFacts(a: std.mem.Allocator, program: typed.Program, source: ?language.source.Source, targets: []const language.semantic_summary.HintTarget) error{OutOfMemory}![]const []const language.semantic_summary.CallerFact {
    const out = try a.alloc([]const language.semantic_summary.CallerFact, targets.len);
    @memset(out, &.{});
    if (targets.len == 0) return out;
    try markCallViews(a, program);
    const before: Shared = .{ .program = program, .linear = try ownedTypes(a, program), .source = source, .case_payloads = try BorrowedRecords.casePayloads(a, program) };
    const callers = try targetCallers(a, program, targets);
    const accepted = try a.alloc(?bool, program.functions.len);
    @memset(accepted, null);
    const declared = try a.dupe(typed.Function, program.functions);
    var after = before;
    after.program.functions = declared;
    for (targets, out, callers) |target, *facts, list| {
        if (target.callee >= declared.len) continue;
        const saved = declared[target.callee];
        defer declared[target.callee] = saved;
        try declareAdvice(a, &declared[target.callee], target);
        var found: std.ArrayList(language.semantic_summary.CallerFact) = .empty;
        for (list) |caller| {
            if (accepted[caller] == null) {
                var ignored: Failure = .{};
                accepted[caller] = if (checkFunction(a, before, program.functions[caller], &ignored, .{ .active = true })) |_| true else |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Rejected => false,
                };
            }
            var refused: Failure = .{};
            const keeps = accepted[caller].? and if (checkFunction(a, after, declared[caller], &refused, .{ .active = true })) |_| false else |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Rejected => !(target.result and !target.strict and std.mem.eql(u8, refused.code, "E_BORROW_UNDECLARED")),
            };
            try found.append(a, .{ .caller = caller, .keeps = keeps });
        }
        facts.* = found.items;
    }
    return out;
}

/// Change `function`'s signature the way the hint `target` advises: its result declared `from` the parameter, or the
/// parameter taken `own`.
fn declareAdvice(a: std.mem.Allocator, function: *typed.Function, target: language.semantic_summary.HintTarget) error{OutOfMemory}!void {
    if (target.result) {
        const sources = try a.alloc(u16, 1);
        sources[0] = std.math.cast(u16, target.position) orelse 0;
        function.signature.return_origin = .{ .params = sources };
        return;
    }
    const own_parameters = try a.alloc(bool, @max(function.signature.parameter_count, function.scope.own_parameters.len, target.position + 1));
    @memset(own_parameters, false);
    @memcpy(own_parameters[0..function.scope.own_parameters.len], function.scope.own_parameters);
    own_parameters[target.position] = true;
    function.scope.own_parameters = own_parameters;
}

/// For each target, the functions with a checked body that call its function (itself left out), each body walked once.
fn targetCallers(a: std.mem.Allocator, program: typed.Program, targets: []const language.semantic_summary.HintTarget) error{OutOfMemory}![]const []const usize {
    const wanted = try a.alloc(bool, program.functions.len);
    @memset(wanted, false);
    for (targets) |target| if (target.callee < wanted.len) {
        wanted[target.callee] = true;
    };
    const by_callee = try a.alloc(std.ArrayList(usize), program.functions.len);
    @memset(by_callee, .empty);
    for (program.functions, 0..) |caller, index| {
        if (!caller.scope.body_complete) continue;
        var walker = try typed_walk.Walker.init(a, program, caller.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item != .expression) continue;
            const call = switch (program.nodes[@backingInt(item.expression)].data) {
                .call => |value| value,
                else => continue,
            };
            const callee = @backingInt(call.function);
            if (callee >= wanted.len or !wanted[callee] or callee == index) continue;
            const list = &by_callee[callee];
            if (list.items.len == 0 or list.items[list.items.len - 1] != index) try list.append(a, index);
        }
    }
    const out = try a.alloc([]const usize, targets.len);
    for (targets, out) |target, *list| list.* = if (target.callee < by_callee.len) by_callee[target.callee].items else &.{};
    return out;
}

/// The first function of `program` that calls `callee` and passes, at parameter `position`, an argument it still needs
/// after the call (F-27): the ownership check accepts the caller as written and refuses it once that parameter is `own`,
/// so the caller would have to pass a copy. Null when every caller can give the argument, or when none is in the program.
/// `W_COPY_MOVE`'s advice to make the parameter `own` is withheld for such a function (`src/main.zig`).
pub fn keepingArgumentCallerOf(a: std.mem.Allocator, program: typed.Program, source: ?language.source.Source, callee: usize, position: usize) Error!?usize {
    if (callee >= program.functions.len) return null;
    const function = program.functions[callee];
    if (position >= function.signature.parameter_count) return null;
    try markCallViews(a, program);
    const linear = try ownedTypes(a, program);
    const payloads = try BorrowedRecords.casePayloads(a, program);
    const before: Shared = .{ .program = program, .linear = linear, .source = source, .case_payloads = payloads };
    const own_parameters = try a.alloc(bool, @max(function.signature.parameter_count, function.scope.own_parameters.len));
    @memset(own_parameters, false);
    @memcpy(own_parameters[0..function.scope.own_parameters.len], function.scope.own_parameters);
    own_parameters[position] = true;
    const declared = try a.dupe(typed.Function, program.functions);
    declared[callee].scope.own_parameters = own_parameters;
    return firstRefusedCaller(a, before, declared, callee, null);
}

/// The first caller of `own` that the ownership check accepts over `before`'s functions and refuses over `declared`
/// (the same functions with `own`'s signature changed), for any code but `exempt`; null when there is none.
fn firstRefusedCaller(a: std.mem.Allocator, before: Shared, declared: []typed.Function, own: usize, exempt: ?[]const u8) Error!?usize {
    var after = before;
    after.program.functions = declared;
    for (before.program.functions, 0..) |caller, index| {
        if (index == own or !caller.scope.body_complete) continue;
        if (!try callsFunction(a, before.program, caller, own)) continue;
        var ignored: Failure = .{};
        checkFunction(a, before, caller, &ignored, .{ .active = true }) catch |err| {
            if (err == error.Rejected) continue;
            return err;
        };
        var refused: Failure = .{};
        checkFunction(a, after, declared[index], &refused, .{ .active = true }) catch |err| {
            if (err != error.Rejected) return err;
            if (exempt) |code| if (std.mem.eql(u8, refused.code, code)) continue;
            return index;
        };
    }
    return null;
}

/// Whether `caller`'s body calls the function at `callee`.
fn callsFunction(a: std.mem.Allocator, program: typed.Program, caller: typed.Function, callee: usize) Error!bool {
    var walker = try typed_walk.Walker.init(a, program, caller.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| {
        if (item != .expression) continue;
        switch (program.nodes[@backingInt(item.expression)].data) {
            .call => |call| if (@backingInt(call.function) == callee) return true,
            else => {},
        }
    }
    return false;
}

fn copyEdits(a: std.mem.Allocator, src: language.source.Source, copy: Copy) error{OutOfMemory}!?[]language.diagnostic.Edit {
    if (copy.into_set) if (try setIncludeEdits(a, src, copy)) |edits| return edits;
    var spans: std.ArrayList(Span) = .empty;
    defer spans.deinit(a);
    if (copy.span) |span| {
        if (copy.name != null and !std.mem.eql(u8, src.text(span), copy.name.?)) return null;
        try spans.append(a, span);
    }
    for (copy.borrowed) |span| try spans.append(a, span);
    if (spans.items.len == 0) return null;
    for (spans.items) |span| if (!try copyExpressionSource(a, src, span)) return null;
    const edits = try a.alloc(language.diagnostic.Edit, spans.items.len * 2);
    for (spans.items, 0..) |span, index| {
        edits[index * 2] = .{ .span = .{ .start = span.start, .end = span.start }, .text = "copy(" };
        edits[index * 2 + 1] = .{ .span = .{ .start = span.end, .end = span.end }, .text = ")" };
    }
    return edits;
}

/// Render the same located diagnostic for check, dump-ir, build and run.
pub fn render(a: std.mem.Allocator, src: language.source.Source, failure: Failure, format: language.diagnostic_output.Format, report: *std.ArrayList(u8)) error{OutOfMemory}!void {
    const located = try diagnosticOf(a, src, failure);
    defer if (located.copies) |owned| a.free(owned);
    language.friction_session.note(located.diagnostic);
    const rendered = try language.diagnostic_output.render(a, located.diagnostic, src, format);
    defer a.free(rendered);
    try report.appendSlice(a, rendered);
}

/// A refusal as the diagnostic `render` prints, and the copy repair's edits it allocated from `a`, which the caller frees.
pub const Located = struct { diagnostic: language.diagnostic.Diagnostic, copies: ?[]language.diagnostic.Edit };

/// The diagnostic `render` prints for a refusal, with its certain repair.
pub fn diagnosticOf(a: std.mem.Allocator, src: language.source.Source, failure: Failure) error{OutOfMemory}!Located {
    std.debug.assert(failure.code.len != 0);
    std.debug.assert(failure.message.len != 0);
    const related: ?language.diagnostic.Related = if (failure.notes.related) |value|
        .{ .span = value.span, .message = value.message }
    else
        null;
    var diagnostic: language.diagnostic.Diagnostic = .{ .severity = .err, .code = failure.code, .span = failure.span, .message = failure.message, .related = related };
    diagnostic.provenance.rule = failure.rule;
    if (failure.notes.cause) |cause| diagnostic.provenance.cause = .{ .span = cause.span, .message = cause.message, .role = .cause };
    // A borrow repair replaces the copy repair: the borrow is what keeps the copy from running.
    var borrowed = false;
    switch (failure.repair) {
        .write_back => |edits| if (edits.len > 0) {
            diagnostic.provenance.fix = .{ .edit = edits[0], .more = edits[1..] };
            borrowed = true;
        },
        .explicit_fix => |edits| if (edits.len > 0) {
            diagnostic.provenance.fix = .{ .edit = edits[0], .more = edits[1..] };
            borrowed = true;
        },
        .receiver => |site| if (try receiver_repair.prove(a, src, site)) |fix| {
            diagnostic.provenance.fix = fix;
            borrowed = true;
        },
        .const_binding => |name| if (constBindingEdit(src, name)) |edit| {
            diagnostic.provenance.fix = .{ .edit = edit };
            borrowed = true;
        },
        else => {},
    }
    const copies = if (borrowed) null else try copyEdits(a, src, failure.copy);
    if (copies) |edits| diagnostic.provenance.fix = .{ .edit = edits[0], .more = edits[1..] };
    // The resource repair takes the declaration over the copy repair: the value
    // is move-only, so `own` is the only spelling that keeps it.
    switch (failure.repair) {
        .own_parameter => |name| if (mutToOwnEdit(src, name)) |edit| {
            diagnostic.provenance.fix = .{ .edit = edit };
        },
        else => {},
    }
    return .{ .diagnostic = diagnostic, .copies = copies };
}

/// The edit that rewrites a binding's `mut` marker to `const`, when the declaration spells `mut name`.
fn constBindingEdit(src: language.source.Source, name: Span) ?language.diagnostic.Edit {
    if (name.start < 4 or !std.mem.eql(u8, src.bytes[name.start - 4 .. name.start], "mut ")) return null;
    return .{ .span = .{ .start = name.start - 4, .end = name.start }, .text = "const " };
}

/// The edit that rewrites one parameter's `mut` marker to `own`, in either
/// declared spelling: `mut name: T` before the name, or `name: mut T` after it.
/// The scan stops at the end of the declaration line, and the prefix spelling
/// answers first, so a later parameter's marker is never taken.
fn mutToOwnEdit(src: language.source.Source, name: Span) ?language.diagnostic.Edit {
    const bytes = src.bytes;
    if (name.start >= 4 and std.mem.eql(u8, bytes[name.start - 4 .. name.start], "mut "))
        return .{ .span = .{ .start = name.start - 4, .end = name.start }, .text = "own " };
    const line_end = std.mem.indexOfScalarPos(u8, bytes, name.end, '\n') orelse bytes.len;
    const line = bytes[name.end..line_end];
    const at = std.mem.indexOf(u8, line, "mut ") orelse return null;
    const start = name.end + at;
    return .{ .span = .{ .start = start, .end = start + 4 }, .text = "own " };
}
