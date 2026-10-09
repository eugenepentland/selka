//! Stand-in planning, verification and summary production for one
//! `sema.checkCached` request (see `semantic_summary.zig`).
//!
//! A body stands in for itself when its previous summary is stubbable and its
//! dependency context and declaration-region digest are unchanged. The check
//! then seeds the cross-function passes with the stored facts, replays the
//! stored diagnostics, and afterwards confirms that every body it did check
//! still has exactly the facts it had before and closes no call cycle through a
//! stood-in body. Otherwise the stored facts might not be the ones a full check
//! computes, and the request asks for a full check instead.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const origins = @import("origins.zig");
const summary = @import("semantic_summary.zig");
const semantic_key = @import("semantic_key.zig");
const sem_copy = @import("semantic_copy.zig");
const semantic_cache = @import("semantic_cache.zig");

/// One checked instance's node and statement intervals and the diagnostics
/// appended while its body was checked.
pub const Checked = struct {
    instance: usize,
    nodes: source.Span,
    statements: source.Span,
    diagnostics: []const diagnostic.Diagnostic,
};

/// Everything `produce` reads besides the plan and the program's facts.
pub const Outputs = struct {
    /// Diagnostics the whole-program passes appended, before any replay.
    pass: []const diagnostic.Diagnostic,
    /// The checked syntax, for each declaration's kind.
    syntax: ast.Program,
};

