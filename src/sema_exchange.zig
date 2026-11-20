//! `take(mut place)` and `exchange(mut place, value)` (LANG1 item 3): the sema check of the two prelude
//! spellings that move a value out of a mutable place. The place is written, never moved from; its old value
//! answers the call, and the typed node is built here.

const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const receiver_marker = @import("sema_receiver_marker.zig");
const Error = @import("diagnostic.zig").Error;
const source = @import("source.zig");
const prelude = @import("prelude.zig");
const collections = @import("collection_lower.zig");

/// The spelling of a `take` or `exchange` call that names the prelude function (not a declaration or module name).
pub fn spelling(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?[]const u8 {
    const name = self.src.text(call.name);
    if (!std.mem.eql(u8, name, "take") and !std.mem.eql(u8, name, "exchange")) return null;
    return if (try self.preludeName(call)) name else null;
}

/// `take(mut place)` and `exchange(mut place, value)` (LANG1 item 3, G3 3A): the place's value moves out to the result
/// and the place takes `value`, or the type's default value for `take`: an empty collection, `None`, or a record built
/// from its field defaults. The place is a mutable local, a record-field chain of one, a list element (`xs[i]`, `xs[i].f`)
/// or a `match mut` binding; a dictionary value is refused until its exchange lands. `exchange` takes any type but a
/// resource; `take` of a type with no default is refused with the exchange to write instead. The place is borrowed `mut`,
/// so its marker is the call's receiver marker (M3, W2): a missing `mut` or an `own` there carries the exact edit, as
/// `append` does. A named managed `value` moves in and takes `own` (B2); Core decides that move.
pub fn check(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), name: []const u8) Error!typed.Node {
    const exchange = std.mem.eql(u8, name, "exchange");
    const wanted: usize = if (exchange) 2 else 1;
    if (call.arguments.len != wanted)
        return self.sink.fail("E_ARITY", node.span, if (exchange) "exchange takes a place and a value: `exchange(mut place, value)`" else "take takes one place: `take(mut place)`");
    const marked = try receiver_marker.require(Checker, self, name, call);
    const replacement = if (exchange) self.resolved.at(@backingInt(call.arguments[1])).? else null;
    return placeMove(Checker, self, .{ .place = call.arguments[0], .span = node.span, .marker = marked.span, .replacement = replacement });
}

/// One move out of a place: the place as written (resolved already), the span of the call or loop that moves, where a
/// refusal of the place points, and the value that takes the place, null for `take`'s default.
pub const Move = struct { place: ast.NodeId, span: source.Span, marker: ?source.Span = null, replacement: ?typed.NodeId = null };

/// The node of `take(mut place)` or of `exchange(mut place, replacement)`, the call `check` reads, and also how a
/// `detach` loop takes its collection out and puts it back (`loop_detach.zig`).
pub fn placeMove(comptime Checker: type, self: *Checker, move: Move) Error!typed.Node {
    const shape = try placeShape(Checker, self, move.place, move.marker orelse move.span);
    try self.requireWritableRoot(move.place);
    const place = self.resolved.at(@backingInt(move.place)).?;
    const ty = self.nodes.items[@backingInt(place)].ty;
    if (!emptyable(self, ty) and resource(self, ty))
        return self.sink.fail("E_TAKE_TYPE", move.span, "take and exchange do not move a resource, a capability or a pending result out of a place; keep it in its scope");
    if (move.replacement == null) {
        try @import("sealed_rules.zig").checkHere(Checker, self, .take, ty, move.span);
    }
    var value: ?typed.NodeId = null;
    if (move.replacement) |replacement| {
        try self.require(self.nodes.items[@backingInt(replacement)].ty, ty, move.span);
        value = replacement;
    } else if (@import("c_abi.zig").foreignHandle(ty, self.catalog.records)) {
        // `take` of a handle leaves the null handle, `T()`.
        const lower: collections.Builder(Checker) = .{ .checker = self, .span = move.span };
        value = try lower.node(ty, .{ .integer = 0 });
    } else if (!emptyable(self, ty)) {
        value = try recordDefault(Checker, self, ty, move.span) orelse {
            const name = try typed.surfaceTypeName(self.allocator, ty, self.catalog.records);
            const message = if (try severalFields(Checker, self, move.place, move.span)) |together|
                try std.fmt.allocPrint(self.allocator, no_default_fields, .{ name, together })
            else
                try std.fmt.allocPrint(self.allocator, no_default, .{name});
            return self.sink.fail("E_TAKE_TYPE", move.span, message);
        };
    }
    if (shape == .plain) return .{ .span = move.span, .ty = ty, .data = .{ .place_exchange = .{ .place = place, .value = value } } };
    // An element or a `match mut` binding is a place the lowering reaches through a receiver, as `append(mut xs[i], v)`
    // does: a compiler temporary initialized from the place names it, and the exchange writes through that temporary.
    const lower: collections.Builder(Checker) = .{ .checker = self, .span = move.span };
    const owner = try lower.local(ty);
    const init = try lower.stmt(.{ .initialize = .{ .slot = owner, .value = place } });
    const swapped = try lower.node(ty, .{ .place_exchange = .{ .place = try lower.read(owner), .value = value } });
    return lower.block(&.{init}, swapped);
}

