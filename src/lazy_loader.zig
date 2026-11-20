//! The loader of a merged program whose function bodies are filled on demand (`ast.Loader`).
//!
//! `project_syntax.build` allocates the merged node and statement tables at their full length, writes the declaration-level trees and
//! the trees of every module the syntax store did not serve lazily, and leaves the bodies of lazily served modules unwritten. This
//! loader writes one of those bodies, relocated at the base its module already has in the run, when `ast.ensureBody` asks for it.
//! Every id and span of a loaded body is what the eager merge would have written, since the same decoder and the same `Mapper` make
//! it: a loaded interval is bit-identical to the eager table.
//!
//! The loader is single-threaded, as the front end is: a Debug build asserts that every call comes from the thread of the first.
const std = @import("std");
const builtin = @import("builtin");
const ast = @import("ast.zig");
const source = @import("source.zig");
const interfaces = @import("interfaces.zig");
const syntax_store = @import("syntax_store.zig");
const lazy_module = @import("lazy_module.zig");
const Mapper = @import("ast_copy.zig").Mapper;

/// Where one module lies in the merged tables.
pub const Base = struct {
    node: usize,
    statement: usize,
    node_count: usize,
    statement_count: usize,
    /// The slots of this module's lazy bodies are `slots[first_slot..end_slot]`.
    first_slot: u32,
    end_slot: u32,
    /// A parse of the module's bytes, made when a stored body was gone or damaged.
    reparsed: ?ast.Program = null,
};

/// One lazy body: the merged id of its root statement (which is always filled), its module and its position in that module's table.
pub const Slot = struct { root: u32, module: u32, body: u32, loaded: bool = false };

/// The merged tables the loader writes.
pub const Tables = struct { nodes: []ast.Node, statements: []ast.Statement };

/// What changes while bodies are filled: the thread that fills them, the interface programs hold and how many have been filled.
pub const State = struct {
    owner: ?std.Thread.Id = null,
    /// The interface programs hold; the pointer in `Facts.loader` points here.
    interface: ast.Loader = undefined,
    /// Bodies filled so far, for the statistics a test reads.
    filled: usize = 0,
};