/// Per-request stand-in state; every allocation belongs to the check's arena.
pub const Plan = struct {
    request: *summary.Request,
    prepared: *const semantic_key.Prepared,
    /// The request's reuse session: fresh catalog names and record shapes.
    session: *semantic_cache.Session,
    /// Previous summary position standing in for each ordinary instance, or null.
    stand_ins: []?u32,
    /// Every checked instance, in check order.
    checked: std.ArrayList(Checked) = .empty,
    /// Instance index of the entry point, which is always checked.
    main: usize,
    /// A bounded-body fallback still replaces the summaries that caused it.
    allocation_fallback: bool = false,

    /// Plan stand-ins for one request. `main` is the entry point's instance.
    pub fn init(allocator: std.mem.Allocator, request: *summary.Request, session: *semantic_cache.Session, main: usize) error{OutOfMemory}!Plan {
        const prepared = &session.prepared;
        const count = prepared.ordinary_ast.len;
        const stand_ins = try allocator.alloc(?u32, count);
        errdefer allocator.free(stand_ins);
        @memset(stand_ins, null);
        request.stood_in = 0;
        request.prepared = prepared.*;
        if (request.declared) {
            // An imported interface's declared function has no body here, so
            // its stored facts stand in unconditionally (MODULE-INTERFACE-1).
            const previous = request.previous orelse return .{ .request = request, .prepared = prepared, .session = session, .stand_ins = stand_ins, .main = main };
            for (prepared.ordinary_ast, 0..) |ast_index, instance| {
                if (instance == main) continue;
                stand_ins[instance] = previous.find(prepared.keys[ast_index]) orelse continue;
                request.stood_in += 1;
            }
        } else if (request.previous) |previous| {
            // Previous table record position -> its shape in the fresh catalog.
            const shapes = try allocator.alloc(ShapeState, previous.records.len);
            defer allocator.free(shapes);
            @memset(shapes, .unknown);
            for (prepared.ordinary_ast, 0..) |ast_index, instance| {
                if (instance == main) continue;
                const position = previous.find(prepared.keys[ast_index]) orelse continue;
                const stored = previous.summaries[position];
                if (!stored.stubbable) continue;
                if (!std.mem.eql(u8, &stored.context, &prepared.contexts[ast_index])) continue;
                const region = prepared.regions[ast_index];
                if (region.end - region.start != stored.region.len) continue;
                if (!std.mem.eql(u8, &prepared.recalled.digests[ast_index], &stored.region.digest)) continue;
                if (!try touchedShapesMatch(allocator, session, previous, stored.uses, shapes)) continue;
                stand_ins[instance] = position;
                request.stood_in += 1;
            }
        }
        return .{ .request = request, .prepared = prepared, .session = session, .stand_ins = stand_ins, .main = main };
    }

    /// Keep bounded bodies and their callees concrete for Core allocation checks.
    /// Previous edges live in the previous table; remap by stable key, never by
    /// current declaration position. A changed bounded body has unknown new edges
    /// and conservatively requests concrete trees (ordinary body reuse still works).
    pub fn requireAllocationBodies(self: *Plan, allocator: std.mem.Allocator, syntax: ast.Program) error{OutOfMemory}!void {
        if (self.request.body_policy != .allocation_contracts or self.request.declared) return;
        const previous = self.request.previous orelse return;
        const required = try allocator.alloc(bool, previous.summaries.len);
        defer allocator.free(required);
        @memset(required, false);
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(allocator);
        for (self.prepared.ordinary_ast) |ast_index| {
            const bound = syntax.functions[ast_index].policy.effect_bound orelse continue;
            if (!@import("effect_set.zig").coreAllocationBound(self.session.src, bound)) continue;
            const position = previous.find(self.prepared.keys[ast_index]) orelse {
                self.allocation_fallback = true;
                self.request.body_policy = .concrete;
                return;
            };
            const stored = previous.summaries[position];
            if (!std.mem.eql(u8, &stored.context, &self.prepared.contexts[ast_index]) or !std.mem.eql(u8, &stored.region.digest, &self.prepared.recalled.digests[ast_index])) {
                self.allocation_fallback = true;
                self.request.body_policy = .concrete;
                return;
            }
            try pending.append(allocator, position);
        }
        while (pending.pop()) |position| {
            if (required[position]) continue;
            required[position] = true;
            for (previous.summaries[position].uses.callees) |callee| if (callee < required.len and !required[callee]) try pending.append(allocator, callee);
        }
        for (self.prepared.ordinary_ast, self.stand_ins) |ast_index, *position| {
            const previous_position = previous.find(self.prepared.keys[ast_index]) orelse continue;
            if (required[previous_position] and position.* != null) {
                position.* = null;
                self.request.stood_in -= 1;
            }
        }
    }

    /// The previous summary standing in for ordinary instance `i`'s
    /// cross-function facts, or null when the passes compute them.
    pub fn standIn(self: *const Plan, i: usize) ?*const summary.Summary {
        if (i >= self.stand_ins.len) return null;
        const position = self.stand_ins[i] orelse return null;
        return &self.request.previous.?.summaries[position];
    }

    /// The previous summary standing in for ordinary instance `i`'s whole
    /// body, or null when the body must be checked (always, for a command that
    /// lowers the checked program).
    pub fn bodyStandIn(self: *const Plan, i: usize) ?*const summary.Summary {
        if (self.request.body_policy == .concrete) return null;
        return self.standIn(i);
    }

    /// Whether any body is stood in by a summary in this request.
    pub fn active(self: *const Plan) bool {
        return self.request.stood_in != 0;
    }

    /// Replay the diagnostics a stood-in body produced while it was checked.
    pub fn replayBody(self: *const Plan, i: usize, sink: *diagnostic.Sink) error{OutOfMemory}!void {
        const stored = self.bodyStandIn(i) orelse return;
        const start = self.regionOf(i).start;
        for (stored.notes.body) |note| try sink.items.append(sink.allocator, summary.diagnosticOf(note, start));
    }

    /// Replay the warnings the whole-program passes reported inside every
    /// stood-in body; those passes skip stood-in bodies.
    pub fn replayPasses(self: *const Plan, sink: *diagnostic.Sink) error{OutOfMemory}!void {
        for (0..self.stand_ins.len) |i| {
            const stored = self.standIn(i) orelse continue;
            const start = self.regionOf(i).start;
            for (stored.notes.pass) |note| try sink.items.append(sink.allocator, summary.diagnosticOf(note, start));
        }
    }

    /// Record one checked instance. Its diagnostics are copied, because the
    /// sink is reordered before summaries are produced.
    pub fn recordChecked(self: *Plan, allocator: std.mem.Allocator, record: Checked) error{OutOfMemory}!void {
        var owned = record;
        owned.diagnostics = if (record.diagnostics.len == 0) &.{} else try allocator.dupe(diagnostic.Diagnostic, record.diagnostics);
        try self.checked.append(allocator, owned);
    }

    /// Stand-in facts for the effect and mutation passes, by function index.
    pub fn passStubs(self: *const Plan, allocator: std.mem.Allocator, function_count: usize) error{OutOfMemory}![]const ?origins.Fact {
        if (!self.active()) return &.{};
        const stubs = try allocator.alloc(?origins.Fact, function_count);
        @memset(stubs, null);
        for (0..@min(self.stand_ins.len, function_count)) |i| {
            if (self.standIn(i)) |stored| stubs[i] = summary.toFact(stored.fact);
        }
        return stubs;
    }

    /// Whether the stored facts the stand-ins supplied are the ones a full
    /// check computes: every checked ordinary body with a previous summary
    /// still has exactly its stored facts, and no call cycle passes through
    /// both a checked and a stood-in body.
    pub fn consistent(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, facts: []const origins.Fact) error{OutOfMemory}!bool {
        if (!self.active()) return true;
        const previous = self.request.previous.?;
        for (self.prepared.ordinary_ast, 0..) |ast_index, instance| {
            if (self.standIn(instance) != null or instance >= facts.len) continue;
            const position = previous.find(self.prepared.keys[ast_index]) orelse continue;
            if (!summary.sameFact(summary.fromFact(facts[instance]), previous.summaries[position].fact)) return false;
        }
        return !try self.mixedCycle(allocator, program);
    }

    /// Whether a checked body reaches itself through a stood-in body. Stood-in
    /// facts are fixed, so a cycle through one could keep a stale fixed point.
    fn mixedCycle(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program) error{OutOfMemory}!bool {
        const current = try self.currentPositions(allocator);
        // Only bodies whose facts the passes computed walk their own edges; a
        // stood-in body's facts rest on its stored callees.
        const checked_edges = try allocator.alloc(?[]const u32, program.functions.len);
        @memset(checked_edges, null);
        for (self.checked.items) |record| {
            if (self.standIn(record.instance) != null) continue;
            if (record.instance < checked_edges.len) checked_edges[record.instance] = try callTargets(allocator, program, record);
        }
        const visited = try allocator.alloc(bool, program.functions.len);
        var stack: std.ArrayList(u32) = .empty;
        for (self.checked.items) |record| {
            const start = checked_edges[record.instance] orelse continue;
            @memset(visited, false);
            stack.clearRetainingCapacity();
            for (start) |target| if (self.standIn(target) != null) try stack.append(allocator, target);
            while (stack.pop()) |node| {
                if (node == record.instance) return true;
                if (node >= visited.len or visited[node]) continue;
                visited[node] = true;
                if (self.standIn(node)) |stored| {
                    for (stored.uses.callees) |position| if (current[position]) |next| try stack.append(allocator, next);
                } else if (checked_edges[node]) |edges| {
                    try stack.appendSlice(allocator, edges);
                }
            }
        }
        return false;
    }

    /// Previous table position -> this request's ordinary instance.
    fn currentPositions(self: *const Plan, allocator: std.mem.Allocator) error{OutOfMemory}![]const ?u32 {
        const previous = self.request.previous orelse return &.{};
        const current = try allocator.alloc(?u32, previous.summaries.len);
        @memset(current, null);
        for (self.prepared.ordinary_ast, 0..) |ast_index, instance| {
            if (previous.find(self.prepared.keys[ast_index])) |position| current[position] = @intCast(instance);
        }
        return current;
    }

    /// Whether this request should publish a summary table. A command that
    /// lowers publishes one only when it had none to stand in (or repeated in
    /// full), so the next such command does not repeat the passes again.
    pub fn publishes(self: *const Plan) bool {
        return self.allocation_fallback or self.request.body_policy != .concrete or self.request.previous == null;
    }

    /// This request's summary table, one entry per ordinary instance in order.
    pub fn produce(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, facts: []const origins.Fact, outputs: Outputs) error{ OutOfMemory, InternalError }!summary.Table {
        const count = self.prepared.ordinary_ast.len;
        const table = try allocator.alloc(summary.Summary, count);
        var names: RecordNames = .{};
        const current = try self.currentPositions(allocator);
        const records = try allocator.alloc(?usize, count);
        @memset(records, null);
        for (self.checked.items, 0..) |record, position| {
            if (record.instance < count) records[record.instance] = position;
        }
        const pass = try allocator.dupe(diagnostic.Diagnostic, outputs.pass);
        std.mem.sort(diagnostic.Diagnostic, pass, {}, startsBefore);
        for (0..count) |instance| {
            if (self.standIn(instance)) |stored| {
                table[instance] = stored.*;
                table[instance].uses.callees = try remapCallees(allocator, stored.uses.callees, current);
                if (table[instance].uses.callees.len != stored.uses.callees.len) table[instance].stubbable = false;
                table[instance].uses.records = try names.carry(allocator, self.request.previous.?.records, stored.uses.records);
                continue;
            }
            const record = if (records[instance]) |position| self.checked.items[position] else null;
            table[instance] = try self.checkedSummary(allocator, program, .{ .instance = instance, .record = record, .fact = if (instance < facts.len) facts[instance] else .{} }, pass, outputs);
            if (record) |checked_record| try self.touched(allocator, program, checked_record, &names, &table[instance]);
        }
        return .{ .records = names.list.items, .summaries = table };
    }

    /// Record the catalog records one checked body's tree touched and their
    /// combined shape; a tree that touched a record without a stable name or
    /// shape is not stubbable.
    fn touched(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, record: Checked, names: *RecordNames, entry: *summary.Summary) error{ OutOfMemory, InternalError }!void {
        const indices = (try treeRecords(allocator, program, record, self.prepared.ordinary_ast.len, self.session.remap.initial_record_count)) orelse {
            entry.stubbable = false;
            return;
        };
        const positions = try allocator.alloc(u32, indices.len);
        const shapes = try allocator.alloc(summary.Shape, indices.len);
        for (indices, positions, shapes) |index, *position, *shape| {
            const name = program.records[index].name;
            position.* = try names.intern(allocator, name);
            const digest = (try self.session.shapeOf(name)) orelse {
                entry.stubbable = false;
                return;
            };
            shape.* = .{ .name = name, .digest = digest };
        }
        entry.uses.records = positions;
        entry.uses.shape = summary.combineShapes(shapes);
    }

    /// One checked ordinary instance's summary.
    fn checkedSummary(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, checked: CheckedInstance, pass: []const diagnostic.Diagnostic, outputs: Outputs) error{ OutOfMemory, InternalError }!summary.Summary {
        const ast_index = self.prepared.ordinary_ast[checked.instance];
        const region = self.prepared.regions[ast_index];
        var stubbable = checked.instance != self.main and checked.record != null;
        if (checked.record != null and !admitsStandIn(program.functions[checked.instance], outputs.syntax.functions[ast_index])) stubbable = false;
        const body_notes = try notesIn(allocator, if (checked.record) |record| record.diagnostics else &.{}, region, &stubbable);
        const pass_notes = try notesIn(allocator, passItemsIn(pass, region), region, &stubbable);
        return .{
            .key = self.prepared.keys[ast_index],
            .context = self.prepared.contexts[ast_index],
            .region = .{
                .len = @intCast(region.end - region.start),
                .digest = self.prepared.recalled.digests[ast_index],
                .names = self.prepared.recalled.names[ast_index],
            },
            .fact = summary.fromFact(checked.fact),
            .notes = .{ .body = body_notes, .pass = pass_notes },
            .uses = .{ .callees = if (checked.record) |record| try callTargets(allocator, program, record) else &.{} },
            .stubbable = stubbable,
        };
    }

    fn regionOf(self: *const Plan, i: usize) source.Span {
        return self.prepared.regions[self.prepared.ordinary_ast[i]];
    }
};

