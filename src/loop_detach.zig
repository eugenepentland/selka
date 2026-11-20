//! `for x in detach place:` (LOOPDETACH, 17 November 2026): a loop over a collection that a record holds, whose body may
//! change the record. The loop moves the collection out of its place before the first iteration, as `take(mut place)`
//! does (the place holds its type's empty value while the loop runs), walks the moved-out collection as a loop over a
//! local walks it, and moves it back when the loop ends by any way:
//!
//! - running out or `break`: after the loop;
//! - `return value` and `fail value`: the value is evaluated into a hidden local first (`<return>`, as a postcondition
//!   stages it), then each `detach` loop the exit leaves puts its collection back, innermost first, then the held value
//!   leaves (`stage`);
//! - a `try` in the body whose error leaves: the parser arms a clause of the `on fail:` kind over the body
//!   (`on_fail.zig`), so the `try` is rewritten into the `match` whose failure arm runs the `on fail:` clauses and then
//!   `fail`s, and that `fail` is staged as above.
//!
//! So Core and the validators see only forms they already accept: a `take`, a borrowing loop over a local, and an
//! `exchange` that puts the local back. The ownership check accepts the put-back before an exit while the loop's loans
//! on the collection are open, in exactly that shape (`single_owner.zig`, `detachExit`); a hand-written put-back keeps
//! today's refusal.
//!
//! The put-back finds the place as it left it, the empty value. If the body or a function it called wrote the place
//! while the collection was set aside, putting it back would drop one of the two collections, so the put-back traps
//! (`R_ASSERT`) with a message that names the place and the loop's line instead.
//!
//! The place is what `take(mut place)` accepts: a field chain of a `mut` local, a `mut` parameter or a `match mut`
//! binding, through list elements. Each index in it is a number or a name that cannot change while the loop runs, so
//! that the put-back reaches the element the loop took from. A dictionary value is refused, as `take` refuses it, and
//! so is a place that an enclosing `detach` loop has set aside, or one inside it: that place is empty during the loop.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const collections = @import("collection_lower.zig");
const sema_exchange = @import("sema_exchange.zig");
const Error = @import("diagnostic.zig").Error;

/// The code of a `detach` loop's refusals of its source.
pub const code = "E_ITERATION";
const not_a_place = "`detach` takes a collection out of a place for the loop and puts it back after: a field of a `mut` local " ++
    "or a `mut` parameter (`for item in detach env.items:`), or an element of a list there; loop over a value directly with `for x in values:`";
const moving_index = "a `detach` loop puts the collection back where its place points when the loop ends, so an index in the place " ++
    "is a number or a name the loop cannot change: bind it first (`const at = i`) and write `detach rows[at].items`";
const dictionary_value = "`detach` does not reach a dictionary value: move it out with `d.pop(key)`, loop over it, and store it back " ++
    "with `d[key] = value`";
const one_name = "a `detach` loop binds one name, `for x in detach place:`; number the elements with a counter of its own";

/// One active `detach` loop: what each of its put-backs needs.
pub const Frame = struct {
    /// The place, as written; each put-back checks it again.
    place: ast.NodeId,
    /// The hidden local that holds the collection while the loop runs.
    list: typed.LocalId,
    /// The place's span, where the put-back's trap is located.
    span: source.Span,
    /// The place as written with its spaces removed, to refuse a place an enclosing `detach` loop set aside.
    path: []const u8,
    /// The message of the trap of a place written while it was set aside.
    message: []const u8,
};

/// A `for` loop's parsed parts.
const ForEach = @FieldType(@FieldType(ast.Statement, "data"), "for_each");
/// What checking a statement makes.
const StatementData = @FieldType(typed.Statement, "data");

