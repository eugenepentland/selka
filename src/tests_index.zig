//! Shared "which discovered tests reach this declaration" index over one
//! checked program. `selka tests-for`, the related notes `selka lint` puts on
//! a finding, and the `tests` column of `selka list-interfaces` all read this
//! one walk, so the three never disagree about what a test is or what reaches.
const std = @import("std");
const ast = @import("ast.zig");
const entry_adapter = @import("entry_adapter.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");

/// Building an index allocates; there is no other failure mode.
pub const Error = std.mem.Allocator.Error;

/// One module's parsed syntax and source, the inputs test discovery needs.
pub const ModuleSyntax = struct { name: []const u8, src: source.Source, syntax: ast.Program };

/// Direct and transitive discovered tests that reach one declaration, in
/// discovery order. Names are the checked program's module-qualified names.
pub const Answer = struct {
    direct: []const []const u8 = &.{},
    reached: []const []const u8 = &.{},
};

/// Per-declaration reachability, owned by its arena until `deinit`.
pub const Index = struct {
    arena: std.heap.ArenaAllocator,
    /// Tests whose body calls each function directly, by function index.
    direct: [][]const []const u8,
    /// Every test that reaches each function, directly or transitively.
    reached: [][]const []const u8,

    /// Release every table and list built for this index.
    pub fn deinit(self: *Index) void {
        self.arena.deinit();
    }

    /// The direct and transitive tests that reach `target`. An identity from
    /// another program yields empty lists rather than an out-of-bounds read.
    pub fn answer(self: *const Index, target: typed.FunctionId) Answer {
        const index = @backingInt(target);
        if (index >= self.direct.len) return .{};
        return .{ .direct = self.direct[index], .reached = self.reached[index] };
    }
};

/// Discover the test functions of a checked program: a `test_`-prefixed local
/// name, or any declaration carrying `@test`, without a generic parameter list.
pub fn discoveredTests(memory: std.mem.Allocator, program: typed.Program, modules: []const ModuleSyntax) Error![]typed.FunctionId {
    var tests: std.ArrayList(typed.FunctionId) = .empty;
    defer tests.deinit(memory);
    var names_arena = std.heap.ArenaAllocator.init(memory);
    defer names_arena.deinit();
    const attributed = try testAttributed(names_arena.allocator(), modules);
    for (program.functions) |function| {
        if (function.type_arguments.len != 0) continue;
        if (std.mem.eql(u8, function.name, entry_adapter.wrapper_name)) continue;
        if (std.mem.startsWith(u8, function.name, "lambda@")) continue;
        if (@import("invariant_callbacks.zig").isName(function.name)) continue;
        const local = localName(function.name);
        if (!std.mem.startsWith(u8, local, "test_") and !attributed.contains(function.name)) continue;
        try tests.append(memory, function.id);
    }
    return tests.toOwnedSlice(memory);
}

/// The `module::name` identity of every top-level function carrying `@test`,
/// read from each module's syntax once, so discovery answers each checked
/// function with one lookup instead of scanning every module per function.
fn testAttributed(arena: std.mem.Allocator, modules: []const ModuleSyntax) Error!std.StringHashMapUnmanaged(void) {
    var names: std.StringHashMapUnmanaged(void) = .empty;
    for (modules) |module| {
        if (module.syntax.attributes.len == 0) continue;
        for (module.syntax.functions) |function| {
            if (function.policy.owner != null) continue;
            if (!ast.hasAttribute(module.syntax, function.name, .@"test")) continue;
            try names.put(arena, try std.fmt.allocPrint(arena, "{s}::{s}", .{ module.name, module.src.text(function.name) }), {});
        }
    }
    return names;
}

/// Resolve each function's direct `.call` targets by walking its checked body.
/// Function-value `invoke` sites are not resolved call edges and are excluded,
/// exactly as the quality call graph excludes them.
pub fn callGraph(memory: std.mem.Allocator, program: typed.Program) Error![][]const typed.FunctionId {
    const graph = try memory.alloc([]const typed.FunctionId, program.functions.len);
    for (program.functions, 0..) |function, index| {
        var calls: std.ArrayList(typed.FunctionId) = .empty;
        defer calls.deinit(memory);
        var walker = try walk.Walker.init(memory, program, function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .expression => |id| switch (program.nodes[@backingInt(id)].data) {
                .call => |call| try calls.append(memory, call.function),
                else => {},
            },
            .statement => {},
        };
        graph[index] = try calls.toOwnedSlice(memory);
    }
    return graph;
}

/// Invert a call graph and a test set into per-function direct and transitive
/// test answers, in test discovery order.
pub fn build(memory: std.mem.Allocator, program: typed.Program, call_graph: []const []const typed.FunctionId, tests: []const typed.FunctionId) Error!Index {
    const names = try memory.alloc([]const u8, program.functions.len);
    defer memory.free(names);
    for (names, program.functions) |*name, function| name.* = function.name;
    return buildNamed(memory, names, call_graph, tests);
}

/// `build` over any function table: `names[i]` is the qualified name of the
/// function the graph and the test list identify as `i`. A syntax-derived graph
/// (`navigation_syntax.zig`) indexes its own declaration table this way, so the
/// checked and the unchecked answers share one reachability walk.
pub fn buildNamed(memory: std.mem.Allocator, names: []const []const u8, call_graph: []const []const typed.FunctionId, tests: []const typed.FunctionId) Error!Index {
    var arena = std.heap.ArenaAllocator.init(memory);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    const count = names.len;
    const direct_lists = try scratch.alloc(std.ArrayList([]const u8), count);
    const reached_lists = try scratch.alloc(std.ArrayList([]const u8), count);
    for (direct_lists) |*list| list.* = .empty;
    for (reached_lists) |*list| list.* = .empty;
    const visited = try scratch.alloc(bool, count);
    var pending: std.ArrayList(typed.FunctionId) = .empty;
    for (tests) |test_id| {
        const test_index = @backingInt(test_id);
        if (test_index >= count) continue;
        const name = names[test_index];
        @memset(visited, false);
        pending.clearRetainingCapacity();
        visited[test_index] = true;
        try pending.append(scratch, test_id);
        while (pending.pop()) |current| {
            try reached_lists[@backingInt(current)].append(scratch, name);
            for (call_graph[@backingInt(current)]) |callee| {
                const target = @backingInt(callee);
                if (target >= visited.len or visited[target]) continue;
                visited[target] = true;
                try pending.append(scratch, callee);
            }
        }
        for (call_graph[test_index]) |callee| try direct_lists[@backingInt(callee)].append(scratch, name);
    }
    const direct = try scratch.alloc([]const []const u8, count);
    const reached = try scratch.alloc([]const []const u8, count);
    for (direct, reached, direct_lists, reached_lists) |*kept, *everything, direct_list, reached_list| {
        kept.* = direct_list.items;
        everything.* = reached_list.items;
    }
    return .{ .arena = arena, .direct = direct, .reached = reached };
}

/// Local (unqualified) part of a `module::name` function identity.
fn localName(qualified: []const u8) []const u8 {
    const at = std.mem.indexOf(u8, qualified, "::") orelse return qualified;
    return qualified[at + 2 ..];
}