/// One checked ordinary instance, its check record when it has one, and the
/// facts the passes inferred for it.
const CheckedInstance = struct { instance: usize, record: ?Checked, fact: origins.Fact };

fn startsBefore(_: void, a: diagnostic.Diagnostic, b: diagnostic.Diagnostic) bool {
    return a.span.start < b.span.start;
}

/// The pass diagnostics (sorted by start) whose primary span starts in `region`.
fn passItemsIn(items: []const diagnostic.Diagnostic, region: source.Span) []const diagnostic.Diagnostic {
    var low: usize = 0;
    var high = items.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (items[middle].span.start < region.start) low = middle + 1 else high = middle;
    }
    var end = low;
    while (end < items.len and items[end].span.start < region.end) end += 1;
    return items[low..end];
}

/// Whether a function's declaration kind lets a summary stand in for it:
/// constants, conversions and host or foreign declarations are checked fresh.
fn admitsStandIn(function: typed.Function, declared: ast.Function) bool {
    return function.policy.host == null and !function.policy.c_abi and !function.policy.conversion and !declared.policy.constant;
}

/// The ordinary instances one checked body calls directly, deduplicated.
fn callTargets(allocator: std.mem.Allocator, program: typed.Program, record: Checked) error{OutOfMemory}![]const u32 {
    var targets: std.ArrayList(u32) = .empty;
    const end = @min(record.nodes.end, program.nodes.len);
    var index = @min(record.nodes.start, end);
    while (index < end) : (index += 1) {
        const node = program.nodes[index];
        if (node.data != .call) continue;
        const callee: u32 = @intCast(@backingInt(node.data.call.function));
        if (callee == record.instance) continue;
        if (std.mem.indexOfScalar(u32, targets.items, callee) == null) try targets.append(allocator, callee);
    }
    return targets.toOwnedSlice(allocator);
}

