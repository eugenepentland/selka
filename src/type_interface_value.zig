//! Compact raw signature syntax and module facts for one project-wide interface check.
const std = @import("std");
const declaration = @import("declaration_value.zig");
const Span = @import("source.zig").Span;
/// Parameter names and types used by structural requirements.
pub const Field = struct { name: Span, ty: Span };
/// Structural operation syntax; effects and defaults are not read by signature preflight.
pub const Operation = struct { name: Span, parameters: []const Field, return_type: Span };
/// Unresolved named requirement, retaining exact source coordinates.
pub const Reference = struct { alias: ?Span = null, name: Span };
/// Raw generic binder and every requirement used by interface checking.
pub const Generic = struct { name: Span, default_copy: bool, constant_length: bool, requirements: []const Span, fields: []const Field, operations: []const Operation, named: []const Reference };
/// Record interface syntax; field names/defaults do not affect this pass.
pub const Record = struct { name: Span, parameters: []const Generic, fields: []const Span };
/// Variant payload and named-field type syntax in native source order.
pub const Case = struct { payload: ?Span, fields: []const Span };
/// Variant interface syntax; union/fallibility flags do not affect this pass.
pub const Variant = struct { name: Span, parameters: []const Generic, cases: []const Case };
/// Transparent alias or domain backing spelling.
pub const Alias = struct { name: Span, target: Span };
/// Named structural constraint and its single subject binder.
pub const Constraint = struct { name: Span, span: Span, subject: Generic };
/// Function interface syntax, independent of body/effect checking.
pub const Function = struct { name: Span, owner: ?Span, parameters: []const Generic, inputs: []const Span, return_type: Span, failure_type: ?Span };
/// Optional/growable wrappers both recurse into the same base during preflight.
pub const Suffix = struct { span: Span, base: Span };
/// Callable type parameters, result and optional checked error.
pub const Callback = struct { span: Span, parameters: []const Span, return_type: Span, failure_type: ?Span };
/// Array/table syntax; fixed-length expressions are not resolved by this pass.
pub const Array = struct { span: Span, enum_index: ?Span, element: Span };
/// Nominal/builtin constructor and unresolved argument spellings.
pub const Application = struct { span: Span, name: Span, arguments: []const Span };
/// Structural tuple's ordered element spellings.
pub const Tuple = struct { span: Span, elements: []const Span };
/// Separate raw catalogs retain native traversal and type-expression precedence.
pub const Declarations = struct {
    records: []const Record = &.{},
    variants: []const Variant = &.{},
    aliases: []const Alias = &.{},
    domains: []const Alias = &.{},
    constraints: []const Constraint = &.{},
    functions: []const Function = &.{},
};
/// Structural type spelling catalogs.
pub const Types = struct {
    suffixes: []const Suffix = &.{},
    callbacks: []const Callback = &.{},
    arrays: []const Array = &.{},
    applications: []const Application = &.{},
    tuples: []const Tuple = &.{},
};
/// Grouped raw catalogs; wire flattens declaration sections before type sections.
pub const Catalog = struct { declarations: Declarations = .{}, types: Types = .{} };
/// One indexed module, including import usage produced by declaration collection.
pub const Module = struct { context: declaration.Context, imports: []const declaration.Import, symbols: []const declaration.Symbol, import_used: []const bool, syntax: Catalog };
/// All indexed modules and the exact native signature-check traversal order.
pub const Input = struct { order: []const usize, modules: []const Module };
/// Exact successful resolution request and its canonical defining identity.
pub const Resolution = struct { from: usize, alias: ?[]const u8, name: []const u8, kind: declaration.Kind, span: Span, identity: declaration.Identity };
/// Completion acknowledgement, usage in module-ID order and successful resolution trace.
pub const Output = struct { order: []const usize, import_used: []const []const bool, resolutions: []const Resolution };
/// First exact source failure or a completed interface check.
pub const Outcome = union(enum) { success: Output, failure: declaration.Problem };
/// Replies own all decoded bytes and tables until explicitly released.
pub const Decoded = struct {
    arena: std.heap.ArenaAllocator,
    outcome: Outcome,
    /// Release every reply allocation.
    pub fn deinit(self: *Decoded) void {
        self.arena.deinit();
        self.* = undefined;
    }
};
/// Compare full logical outcomes independently of allocation and framing.
pub fn equal(left: Outcome, right: Outcome) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .failure => |problem| declaration.equal(.{ .failure = problem }, .{ .failure = right.failure }),
        .success => |output| equalOutput(output, right.success),
    };
}
fn equalOutput(left: Output, right: Output) bool {
    if (!std.mem.eql(usize, left.order, right.order)) return false;
    if (left.import_used.len != right.import_used.len or left.resolutions.len != right.resolutions.len) return false;
    for (left.import_used, right.import_used) |a, b| if (!std.mem.eql(bool, a, b)) return false;
    for (left.resolutions, right.resolutions) |a, b| {
        if (a.from != b.from or a.kind != b.kind) return false;
        if (!std.meta.eql(a.span, b.span) or !std.meta.eql(a.identity, b.identity)) return false;
        if (!std.mem.eql(u8, a.name, b.name) or !equalOptional(a.alias, b.alias)) return false;
    }
    return true;
}
fn equalOptional(left: ?[]const u8, right: ?[]const u8) bool {
    if ((left == null) != (right == null)) return false;
    return if (left) |bytes| std.mem.eql(u8, bytes, right.?) else true;
}
