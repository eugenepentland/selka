//! Test reachability read from the merged syntax when the bodies do not check.
//!
//! `tests-for` walks the checked call graph, which a project with a type error
//! does not have. This module builds the same graph from the parsed calls
//! instead: each call site resolves by name through the module and import
//! tables the checker resolves through (`interfaces.Index`), so an agent in the
//! middle of a change still learns which tests reach the declaration it is
//! editing. The answer is labeled `basis: syntax`: a call resolved by name
//! without checked types is not a checked fact, so a call the checker would
//! reject still counts and a function value invoked later does not.
const std = @import("std");
const ast = @import("ast.zig");
const interfaces = @import("interfaces.zig");
const pc = @import("project_compile.zig");
const typed = @import("typed.zig");
const tests_index = @import("tests_index.zig");

/// Allocation, or merged syntax whose spans do not map back to a module.
pub const Error = std.mem.Allocator.Error || error{InternalError};

/// The label a syntax-derived answer carries on its last line.
pub const basis = "basis: syntax (the project does not type-check; calls were resolved by name, not by checked types)";

/// A call graph over the merged function declarations, read from syntax. The
/// identities index `names`, the way a checked graph indexes its program's
/// functions, so `tests_index.buildNamed` walks both the same way.
pub const Graph = struct {
    /// `module::name` (`module::Domain.name` for a domain member) of each
    /// declaration, the identity `tests-for` spells.
    names: []const []const u8,
    /// The declarations each declaration's body calls, by index into `names`.
    calls: []const []const typed.FunctionId,
    /// The discovered tests: a non-generic top-level `test_` function or one
    /// carrying `@test`, exactly the checked discovery rule.
    tests: []const typed.FunctionId,
};

/// The source range one declaration covers, from its name to its body's end.
const Range = struct { start: usize, end: usize, function: usize };

fn rangeLess(_: void, left: Range, right: Range) bool {
    return left.start < right.start;
}

/// What one graph build reads while it resolves calls.
const Resolver = struct {
    arena: std.mem.Allocator,
    index: *interfaces.Index,
    by_name: std.StringHashMapUnmanaged(usize) = .empty,

    /// The declaration one call spelling names from inside `from`: a name this
    /// module declares (`f`, `Domain.f`), or a name behind one of its import
    /// aliases (`alias.f`, `alias.Domain.f`, `pkg.mod.f`). Anything else — a
    /// builtin, a constructor, a method on a value — names no declaration.
    fn call(self: *Resolver, from: usize, spelled: []const u8) Error!?usize {
        if (try self.declared(from, spelled)) |found| return found;
        var cursor = spelled.len;
        while (std.mem.lastIndexOfScalar(u8, spelled[0..cursor], '.')) |dot| {
            cursor = dot;
            const target = self.imported(from, spelled[0..dot]) orelse continue;
            return self.declared(target, spelled[dot + 1 ..]);
        }
        return null;
    }

    /// The module one import alias (or imported module path) of `from` names.
    fn imported(self: *const Resolver, from: usize, alias: []const u8) ?usize {
        for (self.index.project.modules.items[from].imports) |item| {
            if (item.matches(alias)) return item.target;
        }
        return null;
    }

    /// The declaration a module's own namespace binds `key` to, following a
    /// re-export to its defining module; null unless it is a function.
    fn declared(self: *Resolver, module: usize, key: []const u8) Error!?usize {
        const unit = self.index.units[module];
        const slot = unit.names.get(key) orelse return null;
        var owner = module;
        var symbol = unit.symbols.items[slot];
        if (symbol.re_export) |target| {
            owner = target.module;
            symbol = self.index.units[target.module].symbols.items[target.symbol];
        }
        if (symbol.kind != .function) return null;
        const qualified = try std.fmt.allocPrint(self.arena, "{s}::{s}", .{ self.index.project.modules.items[owner].name, symbol.name });
        return self.by_name.get(qualified);
    }
};

