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
    /// Catalog records that existed before any body was checked.
    initial_record_count: usize,
    /// The checked syntax, for each declaration's kind.
    syntax: ast.Program,
};

/// Per-request stand-in state; every allocation belongs to the check's arena.
pub const Plan = struct {
    request: *summary.Request,
    prepared: *const semantic_key.Prepared,
    /// Previous summary position standing in for each ordinary instance, or null.
    stand_ins: []?u32,
    /// Every checked instance, in check order.
    checked: std.ArrayList(Checked) = .empty,
    /// Instance index of the entry point, which is always checked.
    main: usize,

    /// Plan stand-ins for one request. `main` is the entry point's instance.
    pub fn init(allocator: std.mem.Allocator, request: *summary.Request, prepared: *const semantic_key.Prepared, main: usize) error{OutOfMemory}!Plan {
        const count = prepared.ordinary_ast.len;
        const stand_ins = try allocator.alloc(?u32, count);
        @memset(stand_ins, null);
        request.stood_in = 0;
        if (request.previous) |previous| {
            for (prepared.ordinary_ast, 0..) |ast_index, instance| {
                if (instance == main) continue;
                const position = previous.find(prepared.keys[ast_index]) orelse continue;
                const stored = previous.summaries[position];
                if (!stored.stubbable) continue;
                if (!std.mem.eql(u8, &stored.context, &prepared.contexts[ast_index])) continue;
                const region = prepared.regions[ast_index];
                if (region.end - region.start != stored.region.len) continue;
                if (!std.mem.eql(u8, &prepared.recalled.digests[ast_index], &stored.region.digest)) continue;
                stand_ins[instance] = position;
                request.stood_in += 1;
            }
        }
        return .{ .request = request, .prepared = prepared, .stand_ins = stand_ins, .main = main };
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
        if (self.request.facts_only) return null;
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
                    for (stored.callees) |position| if (current[position]) |next| try stack.append(allocator, next);
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
        return !self.request.facts_only or self.request.previous == null;
    }

    /// This request's summary table, one entry per ordinary instance in order.
    pub fn produce(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, facts: []const origins.Fact, outputs: Outputs) error{ OutOfMemory, InternalError }![]const summary.Summary {
        const count = self.prepared.ordinary_ast.len;
        const table = try allocator.alloc(summary.Summary, count);
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
                table[instance].callees = try remapCallees(allocator, stored.callees, current);
                if (table[instance].callees.len != stored.callees.len) table[instance].stubbable = false;
                continue;
            }
            const record = if (records[instance]) |position| self.checked.items[position] else null;
            table[instance] = try self.checkedSummary(allocator, program, .{ .instance = instance, .record = record, .fact = if (instance < facts.len) facts[instance] else .{} }, pass, outputs);
        }
        return table;
    }

    /// One checked ordinary instance's summary.
    fn checkedSummary(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, checked: CheckedInstance, pass: []const diagnostic.Diagnostic, outputs: Outputs) error{ OutOfMemory, InternalError }!summary.Summary {
        const ast_index = self.prepared.ordinary_ast[checked.instance];
        const region = self.prepared.regions[ast_index];
        var stubbable = checked.instance != self.main and checked.record != null;
        if (checked.record) |record| {
            if (!try stableTree(allocator, program, record, self.prepared.ordinary_ast.len, outputs.initial_record_count)) stubbable = false;
            if (!admitsStandIn(program.functions[checked.instance], outputs.syntax.functions[ast_index])) stubbable = false;
        }
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
            .callees = if (checked.record) |record| try callTargets(allocator, program, record) else &.{},
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

/// Whether one checked ordinary body's tree names only ordinary functions and
/// types that existed before any body was checked, the condition under which a
/// later check may stand a summary in for it.
fn stableTree(allocator: std.mem.Allocator, program: typed.Program, record: Checked, ordinary_count: usize, initial_record_count: usize) error{ OutOfMemory, InternalError }!bool {
    var refs = sem_copy.RefSet.init(allocator);
    defer refs.deinit();
    const node_end = @min(record.nodes.end, program.nodes.len);
    const statement_end = @min(record.statements.end, program.statements.len);
    try sem_copy.collectRefs(allocator, program.functions[record.instance], program.nodes[@min(record.nodes.start, node_end)..node_end], program.statements[@min(record.statements.start, statement_end)..statement_end], &refs);
    var functions = refs.functions.keyIterator();
    while (functions.next()) |id| if (id.* >= ordinary_count) return false;
    var records = refs.records.keyIterator();
    while (records.next()) |index| if (index.* >= initial_record_count) return false;
    return true;
}
