//! A value one argument gives away and a later argument of the same call or constructor only reads: the call with the reads first.
//!
//! `Source(mem=plain, total=len(plain))` gives `plain` to `mem` and reads its length for `total` in the same call. The language
//! evaluates the arguments of a call and the fields of a constructor from left to right, as they are written (`docs/plan.md`,
//! "Evaluate operands and call arguments from left to right"; a probe with two printing calls shows the written order, not the
//! declared one), so `Source(total=len(plain), mem=own plain)` reads the length and then moves the buffer, with no copy.
//!
//! This file works out that repair from the checked tree and the source: which arguments follow the moved one, whether each
//! only reads (a number or a `bool` that keeps nothing of the value), and the one edit that writes the moved argument last.
//! Whether the function still checks with the call so written is the ownership checker's proof, not this file's.
const std = @import("std");
const language = @import("selka");
const typed = language.typed;
const Span = language.source.Span;
const Edit = language.diagnostic.Edit;

/// The repair of one call or constructor, once its source and its arguments allow it.
pub const Plan = struct {
    /// The call or constructor node.
    container: typed.NodeId,
    /// The call or constructor as it reads with the moved argument evaluated last.
    rewritten: typed.Node,
    /// The one edit that writes the moved argument, with `own`, after the arguments that follow it.
    edit: Edit,
    /// The moved argument as the edit writes it, label included (`mem=own plain`).
    moved: []const u8,
    /// The arguments that follow it, as the source writes them (`total=len(plain)`).
    reads: []const u8,
    /// Where those arguments stand in the source, for a refusal at one of their reads to be matched with this plan.
    reads_span: Span,
    /// The moved argument is a field of a local record (`lat=own state.lat`), which consumes the whole record (FR63).
    field: bool = false,
};

/// What the later arguments are read for: the moved local, whether they read it, and whether a scalar field of it is a read (FR63).
const Scan = struct {
    slot: typed.LocalId,
    fields: bool,
    reads: bool = false,
};

/// The local node at the root of a chain of record-field reads (`state.inner.lat`), or null where the chain starts elsewhere.
pub fn rootLocal(program: typed.Program, id: typed.NodeId) ?typed.NodeId {
    var current = id;
    while (true) switch (program.nodes[@backingInt(current)].data) {
        .field => |field| current = field.base,
        .local => return current,
        else => return null,
    };
}

/// What `plan` found out about the arguments of the call, before it builds anything.
const Written = struct {
    /// The value of each written argument, in the order the source writes them.
    values: []const typed.NodeId,
    /// The position among those values of the moved argument.
    moved_at: usize,
};

/// The repair that writes the argument `moved` of `container` after every argument that follows it, or null where it is not certain:
/// the moved value is a whole local or a field of one (FR63), its argument and every one after it is written with a label (`name=value`) and nothing but
/// commas and blanks separates them, each later argument is a read that keeps nothing of the value (`keepsNothing`), and at
/// least one reads the moved local. Text of the plan is allocated from `a`.
pub fn plan(a: std.mem.Allocator, src: language.source.Source, program: typed.Program, container: typed.NodeId, moved: typed.NodeId) std.mem.Allocator.Error!?Plan {
    const node = program.nodes[@backingInt(container)];
    const found = (try written(a, program, node, moved)) orelse return null;
    const values = found.values;
    const first = found.moved_at;
    if (first + 1 >= values.len) return null;
    const marked = program.nodes[@backingInt(moved)];
    const slot = switch (marked.data) {
        .local => |local| local,
        .field => program.nodes[@backingInt(rootLocal(program, moved) orelse return null)].data.local,
        else => return null,
    };
    var scan: Scan = .{ .slot = slot, .fields = marked.data == .field };
    for (values[first + 1 ..]) |value| if (!keepsNothing(program, value, &scan)) return null;
    if (!scan.reads) return null;
    const text = try rotated(a, src, program, node, values, first) orelse return null;
    return .{
        .container = container,
        .rewritten = try rewrittenOrder(a, node, values.len, first),
        .edit = text.edit,
        .moved = text.moved,
        .reads = text.reads,
        .reads_span = text.reads_span,
        .field = scan.fields,
    };
}

