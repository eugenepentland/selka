//! Scalar body-check batch transport, independent of semantic orchestration.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const declaration = @import("declaration_value.zig");
const diagnostic = @import("diagnostic.zig");
const logical = @import("parser_value.zig");
/// Source diagnostics retain all B1 notes and fixes without runtime-only state.
pub const Diagnostic = logical.SyntaxDiagnostic;
const source = @import("source.zig");
/// Raw source and entry policy; no body decisions have been precomputed.
pub const Context = struct { path: []const u8, source: []const u8, trusted_intrinsics: bool, entry_required: bool };
/// Explicit module namespace and initial import usage in merged coordinates.
pub const Module = struct { context: declaration.Context, offset: usize, imports: []const declaration.Import, symbols: []const declaration.Symbol, import_used: []const bool };
/// Complete raw syntax and namespace inputs for one scalar body batch.
pub const Input = struct { context: Context, program: ast.Program, modules: []const Module };
/// Complete typed tables before entry adaptation and native postpasses.
pub const Batch = struct { nodes: []const typed.Node, statements: []const typed.Statement, functions: []const typed.Function, ranges: []const @import("semantic_copy.zig").Range };
/// Typed bodies and all ordered checker observations.
pub const Output = struct { batch: Batch, import_used: []const []const bool, diagnostics: []const Diagnostic };
/// Located unsupported profile refusal; it never requests native fallback.
pub const Profile = struct { code: []const u8, span: source.Span, message: []const u8 };
/// Checked scalar bodies, source diagnostics, or explicit admission refusal.
pub const Outcome = union(enum) { success: Output, failure: []const Diagnostic, profile: Profile };
/// Reply values own storage independently of the process capture buffer.
pub const Decoded = struct {
    arena: std.heap.ArenaAllocator,
    outcome: Outcome,
    /// Release all decoded tables and observations.
    pub fn deinit(self: *Decoded) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Restore a decoded source diagnostic for the native sink without dropping notes.
pub fn nativeDiagnostic(item: Diagnostic) diagnostic.Diagnostic {
    return .{
        .code = item.code,
        .severity = item.severity,
        .span = item.span,
        .message = item.message,
        .related = item.related,
        .provenance = .{ .origin = item.provenance.origin, .requirement = item.provenance.requirement, .fix = item.provenance.fix },
    };
}

/// Project native B1 diagnostics, rejecting runtime state instead of discarding it.
pub fn diagnostics(a: std.mem.Allocator, items: []const diagnostic.Diagnostic) logical.Error![]const Diagnostic {
    const output = try a.alloc(Diagnostic, items.len);
    errdefer a.free(output);
    for (items, output) |item, *result| {
        if (item.provenance.obligation != null or item.stack.len != 0 or item.stack.omitted != 0) return error.ComponentProtocol;
        result.* = .{
            .code = item.code,
            .severity = item.severity,
            .span = item.span,
            .message = item.message,
            .related = item.related,
            .provenance = .{ .origin = item.provenance.origin, .requirement = item.provenance.requirement, .fix = item.provenance.fix },
        };
    }
    return output;
}
/// Adopt independent body tables into caller-owned arena storage.
pub fn cloneBatch(a: std.mem.Allocator, batch: Batch) logical.Error!Batch {
    const bytes = try logical.encodeTree(a, Batch, batch, "SLKBTB01");
    defer a.free(bytes);
    return logical.decodeInto(Batch, a, bytes, "SLKBTB01");
}
/// Publish complete decoded source diagnostics into a sink-owned arena.
pub fn publish(sink: *diagnostic.Sink, items: []const Diagnostic) logical.Error!void {
    const bytes = try logical.encodeTree(sink.allocator, []const Diagnostic, items, "SLKBTD01");
    defer sink.allocator.free(bytes);
    const owned = try logical.decodeInto([]const Diagnostic, sink.allocator, bytes, "SLKBTD01");
    for (owned) |item| try sink.items.append(sink.allocator, nativeDiagnostic(item));
}
/// Compare complete canonical outcomes independently of value-table ordering.
pub fn equal(a: std.mem.Allocator, left: Outcome, right: Outcome) logical.Error!bool {
    const lhs = try logical.encodeTree(a, Outcome, left, "SLKBKR01");
    defer a.free(lhs);
    const rhs = try logical.encodeTree(a, Outcome, right, "SLKBKR01");
    defer a.free(rhs);
    return std.mem.eql(u8, lhs, rhs);
}
