//! Pure declaration-index transport values, independent of project loading and checking.
const std = @import("std");
const source = @import("source.zig");
/// Declaration categories retain the reference collector's stable group order.
pub const Category = enum(u32) { record, domain, variant, resource, alias, constraint, function };
/// Namespace kind used by later native name resolution.
pub const Kind = enum { type, function, constraint };
/// Original declaration identity, including canonical re-export targets.
pub const Identity = struct { module: usize, symbol: usize };
/// Name, visibility and source location published by one module.
pub const Symbol = struct { name: []const u8, kind: Kind, span: source.Span, exported: bool = false, owner: ?[]const u8 = null, restricted: bool = false, re_export: ?Identity = null };
/// Input source provenance and graph facts; no declaration decisions are precomputed.
pub const Context = struct { module: usize, name: []const u8, path: []const u8, trusted_intrinsics: bool, is_imported: bool, source: []const u8 };
/// AST declaration facts before name construction, conflict checking or export analysis.
pub const Declaration = struct { category: Category, span: source.Span, owner: ?source.Span = null, restricted: bool = false };
/// Parsed direct import with both accepted qualifier spellings.
pub const Import = struct { name: []const u8, alias: []const u8, span: source.Span, target: usize };
/// Parsed export directive with its optional imported-module qualifier.
pub const Export = struct { name: []const u8, alias: ?[]const u8, span: source.Span };
/// Previously indexed direct dependency; its symbols retain defining identities.
pub const Dependency = struct { module: usize, name: []const u8, source_len: usize, symbols: []const Symbol };
/// Complete per-module indexing request, including public declaration markers.
pub const Input = struct { context: Context, declarations: []const Declaration, imports: []const Import, exports: []const Export, public: []const source.Span, dependencies: []const Dependency };
/// Source byte location in an explicitly identified project module.
pub const Site = struct { module: usize, span: source.Span };
/// Existing compiler diagnostic selected by declaration analysis.
pub const Problem = struct { code: []const u8, message: []const u8, site: Site, related: ?Site = null };
/// Indexed symbols and import usage caused by successful re-export resolution.
pub const Output = struct { symbols: []const Symbol, import_used: []const bool };
/// A complete declaration table or the first native-order source failure.
pub const Outcome = union(enum) { success: Output, failure: Problem };
/// Arena-owned decoded values; callers copy adopted values into their own storage.
pub const Decoded = struct {
    arena: std.heap.ArenaAllocator,
    outcome: Outcome,
    /// Release every allocation made while decoding or validating the reply.
    pub fn deinit(self: *Decoded) void {
        self.arena.deinit();
        self.* = undefined;
    }
};
/// Compare logical values independently of allocation and wire layout.
pub fn equal(left: Outcome, right: Outcome) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .failure => |problem| equalProblem(problem, right.failure),
        .success => |output| equalOutput(output, right.success),
    };
}
fn equalProblem(left: Problem, right: Problem) bool {
    return std.mem.eql(u8, left.code, right.code) and std.mem.eql(u8, left.message, right.message) and
        std.meta.eql(left.site, right.site) and std.meta.eql(left.related, right.related);
}
fn equalOutput(left: Output, right: Output) bool {
    if (!std.mem.eql(bool, left.import_used, right.import_used) or left.symbols.len != right.symbols.len) return false;
    for (left.symbols, right.symbols) |a, b| {
        if (!std.mem.eql(u8, a.name, b.name)) return false;
        if (a.kind != b.kind or !std.meta.eql(a.span, b.span)) return false;
        if (a.exported != b.exported or a.restricted != b.restricted) return false;
        if (!std.meta.eql(a.re_export, b.re_export)) return false;
        if ((a.owner == null) != (b.owner == null)) return false;
        if (a.owner) |owner| if (!std.mem.eql(u8, owner, b.owner.?)) return false;
    }
    return true;
}

// spec-case: SELFHOST-DECLARATION-1
test "declaration logical comparison includes visibility ownership and diagnostic provenance" {
    const declaration = Symbol{ .name = "Item", .kind = .type, .span = .{ .start = 0, .end = 4 } };
    var exported = declaration;
    exported.exported = true;
    const native: Outcome = .{ .success = .{ .symbols = &.{declaration}, .import_used = &.{false} } };
    const changed: Outcome = .{ .success = .{ .symbols = &.{exported}, .import_used = &.{false} } };
    try std.testing.expect(equal(native, native));
    try std.testing.expect(!equal(native, changed));
    const failure: Outcome = .{ .failure = .{ .code = "E_DUPLICATE_SYMBOL", .message = "module declaration name is already bound", .site = .{ .module = 0, .span = .{ .start = 4, .end = 8 } } } };
    var related = failure;
    related.failure.related = .{ .module = 0, .span = .{ .start = 0, .end = 4 } };
    try std.testing.expect(equal(failure, failure));
    try std.testing.expect(!equal(failure, related));
    try std.testing.expect(!equal(native, failure));
}