/// The arguments a call or constructor writes, in the order it writes them, and the position of `moved` among them. Null for any
/// other node, a call whose arguments are all positional and in declared order, or a moved value that is none of them.
fn written(a: std.mem.Allocator, program: typed.Program, node: typed.Node, moved: typed.NodeId) std.mem.Allocator.Error!?Written {
    var values: std.ArrayList(typed.NodeId) = .empty;
    switch (node.data) {
        .record => |fields| for (fields) |field| try values.append(a, field.value),
        .call => |call| {
            if (call.evaluation_order.len == 0) return null;
            for (call.evaluation_order) |index| {
                if (index >= call.arguments.len) return null;
                try values.append(a, call.arguments[index]);
            }
        },
        else => return null,
    }
    // A default stands outside the call's text and is evaluated after the written arguments, which stay in front of it.
    var count: usize = 0;
    for (values.items) |value| {
        if (!inside(program.nodes[@backingInt(value)].span, node.span)) break;
        count += 1;
    }
    for (values.items[count..]) |value| if (inside(program.nodes[@backingInt(value)].span, node.span)) return null;
    const at = std.mem.indexOfScalar(typed.NodeId, values.items[0..count], moved) orelse return null;
    return .{ .values = values.items[0..count], .moved_at = at };
}

fn inside(span: Span, outer: Span) bool {
    return span.start > outer.start and span.end < outer.end;
}

/// Whether the expression reads nothing of the moved value that outlives the read, and moves nothing: a number or a `bool` that
/// only reads (an integer or `bool` literal, a local of a scalar type, the length of a local, and arithmetic, comparison, logic or a
/// cast over those), or a text or bytes literal, which reads nothing at all. A text, a bytes or a list local, a slice, a field, a
/// call or a constructed collection is not one: it may keep part of the value, change it, or be changed by the move. Where a field of
/// the record was moved, a field of that record that is a number or a `bool` is one too (FR63). `scan.reads` is set when the length of
/// the moved local, or such a field, is read.
fn keepsNothing(program: typed.Program, id: typed.NodeId, scan: *Scan) bool {
    const node = program.nodes[@backingInt(id)];
    if (node.own or node.view or node.type_dependent) return false;
    if (literal(program, id)) return true;
    return switch (node.data) {
        .integer, .boolean => true,
        .local => !node.ty.isAggregate(),
        .field => !node.ty.isAggregate() and fieldOf(program, id, scan),
        .length => |inner| lengthOf(program, inner, scan),
        .block_value => |block| node.ty.isAggregate() == false and stagedLength(program, block.body, block.value, scan),
        .cast => |inner| !node.ty.isAggregate() and keepsNothing(program, inner, scan),
        .unary => |unary| keepsNothing(program, unary.operand, scan),
        .binary => |binary| keepsNothing(program, binary.left, scan) and keepsNothing(program, binary.right, scan),
        else => false,
    };
}

/// Whether the value is a text or bytes literal, as `single_owner.staticText` tests it: an array of integers of a text or bytes type.
fn literal(program: typed.Program, id: typed.NodeId) bool {
    const node = program.nodes[@backingInt(id)];
    if (node.data != .array or !node.ty.isAggregate() or node.ty.recordIndex() >= program.records.len) return false;
    const record = program.records[node.ty.recordIndex()];
    if (!record.isCollection() or (record.collection.kind != .string and record.collection.kind != .bytes)) return false;
    for (node.data.array) |item| if (program.nodes[@backingInt(item)].data != .integer) return false;
    return true;
}