/// The state behind an `ast.Loader`.
pub const Loader = struct {
    arena: std.mem.Allocator,
    index: *interfaces.Index,
    src: source.Source,
    tables: Tables,
    bases: []Base,
    /// Sorted by `root`, and so by module.
    slots: []Slot,
    state: State = .{},

    /// Wire `interface` to this loader and return it.
    pub fn attach(self: *Loader) *const ast.Loader {
        self.state.interface = .{ .context = self, .body = ensureBody, .module = ensureModule, .all = ensureAll, .body_at = bodyAt };
        return &self.state.interface;
    }

    fn assertOneThread(self: *Loader) void {
        if (builtin.mode != .debug) return;
        const current = std.Thread.getCurrentId();
        if (self.state.owner) |owner| std.debug.assert(owner == current) else self.state.owner = current;
    }

    fn find(self: *const Loader, root: u32) ?*Slot {
        var low: usize = 0;
        var high: usize = self.slots.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.slots[middle].root < root) low = middle + 1 else high = middle;
        }
        if (low == self.slots.len or self.slots[low].root != root) return null;
        return &@constCast(self.slots)[low];
    }

    fn ensureBody(context: *anyopaque, root: ast.StatementId) std.mem.Allocator.Error!void {
        const self: *Loader = @ptrCast(@alignCast(context));
        self.assertOneThread();
        const slot = self.find(@intCast(@backingInt(root))) orelse return;
        if (!slot.loaded) try self.load(slot);
    }

    /// The lazy body whose root statement spans source offset `at`, filled, and where its trees lie. Roots are in source order, and a root is
    /// always filled, so a search by their spans needs no body.
    fn bodyAt(context: *anyopaque, at: usize) std.mem.Allocator.Error!?ast.Scan {
        const self: *Loader = @ptrCast(@alignCast(context));
        self.assertOneThread();
        var low: usize = 0;
        var high: usize = self.slots.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.tables.statements[self.slots[middle].root].span.start <= at) low = middle + 1 else high = middle;
        }
        if (low == 0) return null;
        const slot = &self.slots[low - 1];
        if (at >= self.tables.statements[slot.root].span.end) return null;
        if (!slot.loaded) try self.load(slot);
        const base = self.bases[slot.module];
        const reference = self.index.units[slot.module].lazy.?.declarations.bodies[slot.body];
        return .{
            .node_start = base.node + reference.nodes.start,
            .node_end = base.node + reference.nodes.end,
            .statement_start = base.statement + reference.statements.start,
            // The root statement follows the interval and is read as part of the body.
            .statement_end = base.statement + reference.statements.end + 1,
        };
    }

    fn ensureModule(context: *anyopaque, module: usize) std.mem.Allocator.Error!void {
        const self: *Loader = @ptrCast(@alignCast(context));
        self.assertOneThread();
        const base = self.bases[module];
        for (self.slots[base.first_slot..base.end_slot]) |*slot| if (!slot.loaded) try self.load(slot);
    }

    fn ensureAll(context: *anyopaque) std.mem.Allocator.Error!void {
        const self: *Loader = @ptrCast(@alignCast(context));
        self.assertOneThread();
        for (self.slots) |*slot| if (!slot.loaded) try self.load(slot);
    }

    /// The body `slot` names, decoded from its module's entry, or taken from a parse of the module when the entry is gone or damaged.
    fn body(self: *Loader, slot: Slot) std.mem.Allocator.Error!syntax_store.Body {
        const unit = &self.index.units[slot.module];
        const module = unit.lazy.?;
        if (try module.entry(self.arena)) |entry| {
            const section = module.declarations.section(entry, slot.body) catch return self.reparse(slot);
            return syntax_store.decodeBody(self.arena, module.declarations, slot.body, section) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.reparse(slot),
            };
        }
        return self.reparse(slot);
    }

    /// The body `slot` names, from a parse of its module: a parse yields the ids the stored entry was made from.
    fn reparse(self: *Loader, slot: Slot) std.mem.Allocator.Error!syntax_store.Body {
        const base = &self.bases[slot.module];
        if (base.reparsed == null) {
            base.reparsed = interfaces.reparse(self.index.project, slot.module) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => std.debug.panic("a module whose stored syntax parsed no longer parses: {s}", .{@errorName(err)}),
            };
        }
        const reference = self.index.units[slot.module].lazy.?.declarations.bodies[slot.body];
        return syntax_store.bodyOfParse(base.reparsed.?, reference);
    }

    fn load(self: *Loader, slot: *Slot) std.mem.Allocator.Error!void {
        const base = self.bases[slot.module];
        const reference = self.index.units[slot.module].lazy.?.declarations.bodies[slot.body];
        const map: Mapper = .{ .src = self.src, .module = slot.module, .nodes = base.node, .statements = base.statement, .node_count = base.node_count, .statement_count = base.statement_count };
        var decoded = try self.body(slot.*);
        place(self, map, base, reference, decoded) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            // A body whose ids or spans do not fit its module is damaged however it was found; the parse is the authority.
            else => {
                decoded = try self.reparse(slot.*);
                place(self, map, base, reference, decoded) catch |again| switch (again) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => std.debug.panic("a re-parsed body does not fit its module: {s}", .{@errorName(again)}),
                };
            },
        };
        slot.loaded = true;
        self.state.filled += 1;
    }

    fn place(self: *Loader, map: Mapper, base: Base, reference: syntax_store.BodyRef, decoded: syntax_store.Body) !void {
        for (decoded.nodes, 0..) |node, k| self.tables.nodes[base.node + reference.nodes.start + k] = try map.value(self.arena, ast.Node, node);
        for (decoded.statements, 0..) |statement, k| self.tables.statements[base.statement + reference.statements.start + k] = try map.value(self.arena, ast.Statement, statement);
    }
};
