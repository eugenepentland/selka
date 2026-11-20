//! Declaration-time checks of record field defaults. A default is checked where a constructor first builds it, like a
//! parameter's type; the one question asked of the declaration itself is whether a default that builds a record can build
//! it: `inner: Inner = Inner()` is refused where it is written when `Inner` has a field without a default, instead of at
//! the first `Outer()` anywhere in the program.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const typed = @import("typed.zig");
const record_calls = @import("record_calls.zig");
const Catalog = @import("records.zig").Catalog;
const sealed_rules = @import("sealed_rules.zig");

/// The deepest constructor nesting a default is followed through. Source text is finite, so the bound only guards a
/// pathological program.
const depth_limit = 16;

/// Report, for every non-generic record of `program`, each field default that builds a record without a value for one
/// of its required fields. The diagnostic is `E_INCOMPLETE_CONSTRUCTION` at the default, with the one edit that repairs
/// it: delete ` = default`. The field was never usable with that default (a construction that left it out was refused),
/// so a program that checked before keeps its meaning. Findings are appended, and checking goes on to the rest.
pub fn check(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, catalog: Catalog, sink: *diagnostic.Sink) diagnostic.Error!void {
    for (program.types.records) |record| {
        if (record.type_parameters.len != 0) continue;
        for (record.fields) |field| {
            const default = field.default_value orelse continue;
            const walk: Walk = .{ .allocator = allocator, .src = src, .program = program, .catalog = catalog, .sink = sink, .field = field };
            try walk.buildable(default, 0);
        }
    }
}

/// What one default is followed with: the program and its catalog, and the field whose default it is, for the message and the repair.
const Walk = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    catalog: Catalog,
    sink: *diagnostic.Sink,
    field: ast.Parameter,

    /// Follow one default expression: a record constructor must name every required field of its record, and so must each
    /// constructor among its arguments.
    fn buildable(self: Walk, id: ast.NodeId, depth: usize) diagnostic.Error!void {
        if (depth >= depth_limit) return;
        const node = self.program.nodes.items[@backingInt(id)];
        const call = switch (node.data) {
            .call => |call| call,
            else => return,
        };
        // A constructor with a module qualifier, a type argument or a positional argument is left to the first construction.
        if (call.owner != null or call.type_arguments.len != 0) return;
        if (call.arguments.len != 0 and call.argument_names.len != call.arguments.len) return;
        for (call.argument_names) |name| if (name == null) return;
        const ty = try record_calls.recordType(self.src, self.catalog, call.name, self.sink) orelse return;
        // A default written in another module than a sealed record's builds one where that module's text is (W11, rule 2).
        const sealed: sealed_rules.Context = .{ .src = self.src, .names = self.catalog.module_names, .records = self.catalog.records, .syntax = self.program };
        try sealed_rules.check(sealed, self.allocator, self.sink, .{ .operation = .default, .ty = ty, .at = node.span });
        for (self.catalog.records[ty.recordIndex()].fields) |field| {
            if (field.default_value != null or supplies(self.src, call, field.name)) continue;
            return self.report(node.span, call.name, field);
        }
        for (call.arguments) |argument| try self.buildable(argument, depth + 1);
    }

    /// Append the refusal of the default written at `at`, which builds `constructor` without `missing`, and its repair.
    fn report(self: Walk, at: source.Span, constructor: source.Span, missing: typed.Field) diagnostic.Error!void {
        const message = try std.fmt.allocPrint(
            self.allocator,
            "the default of field `{s}` builds `{s}` without its required field `{s}`; give `{s}` a default, name it in this default, or drop the default",
            .{ self.src.text(self.field.name), self.src.text(constructor), missing.name, missing.name },
        );
        const edit: diagnostic.Edit = .{ .span = .{ .start = self.field.ty.end, .end = at.end }, .text = "" };
        try self.sink.appendFix(.{
            .code = "E_INCOMPLETE_CONSTRUCTION",
            .span = at,
            .message = message,
            .related = .{ .span = missing.declaration, .message = "required field declared here" },
        }, edit);
    }
};

/// Whether `call` names the field `name` among its keyword arguments.
fn supplies(src: source.Source, call: anytype, name: []const u8) bool {
    for (call.argument_names) |label| if (label) |span| if (std.mem.eql(u8, src.text(span), name)) return true;
    return false;
}
