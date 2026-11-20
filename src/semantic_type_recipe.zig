//! Replay portable interner inputs through the fresh checker's normal type rules.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const owned = @import("semantic_entry.zig");
const copy = @import("semantic_copy.zig");
const nominal = @import("nominal_catalog.zig");
const Error = @import("diagnostic.zig").Error;

/// One request scans the syntax of each module a recipe names a site in, once, retaining only immediate function-value slot candidates.
/// Warm recipe resolution then costs one source-site lookup, and a module no recipe reaches is never scanned.
pub const Sites = struct {
    /// The runs of the tables scanned so far, as their first and last node ids: a lazy body, or the whole module around an offset in no body.
    scanned: std.AutoHashMapUnmanaged([2]usize, void) = .empty,
    entries: std.AutoHashMapUnmanaged(source.Span, Context) = .empty,
    const Context = union(enum) {
        direct: struct { parent: @import("ast.zig").NodeId, position: usize },
        binding: ?source.Span,
        ambiguous,
    };
    fn put(self: *Sites, allocator: std.mem.Allocator, site: source.Span, context: Context) error{OutOfMemory}!void {
        const entry = try self.entries.getOrPut(allocator, site);
        entry.value_ptr.* = if (entry.found_existing) .ambiguous else context;
    }
    /// Scan the trees around offset `at`, unless an earlier site already did: a site and the call or binding that holds it lie in one function
    /// body, so a program whose bodies are filled on demand scans, and fills, that body alone.
    fn prepare(self: *Sites, comptime Checker: type, checker: *Checker, at: usize) error{OutOfMemory}!void {
        const ast = @import("ast.zig");
        const scan = try ast.scanAt(checker.syntax, at);
        const scanned = try self.scanned.getOrPut(checker.allocator, .{ scan.node_start, scan.node_end });
        if (scanned.found_existing) return;
        for (checker.syntax.nodes.items[scan.node_start..scan.node_end], scan.node_start..) |node, parent| {
            if (node.data != .call) continue;
            for (node.data.call.arguments, 0..) |argument, position| {
                const value = checker.syntax.nodes.items[@backingInt(argument)];
                if (value.data != .name) continue;
                try self.put(checker.allocator, value.span, .{ .direct = .{ .parent = @fromBackingInt(parent), .position = position } });
            }
        }
        for (checker.syntax.statements.items[scan.statement_start..scan.statement_end]) |statement| {
            if (statement.data != .binding) continue;
            const binding = statement.data.binding;
            const value = checker.syntax.nodes.items[@backingInt(binding.value)];
            if (value.data != .name) continue;
            try self.put(checker.allocator, value.span, .{ .binding = binding.annotation });
        }
    }
};

fn relocate(span: source.Span, before: source.Span, after: source.Span) ?source.Span {
    if (span.start < before.start or span.end < span.start or span.end > before.end) return null;
    return .{ .start = after.start + span.start - before.start, .end = after.start + span.end - before.start };
}
fn child(old: typed.Type, remaps: []const copy.RecordRemap) ?typed.Type {
    return if (old.isAggregate()) copy.findRecord(remaps, old.recordIndex()) else old;
}
/// No schema or ownership contract is copied: the normal interner derives
/// it from fresh child types or the current function-value use site's syntax.
pub fn resolve(comptime Checker: type, checker: *Checker, sites: *Sites, recipe: owned.TypeRecipe, before: source.Span, after: source.Span, remaps: []const copy.RecordRemap) Error!?typed.Type {
    return switch (recipe) {
        .array => |array| try checker.catalog.instantiateArray(checker.allocator, child(array.element, remaps) orelse return null, array.length, relocate(array.site, before, after) orelse return null, checker.sink),
        .tuple => |tuple| tuple: {
            const elements = try checker.allocator.alloc(typed.Type, tuple.len);
            for (tuple, elements) |old, *element| element.* = child(old, remaps) orelse return null;
            break :tuple try checker.catalog.tupleType(elements);
        },
        .callable => |site| try callable(Checker, checker, sites, relocate(site, before, after) orelse return null),
        .instance => |instance| try instantiate(checker, instance, before, after, remaps),
    };
}