/// Check `for x in detach place:`: the take, the loop over the taken collection (`walk`, the ordinary walk of a
/// checked source), and the put-back after it.
pub fn statement(comptime Checker: type, self: *Checker, stmt: ast.Statement, each: ForEach, walk: anytype) Error!StatementData {
    const place_span = self.syntax.nodes.items[@backingInt(each.iterable)].span;
    if (each.index_name != null or each.enumerated) return self.sink.fail(code, stmt.span, one_name);
    try stablePlace(Checker, self, each.iterable);
    const path = try pathText(self.allocator, self.src, place_span);
    for (self.loops.active.items) |scope| if (scope.detach) |outer| if (overlaps(outer.path, path)) {
        const message = try std.fmt.allocPrint(self.allocator, "`{s}` is set aside by the `detach` loop around this one, so it is empty here; " ++
            "loop over the collection the outer loop binds, or detach a different place", .{self.src.text(outer.span)});
        return self.sink.fail(code, place_span, message);
    };
    _ = try self.expression(each.iterable);
    try refuseDictionaryValue(Checker, self, each.iterable, place_span);
    const b: collections.Builder(Checker) = .{ .checker = self, .span = place_span };
    const taken = try sema_exchange.placeMove(Checker, self, .{ .place = each.iterable, .span = place_span });
    const list = try b.local(taken.ty);
    // An ordinary owner, as `mut items = take(mut place)` declares: a `<` name would make it a borrowing alias.
    self.locals.items[@backingInt(list)].name = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ typed.detach_owner, path });
    self.locals.items[@backingInt(list)].usage = .{ .reads = 1, .writes = 1 };
    const frame = try self.allocator.create(Frame);
    frame.* = .{ .place = each.iterable, .list = list, .span = place_span, .path = path, .message = try trapMessage(self.allocator, self.src, place_span) };
    const take = try b.stmt(.{ .initialize = .{ .slot = list, .value = try b.node(taken.ty, taken.data) } });
    const loop = try b.stmt(try walk(Checker, self, stmt, each, .{ .source = try b.read(list), .frame = frame }));
    const back = try restore(Checker, self, frame);
    return .{ .block = try self.allocator.dupe(typed.StatementId, &.{ take, loop, back }) };
}

/// The put-back of one loop: `exchange(mut place, own list)`, and the trap when what it replaced is not empty.
pub fn restore(comptime Checker: type, self: *Checker, frame: *const Frame) Error!typed.StatementId {
    const b: collections.Builder(Checker) = .{ .checker = self, .span = frame.span };
    _ = try self.expression(frame.place);
    const back = try b.read(frame.list);
    self.nodes.items[@backingInt(back)].own = true;
    const moved = try sema_exchange.placeMove(Checker, self, .{ .place = frame.place, .span = frame.span, .replacement = back });
    const replaced = try b.local(moved.ty);
    self.locals.items[@backingInt(replaced)].name = "replaced collection";
    const swap = try b.stmt(.{ .initialize = .{ .slot = replaced, .value = try b.node(moved.ty, moved.data) } });
    const empty = try b.binary(.eq, try b.length(replaced), try b.integer(0), .bool);
    const check = try b.stmt(.{ .assertion = .{ .condition = empty, .message = frame.message } });
    return b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{ swap, check }) });
}

/// An exit's value staged before the put-backs: the statements that hold it and put the collections back, and the read
/// of the held value that leaves.
pub const Staged = struct { statements: []const typed.StatementId, value: typed.NodeId };

/// Stage the value of a `return` or `fail` inside `detach` loops: it is evaluated into a hidden local first, as a
/// postcondition stages it (`<return>`), then each loop it leaves puts its collection back, innermost first, and then
/// the held value leaves. Null outside a `detach` loop. The ownership check accepts the put-back's move while the
/// loops' loans on the collection are open only in this shape (`single_owner.zig`, `detachExit`).
pub fn stage(comptime Checker: type, self: *Checker, value: typed.NodeId, span: source.Span) Error!?Staged {
    var index = self.loops.active.items.len;
    var statements: std.ArrayList(typed.StatementId) = .empty;
    const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
    var held: ?typed.LocalId = null;
    while (index > 0) {
        index -= 1;
        const frame = self.loops.active.items[index].detach orelse continue;
        if (held == null) {
            const ty = self.nodes.items[@backingInt(value)].ty;
            held = @fromBackingInt(self.locals.items.len);
            try self.locals.append(self.allocator, .{
                .name = "<return>",
                .declaration = span,
                .ty = ty,
                .mutable = false,
                .origin = .contract_value,
                .ownership = .{ .initialized = true },
                .usage = .{ .reads = 1, .temporary = true },
            });
            try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = held.?, .value = value } }));
        }
        try statements.append(self.allocator, try restore(Checker, self, frame));
    }
    const slot = held orelse return null;
    return .{ .statements = statements.items, .value = try b.read(slot) };
}

