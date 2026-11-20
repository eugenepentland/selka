//! Source edits for a return contract already validated by Core.
const std = @import("std");
const language = @import("selka");
const Span = language.source.Span;
const Edit = language.diagnostic.Edit;

const Parsed = struct { src: language.source.Source, declaration: language.ast.Function, offset: usize };

fn parse(a: std.mem.Allocator, src: language.source.Source, declaration: Span) error{OutOfMemory}!?Parsed {
    var original = src;
    var name = declaration;
    var offset: usize = 0;
    if (src.origins.len != 0) {
        const mapped = src.originalSpan(declaration) catch return null;
        const origin = src.origins[mapped.input];
        original = origin.original;
        name = mapped.span;
        offset = origin.start;
    }
    var sink: language.diagnostic.Sink = .{ .allocator = a };
    const tokens = language.lexer.lex(a, original.bytes, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    var parser: language.parser.Parser = .{ .src = original, .storage = a, .tokens = tokens, .sink = &sink };
    const syntax = parser.parseModule() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    for (syntax.functions) |function| {
        if (function.name.start == name.start and function.name.end == name.end)
            return .{ .src = original, .declaration = function, .offset = offset };
    }
    return null;
}

/// Add every required source in parameter order, replacing an existing names
/// list as a unit. The caller supplies the union of declared and missing names.
pub fn amend(a: std.mem.Allocator, src: language.source.Source, declaration: Span, positions: []const usize) error{OutOfMemory}!?Edit {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const parsed = (try parse(scratch.allocator(), src, declaration)) orelse return null;
    const signature = parsed.declaration.signature;
    var names: std.ArrayList(u8) = .empty;
    defer names.deinit(a);
    for (signature.parameters, 0..) |parameter, position| {
        if (std.mem.indexOfScalar(usize, positions, position) == null) continue;
        if (names.items.len != 0) try names.appendSlice(a, ", ");
        try names.appendSlice(a, parsed.src.text(parameter.name));
    }
    if (names.items.len == 0) return null;
    var span: Span = undefined;
    var text: []const u8 = undefined;
    if (signature.borrowing.len != 0) {
        span = Span.join(signature.borrowing[0], signature.borrowing[signature.borrowing.len - 1]);
        text = try names.toOwnedSlice(a);
    } else {
        span = .{ .start = signature.return_type.end, .end = signature.return_type.end };
        text = try std.fmt.allocPrint(a, " from {s}", .{names.items});
    }
    return .{ .span = .{ .start = span.start + parsed.offset, .end = span.end + parsed.offset }, .text = text };
}

/// A copy repair changes a borrowing function to an owned result, so the
/// declared clause must disappear together with the copies on its returns.
pub fn remove(a: std.mem.Allocator, src: language.source.Source, declaration: Span) error{OutOfMemory}!?Edit {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const parsed = (try parse(scratch.allocator(), src, declaration)) orelse return null;
    const signature = parsed.declaration.signature;
    if (signature.borrowing.len == 0) return null;
    return .{ .span = .{
        .start = signature.return_type.end + parsed.offset,
        .end = signature.borrowing[signature.borrowing.len - 1].end + parsed.offset,
    }, .text = "" };
}

/// The removal of a generic declaration's `from` clause when no source it names mentions a type parameter in its declared type
/// (lane HC), else null. Such a source has the same type in every instance, so it can lend an instance's result only where a
/// type parameter makes the result a type of its storage. A body checked for every type argument cannot make a value of a
/// type parameter from it, so no instance's result borrows the source, and the clause says nothing in any instance: its
/// removal is certain. A source whose type names a type parameter may lend in another instance, so no edit is offered.
pub fn removeConcreteSources(a: std.mem.Allocator, src: language.source.Source, declaration: Span) error{OutOfMemory}!?Edit {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const parsed = (try parse(scratch.allocator(), src, declaration)) orelse return null;
    const signature = parsed.declaration.signature;
    if (signature.borrowing.len == 0) return null;
    for (signature.borrowing) |name| {
        const parameter = for (signature.parameters) |parameter| {
            if (std.mem.eql(u8, parsed.src.text(parameter.name), parsed.src.text(name))) break parameter;
        } else return null;
        if (parameter.own) return null;
        if (namesTypeParameter(parsed.src.text(parameter.ty), signature.type_parameters, parsed.src)) return null;
    }
    return .{ .span = .{
        .start = signature.return_type.end + parsed.offset,
        .end = signature.borrowing[signature.borrowing.len - 1].end + parsed.offset,
    }, .text = "" };
}

/// Whether the type spelling `spelled` has a word that is the name of one of `type_parameters`.
fn namesTypeParameter(spelled: []const u8, type_parameters: []const language.ast.TypeParameter, src: language.source.Source) bool {
    var at: usize = 0;
    while (at < spelled.len) {
        if (!word(spelled[at])) {
            at += 1;
            continue;
        }
        const start = at;
        while (at < spelled.len and word(spelled[at])) at += 1;
        for (type_parameters) |type_parameter| if (std.mem.eql(u8, src.text(type_parameter.name), spelled[start..at])) return true;
    }
    return false;
}

fn word(octet: u8) bool {
    return std.ascii.isAlphanumeric(octet) or octet == '_';
}