/// Whether `inner` is a whole unmarked local whose length is read, or a field of the record whose field was moved (FR63); sets
/// `reads` when it is the moved local or a field of it.
fn lengthOf(program: typed.Program, inner: typed.NodeId, scan: *Scan) bool {
    const target = program.nodes[@backingInt(inner)];
    if (target.own) return false;
    if (target.data == .field) return fieldOf(program, inner, scan);
    if (target.data != .local) return false;
    if (target.data.local == scan.slot) scan.reads = true;
    return true;
}

/// Whether the field read at `id` is of the record whose field is moved, written as a chain of field reads from its local; sets `reads`.
fn fieldOf(program: typed.Program, id: typed.NodeId, scan: *Scan) bool {
    if (!scan.fields) return false;
    const root = rootLocal(program, id) orelse return false;
    if (program.nodes[@backingInt(root)].data.local != scan.slot) return false;
    scan.reads = true;
    return true;
}

/// The length of a text or a list local as the lowering writes it: a hidden local initialized from the local, then the length of
/// that hidden local (a list's, as a number of another width, through a cast). `bytes`, a dictionary and a set read `.length` of the
/// local itself. Nothing else may stand in the block: it is one read, and the hidden local holds nothing after it.
fn stagedLength(program: typed.Program, body: typed.StatementId, value: typed.NodeId, scan: *Scan) bool {
    const statement = program.statements[@backingInt(body)];
    if (statement.data != .block or statement.data.block.len != 1) return false;
    const initial = program.statements[@backingInt(statement.data.block[0])];
    if (initial.data != .initialize) return false;
    const hidden = initial.data.initialize.slot;
    var measured = program.nodes[@backingInt(value)];
    if (measured.data == .cast and !measured.ty.isAggregate()) measured = program.nodes[@backingInt(measured.data.cast)];
    if (measured.data != .buffer_operation) return false;
    const operation = measured.data.buffer_operation;
    if (operation.kind != .length or operation.owner != hidden or operation.arguments.len != 0) return false;
    return lengthOf(program, initial.data.initialize.value, scan);
}

/// The rewritten source text, from the label of the moved argument to the end of the last one: the arguments after it in their
/// order, the separators where they were, and the moved argument last with `own` before its value.
const Text = struct { edit: Edit, moved: []const u8, reads: []const u8, reads_span: Span };

fn rotated(a: std.mem.Allocator, src: language.source.Source, program: typed.Program, node: typed.Node, values: []const typed.NodeId, first: usize) std.mem.Allocator.Error!?Text {
    const bytes = src.bytes;
    if (node.span.end > bytes.len or node.span.end == 0 or bytes[node.span.end - 1] != ')') return null;
    const moved_span = program.nodes[@backingInt(values[first])].span;
    const labels = try a.alloc(usize, values.len - first);
    for (values[first..], labels) |value, *label| {
        const span = program.nodes[@backingInt(value)].span;
        if (span.end > bytes.len) return null;
        label.* = labelStart(bytes, span.start) orelse return null;
    }
    const last = program.nodes[@backingInt(values[values.len - 1])].span;
    if (!blanks(bytes[last.end .. node.span.end - 1], 1)) return null;
    var out: std.ArrayList(u8) = .empty;
    for (values[first + 1 ..], 1..) |value, offset| {
        const before = program.nodes[@backingInt(values[first + offset - 1])].span;
        const separator = bytes[before.end..labels[offset]];
        if (!blanks(separator, 1) or std.mem.count(u8, separator, ",") != 1) return null;
        try out.appendSlice(a, bytes[labels[offset]..program.nodes[@backingInt(value)].span.end]);
        try out.appendSlice(a, separator);
    }
    const own = if (program.nodes[@backingInt(values[first])].own) "" else "own ";
    const moved = try std.fmt.allocPrint(a, "{s}{s}{s}", .{ bytes[labels[0]..moved_span.start], own, bytes[moved_span.start..moved_span.end] });
    try out.appendSlice(a, moved);
    const reads_span: Span = .{ .start = labels[1], .end = last.end };
    return .{
        .edit = .{ .span = .{ .start = labels[0], .end = last.end }, .text = out.items },
        .moved = moved,
        .reads = try flattened(a, bytes[reads_span.start..reads_span.end]),
        .reads_span = reads_span,
    };
}