/// Refuse a source that is no place, or a place with an index the loop could change.
fn stablePlace(comptime Checker: type, self: *Checker, id: ast.NodeId) Error!void {
    var current = id;
    while (true) {
        const node = self.syntax.nodes.items[@backingInt(current)];
        switch (node.data) {
            .name => return,
            .field => |field| current = field.base,
            .index => |index| {
                if (!try fixedIndex(Checker, self, index.index)) return self.sink.fail(code, self.syntax.nodes.items[@backingInt(index.index)].span, moving_index);
                current = index.base;
            },
            else => return self.sink.fail(code, self.syntax.nodes.items[@backingInt(id)].span, not_a_place),
        }
    }
}

/// Whether an index is a number or a name of a binding that cannot be assigned.
fn fixedIndex(comptime Checker: type, self: *Checker, id: ast.NodeId) Error!bool {
    return switch (self.syntax.nodes.items[@backingInt(id)].data) {
        // A text is a dictionary's key, which the refusal of a dictionary value below names.
        .integer, .text => true,
        .name => |name| if (self.active.get(self.src.text(name))) |slot| !self.locals.items[@backingInt(slot)].mutable else false,
        else => false,
    };
}

/// Refuse a place whose last step is a dictionary's value (`take` does not reach one).
fn refuseDictionaryValue(comptime Checker: type, self: *Checker, id: ast.NodeId, span: source.Span) Error!void {
    var current = id;
    while (true) switch (self.syntax.nodes.items[@backingInt(current)].data) {
        .field => |field| current = field.base,
        .index => |index| {
            const base = self.resolved.at(@backingInt(index.base)) orelse return;
            const ty = self.nodes.items[@backingInt(base)].ty;
            if (ty.isAggregate() and self.catalog.records[ty.recordIndex()].isCollection() and self.catalog.records[ty.recordIndex()].collection.kind == .dictionary)
                return self.sink.fail(code, span, dictionary_value);
            current = index.base;
        },
        else => return,
    };
}

/// The place's text without spaces, which names the same place however it is spaced.
fn pathText(allocator: std.mem.Allocator, src: source.Source, span: source.Span) Error![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    for (src.text(span)) |byte| if (!std.ascii.isWhitespace(byte)) try text.append(allocator, byte);
    return text.items;
}

/// Whether one place path is the other or lies inside it (`ev.items` and `ev.items[0].kids`).
fn overlaps(a: []const u8, b: []const u8) bool {
    const short, const long = if (a.len <= b.len) .{ a, b } else .{ b, a };
    if (!std.mem.startsWith(u8, long, short)) return false;
    return long.len == short.len or long[short.len] == '.' or long[short.len] == '[';
}

/// The trap message of a place that was written while its collection was set aside.
fn trapMessage(allocator: std.mem.Allocator, src: source.Source, span: source.Span) Error![]const u8 {
    const place = src.text(span);
    return std.fmt.allocPrint(allocator, "the `detach` loop on line {d} puts `{s}` back, but `{s}` was written while the loop had it set aside " ++
        "(by the loop's body or a function it called), and putting it back would lose what was written; collect new elements " ++
        "in a list of their own and add them after the loop", .{ src.locate(span.start).line, place, place });
}

test "a place overlaps itself and the places inside it, not a sibling with a longer name" {
    try std.testing.expect(overlaps("ev.items", "ev.items"));
    try std.testing.expect(overlaps("ev.items", "ev.items[0].kids"));
    try std.testing.expect(overlaps("ev.items.kids", "ev.items"));
    try std.testing.expect(!overlaps("ev.items", "ev.items_done"));
    try std.testing.expect(!overlaps("ev.items", "ev.names"));
}