/// Map stored callee positions to this request's instances; a callee that no
/// longer exists is dropped (the caller then records the entry unstubbable).
fn remapCallees(allocator: std.mem.Allocator, callees: []const u32, current: []const ?u32) error{OutOfMemory}![]const u32 {
    var out: std.ArrayList(u32) = .empty;
    for (callees) |position| {
        if (position < current.len) if (current[position]) |instance| try out.append(allocator, instance);
    }
    return out.toOwnedSlice(allocator);
}

/// Diagnostics as region-relative notes; one that cannot be stored makes the
/// function unstubbable.
fn notesIn(allocator: std.mem.Allocator, items: []const diagnostic.Diagnostic, region: source.Span, stubbable: *bool) error{OutOfMemory}![]const summary.Note {
    if (items.len == 0) return &.{};
    var notes: std.ArrayList(summary.Note) = .empty;
    for (items) |item| {
        if (!summary.storable(item, region)) {
            stubbable.* = false;
            continue;
        }
        try notes.append(allocator, summary.noteOf(item, region.start));
    }
    return notes.toOwnedSlice(allocator);
}

/// The catalog records one checked ordinary body's tree touches, or null
/// when it names a function or record that did not exist before any body was
/// checked (a specialization, a lambda, a type interned while checking): a
/// later check cannot stand a summary in for such a body.
fn treeRecords(allocator: std.mem.Allocator, program: typed.Program, record: Checked, ordinary_count: usize, initial_record_count: usize) error{ OutOfMemory, InternalError }!?[]const usize {
    var refs = sem_copy.RefSet.init(allocator);
    defer refs.deinit();
    const node_end = @min(record.nodes.end, program.nodes.len);
    const statement_end = @min(record.statements.end, program.statements.len);
    try sem_copy.collectRefs(allocator, program.functions[record.instance], program.nodes[@min(record.nodes.start, node_end)..node_end], program.statements[@min(record.statements.start, statement_end)..statement_end], &refs);
    var functions = refs.functions.keyIterator();
    while (functions.next()) |id| if (id.* >= ordinary_count) return null;
    const indices = try allocator.alloc(usize, refs.records.count());
    var records = refs.records.keyIterator();
    var count: usize = 0;
    while (records.next()) |index| : (count += 1) {
        if (index.* >= initial_record_count or index.* >= program.records.len) return null;
        indices[count] = index.*;
    }
    return indices;
}

