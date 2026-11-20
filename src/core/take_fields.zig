//! Several fields moved out of one record: the moves written with `take(mut state.field)`, which leave each field's default.
//!
//! `own state.lat` consumes the whole record `state` (rule B8), so a second `own state.status` is refused, whatever the order. When
//! `state` is a `mut` local the function owns, `take(mut state.lat)` and `take(mut state.status)` move each value out and leave the
//! type's default in its place (`docs/value-semantics.md`), and the record is never consumed. That changes what a later use of
//! `state` or of a moved field sees (a default instead of a refusal), so the repair is certain only where the statement that holds
//! the moves is the last use of them.
//!
//! This file works out the moves and that statement from the checked tree and the source; whether the function still checks with
//! the `take`s written is the ownership checker's proof, not this file's.
const std = @import("std");
const language = @import("selka");
const typed = language.typed;
const typed_walk = language.typed_walk;
const read_first = @import("read_first.zig");
const escape_message = @import("escape_message.zig");
const Span = language.source.Span;
const Edit = language.diagnostic.Edit;
const Allocator = std.mem.Allocator;

/// The moves of fields out of the record at a refusal, and the repair when it is certain.
pub const Found = struct {
    /// The field moved first, which consumed the record.
    first: typed.NodeId,
    /// Every field moved out of the record, in the order the source writes them: the first, the refused one and any other.
    moves: []const typed.NodeId,
    /// The `take` repair; null when a condition fails (the message then says what moving several fields needs).
    repair: ?Repair,
    /// The refused move.
    refused: typed.NodeId,
    /// Where the refused move stands against the first (FR91B): another statement, the same one on some paths, a branch, or
    /// the same field again.
    shape: escape_message.ConsumedShape,
    /// The repair that writes the two moves in the call or constructor that follows them (FR91B); null where it is not certain.
    join: ?Join,
    /// The smallest call or constructor on one line that holds both moves, as the source writes it; empty where none does.
    holder: []const u8,
};

/// FR91B: `const a = own p.x` and `const b = own p.y`, then a statement whose one call or constructor takes `own a` and `own b`
/// and is their only use: the edits delete the two statements and write `own p.x` and `own p.y` where `own a` and `own b` stood.
pub const Join = struct {
    /// The deletion of the two statements, then the two uses rewritten, in the order of the source.
    edits: []const Edit,
    /// The `own a` and `own b` nodes of the call or constructor, in the order of the moves.
    uses: [2]typed.NodeId,
    /// The two statements the edits delete.
    cleared: [2]typed.StatementId,
    /// The call or constructor as the edits write it (`total(own p.lo, own p.hi)`).
    text: []const u8,
};

/// The edits that write each move as `take(mut place)`, and the places they name.
pub const Repair = struct {
    /// One edit for each move, in the order of `Found.moves`.
    edits: []const Edit,
    /// The place of each move as the source writes it, without `own` (`state.lat`).
    places: []const []const u8,
};

/// The local record and the two uses a refusal is about: the span of its local at the first move and at the refused one.
pub const Site = struct { slot: usize, moved: Span, refused: Span };

/// What one walk of the function found about the local: where it is read, every field read and every statement.
const Scene = struct {
    program: typed.Program,
    function: typed.Function,
    slot: usize,
    uses: []const typed.NodeId,
    fields: []const typed.NodeId,
    statements: []const typed.StatementId,
    moves: []const typed.NodeId,
};