/// FR91B: when `take(mut q.lo)` takes a field of a local record (not a parameter) whose other field this statement, the one
/// before it or the one after it also moves out (`own q.hi` or `take(mut q.hi)`), the moves written with `own` in one statement, which leaves
/// nothing behind: the writer's own expression where this statement holds both (`total(own q.lo, own q.hi)`), else
/// `f(own q.lo, own q.hi)`. Null otherwise. Statements are read as the source's lines.
fn severalFields(comptime Checker: type, self: *Checker, place: ast.NodeId, span: source.Span) Error!?[]const u8 {
    var node = self.syntax.nodes.items[@backingInt(place)];
    if (node.data == .mut_argument) node = self.syntax.nodes.items[@backingInt(node.data.mut_argument)];
    if (node.data != .field) return null;
    const base = self.syntax.nodes.items[@backingInt(node.data.field.base)];
    if (base.data != .name) return null;
    const record = self.src.text(base.data.name);
    const field = self.src.text(node.data.field.name);
    const slot = self.active.get(record) orelse return null;
    if (self.locals.items[@backingInt(slot)].origin != .local) return null;
    const bytes = self.src.bytes;
    const line_start = if (std.mem.lastIndexOfScalar(u8, bytes[0..span.start], '\n')) |at| at + 1 else 0;
    const line_end = std.mem.indexOfScalarPos(u8, bytes, span.start, '\n') orelse bytes.len;
    const line = bytes[line_start..line_end];
    if (try otherField(self.allocator, line, record, field) != null) {
        // The statement holds both: its expression with each `take(mut q.f)` written `own q.f`.
        var text = std.mem.trim(u8, line, " \t\r");
        for ([_][]const u8{ "return ", "const ", "mut " }) |lead| if (std.mem.startsWith(u8, text, lead)) {
            text = text[lead.len..];
            if (!std.mem.eql(u8, lead, "return ")) text = if (std.mem.indexOf(u8, text, " = ")) |at| text[at + 3 ..] else text;
        };
        const written = try owning(self.allocator, text, record);
        return written;
    }
    var previous_end = line_start;
    while (previous_end > 0) {
        const end = previous_end - 1;
        const start = if (std.mem.lastIndexOfScalar(u8, bytes[0..end], '\n')) |at| at + 1 else 0;
        const candidate = std.mem.trim(u8, bytes[start..end], " \t\r");
        previous_end = start;
        if (candidate.len == 0 or candidate[0] == '#') continue;
        const other = (try otherField(self.allocator, candidate, record, field)) orelse break;
        const written = try std.fmt.allocPrint(self.allocator, "f(own {s}.{s}, own {s}.{s})", .{ record, other, record, field });
        return written;
    }
    // The statement after this one.
    var next_start = line_end + 1;
    while (next_start < bytes.len) {
        const end = std.mem.indexOfScalarPos(u8, bytes, next_start, '\n') orelse bytes.len;
        const candidate = std.mem.trim(u8, bytes[next_start..end], " \t\r");
        next_start = end + 1;
        if (candidate.len == 0 or candidate[0] == '#') continue;
        const other = (try otherField(self.allocator, candidate, record, field)) orelse return null;
        const written = try std.fmt.allocPrint(self.allocator, "f(own {s}.{s}, own {s}.{s})", .{ record, field, record, other });
        return written;
    }
    return null;
}

