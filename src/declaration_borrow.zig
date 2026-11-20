//! Declaration-only normalization of a function's explicit return sources.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");

/// Normalize source names into parameter positions without reading a body.
/// Repeated names collapse; unknown names never silently publish a fresh result.
pub fn positions(allocator: std.mem.Allocator, src: source.Source, signature: ast.FunctionSignature) error{ OutOfMemory, InternalError }![]const u16 {
    var out: std.ArrayList(u16) = .empty;
    errdefer out.deinit(allocator);
    var matched: usize = 0;
    for (signature.parameters, 0..) |parameter, index| {
        var count: usize = 0;
        for (signature.borrowing) |name| {
            if (std.mem.eql(u8, src.text(name), src.text(parameter.name))) count += 1;
        }
        matched += count;
        if (count != 0) try out.append(allocator, std.math.cast(u16, index) orelse return error.InternalError);
    }
    if (matched != signature.borrowing.len) return error.InternalError;
    return out.toOwnedSlice(allocator);
}

/// The source region omitted from normalized headers and replaced by positions.
pub fn clause(signature: ast.FunctionSignature) ?source.Span {
    if (signature.borrowing.len == 0) return null;
    return .{ .start = signature.return_type.end, .end = signature.borrowing[signature.borrowing.len - 1].end };
}

/// Exclude implementation-only type spellings before collecting declaration
/// shapes. Signature/default/nominal-field spellings remain available.
pub fn signatureProgram(allocator: std.mem.Allocator, program: ast.Program) error{OutOfMemory}!ast.Program {
    var out = program;
    inline for (.{ "suffixes", "callbacks", "arrays", "applications", "tuples" }) |category| {
        const items = @field(program.types.expressions, category);
        const T = @typeInfo(@TypeOf(items)).pointer.child;
        var kept: std.ArrayList(T) = .empty;
        for (items) |item| {
            if (insideBody(program, item.span)) continue;
            try kept.append(allocator, item);
        }
        @field(out.types.expressions, category) = try kept.toOwnedSlice(allocator);
    }
    return out;
}

fn insideBody(program: ast.Program, span: source.Span) bool {
    for (program.functions) |function| {
        if (function.policy.constant) continue;
        const body = program.statements.items[@backingInt(function.body)].span;
        if (span.start >= body.start and span.end <= body.end) return true;
    }
    return false;
}
