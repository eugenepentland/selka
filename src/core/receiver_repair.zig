//! Certain source edits for a receiver conflict already proved by Core R2.
//! The proof preserves prior scalar reads by accepting only literal assignment
//! values and no earlier index operation before the call that moves into a local.
const std = @import("std");
const language = @import("selka");
const ast = language.ast;
const source = language.source;
const diagnostic = language.diagnostic;
const migration = language.migration_support;
const Span = source.Span;

/// Source anchors supplied only after Core proves a receiver mutation conflict.
/// The call must return a non-Unit scalar; moves and borrowed results are excluded
/// by the caller. `receiver` may be a lowered anchor inside its source statement.
pub const Site = struct { receiver: Span, call: Span };

const Local = struct { src: source.Source, site: Site, offset: usize };
const Path = enum { absent, call, unsafe };
const Proof = struct {
    syntax: ast.Program,
    call: ast.NodeId,

    fn literal(self: Proof, id: ast.NodeId) bool {
        return switch (self.syntax.nodes.items[@backingInt(id)].data) {
            .integer, .boolean, .unit => true,
            else => false,
        };
    }

    fn index(self: Proof, base: Path, id: ast.NodeId) Path {
        if (base == .unsafe) return .unsafe;
        if (id == self.call) return if (base == .absent) .call else .unsafe;
        // Even a constant earlier index can trap before the call. Indices after
        // it keep their order and may use literal keys without observing a name.
        if (base != .call) return .unsafe;
        return switch (self.syntax.nodes.items[@backingInt(id)].data) {
            .integer, .boolean, .text, .bytes => base,
            else => .unsafe,
        };
    }

    fn path(self: Proof, id: ast.NodeId, depth: usize) Path {
        if (depth >= 128) return .unsafe;
        return switch (self.syntax.nodes.items[@backingInt(id)].data) {
            .name => .absent,
            .field => |field| self.path(field.base, depth + 1),
            .index => |item| self.index(self.path(item.base, depth + 1), item.index),
            else => .unsafe,
        };
    }

    fn assignment(self: Proof, id: ast.NodeId) bool {
        return switch (self.syntax.nodes.items[@backingInt(id)].data) {
            .field_assignment => |write| write.op == .set and self.literal(write.value) and self.path(write.target, 0) == .call,
            .list_operation => |write| write.kind == .write and write.arguments.len == 2 and self.literal(write.arguments[1]) and
                self.index(self.path(write.base, 0), write.arguments[0]) == .call,
            .buffer_operation => |write| write.kind == .write and write.arguments.len == 2 and self.literal(write.arguments[1]) and write.arguments[0] == self.call,
            else => false,
        };
    }
};

fn contains(outer: Span, inner: Span) bool {
    return outer.start <= inner.start and inner.start < inner.end and inner.end <= outer.end;
}

fn original(src: source.Source, site: Site) ?Local {
    if (!contains(.{ .start = 0, .end = src.bytes.len }, site.receiver) or !contains(.{ .start = 0, .end = src.bytes.len }, site.call)) return null;
    if (src.origins.len == 0) return .{ .src = src, .site = site, .offset = 0 };
    const receiver = src.originalSpan(site.receiver) catch return null;
    const call = src.originalSpan(site.call) catch return null;
    if (receiver.input != call.input) return null;
    const origin = src.origins[call.input];
    return .{ .src = origin.original, .site = .{ .receiver = receiver.span, .call = call.span }, .offset = origin.start };
}

fn parse(a: std.mem.Allocator, src: source.Source) error{OutOfMemory}!?ast.Program {
    var sink: diagnostic.Sink = .{ .allocator = a };
    defer sink.deinit();
    const tokens = language.lexer.lex(a, src.bytes, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    var parser: language.parser.Parser = .{ .src = src, .storage = a, .tokens = tokens, .sink = &sink };
    defer parser.release();
    return parser.parse() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
}

fn statement(syntax: ast.Program, site: Site) ?Span {
    var call: ?ast.NodeId = null;
    for (syntax.nodes.items, 0..) |node, index| {
        if (!std.meta.eql(node.span, site.call)) continue;
        if (node.data == .call or node.data == .method_call) call = @fromBackingInt(index);
    }
    const proof: Proof = .{ .syntax = syntax, .call = call orelse return null };
    var found: ?Span = null;
    for (syntax.statements.items) |item| {
        if (item.data != .discard) continue;
        if (!contains(item.span, site.receiver)) continue;
        if (!contains(item.span, site.call)) continue;
        if (!proof.assignment(item.data.discard)) continue;
        if (found == null or item.span.end - item.span.start < found.?.end - found.?.start) found = item.span;
    }
    return found;
}

fn shift(span: Span, offset: usize) Span {
    return .{ .start = span.start + offset, .end = span.end + offset };
}

/// Hoist exactly one scalar call before a simple literal receiver assignment.
/// Return no edit for prior place reads, other effects, augmented assignments,
/// conditional or multiline expressions, inline statements, or crossed modules.
/// All returned edit text and the secondary edit array belong to `a`.
pub fn prove(a: std.mem.Allocator, src: source.Source, site: Site) error{OutOfMemory}!?diagnostic.Fix {
    const local = original(src, site) orelse return null;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const syntax = (try parse(arena.allocator(), local.src)) orelse return null;
    const enclosing = statement(syntax, local.site) orelse return null;
    if (std.mem.indexOfAny(u8, local.src.text(enclosing), "\r\n") != null) return null;
    const name = migration.freshOriginNameAt(a, local.src, "mutation_result", local.site.call.start) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    errdefer a.free(name);
    const declaration = try std.fmt.allocPrint(a, "const {s} = {s}", .{ name, local.src.text(local.site.call) });
    defer a.free(declaration);
    var insertion = (try migration.insertBeforeStatement(a, local.src, enclosing, declaration)) orelse {
        a.free(name);
        return null;
    };
    errdefer a.free(insertion.text);
    insertion.span = shift(insertion.span, local.offset);
    const more = try a.alloc(diagnostic.Edit, 1);
    more[0] = .{ .span = shift(local.site.call, local.offset), .text = name };
    return .{ .edit = insertion, .more = more };
}