/// The text with each run of blanks and line breaks as one space, for a message that quotes a call written over several lines.
fn flattened(a: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var gap = false;
    for (text) |byte| {
        if (std.ascii.isWhitespace(byte)) {
            gap = true;
            continue;
        }
        if (gap and out.items.len != 0) try out.append(a, ' ');
        gap = false;
        try out.append(a, byte);
    }
    return out.items;
}

/// The start of the label of an argument whose value begins at `at`: `name=` with only blanks around the `=`, and the argument
/// opened by `(` or `,`. Null where the argument is positional.
fn labelStart(bytes: []const u8, at: usize) ?usize {
    var index = at;
    while (index > 0 and (bytes[index - 1] == ' ' or bytes[index - 1] == '\t')) index -= 1;
    if (index == 0 or bytes[index - 1] != '=') return null;
    index -= 1;
    while (index > 0 and (bytes[index - 1] == ' ' or bytes[index - 1] == '\t')) index -= 1;
    const end = index;
    while (index > 0 and (std.ascii.isAlphanumeric(bytes[index - 1]) or bytes[index - 1] == '_')) index -= 1;
    if (index == end or std.ascii.isDigit(bytes[index])) return null;
    var before = index;
    while (before > 0 and std.ascii.isWhitespace(bytes[before - 1])) before -= 1;
    if (before == 0 or (bytes[before - 1] != '(' and bytes[before - 1] != ',')) return null;
    return index;
}

/// Whether `text` is only blanks, line breaks and at most `commas` commas: no comment, no bracket, no operator.
fn blanks(text: []const u8, commas: usize) bool {
    var seen: usize = 0;
    for (text) |byte| switch (byte) {
        ' ', '\t', '\r', '\n' => {},
        ',' => seen += 1,
        else => return false,
    };
    return seen <= commas;
}

/// The call or constructor with the moved argument last among its written arguments: the fields of a constructor, or the
/// evaluation order of a call, rotated one place from the moved argument's position.
fn rewrittenOrder(a: std.mem.Allocator, node: typed.Node, count: usize, first: usize) std.mem.Allocator.Error!typed.Node {
    var out = node;
    switch (node.data) {
        .record => |fields| {
            const copy = try a.dupe(typed.FieldInit, fields);
            std.mem.rotate(typed.FieldInit, copy[first..count], 1);
            out.data = .{ .record = copy };
        },
        .call => |call| {
            const copy = try a.dupe(usize, call.evaluation_order);
            std.mem.rotate(usize, copy[first..count], 1);
            out.data = .{ .call = .{ .evaluation_order = copy, .function = call.function, .arguments = call.arguments } };
        },
        else => unreachable,
    }
    return out;
}

/// The refusal of a read after the move, rewritten to name the order that reads first: `name` was moved, and `plan` writes the read before it.
pub fn movedMessage(a: std.mem.Allocator, name: []const u8, found: Plan) std.mem.Allocator.Error![]const u8 {
    if (found.field) return std.fmt.allocPrint(
        a,
        "'{s}' was moved or is unavailable on this path; write `{s}` before `{s}` so that it is read before `{s}` is consumed, or write copy(...) to keep both",
        .{ name, found.reads, found.moved, name },
    );
    return std.fmt.allocPrint(
        a,
        "'{s}' was moved or is unavailable on this path; write `{s}` before `{s}` to read it before it moves, or use copy(value) when both values are needed",
        .{ name, found.reads, found.moved },
    );
}