/// A field of `record` other than `field` that `line` moves out with `own record.f` or `take(mut record.f)`.
fn otherField(allocator: std.mem.Allocator, line: []const u8, record: []const u8, field: []const u8) Error!?[]const u8 {
    for ([_][]const u8{ "own ", "take(mut " }) |lead| {
        const needle = try std.fmt.allocPrint(allocator, "{s}{s}.", .{ lead, record });
        var at: usize = 0;
        while (std.mem.indexOfPos(u8, line, at, needle)) |found| {
            at = found + needle.len;
            if (found > 0 and (std.ascii.isAlphanumeric(line[found - 1]) or line[found - 1] == '_')) continue;
            var end = at;
            while (end < line.len and (std.ascii.isAlphanumeric(line[end]) or line[end] == '_')) end += 1;
            if (end > at and !std.mem.eql(u8, line[at..end], field)) return line[at..end];
        }
    }
    return null;
}

/// `text` with each `take(mut record.f)` written `own record.f`.
fn owning(allocator: std.mem.Allocator, text: []const u8, record: []const u8) Error![]const u8 {
    const taken = try std.fmt.allocPrint(allocator, "take(mut {s}.", .{record});
    var out: std.ArrayList(u8) = .empty;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, text, at, taken)) |found| {
        var end = found + taken.len;
        while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_' or text[end] == '.')) end += 1;
        try out.appendSlice(allocator, text[at..found]);
        try out.print(allocator, "own {s}.{s}", .{ record, text[found + taken.len .. end] });
        at = if (end < text.len and text[end] == ')') end + 1 else end;
    }
    try out.appendSlice(allocator, text[at..]);
    return out.toOwnedSlice(allocator);
}

/// Give `exchange`'s replacement the type of the place it fills before it is checked, so `exchange(mut slot.pending,
/// None)` and `exchange(mut slot.pending, Some([9]))` infer their optional and `exchange(mut xs, [])` its empty list.
/// Only a place that is a local, or a field or list-element path of one, answers early; any other place leaves the replacement unhinted
/// and its own type is then matched against the place's.
pub fn hintReplacement(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
    if (call.arguments.len != 2) return;
    const ty = placeType(Checker, self, call.arguments[0]) orelse return;
    // An `own` marker wraps the value it gives away, so the hint goes to the wrapped expression.
    const value = self.syntax.nodes.items[@backingInt(call.arguments[1])];
    try self.hint(if (value.data == .own_argument) value.data.own_argument else call.arguments[1], ty);
}

/// The type of a place spelled as a local or a field or list-element path of one, read from the syntax before it is checked.
fn placeType(comptime Checker: type, self: *Checker, id: ast.NodeId) ?typed.Type {
    const node = self.syntax.nodes.items[@backingInt(id)];
    switch (node.data) {
        .mut_argument => |inner| return placeType(Checker, self, inner),
        .name => |name| {
            const slot = self.active.get(self.src.text(name)) orelse return null;
            return self.locals.items[@backingInt(slot)].ty;
        },
        .field => |field| {
            const base = placeType(Checker, self, field.base) orelse return null;
            if (!base.isAggregate()) return null;
            const wanted = self.src.text(field.name);
            for (self.catalog.records[base.recordIndex()].fields) |candidate| {
                if (std.mem.eql(u8, candidate.name, wanted)) return candidate.ty;
            }
            return null;
        },
        .index => |index| {
            const base = placeType(Checker, self, index.base) orelse return null;
            if (!base.isAggregate() or self.catalog.records[base.recordIndex()].collection.kind != .list) return null;
            return self.catalog.records[base.recordIndex()].shape.buffer;
        },
        else => return null,
    }
}

/// How the lowering reaches a `take`/`exchange` place: `plain` is a local or a record-field chain of an ordinary local,
/// which the exchange rebuilds field by field; `receiver` is a chain through a list element or rooted at a `match mut`
/// binding, which goes through a receiver temporary.
const PlaceShape = enum { plain, receiver };

