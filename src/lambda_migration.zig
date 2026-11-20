//! Typed recognition for the retired lambda spelling; no executable lowering.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const migration = @import("migration_support.zig");
const Names = @import("module_names.zig").Names;
const removed_code = "E_LAMBDA_REMOVED";

/// Source-level facts needed to render a helper in its owning module.
pub const Context = struct {
    src: source.Source,
    syntax: ast.Program,
    names: ?*Names,
    records: []const typed.Record,
    sink: *diagnostic.Sink,
};

/// Publish a named helper only after the original callback body has type checked.
pub fn reject(allocator: std.mem.Allocator, context: Context, lambda: ast.Lambda, contract: typed.Callable) diagnostic.Error {
    const src = context.src;
    const syntax = context.syntax;
    const names = context.names;
    const records = context.records;
    const sink = context.sink;
    const message = "lambdas were removed; declare a named top-level function and pass it by name";
    const name = migration.freshOriginNameAt(allocator, src, "lambda_fn", lambda.span.start) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidSourceSpan => return sink.fail(removed_code, lambda.span, message),
    };
    var insertion: ?usize = null;
    for (syntax.functions) |function| {
        const body = syntax.statements.items[@backingInt(function.body)].span;
        if (body.start <= lambda.span.start and body.end >= lambda.span.end) {
            // Generic templates never reach this path: a concrete specialization
            // cannot establish source-level types for a reusable helper.
            if (function.signature.type_parameters.len != 0) return sink.fail(removed_code, lambda.span, message);
            const start = ast.declarationStart(syntax, function.name);
            insertion = declarationLine(src.bytes, start);
            break;
        }
    }
    const at = insertion orelse return sink.fail(removed_code, lambda.span, message);
    var prefix: []const u8 = "";
    if (names) |module_names| {
        const origin = src.originalSpan(lambda.span) catch return sink.fail(removed_code, lambda.span, message);
        const module = module_names.index.project.modules.items[origin.input].name;
        prefix = try std.fmt.allocPrint(allocator, "{s}.", .{module});
    }
    var text: std.Io.Writer.Allocating = .init(allocator);
    text.writer.print("func {s}(", .{name}) catch return error.OutOfMemory;
    for (lambda.parameters, contract.parameters, 0..) |parameter, ty, index| {
        if (index != 0) text.writer.writeAll(", ") catch return error.OutOfMemory;
        if (std.mem.indexOfScalar(u16, contract.mutates, @intCast(index)) != null) text.writer.writeAll("mut ") catch return error.OutOfMemory;
        text.writer.print("{s}: {s}", .{ src.text(parameter), try typeText(allocator, ty, records, prefix) }) catch return error.OutOfMemory;
    }
    text.writer.print(") -> {s}:\n    return {s}\n\n", .{ try typeText(allocator, contract.return_type, records, prefix), src.text(syntax.nodes.items[@backingInt(lambda.body)].span) }) catch return error.OutOfMemory;
    // A multiline match ends at a dedent that includes the next statement's
    // leading whitespace. Keep that statement separator outside the replacement.
    var replacement = lambda.span;
    replacement.end = replacement.start + std.mem.trimEnd(u8, src.text(replacement), " \t\r\n").len;
    try sink.appendFix(.{ .code = removed_code, .span = lambda.span, .message = message }, .{ .span = replacement, .text = name });
    sink.items.items[sink.items.items.len - 1].provenance.fix.?.more = try allocator.dupe(diagnostic.Edit, &.{.{ .span = .{ .start = at, .end = at }, .text = try text.toOwnedSlice() }});
    return error.SourceError;
}

fn typeText(allocator: std.mem.Allocator, ty: typed.Type, records: []const typed.Record, prefix: []const u8) ![]const u8 {
    const rendered = try typed.surfaceTypeName(allocator, ty, records);
    return migration.localTypeText(allocator, rendered, prefix);
}

/// Leave existing documentation and spec tags attached to their declaration.
fn declarationLine(bytes: []const u8, start: usize) usize {
    var at = if (std.mem.lastIndexOfScalar(u8, bytes[0..start], '\n')) |newline| newline + 1 else 0;
    while (at > 0) {
        const end = at - 1;
        const previous = if (std.mem.lastIndexOfScalar(u8, bytes[0..end], '\n')) |newline| newline + 1 else 0;
        const line = std.mem.trim(u8, bytes[previous..end], " \t\r");
        if (!std.mem.startsWith(u8, line, "#")) break;
        at = previous;
    }
    return at;
}