/// Whether a record's shape in the fresh catalog is known yet, and what it is.
const ShapeState = union(enum) { unknown, missing, known: [32]u8 };

/// Whether every record a stored body touched still exists with the shape it
/// had, compared through the order-independent combined digest.
fn touchedShapesMatch(allocator: std.mem.Allocator, session: *semantic_cache.Session, previous: *const summary.Index, uses: summary.Uses, shapes: []ShapeState) error{OutOfMemory}!bool {
    const touched = try allocator.alloc(summary.Shape, uses.records.len);
    defer allocator.free(touched);
    for (uses.records, touched) |position, *shape| {
        if (shapes[position] == .unknown) {
            shapes[position] = if (try session.shapeOf(previous.records[position])) |digest| .{ .known = digest } else .missing;
        }
        const digest = switch (shapes[position]) {
            .known => |known| known,
            else => return false,
        };
        shape.* = .{ .name = previous.records[position], .digest = digest };
    }
    const combined = summary.combineShapes(touched);
    return std.mem.eql(u8, &combined, &uses.shape);
}

/// The record-name list of the table being produced.
const RecordNames = struct {
    list: std.ArrayList([]const u8) = .empty,
    positions: std.StringHashMapUnmanaged(u32) = .empty,

    fn intern(self: *RecordNames, allocator: std.mem.Allocator, name: []const u8) error{OutOfMemory}!u32 {
        const entry = try self.positions.getOrPut(allocator, name);
        if (!entry.found_existing) {
            entry.value_ptr.* = @intCast(self.list.items.len);
            try self.list.append(allocator, name);
        }
        return entry.value_ptr.*;
    }

    /// Positions in this table of records another table named by position.
    fn carry(self: *RecordNames, allocator: std.mem.Allocator, previous: []const []const u8, positions: []const u32) error{OutOfMemory}![]const u32 {
        const out = try allocator.alloc(u32, positions.len);
        for (positions, out) |position, *carried| carried.* = try self.intern(allocator, previous[position]);
        return out;
    }
};