/// The first and the refused move of fields out of local `site.slot`, or null where they are not two moves of fields of it. Text of
/// the result is allocated from `a`.
pub fn find(a: Allocator, src: language.source.Source, program: typed.Program, function: typed.Function, site: Site) Allocator.Error!?Found {
    var uses: std.ArrayList(typed.NodeId) = .empty;
    var fields: std.ArrayList(typed.NodeId) = .empty;
    var statements: std.ArrayList(typed.StatementId) = .empty;
    var moves: std.ArrayList(typed.NodeId) = .empty;
    var walker = try typed_walk.Walker.init(a, program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| switch (item) {
        .statement => |id| try statements.append(a, id),
        .expression => |id| {
            const node = program.nodes[@backingInt(id)];
            switch (node.data) {
                .local => |local| if (@backingInt(local) == site.slot) try uses.append(a, id),
                .field => {
                    try fields.append(a, id);
                    if (node.own and rootSlot(program, id) == site.slot) try moves.append(a, id);
                },
                else => {},
            }
        },
    };
    std.mem.sort(typed.NodeId, moves.items, program, earlier);
    var first: ?typed.NodeId = null;
    var refused: ?typed.NodeId = null;
    for (moves.items) |id| {
        const root = program.nodes[@backingInt(read_first.rootLocal(program, id).?)].span;
        if (root.start == site.moved.start and root.end == site.moved.end) first = id;
        if (root.start == site.refused.start and root.end == site.refused.end) refused = id;
    }
    const start = first orelse return null;
    const second = refused orelse return null;
    if (moves.items.len < 2) return null;
    const scene: Scene = .{
        .program = program,
        .function = function,
        .slot = site.slot,
        .uses = uses.items,
        .fields = fields.items,
        .statements = statements.items,
        .moves = moves.items,
    };
    return .{
        .first = start,
        .moves = moves.items,
        .repair = try repairOf(a, src, scene),
        .refused = second,
        .shape = shapeOf(src.bytes, scene, start, second),
        .join = try joinOf(a, src.bytes, scene),
        .holder = holderText(src.bytes, scene, start, second),
    };
}

/// The text of the smallest call or constructor on one line that holds both moves.
fn holderText(bytes: []const u8, scene: Scene, first: typed.NodeId, refused: typed.NodeId) []const u8 {
    const at = scene.program.nodes[@backingInt(first)].span;
    const later = scene.program.nodes[@backingInt(refused)].span;
    var best: []const u8 = "";
    for (scene.program.nodes) |node| switch (node.data) {
        .call, .record => {
            const both = holds(node.span, at) and holds(node.span, later);
            if (!both or node.span.end > bytes.len) continue;
            const text = bytes[node.span.start..node.span.end];
            if (std.mem.indexOfScalar(u8, text, '\n') != null or (best.len != 0 and text.len >= best.len)) continue;
            best = text;
        },
        else => {},
    };
    return best;
}

/// Whether `span` lies in the right operand of an `and` or `or`, which runs only on some paths.
fn shortCircuited(program: typed.Program, span: Span) bool {
    for (program.nodes) |node| switch (node.data) {
        .binary => |binary| if (binary.op == .logical_and or binary.op == .logical_or) {
            if (holds(program.nodes[@backingInt(binary.right)].span, span)) return true;
        },
        else => {},
    };
    return false;
}

/// Where the refused move stands against the first: the same field again, the same statement (where it runs only on some paths,
/// as the moves of a statement that all run are accepted together, or in an operation whose operands no group reaches), a branch
/// the first's statement is outside of, or another statement.
fn shapeOf(bytes: []const u8, scene: Scene, first: typed.NodeId, refused: typed.NodeId) escape_message.ConsumedShape {
    const at = scene.program.nodes[@backingInt(first)].span;
    const later = scene.program.nodes[@backingInt(refused)].span;
    if (std.mem.eql(u8, placeText(bytes, at), placeText(bytes, later))) return .twice;
    if (innermost(scene, at) == innermost(scene, later)) return if (shortCircuited(scene.program, later)) .conditional else .operand;
    for (scene.statements) |id| {
        const statement = scene.program.statements[@backingInt(id)];
        switch (statement.data) {
            .branch, .match => if (holds(statement.span, later) and !holds(statement.span, at)) return .branch,
            else => {},
        }
    }
    return .separate;
}

/// The place a move names after its `own` (`p.lo`), or its whole text where it is not written so.
pub fn placeText(bytes: []const u8, span: Span) []const u8 {
    if (span.end > bytes.len) return "";
    return if (marked(bytes, span)) |found| found[1] else bytes[span.start..span.end];
}

/// The join repair, once the two moves are the initial values of two `const` locals declared one after the other, each used
/// once, as `own a` and `own b` of one call or constructor in the statement right after them, and the record is used nowhere
/// else from the first of them on. Unnamed fields are then destroyed at that statement instead of the first, so no field of the
/// record may be a resource, whose closing would move.
fn joinOf(a: Allocator, bytes: []const u8, scene: Scene) Allocator.Error!?Join {
    if (scene.moves.len != 2) return null;
    var stores: [2]typed.StatementId = undefined;
    var slots: [2]usize = undefined;
    for (scene.moves, 0..) |move, index| {
        stores[index] = initializing(scene, move) orelse return null;
        slots[index] = @backingInt(scene.program.statements[@backingInt(stores[index])].data.initialize.slot);
        const local = scene.function.scope.locals[slots[index]];
        if (local.mutable or local.origin != .local or local.usage.temporary or local.ownership.view) return null;
    }
    const after = following(scene, stores) orelse return null;
    const held = scene.program.statements[@backingInt(after)].span;
    const first_span = scene.program.statements[@backingInt(stores[0])].span;
    for (scene.uses) |use| {
        if (scene.program.nodes[@backingInt(use)].span.start >= first_span.start and !movesRoot(scene, use)) return null;
    }
    const record_ty = scene.program.nodes[@backingInt(read_first.rootLocal(scene.program, scene.moves[0]).?)].ty;
    if (!record_ty.isAggregate() or record_ty.recordIndex() >= scene.program.records.len) return null;
    for (scene.program.records[record_ty.recordIndex()].fields) |field| {
        if (typed.moveOnly(field.ty, scene.program.records) or typed.requiresHandling(field.ty, scene.program.records)) return null;
    }
    const uses = (try onlyUses(a, scene, slots)) orelse return null;
    for (uses) |use| if (!holds(held, scene.program.nodes[@backingInt(use)].span)) return null;
    const holder = sharedHolder(scene, uses) orelse return null;
    return joinEdits(a, bytes, scene, .{ .stores = stores, .uses = uses, .after = after, .holder = holder });
}

/// The statement that initializes a local with exactly `move`.
fn initializing(scene: Scene, move: typed.NodeId) ?typed.StatementId {
    for (scene.statements) |id| switch (scene.program.statements[@backingInt(id)].data) {
        .initialize => |store| if (store.value == move) return id,
        else => {},
    };
    return null;
}

/// The statement right after the two, when a block holds them one after the other.
fn following(scene: Scene, stores: [2]typed.StatementId) ?typed.StatementId {
    for (scene.statements) |id| switch (scene.program.statements[@backingInt(id)].data) {
        .block => |items| for (items, 0..) |item, index| {
            if (item != stores[0]) continue;
            if (index + 2 >= items.len or items[index + 1] != stores[1]) return null;
            return items[index + 2];
        },
        else => {},
    };
    return null;
}

/// The one use of each of the two locals, when each has exactly one and it is written `own a`.
fn onlyUses(a: Allocator, scene: Scene, slots: [2]usize) Allocator.Error!?[2]typed.NodeId {
    var found: [2]?typed.NodeId = .{ null, null };
    var walker = try typed_walk.Walker.init(a, scene.program, scene.function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| switch (item) {
        .expression => |id| switch (scene.program.nodes[@backingInt(id)].data) {
            .local => |local| for (slots, &found) |slot, *use| if (@backingInt(local) == slot) {
                if (use.* != null or !scene.program.nodes[@backingInt(id)].own) return null;
                use.* = id;
            },
            else => {},
        },
        .statement => {},
    };
    return .{ found[0] orelse return null, found[1] orelse return null };
}

/// The call or constructor both uses are arguments or field values of.
fn sharedHolder(scene: Scene, uses: [2]typed.NodeId) ?typed.NodeId {
    for (scene.program.nodes, 0..) |node, index| {
        var count: usize = 0;
        switch (node.data) {
            .call => |call| for (call.arguments) |argument| {
                count += @intFromBool(argument == uses[0] or argument == uses[1]);
            },
            .record => |fields| for (fields) |field| {
                count += @intFromBool(field.value == uses[0] or field.value == uses[1]);
            },
            else => {},
        }
        if (count == 2) return @fromBackingInt(index);
    }
    return null;
}

/// The parts of a join the edits are written from.
const Joined = struct { stores: [2]typed.StatementId, uses: [2]typed.NodeId, after: typed.StatementId, holder: typed.NodeId };

/// The edits of the join, when the two statements stand alone on their lines with only blank space up to the statement after
/// them, the call or constructor is on one line, and each use is written `own a`.
fn joinEdits(a: Allocator, bytes: []const u8, scene: Scene, joined: Joined) Allocator.Error!?Join {
    const statements = scene.program.statements;
    const one = statements[@backingInt(joined.stores[0])].span;
    const two = statements[@backingInt(joined.stores[1])].span;
    const next = statements[@backingInt(joined.after)].span;
    if (next.end > bytes.len) return null;
    var start = one.start;
    while (start > 0 and (bytes[start - 1] == ' ' or bytes[start - 1] == '\t')) start -= 1;
    if (start > 0 and bytes[start - 1] != '\n') return null;
    var end = next.start;
    while (end > 0 and (bytes[end - 1] == ' ' or bytes[end - 1] == '\t')) end -= 1;
    if (end <= two.end) return null;
    if (!blank(bytes[one.end..two.start]) or !blank(bytes[two.end..end])) return null;
    var out: std.ArrayList(Edit) = .empty;
    try out.append(a, .{ .span = .{ .start = start, .end = end }, .text = "" });
    const holder = scene.program.nodes[@backingInt(joined.holder)].span;
    if (holder.end > bytes.len or std.mem.indexOfScalar(u8, bytes[holder.start..holder.end], '\n') != null) return null;
    const nodes = scene.program.nodes;
    const order: [2]usize = if (nodes[@backingInt(joined.uses[0])].span.start < nodes[@backingInt(joined.uses[1])].span.start) .{ 0, 1 } else .{ 1, 0 };
    var text: std.ArrayList(u8) = .empty;
    var cursor = holder.start;
    for (order) |index| {
        const use = nodes[@backingInt(joined.uses[index])];
        const at, const name = marked(bytes, use.span) orelse return null;
        if (at < holder.start or !std.mem.eql(u8, name, scene.function.scope.locals[@backingInt(use.data.local)].name)) return null;
        const place = placeText(bytes, nodes[@backingInt(scene.moves[index])].span);
        if (!chain(place)) return null;
        const replacement = try std.fmt.allocPrint(a, "own {s}", .{place});
        try out.append(a, .{ .span = .{ .start = at, .end = use.span.end }, .text = replacement });
        try text.appendSlice(a, bytes[cursor..at]);
        try text.appendSlice(a, replacement);
        cursor = use.span.end;
    }
    try text.appendSlice(a, bytes[cursor..holder.end]);
    return .{ .edits = out.items, .uses = joined.uses, .cleared = joined.stores, .text = text.items };
}

/// Whether the text is only white space.
fn blank(text: []const u8) bool {
    for (text) |byte| if (!std.ascii.isWhitespace(byte)) return false;
    return true;
}

fn earlier(program: typed.Program, left: typed.NodeId, right: typed.NodeId) bool {
    return program.nodes[@backingInt(left)].span.start < program.nodes[@backingInt(right)].span.start;
}

/// The slot of the local at the root of a chain of field reads, or none.
fn rootSlot(program: typed.Program, id: typed.NodeId) ?usize {
    const root = read_first.rootLocal(program, id) orelse return null;
    return @backingInt(program.nodes[@backingInt(root)].data.local);
}

fn holds(outer: Span, inner: Span) bool {
    return outer.start <= inner.start and inner.end <= outer.end;
}

/// The repair, once the local, the statement that holds the moves, the later uses and the types all allow it.
fn repairOf(a: Allocator, src: language.source.Source, scene: Scene) Allocator.Error!?Repair {
    const local = scene.function.scope.locals[scene.slot];
    // A parameter's storage is the caller's: a `take` there would leave defaults the caller sees.
    if (!local.mutable or local.origin != .local or scene.slot < scene.function.signature.parameter_count) return null;
    if (local.ownership.view or local.usage.temporary) return null;
    const site = scene.program.nodes[@backingInt(scene.moves[0])].span;
    const inside = innermost(scene, site) orelse return null;
    switch (scene.program.statements[@backingInt(inside)].data) {
        .block, .branch, .match, .loop, .range_loop, .with_scope => return null,
        else => {},
    }
    const held = scene.program.statements[@backingInt(inside)].span;
    for (scene.moves) |move| if (!holds(held, scene.program.nodes[@backingInt(move)].span)) return null;
    if (!stillOnce(scene, held, local.declaration)) return null;
    if (!usedOnlyHere(scene, held)) return null;
    for (scene.moves) |move| if (!leavesDefault(scene.program, scene.program.nodes[@backingInt(move)].ty)) return null;
    const written = try edits(a, src.bytes, scene);
    return written;
}

/// The smallest statement that holds `at`.
fn innermost(scene: Scene, at: Span) ?typed.StatementId {
    var best: ?typed.StatementId = null;
    var size: usize = std.math.maxInt(usize);
    for (scene.statements) |id| {
        const span = scene.program.statements[@backingInt(id)].span;
        if (!holds(span, at) or span.end - span.start > size) continue;
        best = id;
        size = span.end - span.start;
    }
    return best;
}

/// Whether no loop holds the statement without holding the declaration of the local: the moves would then run again on defaults.
fn stillOnce(scene: Scene, held: Span, declaration: Span) bool {
    for (scene.statements) |id| {
        const statement = scene.program.statements[@backingInt(id)];
        switch (statement.data) {
            .loop, .range_loop => if (holds(statement.span, held) and !holds(statement.span, declaration)) return false,
            else => {},
        }
    }
    return true;
}

/// Whether every use of the local after the statement's start is inside it and is either the local of a move or a read of a field that
/// no move takes: a later use would now see a default instead of being refused.
fn usedOnlyHere(scene: Scene, held: Span) bool {
    for (scene.uses) |use| {
        const span = scene.program.nodes[@backingInt(use)].span;
        if (span.end <= held.start) continue;
        if (span.start >= held.end) return false;
        if (movesRoot(scene, use)) continue;
        const over = fieldOver(scene, use) orelse return false;
        for (scene.moves) |move| if (fieldOver(scene, read_first.rootLocal(scene.program, move).?) == over) return false;
    }
    return true;
}

/// The index of the field of the record that the field read `use` is the base of, or null where the local is used whole.
fn fieldOver(scene: Scene, use: typed.NodeId) ?usize {
    for (scene.fields) |id| {
        const data = scene.program.nodes[@backingInt(id)].data.field;
        if (data.base == use) return data.index;
    }
    return null;
}

fn movesRoot(scene: Scene, use: typed.NodeId) bool {
    for (scene.moves) |move| if (read_first.rootLocal(scene.program, move).? == use) return true;
    return false;
}

/// Whether `take` leaves a value of the type in a place: an empty collection, `None`, or a record built from its field defaults.
fn leavesDefault(program: typed.Program, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    if (typed.moveOnly(ty, program.records) or typed.requiresHandling(ty, program.records) or typed.sealed(ty, program.records)) return false;
    const record = program.records[ty.recordIndex()];
    if (record.isCollection() or language.reference_tables.prelude.optionShape(ty, program.records) != null) return true;
    if (!record.isRecord()) return false;
    for (record.fields) |field| if (field.default_value == null) return false;
    return true;
}

/// The edit of each move: from its `own` to the end of the place, replaced by `take(mut place)`. Null where a place is not written
/// as a plain chain of names after `own`, or one place is another's or is written twice.
fn edits(a: Allocator, bytes: []const u8, scene: Scene) Allocator.Error!?Repair {
    var out: std.ArrayList(Edit) = .empty;
    var places: std.ArrayList([]const u8) = .empty;
    for (scene.moves) |move| {
        const span = scene.program.nodes[@backingInt(move)].span;
        if (span.end > bytes.len) return null;
        const start, const place = marked(bytes, span) orelse return null;
        if (!chain(place)) return null;
        for (places.items) |other| if (std.mem.eql(u8, other, place) or prefixed(other, place) or prefixed(place, other)) return null;
        try places.append(a, place);
        try out.append(a, .{ .span = .{ .start = start, .end = span.end }, .text = try std.fmt.allocPrint(a, "take(mut {s})", .{place}) });
    }
    return .{ .edits = out.items, .places = places.items };
}

/// Where the `own` of the move starts and the place after it, whether the node's span begins at `own` or after it.
fn marked(bytes: []const u8, span: Span) ?struct { usize, []const u8 } {
    if (std.mem.startsWith(u8, bytes[span.start..span.end], "own") and span.end - span.start > 3 and std.ascii.isWhitespace(bytes[span.start + 3])) {
        var at = span.start + 3;
        while (std.ascii.isWhitespace(bytes[at])) at += 1;
        return .{ span.start, bytes[at..span.end] };
    }
    var at = span.start;
    while (at > 0 and (bytes[at - 1] == ' ' or bytes[at - 1] == '\t')) at -= 1;
    if (at < 3 or !std.mem.eql(u8, bytes[at - 3 .. at], "own")) return null;
    if (at > 3 and (std.ascii.isAlphanumeric(bytes[at - 4]) or bytes[at - 4] == '_')) return null;
    return .{ at - 3, bytes[span.start..span.end] };
}

/// Whether the text is names joined by dots, with nothing between: a place `take` can name.
fn chain(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '.') return false;
    return text[0] != '.' and text[text.len - 1] != '.';
}

/// Whether `inner` names a field inside `outer` (`state.inner.lat` inside `state.inner`).
fn prefixed(outer: []const u8, inner: []const u8) bool {
    return inner.len > outer.len and std.mem.startsWith(u8, inner, outer) and inner[outer.len] == '.';
}