/// Build the syntax call graph of a merged compilation in `arena`.
pub fn build(arena: std.mem.Allocator, compilation: *pc.Compilation) Error!Graph {
    const functions = compilation.syntax.functions;
    const names = try arena.alloc([]const u8, functions.len);
    const modules = try arena.alloc(usize, functions.len);
    const ranges = try arena.alloc(Range, functions.len);
    var resolver: Resolver = .{ .arena = arena, .index = compilation.index };
    var tests: std.ArrayList(typed.FunctionId) = .empty;
    const loaded = compilation.index.project.modules.items;
    for (functions, 0..) |function, index| {
        const original = compilation.src.originalSpan(function.name) catch return error.InternalError;
        if (original.input >= loaded.len) return error.InternalError;
        const local = compilation.src.text(function.name);
        names[index] = if (function.policy.owner) |owner|
            try std.fmt.allocPrint(arena, "{s}::{s}.{s}", .{ loaded[original.input].name, compilation.src.text(owner), local })
        else
            try std.fmt.allocPrint(arena, "{s}::{s}", .{ loaded[original.input].name, local });
        modules[index] = original.input;
        const slot = try resolver.by_name.getOrPut(arena, names[index]);
        if (!slot.found_existing) slot.value_ptr.* = index;
        const body = compilation.syntax.statements.items[@backingInt(function.body)].span;
        ranges[index] = .{ .start = function.name.start, .end = body.end, .function = index };
        if (discoverable(compilation.syntax, function, local)) try tests.append(arena, @fromBackingInt(index));
    }
    std.mem.sort(Range, ranges, {}, rangeLess);
    const lists = try arena.alloc(std.ArrayList(typed.FunctionId), functions.len);
    for (lists) |*list| list.* = .empty;
    for (compilation.syntax.nodes.items) |node| {
        const call = switch (node.data) {
            .call => |call| call,
            else => continue,
        };
        const caller = enclosing(ranges, node.span.start) orelse continue;
        const spelled = if (call.owner) |owner|
            compilation.src.text(.{ .start = owner.start, .end = call.name.end })
        else
            compilation.src.text(call.name);
        const callee = try resolver.call(modules[caller], spelled) orelse continue;
        try lists[caller].append(arena, @fromBackingInt(callee));
    }
    const calls = try arena.alloc([]const typed.FunctionId, functions.len);
    for (calls, lists) |*kept, list| kept.* = list.items;
    return .{ .names = names, .calls = calls, .tests = tests.items };
}

/// The checked discovery rule, applied to one declaration.
fn discoverable(syntax: ast.Program, function: ast.Function, local: []const u8) bool {
    if (function.signature.type_parameters.len != 0 or function.policy.owner != null) return false;
    return std.mem.startsWith(u8, local, "test_") or ast.hasAttribute(syntax, function.name, .@"test");
}

/// The declaration whose range covers one merged-source position.
fn enclosing(ranges: []const Range, position: usize) ?usize {
    var low: usize = 0;
    var high = ranges.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (ranges[middle].start <= position) low = middle + 1 else high = middle;
    }
    if (low == 0) return null;
    const found = ranges[low - 1];
    if (position >= found.end) return null;
    return found.function;
}

/// Render the `tests-for` answer for one declaration from the syntax graph:
/// the checked answer's three lines plus the `basis` line that labels it.
/// Returns null when no declaration carries that exact name.
pub fn renderTestsFor(allocator: std.mem.Allocator, graph: Graph, subject: []const u8) Error!?[]u8 {
    var target: ?usize = null;
    for (graph.names, 0..) |name, index| {
        if (std.mem.eql(u8, name, subject)) {
            target = index;
            break;
        }
    }
    const found = target orelse return null;
    var index = try tests_index.buildNamed(allocator, graph.names, graph.calls, graph.tests);
    defer index.deinit();
    const rendered = try @import("navigation.zig").formatTestsFor(allocator, subject, index.answer(@fromBackingInt(found)), basis);
    return rendered;
}