/// Restore one generic named instance through the checker's own nominal path, so the record
/// is the one a fresh check would intern, with the declaration span it would give it: the
/// stored site relocated into the body, or the body's region when the site lies outside it
/// (an instance another body interned first, which is already settled). Any input that does
/// not resolve is a miss (null): an unknown declaration or arity, an argument record that was
/// not remapped, or an internal failure. A source error from the materialization is passed on,
/// so the caller drops the diagnostics it added.
fn instantiate(checker: anytype, instance: owned.Instance, before: source.Span, after: source.Span, remaps: []const copy.RecordRemap) Error!?typed.Type {
    const declaration = nominal.instanceDeclaration(&checker.catalog, instance.name, instance.arguments.len) orelse return null;
    const arguments = try checker.allocator.alloc(typed.Type, instance.arguments.len);
    for (instance.arguments, arguments) |old, *argument| argument.* = child(old, remaps) orelse return null;
    const site = relocate(instance.site, before, after) orelse after;
    const fresh = nominal.instantiateLengths(&checker.catalog, declaration, arguments, instance.lengths, site) catch |err| switch (err) {
        error.InternalError => return null,
        else => |other| return other,
    };
    return fresh;
}

/// Direct call arguments and annotated bindings have a fresh, declaration-owned
/// expected type. Unsupported contextual sites remain conservative misses.
fn callable(comptime Checker: type, checker: *Checker, sites: *Sites, site: source.Span) Error!?typed.Type {
    try sites.prepare(Checker, checker, site.start);
    const context = sites.entries.get(site) orelse return null;
    var expected: ?typed.Type = null;
    switch (context) {
        .ambiguous => return null,
        .binding => |annotation| if (annotation) |span| {
            expected = try checker.catalog.resolve(checker.src, span, checker.sink);
        },
        .direct => |direct| {
            const node = checker.syntax.nodes.items[@backingInt(direct.parent)];
            const call = node.data.call;
            // Generic/member/named dispatch needs its own substitution recipe.
            if (call.owner != null or call.type_arguments.len != 0 or call.argument_names.len != 0) return null;
            // Parsed bracket applications stay in the raw name until ordinary
            // call dispatch splits them. They need the same generic fallback.
            if (std.mem.endsWith(u8, checker.src.text(call.name), "]")) return null;
            const key = if (checker.catalog.module_names) |names| try names.reference(call.name, .function, null, null, checker.sink) else checker.src.text(call.name);
            const declaration = checker.functions.get(key) orelse return null;
            const function = checker.syntax.functions[@backingInt(declaration)];
            if (function.policy.owner != null or function.policy.restricted) return null;
            if (direct.position >= function.signature.parameters.len) return null;
            // Generic slots may need substitution. Reconstruct the target with
            // its own fresh contract instead; the caller requires exact schema
            // equality and its validated dependency receipt covers the consumer.
            if (function.signature.type_parameters.len == 0) {
                expected = try checker.catalog.resolve(checker.src, function.signature.parameters[direct.position].ty, checker.sink);
            }
        },
    }
    const value_key = if (checker.catalog.module_names) |names| try names.reference(site, .function, null, null, checker.sink) else checker.src.text(site);
    const value_declaration = checker.functions.get(value_key) orelse return null;
    // Fallible target reconstruction can materialize a nominal Result graph;
    // unsupported cache recipes must leave that graph untouched on fallback.
    if (checker.syntax.functions[@backingInt(value_declaration)].signature.failure_type != null) return null;
    const previous = checker.expected_types.get(site);
    defer {
        if (previous) |old| {
            checker.expected_types.putAssumeCapacity(site, old);
        } else _ = checker.expected_types.remove(site);
    }
    if (expected) |slot| try checker.expected_types.put(checker.allocator, site, slot) else _ = checker.expected_types.remove(site);
    var node: typed.Node = .{ .span = site, .ty = .unit, .data = .unit };
    if (!try @import("sema_calls.zig").functionValue(Checker, checker, site, &node)) return null;
    if (expected) |slot| {
        const callables = @import("callables.zig");
        const actual = callables.signature(node.ty, checker.catalog.records) orelse return null;
        const destination = callables.signature(slot, checker.catalog.records) orelse return null;
        if (!callables.assignable(actual, destination)) return null;
    }
    return node.ty;
}