/// The shape of a `take`/`exchange` place, or the refusal of one that is no place: a call result or other value, a
/// dictionary value (until the dictionary exchange lands), or an octet of text or bytes.
fn placeShape(comptime Checker: type, self: *Checker, id: ast.NodeId, span: source.Span) Error!PlaceShape {
    var shape: PlaceShape = .plain;
    var current = id;
    while (true) {
        const node = self.syntax.nodes.items[@backingInt(current)];
        switch (node.data) {
            .name => |name| {
                const slot = self.active.get(self.src.text(name)) orelse return shape;
                return if (self.locals.items[@backingInt(slot)].origin == .pattern) .receiver else shape;
            },
            .field => |field| current = field.base,
            .mut_argument => |inner| current = inner,
            .index => |index| {
                const base = self.resolved.at(@backingInt(index.base)) orelse return self.sink.fail("E_ASSIGNMENT_TARGET", span, not_a_place);
                const ty = self.nodes.items[@backingInt(base)].ty;
                const kind = if (ty.isAggregate() and self.catalog.records[ty.recordIndex()].isCollection()) self.catalog.records[ty.recordIndex()].collection.kind else null;
                if (kind == .dictionary) return self.sink.fail("E_ASSIGNMENT_TARGET", span, "take and exchange do not reach a dictionary value yet; move it out with d.pop(key) and store the new one with d[key] = value");
                if (kind != .list) return self.sink.fail("E_ASSIGNMENT_TARGET", span, "take and exchange reach a list element, not an element of this value; assign it with `place[i] = value`");
                shape = .receiver;
                current = index.base;
            },
            else => return self.sink.fail("E_ASSIGNMENT_TARGET", span, not_a_place),
        }
    }
}

const no_default = "take needs a type with a default value to leave behind (a collection, an optional, or a record whose fields all have " ++
    "defaults), and `{s}` has none; write exchange(mut place, value) with the value to leave";

const no_default_fields = "take needs a type with a default value to leave behind (a collection, an optional, or a record whose fields all " ++
    "have defaults), and `{s}` has none; move the fields with `own` in one statement instead, as in `{s}`, which leaves nothing " ++
    "behind, or write exchange(mut place, value) with the value to leave";

const not_a_place = "take and exchange move a local, a record field, a list element or a `match mut` binding; bind a call result to a `mut` local first";

/// Whether a type is one `take` and `exchange` never move out of a place: a resource, a capability, a file or a value
/// with a pending result obligation. The collections and optionals of them that were always accepted stay accepted.
fn resource(self: anytype, ty: typed.Type) bool {
    if (ty.capabilityIndex() != null or ty.isFile()) return true;
    return typed.moveOnly(ty, self.catalog.records) or typed.requiresHandling(ty, self.catalog.records);
}

/// The value `take` leaves in a record place: the record built from its field defaults, as `Record()` builds it. Null
/// when the type is not a plain record or a field has no default.
fn recordDefault(comptime Checker: type, self: *Checker, ty: typed.Type, span: source.Span) Error!?typed.NodeId {
    if (!ty.isAggregate()) return null;
    const record = self.catalog.records[ty.recordIndex()];
    if (!record.isRecord() or record.isCollection()) return null;
    const initializers = try self.allocator.alloc(ast.FieldInit, record.fields.len);
    for (record.fields, initializers) |field, *initializer| {
        const default = field.default_value orelse return null;
        initializer.* = .{ .name = field.declaration, .value = @fromBackingInt(default), .default = true };
    }
    const fields = try self.fields(ty, initializers, true, span);
    const lower: collections.Builder(Checker) = .{ .checker = self, .span = span };
    const built = try lower.node(ty, .{ .record = fields });
    return built;
}

/// Whether a type has an empty value that `take` leaves behind: a list, dictionary, set, text or bytes, or `None` for an
/// optional.
fn emptyable(self: anytype, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    return self.catalog.records[ty.recordIndex()].isCollection() or prelude.optionShape(ty, self.catalog.records) != null;
}
