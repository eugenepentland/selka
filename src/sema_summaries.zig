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
const interfaces = @import("interfaces.zig");
const entry_types = @import("semantic_entry.zig");
const semantic_store = @import("semantic_store.zig");
const syntax_hints = @import("syntax_hints.zig");
const timings = @import("timings.zig");
const module_groups = @import("sema_module_groups.zig");
const sections_mod = @import("semantic_sections.zig");
const builtin = @import("builtin");
const Names = @import("module_names.zig").Names;
const needless_copy = @import("needless_copy.zig");
const copy_for_store = @import("copy_for_store.zig");
const copy_from_repair = @import("copy_from_repair.zig");
const copy_loop_repair = @import("copy_loop_repair.zig");

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
    /// Sites an idiom waiver silenced, ordered by start. The warning they would have been is stored nowhere, so a
    /// function that holds one is not stubbable: removing the waiver must bring the warning back.
    silenced: []const source.Span = &.{},
    /// Sites whose warning, or its absence, read the file beyond the function the site is in (`Sink.file_reads`), ordered by
    /// start. A function that holds one is stored under the digest of its whole file (`Guards.wide`), so any edit of the file
    /// checks it again.
    file_reads: []const source.Span = &.{},
    /// The `W_COPY_MOVE` filter's answers of each checked caller, by instance (`CopyMoves.keeps`); empty when the check judged none.
    keeps: []const []const summary.Keep = &.{},
};

/// What planning reads besides the request and the session.
pub const Inputs = struct {
    /// The profile the planning's phases are added to, when one is attached.
    timing: ?*timings.Profile = null,
    /// The checked syntax, and the project's modules: with them the functions are grouped by module for a host that answers for a module.
    syntax: ast.Program,
    names: ?*Names = null,
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
    /// Previous summary positions invalidated through their actual consumers.
    history: struct {
        affected: []bool = &.{},
        current: []const ?u32 = &.{},
        allocation_fallback: bool = false,
        withheld: []const ?u32 = &.{},
        /// The waivers that decide the idiom warnings, read from the source the first time a summary needs them.
        guards: ?*?syntax_hints.Guards = null,
        /// Functions that stand in for their passes alone although their summary stands in whole: the artifacts that read callee
        /// bodies need their trees, since a callee's body changed, but their passes read only the callees' declarations.
        body_checked: []const bool = &.{},
        /// What the request knows of its modules: the functions whose module the host answered for as a whole (`Demand.allow_module`), so no
        /// `allow` was asked for them, and, for each module group, the section of the previous table that is exactly this module.
        modules: struct {
            covered: []const bool = &.{},
            matched: []const u32 = &.{},
        } = .{},
    } = .{},

    /// Plan stand-ins for one request. `main` is the entry point's instance. `timing`, when a profile is attached, receives the planning's phases
    /// (`plan_decide`, `plan_current`, `plan_consumers`, `plan_sources`, `plan_demand`) beside the caller's own.
    pub fn init(allocator: std.mem.Allocator, request: *summary.Request, session: *semantic_cache.Session, main: usize, inputs: Inputs) error{OutOfMemory}!Plan {
        const timing = inputs.timing;
        const prepared = &session.prepared;
        const guards = try allocator.create(?syntax_hints.Guards);
        guards.* = null;
        const stand_ins = try allocator.alloc(?u32, prepared.ordinary_ast.len);
        errdefer allocator.free(stand_ins);
        @memset(stand_ins, null);
        request.stood_in = 0;
        request.prepared = prepared.*;
        var plan: Plan = .{ .request = request, .prepared = prepared, .session = session, .stand_ins = stand_ins, .main = main };
        plan.history.guards = guards;
        // The modules come first: a module whose functions are those of the last check is decided as a whole, and a host that holds its
        // answers per module (and a check that lowers everything, which writes the receipts that correct a record) is asked by module.
        if (!request.policy.declared) try plan.groupModules(allocator, inputs);
        const decide_lap = Lap.start(timing);
        if (request.policy.declared) {
            // An imported interface's declared function has no body here, so
            // its stored facts stand in unconditionally (MODULE-INTERFACE-1).
            const previous = request.previous orelse return plan;
            plan.standInDeclared(previous);
        } else if (request.previous) |previous| {
            plan.history.withheld = try plan.decide(allocator, previous);
        }
        decide_lap.end("plan_decide");
        const current_lap = Lap.start(timing);
        plan.history.current = try plan.currentPositions(allocator);
        current_lap.end("plan_current");
        const consumers_lap = Lap.start(timing);
        if (!request.policy.declared) try plan.prepareConsumers(allocator);
        consumers_lap.end("plan_consumers");
        if (request.policy.demand) |demand| {
            const sources_lap = Lap.start(timing);
            if (demand.prepare_sources) |prepare| try prepare(demand.context, session.src);
            sources_lap.end("plan_sources");
            const demand_lap = Lap.start(timing);
            try plan.prepareDemand(allocator, inputs);
            demand_lap.end("plan_demand");
        }
        return plan;
    }

    /// Every function of an imported interface that the previous table holds stands in by its key alone.
    fn standInDeclared(self: *Plan, previous: *const summary.Index) void {
        var hint: u32 = 0;
        for (self.prepared.ordinary_ast, 0..) |ast_index, instance| {
            if (instance == self.main) continue;
            const position = previous.findNear(self.prepared.keys[ast_index], hint) orelse continue;
            hint = position + 1;
            self.stand_ins[instance] = position;
            self.request.stood_in += 1;
        }
    }

    /// Decide, for every ordinary function, whether its previous summary stands in: the stored summary found by key, whose context, region
    /// and touched shapes are the fresh ones. Returns the positions that verify sampling withheld.
    ///
    /// A module whose signature (the key-bearing contexts and region digests of its functions, in order) and touched record shapes are those
    /// the previous table holds for it is decided from the flags the table stores, without finding or comparing anything per function; the
    /// other functions take the loop below. A Debug compiler runs the loop over every function as well and holds the two together.
    fn decide(self: *Plan, allocator: std.mem.Allocator, previous: *const summary.Index) error{OutOfMemory}![]const ?u32 {
        const withheld = try allocator.alloc(?u32, self.stand_ins.len);
        @memset(withheld, null);
        var state = Decision.init(allocator, previous, self.request.policy.demand);
        defer state.deinit();
        self.history.modules.matched = try self.matchModules(allocator, previous, &state);
        try self.decideMatched(previous, &state);
        _ = try self.decideLoop(&state, withheld, .unmatched);
        if (builtin.mode == .debug and self.history.modules.matched.len != 0) try self.crossCheckDecision(allocator, previous);
        return withheld;
    }

    /// Which instances `decideLoop` visits: all of them, or those of modules the table did not answer for.
    const Visit = enum { all, unmatched };

    /// The loop over functions: the stored summary found by key, then `candidate`. It fills `stand_ins` and counts what stands in.
    fn decideLoop(self: *Plan, state: *Decision, withheld: []?u32, visit: Visit) error{OutOfMemory}!usize {
        var found: usize = 0;
        // The previous table lists the functions in the order the last program had them, so the position after the last one found is
        // nearly always the next one's: a key compare in sequential memory instead of a hash probe.
        var hint: u32 = 0;
        for (self.prepared.ordinary_ast, 0..) |ast_index, instance| {
            if (instance == self.main) continue;
            if (visit == .unmatched and self.matchedSection(instance) != null) continue;
            const position = state.previous.findNear(self.prepared.keys[ast_index], hint) orelse continue;
            hint = position + 1;
            if (!try self.candidate(state, ast_index, position)) continue;
            if (sampled(self.prepared.keys[ast_index], self.request.policy.verify.every)) {
                withheld[instance] = position;
                continue;
            }
            self.stand_ins[instance] = position;
            self.request.stood_in += 1;
            found += 1;
        }
        return found;
    }

    /// The section of the previous table that is exactly the module of ordinary instance `instance`, or null.
    fn matchedSection(self: *const Plan, instance: usize) ?u32 {
        const matched = self.history.modules.matched;
        if (matched.len == 0) return null;
        const grouping = self.request.prepared.?.grouping;
        if (instance >= grouping.module_of.len) return null;
        const group = grouping.module_of[instance];
        if (group == semantic_key.no_group or matched[group] == no_section) return null;
        return matched[group];
    }

    /// For each module group, the section of the previous table that holds exactly its functions and whose touched records have the shapes
    /// they had (`no_section` for a module that has none), or nothing when there is no table cut by module, no module groups, or a request
    /// that verifies (sampling is by function).
    fn matchModules(self: *Plan, allocator: std.mem.Allocator, previous: *const summary.Index, state: *Decision) error{OutOfMemory}![]const u32 {
        const view = previous.sections orelse return &.{};
        const grouping = self.request.prepared.?.grouping;
        if (grouping.modules.len == 0 or self.request.policy.verify.every != 0) return &.{};
        const matched = try allocator.alloc(u32, grouping.modules.len);
        for (grouping.modules, matched) |group, *slot| {
            slot.* = no_section;
            const section = view.byName(group.module) orelse continue;
            if (view.sizeOf(section) != group.members.len or !std.mem.eql(u8, view.signatureOf(section), &group.signature)) continue;
            if (!try sectionShapesMatch(self.session, view, section, &state.shapes)) continue;
            slot.* = section;
            self.request.prepared.?.grouping.matched += 1;
        }
        return matched;
    }

    /// The stand-ins of the modules the table answered for: the same decision `candidate` makes, from the stored flags.
    fn decideMatched(self: *Plan, previous: *const summary.Index, state: *Decision) error{OutOfMemory}!void {
        const view = previous.sections orelse return;
        if (self.history.modules.matched.len == 0) return;
        const grouping = self.request.prepared.?.grouping;
        for (grouping.modules, self.history.modules.matched) |group, section| {
            if (section == no_section) continue;
            const first = view.firstOf(section);
            for (group.members, 0..) |instance, k| {
                if (instance == self.main) continue;
                const position = first + @as(u32, @intCast(k));
                if (!try self.standsIn(state, instance, position)) continue;
                self.stand_ins[instance] = position;
                self.request.stood_in += 1;
            }
        }
    }

    /// Whether the summary at `position` stands in for `instance`, in a module whose contexts, region digests and touched shapes are the
    /// stored ones: its kind admits a stand-in, and its templates and waiver guard are the fresh ones.
    fn standsIn(self: *const Plan, state: *Decision, instance: usize, position: u32) error{OutOfMemory}!bool {
        const flags = state.previous.flagsAt(position);
        const passes_only = self.request.policy.passes and flags.complete and !flags.holds.refs;
        if (!flags.stubbable and !passes_only) return false;
        if (flags.holds.refs) {
            const refs = state.previous.refsAt(position) orelse return false;
            if (!self.session.templatesStand(state.allocator, refs.templates, state.body_changes)) return false;
        }
        if (flags.holds.guard) {
            const expected = state.previous.guardAt(position) orelse return false;
            if (!try guardHolds(state.allocator, self.history.guards.?, self.session.src, self.regionOf(instance).start, expected)) return false;
        }
        return true;
    }

    /// Debug: the loop over every function gives the stand-ins the module answers gave.
    fn crossCheckDecision(self: *Plan, allocator: std.mem.Allocator, previous: *const summary.Index) error{OutOfMemory}!void {
        const saved = try allocator.dupe(?u32, self.stand_ins);
        defer allocator.free(saved);
        const counted = self.request.stood_in;
        @memset(self.stand_ins, null);
        const scratch = try allocator.alloc(?u32, self.stand_ins.len);
        defer allocator.free(scratch);
        var state = Decision.init(allocator, previous, self.request.policy.demand);
        defer state.deinit();
        const found = try self.decideLoop(&state, scratch, .all);
        std.debug.assert(std.mem.eql(?u32, saved, self.stand_ins));
        self.request.stood_in = counted;
        std.debug.assert(found == counted);
    }

    /// Whether the summary at `position` may stand in for function `ast_index`: its kind admits a stand-in and its context, region digest,
    /// touched shapes, templates and waiver guard are the fresh ones.
    fn candidate(self: *const Plan, state: *Decision, ast_index: usize, position: u32) error{OutOfMemory}!bool {
        const prepared = self.prepared;
        const stored = state.previous.at(position);
        // A function that cannot stand in whole may still stand in for its passes (G2k): its body is checked as usual. One whose tree
        // names a specialization or an interned type does so only once its references resolve, which is a stand-in in whole.
        const whole = stored.stubbable;
        const passes_only = self.request.policy.passes and stored.notes.complete and stored.uses.refs == null;
        if (!whole and !passes_only) return false;
        if (!std.mem.eql(u8, &stored.context, &prepared.contexts[ast_index])) return false;
        const region = prepared.regions[ast_index];
        if (region.end - region.start != stored.region.len) return false;
        if (!std.mem.eql(u8, &prepared.recalled.digests[ast_index], &stored.region.digest)) return false;
        if (!try touchedShapesMatch(self.session, state.previous, position, stored.uses, &state.shapes)) return false;
        if (stored.uses.refs) |refs| if (!self.session.templatesStand(state.allocator, refs.templates, state.body_changes)) return false;
        if (stored.notes.guard) |expected| {
            if (!try guardHolds(state.allocator, self.history.guards.?, self.session.src, region.start, expected)) return false;
        }
        return true;
    }

    /// Close changed declaration contracts and touched shapes over the checked
    /// dependency graph, including names syntax-only keys may not resolve.
    fn prepareConsumers(self: *Plan, allocator: std.mem.Allocator) error{OutOfMemory}!void {
        const previous = self.request.previous orelse return;
        self.history.affected = try allocator.alloc(bool, previous.count());
        @memset(self.history.affected, true);
        const body_changes = if (self.request.policy.demand) |demand| demand.body_dependencies else false;
        try self.affectedMatched(allocator, previous, self.history.affected, body_changes);
        try self.affectedLoop(allocator, previous, self.history.affected, .unmatched);
        if (builtin.mode == .debug and self.history.modules.matched.len != 0) {
            const expected = try allocator.alloc(bool, previous.count());
            defer allocator.free(expected);
            @memset(expected, true);
            try self.affectedLoop(allocator, previous, expected, .all);
            std.debug.assert(std.mem.eql(bool, expected, self.history.affected));
        }
        // A function stale only because a function it calls changed its body keeps its stored passes: the passes read the callees'
        // declarations alone (their inferred facts feed navigation and nothing else), and a declaration that changed is in the
        // function's own context. Its body is checked or replayed all the same, for the artifacts that read the callee's.
        const own = try allocator.dupe(bool, self.history.affected);
        defer allocator.free(own);
        // Nothing is stale (the usual edit): there is no consumer to close over, and the graph of the whole table is not built.
        if (std.mem.indexOfScalar(bool, self.history.affected, true) != null) try invalidateConsumers(allocator, previous, self.history.affected);
        const checked_bodies = try allocator.alloc(bool, self.stand_ins.len);
        @memset(checked_bodies, false);
        self.history.body_checked = checked_bodies;
        for (self.stand_ins, checked_bodies, 0..) |*stand, *body_checked, instance| {
            const position = stand.* orelse continue;
            if (!self.history.affected[position]) continue;
            if (!own[position] and self.request.policy.passes and previous.flagsAt(position).complete) {
                body_checked.* = true;
                self.session.keepBody(instance);
                continue;
            }
            stand.* = null;
            self.request.stood_in -= 1;
        }
    }

    /// `affected` for the functions of the modules the table answered for: their contexts and region digests are the stored ones, so a function
    /// is stale when its templates moved, or when it could have stood in and does not.
    fn affectedMatched(self: *const Plan, allocator: std.mem.Allocator, previous: *const summary.Index, affected: []bool, body_changes: bool) error{OutOfMemory}!void {
        const view = previous.sections orelse return;
        if (self.history.modules.matched.len == 0) return;
        const grouping = self.request.prepared.?.grouping;
        for (grouping.modules, self.history.modules.matched) |group, section| {
            if (section == no_section) continue;
            const first = view.firstOf(section);
            for (group.members, 0..) |instance, k| {
                const position = first + @as(u32, @intCast(k));
                const flags = previous.flagsAt(position);
                const templates_stand = if (flags.holds.refs) self.session.templatesStand(allocator, (previous.refsAt(position) orelse continue).templates, body_changes) else true;
                affected[position] = !templates_stand or (flags.stubbable and self.stand_ins[instance] == null and self.history.withheld[instance] == null);
            }
        }
    }

    /// `affected` by function, found by key: for every function, or for those of modules the table did not answer for.
    fn affectedLoop(self: *const Plan, allocator: std.mem.Allocator, previous: *const summary.Index, affected: []bool, visit: Visit) error{OutOfMemory}!void {
        const body_changes = if (self.request.policy.demand) |demand| demand.body_dependencies else false;
        var hint: u32 = 0;
        for (self.prepared.ordinary_ast, 0..) |ast_index, instance| {
            if (visit == .unmatched and self.matchedSection(instance) != null) continue;
            const position = previous.findNear(self.prepared.keys[ast_index], hint) orelse continue;
            hint = position + 1;
            const stored = previous.at(position);
            const templates_stand = if (stored.uses.refs) |refs| self.session.templatesStand(allocator, refs.templates, body_changes) else true;
            affected[position] = !std.mem.eql(u8, &stored.context, &self.prepared.contexts[ast_index]) or
                (body_changes and !std.mem.eql(u8, &stored.region.digest, &self.prepared.recalled.digests[ast_index])) or
                !templates_stand or
                (stored.stubbable and self.stand_ins[instance] == null and self.history.withheld[instance] == null and
                    std.mem.eql(u8, &stored.region.digest, &self.prepared.recalled.digests[ast_index]));
        }
    }

    /// Ask the lowering host which unchanged bodies have safe raw artifacts: once for each module that has a record, then for each candidate
    /// the module answers did not cover.
    fn prepareDemand(self: *Plan, allocator: std.mem.Allocator, inputs: Inputs) error{OutOfMemory}!void {
        const demand = &self.request.policy.demand.?;
        demand.omitted = try allocator.alloc(bool, self.stand_ins.len);
        @memset(demand.omitted, false);
        self.history.modules.covered = try self.askModules(allocator, inputs);
        for (self.stand_ins, 0..) |stand, instance| {
            if (!self.asksHost(instance, stand)) continue;
            const ast_index = self.prepared.ordinary_ast[instance];
            const key = self.prepared.keys[ast_index];
            if (self.history.modules.covered.len != 0 and self.history.modules.covered[instance]) {
                demand.omitted[instance] = true;
                self.crossCheck(instance);
                continue;
            }
            demand.omitted[instance] = demand.allow(demand.context, key, self.prepared.contexts[ast_index], self.prepared.recalled.digests[ast_index]);
        }
    }

    /// Whether the host is asked about ordinary instance `instance`: only a summary that stands in whole may have its body left out; one that
    /// stands in for the passes alone has its body checked.
    fn asksHost(self: *const Plan, instance: usize, stand: ?u32) bool {
        const position = stand orelse return false;
        if (!self.request.previous.?.flagsAt(position).stubbable) return false;
        return !(instance < self.history.body_checked.len and self.history.body_checked[instance]);
    }

    /// Group the functions by module and publish the groups in the request's prepared facts.
    fn groupModules(self: *Plan, allocator: std.mem.Allocator, inputs: Inputs) error{OutOfMemory}!void {
        const names = inputs.names orelse return;
        const groups_lap = Lap.start(inputs.timing);
        self.request.prepared.?.grouping = try module_groups.group(allocator, self.prepared, inputs.syntax, names);
        groups_lap.end("plan_groups");
    }

    /// Ask the host for each module that has a candidate. Returns which instances a module answer covered; empty when none was asked.
    fn askModules(self: *Plan, allocator: std.mem.Allocator, inputs: Inputs) error{OutOfMemory}![]const bool {
        const prepared = &self.request.prepared.?;
        const grouping = prepared.grouping;
        if (grouping.modules.len == 0) return &.{};
        const demand = &self.request.policy.demand.?;
        const ask = demand.allow_module orelse return &.{};
        const covered = try allocator.alloc(bool, self.stand_ins.len);
        @memset(covered, false);
        var widest: usize = 0;
        for (grouping.modules) |each| widest = @max(widest, each.members.len);
        const out = try allocator.alloc(bool, widest);
        const asks_lap = Lap.start(inputs.timing);
        defer asks_lap.end("plan_modules");
        for (grouping.modules) |each| {
            var wanted = false;
            for (each.members) |instance| wanted = wanted or self.asksHost(instance, self.stand_ins[instance]);
            if (!wanted) continue;
            const answer = out[0..each.members.len];
            @memset(answer, false);
            if (!ask(demand.context, each, answer)) continue;
            for (each.members, answer) |instance, bit| {
                covered[instance] = bit;
                prepared.grouping.covered += @intFromBool(bit);
            }
        }
        return covered;
    }

    /// A module answer is a shortcut for the host's answers about its functions, and may never say more. A Debug compiler asks the host about
    /// every function a module answer covered and holds the two together; a request that verifies does so for them all and counts a difference
    /// as a finding.
    fn crossCheck(self: *Plan, instance: usize) void {
        const demand = &self.request.policy.demand.?;
        const verifying = self.request.policy.verify.every != 0;
        if (builtin.mode != .debug and !verifying) return;
        const ast_index = self.prepared.ordinary_ast[instance];
        const key = self.prepared.keys[ast_index];
        const asked = demand.allow(demand.context, key, self.prepared.contexts[ast_index], self.prepared.recalled.digests[ast_index]);
        if (!verifying) return std.debug.assert(asked);
        self.request.policy.verify.compared += 1;
        if (asked) return;
        self.request.policy.verify.mismatched += 1;
        if (self.request.policy.verify.first.len == 0) self.request.policy.verify.first = key;
    }

    /// Hand a function back to the checker after a module answer covered it: the host's per-function state (the ownership host's record of
    /// what the planner passed) is what `allow` fills, so ask once.
    fn uncover(self: *const Plan, instance: usize) void {
        if (self.history.modules.covered.len == 0 or !self.history.modules.covered[instance]) return;
        const demand = &self.request.policy.demand.?;
        const ast_index = self.prepared.ordinary_ast[instance];
        _ = demand.allow(demand.context, self.prepared.keys[ast_index], self.prepared.contexts[ast_index], self.prepared.recalled.digests[ast_index]);
    }

    /// Keep bounded bodies and their callees concrete for Core allocation checks.
    /// Previous edges live in the previous table; remap by stable key, never by
    /// current declaration position. An unchanged body has its previous edges. A changed or new
    /// body has unknown new edges, so everything it can name is kept concrete: the functions of its
    /// own module and of every module it imports, transitively, which is all it can call (G2i). The
    /// same holds for a changed callee met on the way. Without the import structure (a program with
    /// no module graph) a changed bounded body conservatively requests concrete trees for the whole
    /// program (ordinary body reuse still works).
    pub fn requireAllocationBodies(self: *Plan, allocator: std.mem.Allocator, syntax: ast.Program, names: ?*Names) error{OutOfMemory}!void {
        const demanded = if (self.request.policy.demand) |demand| demand.allocation_contracts else false;
        if ((self.request.body_policy != .allocation_contracts and !demanded) or self.request.policy.declared) return;
        const previous = self.request.previous orelse return;
        const count = self.prepared.ordinary_ast.len;
        const needed = try allocator.alloc(bool, count);
        defer allocator.free(needed);
        @memset(needed, false);
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(allocator);
        for (self.prepared.ordinary_ast, 0..) |ast_index, instance| {
            if (ast.hasAttribute(syntax, syntax.functions[ast_index].name, .noalloc)) try pending.append(allocator, @intCast(instance));
        }
        var scope = ModuleScope{ .allocator = allocator, .names = names };
        defer scope.deinit();
        while (pending.pop()) |instance| {
            if (needed[instance]) continue;
            needed[instance] = true;
            const ast_index = self.prepared.ordinary_ast[instance];
            const unchanged = if (previous.find(self.prepared.keys[ast_index])) |position| blk: {
                const stored = previous.at(position);
                const same = std.mem.eql(u8, &stored.context, &self.prepared.contexts[ast_index]) and std.mem.eql(u8, &stored.region.digest, &self.prepared.recalled.digests[ast_index]);
                const templates_stand = if (stored.uses.refs) |refs| self.session.templatesStand(allocator, refs.templates, true) else true;
                break :blk if (same and templates_stand) position else null;
            } else null;
            if (unchanged) |position| {
                for (previous.calleesAt(position)) |callee| {
                    if (callee >= self.history.current.len) continue;
                    const next = self.history.current[callee] orelse continue;
                    if (!needed[next]) try pending.append(allocator, next);
                }
                continue;
            }
            if (!try scope.markReachable(self, syntax, instance, needed)) {
                self.history.allocation_fallback = true;
                self.request.body_policy = .concrete;
                if (self.request.policy.demand) |demand| @memset(demand.omitted, false);
                return;
            }
        }
        for (needed, self.stand_ins, 0..) |required, *position, instance| {
            if (required and position.* != null) {
                if (self.request.policy.demand) |demand| demand.omitted[instance] = false;
                self.uncover(instance);
                position.* = null;
                self.request.stood_in -= 1;
            }
        }
    }

    /// The end of a check's planning: the stood-in bodies' facts hold (`consistent`), the `W_COPY_MOVE` hints are judged against
    /// every caller (`judgeCopyMoves`), the summary table is produced, and the stood-in bodies' pass warnings are replayed and
    /// the hints a caller would refuse are left out of `sink`. False when the check must repeat in full.
    pub fn finish(self: *Plan, allocator: std.mem.Allocator, program: typed.Program, facts: []const origins.Fact, outputs: Outputs, sink: *diagnostic.Sink) error{ OutOfMemory, InternalError }!bool {
        if (!self.consistent(facts)) return false;
        const judged = try self.judgeCopyMoves(allocator, program, outputs.pass);
        if (judged) |found| if (found.missing) return false;
        var complete = outputs;
        if (judged) |found| complete.keeps = found.keeps;
        if (self.publishes()) self.request.produced = try self.produce(allocator, program, facts, complete);
        try self.replayPasses(sink);
        if (judged) |found| try found.leaveOut(self, program, sink);
        return true;
    }

    /// FR14b: judge each `W_COPY_MOVE` hint of the program, fresh or replayed from a stood-in body's notes, against every caller:
    /// a caller whose body was checked is asked now (`Policy.copy_moves`), and its answers are stored in its summary; a caller
    /// that stood in answers with what its summary stored. A stood-in caller is unchanged, with the callee's declaration in its
    /// dependency context, so its stored answer is the one asking it again would give; it lacks one only when the callee gained
    /// the hint while it stood in, and then the check repeats in full (`missing`). Null when the command judges no hints.
    fn judgeCopyMoves(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, pass: []const diagnostic.Diagnostic) error{OutOfMemory}!?CopyMoves {
        const judge = self.request.policy.copy_moves orelse return null;
        var found: CopyMoves = .{};
        var targets: std.ArrayList(summary.HintTarget) = .empty;
        for (pass) |item| try self.addTarget(allocator, program, &found, &targets, .{ .code = item.code, .message = item.message, .span = item.span });
        found.fresh = targets.items.len;
        if (self.request.previous) |previous| for (self.stand_ins, 0..) |stand, instance| {
            const position = stand orelse continue;
            if (!previous.flagsAt(position).notes.pass) continue;
            const start = self.regionOf(instance).start;
            for (previous.passNotesAt(position)) |note| {
                const span: source.Span = .{ .start = @intCast(start + note.start), .end = @intCast(start + note.end) };
                try self.addTarget(allocator, program, &found, &targets, .{ .code = note.code, .message = note.message, .span = span });
            }
        };
        if (targets.items.len == 0) return found;
        const answers = try judge.facts(judge.context, allocator, program, self.session.src, targets.items);
        const keeps = try allocator.alloc(std.ArrayList(summary.Keep), self.stand_ins.len);
        @memset(keeps, .empty);
        for (targets.items, answers, found.names.items) |target, list, name| for (list) |answer| {
            // A `W_COPY_FOR_STORE` target also asks whether the caller passes a new value or a name it gives up, and where the
            // repair writes `own ` in it (`copy_for_store.callerMarks`); the marks are stored relative to its region.
            const marks: ?[]const u32 = if (target.store and answer.caller < program.functions.len)
                try copy_for_store.callerMarks(allocator, program, program.functions[answer.caller], target.callee, target.position)
            else
                &.{};
            const keeping = answer.keeps or marks == null or
                // A caller that also names the function as a value keeps a `from` target (`E_VIEW_FUNCTION_VALUE`).
                (target.result and answer.caller < program.functions.len and
                    try copy_from_repair.namesAsValue(allocator, program, program.functions[answer.caller], target.callee));
            if (keeping) try found.kept.put(allocator, name.key, {});
            if (target.store) try found.answered.put(allocator, name.key, {});
            if (!keeping) try found.mark(allocator, name.key, marks.?, 0);
            if (answer.caller >= keeps.len) continue;
            const relative = if (keeping) &.{} else try self.relativeMarks(allocator, answer.caller, marks.?);
            try keeps[answer.caller].append(allocator, .{ .callee = name.callee, .parameter = name.parameter, .result = target.result, .keeps = keeping, .marks = relative });
        };
        try self.answerNamedCallers(allocator, program, targets.items, &found, keeps);
        const out = try allocator.alloc([]const summary.Keep, keeps.len);
        for (keeps, out) |list, *slot| slot.* = list.items;
        found.keeps = out;
        try self.storedAnswers(allocator, program, &found, targets.items);
        return found;
    }

    /// `marks` (starts in the program's source) relative to the start of the declaration region of instance `caller`.
    fn relativeMarks(self: *const Plan, allocator: std.mem.Allocator, caller: usize, marks: []const u32) error{OutOfMemory}![]const u32 {
        if (marks.len == 0) return &.{};
        const start = self.regionOf(caller).start;
        const relative = try allocator.alloc(u32, marks.len);
        for (relative, marks) |*slot, mark| slot.* = @intCast(mark - start);
        return relative;
    }

    /// A checked body's stored callees (`storedCallTargets`) also hold the functions it names as values, which the filter does
    /// not count as callers. Each such caller of a target's function gets the answer "keeps nothing", so a later check that
    /// stands it in finds an answer for every target its callees hold; for a `W_COPY_FOR_STORE` target the answer is "keeps":
    /// a function named as a value may be called with anything.
    fn answerNamedCallers(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, targets: []const summary.HintTarget, found: *CopyMoves, keeps: []std.ArrayList(summary.Keep)) error{OutOfMemory}!void {
        // The targets of each function, so a body's callees are each looked up once rather than searched for every target.
        var of_callee: std.AutoHashMapUnmanaged(u32, std.ArrayList(u32)) = .empty;
        for (targets, 0..) |target, index| {
            const entry = try of_callee.getOrPut(allocator, @intCast(target.callee));
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            try entry.value_ptr.append(allocator, @intCast(index));
        }
        var named: std.ArrayList(u32) = .empty;
        for (self.checked.items) |record| {
            if (record.instance >= keeps.len) continue;
            const callees = try storedCallTargets(allocator, program, record, keeps.len);
            named.clearRetainingCapacity();
            for (callees) |callee| if (of_callee.get(callee)) |list| try named.appendSlice(allocator, list.items);
            // In target order, as a search of every target answers them.
            std.mem.sort(u32, named.items, {}, std.sort.asc(u32));
            for (named.items, 0..) |index, at| {
                if (at > 0 and named.items[at - 1] == index) continue;
                const target = targets[index];
                const name = found.names.items[index];
                if (answered(keeps[record.instance].items, name, target.result)) continue;
                // A function with a `from` result cannot be named as a value (`E_VIEW_FUNCTION_VALUE`), so the use keeps the
                // `from` hint's target and `W_COPY_RETURNED`'s, as it keeps `W_COPY_FOR_STORE`'s.
                const keeping = target.store or target.result;
                try keeps[record.instance].append(allocator, .{ .callee = name.callee, .parameter = name.parameter, .result = target.result, .keeps = keeping });
                if (!keeping) continue;
                if (target.store) try found.answered.put(allocator, name.key, {});
                try found.kept.put(allocator, name.key, {});
            }
        }
    }

    /// Add the target of one diagnostic when it is a judged hint inside an ordinary function's body.
    fn addTarget(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, found: *CopyMoves, targets: *std.ArrayList(summary.HintTarget), hint: Hint) error{OutOfMemory}!void {
        const target = self.hintTarget(program, hint.code, hint.message, hint.span) orelse return;
        const name = try self.targetName(allocator, program, target);
        if ((try found.seen.getOrPut(allocator, name.key)).found_existing) return;
        try targets.append(allocator, target);
        try found.names.append(allocator, name);
    }

    /// The target of a judged hint at `span`: the ordinary function whose declaration region holds it and the position of the
    /// parameter its advice names. A stood-in function keeps its parameters, so a replayed hint finds its function too.
    fn hintTarget(self: *const Plan, program: typed.Program, code: []const u8, message: []const u8, span: source.Span) ?summary.HintTarget {
        const judged = needless_copy.judgedByCallers(code, message) orelse copy_for_store.judged(code, message) orelse
            copy_from_repair.judged(code, message) orelse return null;
        const store = std.mem.eql(u8, code, copy_for_store.code);
        const strict = std.mem.eql(u8, code, copy_from_repair.code);
        for (0..@min(self.stand_ins.len, program.functions.len)) |instance| {
            const function = program.functions[instance];
            // The declaration's region, not the checked body's statement: a checked body may be a statement the checker made
            // (a fallible function's), whose span is not the source body's.
            const region = self.regionOf(instance);
            if (span.start < region.start or span.end > region.end) continue;
            const count = @min(function.signature.parameter_count, function.scope.locals.len);
            // A function with no body of its own (a host or conversion declaration) may name a statement that spans other bodies,
            // so a function whose parameters lack the name is passed over, as `src/main.zig: copyMoveKept` does.
            for (function.scope.locals[0..count], 0..) |local, position| {
                if (std.mem.eql(u8, local.name, judged.parameter)) return .{ .callee = instance, .result = judged.form == .result, .position = position, .store = store, .strict = strict };
            }
        }
        return null;
    }

    /// What names a target across checks: the callee's stable key and the parameter, and one string of both and the advice.
    fn targetName(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, target: summary.HintTarget) error{OutOfMemory}!TargetName {
        const callee = self.prepared.keys[self.prepared.ordinary_ast[target.callee]];
        const name = program.functions[target.callee].scope.locals[target.position].name;
        // A `W_COPY_FOR_STORE` target asks a stricter question than the `for x in own` hint of the same parameter (a new
        // value at every call), so its answers are stored under their own name, which no parameter can spell.
        // A `W_COPY_RETURNED` target asks a stricter question than the `from` hint beside it (a caller refused for any reason):
        // its answers are stored under `from NAME`.
        const parameter = if (target.store)
            try std.fmt.allocPrint(allocator, "own {s}", .{name})
        else if (target.strict)
            try std.fmt.allocPrint(allocator, "from {s}", .{name})
        else
            name;
        return .{ .callee = callee, .parameter = parameter, .key = try keepKey(allocator, callee, parameter, target.result), .store = target.store };
    }

    /// The stored answers of the callers that stood in whole: a keeper among them leaves its hint out, and one that calls the
    /// function of a fresh target with no answer for it makes the check repeat (`CopyMoves.missing`). A replayed target needs no
    /// such look: its function and that caller both stood in, and whichever of their summaries is the later was made by a check
    /// that judged this hint with that caller's body or found the answer missing and repeated in full.
    fn storedAnswers(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, found: *CopyMoves, targets: []const summary.HintTarget) error{OutOfMemory}!void {
        const previous = self.request.previous orelse return;
        // The targets by their function's position in the previous table, chained: `first` per position, `next` per target.
        const first = try allocator.alloc(?u32, previous.count());
        @memset(first, null);
        const next = try allocator.alloc(?u32, targets.len);
        @memset(next, null);
        for (found.names.items[0..found.fresh], 0..) |name, index| {
            const position = previous.find(name.callee) orelse continue;
            next[index] = first[position];
            first[position] = @intCast(index);
        }
        for (self.stand_ins, 0..) |stand, instance| {
            const position = stand orelse continue;
            if (instance < program.functions.len and program.functions[instance].scope.body_complete) continue;
            const stored = if (previous.flagsAt(position).holds.keeps) previous.keepsAt(position) else &.{};
            for (stored) |keep| {
                // A `W_COPY_FOR_STORE` answer is stored under `own NAME` (`targetName`); only those count as answered.
                const store = std.mem.startsWith(u8, keep.parameter, "own ");
                if (!keep.keeps and !store) continue;
                const key = try keepKey(allocator, keep.callee, keep.parameter, keep.result);
                if (keep.keeps) try found.kept.put(allocator, key, {});
                if (store) try found.answered.put(allocator, key, {});
                if (store and !keep.keeps) try found.mark(allocator, key, keep.marks, @intCast(self.regionOf(instance).start));
            }
            if (found.fresh == 0) continue;
            for (previous.calleesAt(position)) |callee| {
                if (callee >= first.len or callee == position) continue;
                var at = first[callee];
                while (at) |index| : (at = next[index]) {
                    if (!answered(stored, found.names.items[index], targets[index].result)) found.missing = true;
                }
            }
        }
    }

    /// The position of the previous summary standing in for ordinary instance `i`'s cross-function facts, or null when the passes compute them.
    pub fn standInPosition(self: *const Plan, i: usize) ?u32 {
        if (i >= self.stand_ins.len) return null;
        return self.stand_ins[i];
    }

    /// The previous summary standing in for ordinary instance `i`'s cross-function facts, or null when the passes compute them.
    pub fn standIn(self: *const Plan, i: usize) ?*const summary.Summary {
        const position = self.standInPosition(i) orelse return null;
        return self.request.previous.?.at(position);
    }

    /// The position of the previous summary standing in for ordinary instance `i`'s whole body, or null when checking needs its tree. A
    /// lowering host must admit a safe persisted artifact before a demand request may omit the body.
    pub fn bodyStandInPosition(self: *const Plan, i: usize) ?u32 {
        if (self.history.allocation_fallback) return null;
        if (i < self.history.body_checked.len and self.history.body_checked[i]) return null;
        if (self.request.policy.demand) |demand| {
            if (i >= demand.omitted.len or !demand.omitted[i]) return null;
        } else if (self.request.body_policy == .concrete) return null;
        const position = self.standInPosition(i) orelse return null;
        return if (self.request.previous.?.flagsAt(position).stubbable) position else null;
    }

    /// Whether ordinary instance `i`'s whole body is stood in for by a previous summary.
    pub fn bodyStandsIn(self: *const Plan, i: usize) bool {
        return self.bodyStandInPosition(i) != null;
    }

    /// The ordinary instances that the bodies standing in whole name as function values. Those bodies were not checked here, so the checked
    /// program holds none of their `function_value` nodes, and the previous table says what they named.
    pub fn standInValues(self: *const Plan, allocator: std.mem.Allocator) error{OutOfMemory}![]const u32 {
        const previous = self.request.previous orelse return &.{};
        var named: std.ArrayList(u32) = .empty;
        for (0..self.stand_ins.len) |instance| {
            const position = self.bodyStandInPosition(instance) orelse continue;
            try named.appendSlice(allocator, try remapCallees(allocator, previous.valuesAt(position), self.history.current));
        }
        return named.toOwnedSlice(allocator);
    }

    /// Whether any body is stood in by a summary in this request.
    pub fn active(self: *const Plan) bool {
        return self.request.stood_in != 0;
    }

    /// Mark the imports every stood-in body's recorded references go through. A body that is
    /// stood in is never resolved again, so without this `W_UNUSED_IMPORT` would name an import
    /// only such a body uses. Names come from the same syntax walk that keys the body's context.
    pub fn noteImportUses(self: *const Plan, index: *interfaces.Index, src: source.Source, syntax: ast.Program) void {
        for (self.prepared.ordinary_ast, 0..) |ast_index, instance| {
            if (!self.bodyStandsIn(instance)) continue;
            const module = if (src.origins.len == 0) 0 else (src.originalSpan(syntax.functions[ast_index].name) catch continue).input;
            for (self.prepared.recalled.names[ast_index]) |name| index.noteReferenceUse(module, name.text, name.owner);
        }
    }

    /// Replay the diagnostics a stood-in body produced while it was checked.
    pub fn replayBody(self: *const Plan, i: usize, sink: *diagnostic.Sink) error{OutOfMemory}!void {
        const position = self.bodyStandInPosition(i) orelse return;
        const previous = self.request.previous.?;
        if (!previous.flagsAt(position).notes.body) return;
        const start = self.regionOf(i).start;
        for (previous.bodyNotesAt(position)) |note| try sink.items.append(sink.allocator, try summary.diagnosticOf(sink.allocator, note, start));
    }

    /// Replay the warnings the whole-program passes reported inside every
    /// stood-in body; those passes skip stood-in bodies.
    pub fn replayPasses(self: *const Plan, sink: *diagnostic.Sink) error{OutOfMemory}!void {
        for (0..self.stand_ins.len) |i| {
            const position = self.stand_ins[i] orelse continue;
            const previous = self.request.previous.?;
            if (!previous.flagsAt(position).notes.pass) continue;
            const start = self.regionOf(i).start;
            for (previous.passNotesAt(position)) |note| try sink.items.append(sink.allocator, try summary.diagnosticOf(sink.allocator, note, start));
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
        const previous = self.request.previous.?;
        for (0..@min(self.stand_ins.len, function_count)) |i| {
            if (self.stand_ins[i]) |position| stubs[i] = summary.toFact(previous.factAt(position));
        }
        return stubs;
    }

    /// Whether checked bodies still agree with their retained local facts.
    /// Calls read declarations, so cycles through stood-in bodies do not form a
    /// summary fixed point and need no special invalidation fallback.
    pub fn consistent(self: *const Plan, facts: []const origins.Fact) bool {
        if (!self.active()) return true;
        const previous = self.request.previous.?;
        for (self.prepared.ordinary_ast, 0..) |ast_index, instance| {
            if (self.stand_ins[instance] != null or instance >= facts.len) continue;
            const position = previous.find(self.prepared.keys[ast_index]) orelse continue;
            const body_changes = if (self.request.policy.demand) |demand| demand.body_dependencies else false;
            // With a lowering host whose artifacts read no fact of an edited body, that body has the facts its new text gives it: nothing that
            // stands in reads them (the passes read the callees' declarations alone), so they are not held against the old ones. Without
            // this an edit that changes what a function writes repeats the whole check.
            const edited = !std.mem.eql(u8, &previous.regionAt(position).digest, &self.prepared.recalled.digests[ast_index]);
            const unread = if (self.request.policy.demand) |demand| demand.facts_unread else false;
            if (unread and edited) continue;
            if (body_changes and position < self.history.affected.len and self.history.affected[position]) continue;
            if (!summary.sameFact(summary.fromFact(facts[instance]), previous.factAt(position))) return false;
        }
        return true;
    }

    /// Previous table position -> this request's ordinary instance.
    fn currentPositions(self: *const Plan, allocator: std.mem.Allocator) error{OutOfMemory}![]const ?u32 {
        const previous = self.request.previous orelse return &.{};
        const current = try allocator.alloc(?u32, previous.count());
        @memset(current, null);
        if (previous.sections) |view| if (self.history.modules.matched.len != 0) {
            // A module the table answered for is the same functions in the same order: position by position.
            for (self.request.prepared.?.grouping.modules, self.history.modules.matched) |group, section| {
                if (section == no_section) continue;
                for (group.members, view.firstOf(section)..) |instance, position| current[position] = instance;
            }
        };
        var hint: u32 = 0;
        for (self.prepared.ordinary_ast, 0..) |ast_index, instance| {
            if (self.matchedSection(instance) != null) continue;
            if (previous.findNear(self.prepared.keys[ast_index], hint)) |position| {
                current[position] = @intCast(instance);
                hint = position + 1;
            }
        }
        return current;
    }

    /// Compare each function withheld from standing in (verify sampling) with the summary that would have stood in for it: the same facts
    /// and the same pass warnings and, for one that would have stood in whole, the same body diagnostics and the same references to the
    /// catalog. A function whose consumers changed is not compared, as `consistent` does not compare it. The counts go back to the
    /// request's policy.
    pub fn verifyWithheld(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, facts: []const origins.Fact, pass_items: []const diagnostic.Diagnostic) error{ OutOfMemory, InternalError }!void {
        if (self.history.withheld.len == 0) return;
        const previous = self.request.previous orelse return;
        const body_changes = if (self.request.policy.demand) |demand| demand.body_dependencies else false;
        const pass = try allocator.dupe(diagnostic.Diagnostic, pass_items);
        std.mem.sort(diagnostic.Diagnostic, pass, {}, startsBefore);
        var checked_at: std.AutoHashMapUnmanaged(usize, usize) = .empty;
        for (self.checked.items, 0..) |record, position| try checked_at.put(allocator, record.instance, position);
        const verify = &self.request.policy.verify;
        for (self.history.withheld, 0..) |held, instance| {
            const position = held orelse continue;
            if (instance >= facts.len) continue;
            if (body_changes and position < self.history.affected.len and self.history.affected[position]) continue;
            const stored = previous.at(position).*;
            const region = self.regionOf(instance);
            var complete = true;
            const notes = try notesIn(allocator, passItemsIn(pass, region), region, &complete);
            verify.compared += 1;
            const what: ?[]const u8 = if (!complete)
                "pass warnings that cannot be stored"
            else if (!summary.sameFact(summary.fromFact(facts[instance]), stored.fact))
                "facts"
            else if (!sameNotes(notes, stored.notes.pass))
                "pass warnings"
            else if (stored.stubbable)
                try self.bodyDifference(allocator, program, checked_at.get(instance), .{ .stored = stored, .position = position })
            else
                null;
            const found = what orelse continue;
            verify.mismatched += 1;
            if (verify.first.len == 0) verify.first = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ stored.key, found });
        }
    }

    /// What differs between the body a withheld whole stand-in was checked as and its summary: the diagnostics it reports, the functions it
    /// names as values or the specializations and types it needs; null when nothing, and for a body that was not checked in this request (it
    /// failed).
    fn bodyDifference(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, at: ?usize, held: Held) error{ OutOfMemory, InternalError }!?[]const u8 {
        const checked_at = at orelse return null;
        const stored = held.stored;
        const record = self.checked.items[checked_at];
        const region = self.regionOf(record.instance);
        var complete = true;
        if (!sameNotes(try notesIn(allocator, record.diagnostics, region, &complete), stored.notes.body)) return "body diagnostics";
        const named = try remapCallees(allocator, self.request.previous.?.valuesAt(held.position), self.history.current);
        const fresh_values = try storedValueTargets(allocator, program, record, self.prepared.ordinary_ast.len);
        if (!sameTargets(fresh_values, named)) return "function values";
        const refs = stored.uses.refs orelse return null;
        const fresh = try self.session.summaryRefs(allocator, program, record.instance, .{ .nodes = record.nodes, .statements = record.statements });
        return if (sameRefs(fresh, refs)) null else "references";
    }

    /// A withheld stand-in: the summary that would have stood in and its position in the previous table.
    const Held = struct { stored: summary.Summary, position: u32 };

    /// Whether this request should publish a summary table. A command that
    /// lowers publishes one only when it had none to stand in (or repeated in
    /// full), so the next such command does not repeat the passes again.
    pub fn publishes(self: *const Plan) bool {
        return self.history.allocation_fallback or self.request.policy.demand != null or self.request.body_policy != .concrete or self.request.previous == null;
    }

    /// This request's summary table, one entry per ordinary instance in order, cut into one section per module. A module the previous table
    /// holds exactly (every function stands in, in its place, and none was made stale) is a section that is stored as it was: its rows here
    /// carry the key, facts and flags, and nothing is decoded for it.
    pub fn produce(self: *Plan, allocator: std.mem.Allocator, program: typed.Program, facts: []const origins.Fact, outputs: Outputs) error{ OutOfMemory, InternalError }!summary.Table {
        const count = self.prepared.ordinary_ast.len;
        const table = try allocator.alloc(summary.Summary, count);
        var production: Production = .{};
        const current = self.history.current;
        const records = try allocator.alloc(?usize, count);
        @memset(records, null);
        for (self.checked.items, 0..) |record, position| {
            if (record.instance < count) {
                records[record.instance] = position;
            } else try production.instances.put(allocator, record.instance, position);
        }
        const pass = try allocator.dupe(diagnostic.Diagnostic, outputs.pass);
        std.mem.sort(diagnostic.Diagnostic, pass, {}, startsBefore);
        const layout = try self.layoutSections(allocator);
        const reused = try allocator.alloc(bool, count);
        @memset(reused, false);
        for (layout) |section| {
            if (section.reuse == null) continue;
            for (section.members) |instance| reused[instance] = true;
        }
        for (0..count) |instance| {
            if (reused[instance]) {
                table[instance] = self.lightRow(instance);
                continue;
            }
            if (self.standIn(instance)) |stored| {
                table[instance] = stored.*;
                const callees = self.request.previous.?.calleesAt(self.stand_ins[instance].?);
                table[instance].uses.callees = try remapCallees(allocator, callees, current);
                const values = self.request.previous.?.valuesAt(self.stand_ins[instance].?);
                table[instance].uses.values = try remapCallees(allocator, values, current);
                if (table[instance].uses.callees.len != callees.len or table[instance].uses.values.len != values.len) {
                    table[instance].stubbable = false;
                    table[instance].notes.complete = false;
                }
                table[instance].uses.records = try production.names.carry(allocator, self.request.previous.?, self.stand_ins[instance].?, stored.uses.records);
                // A function that stood in for its passes alone had its body checked, and its answers are this check's.
                if (instance < outputs.keeps.len and outputs.keeps[instance].len != 0) table[instance].notes.keeps = outputs.keeps[instance];
                continue;
            }
            const record = if (records[instance]) |position| self.checked.items[position] else null;
            table[instance] = try self.checkedSummary(allocator, program, .{ .instance = instance, .record = record, .fact = if (instance < facts.len) facts[instance] else .{} }, pass, outputs);
            if (record) |checked_record| try self.touched(allocator, program, checked_record, &production, &table[instance]);
        }
        if (builtin.mode == .debug) for (layout) |section| {
            if (section.reuse == null) continue;
            for (section.members) |instance| self.expectLightRow(table[instance], instance);
        };
        return .{ .records = production.names.list.items, .record_shapes = production.names.shapes.items, .summaries = table, .sections = layout };
    }

    /// Debug: a function of a section stored as it was is what the summary stored for it says it is.
    fn expectLightRow(self: *const Plan, row: summary.Summary, instance: usize) void {
        const full = self.request.previous.?.at(self.stand_ins[instance].?).*;
        std.debug.assert(std.mem.eql(u8, full.key, row.key));
        std.debug.assert(std.mem.eql(u8, &full.context, &row.context));
        std.debug.assert(full.region.len == row.region.len);
        std.debug.assert(std.mem.eql(u8, &full.region.digest, &row.region.digest));
        std.debug.assert(summary.sameFact(full.fact, row.fact));
        std.debug.assert(full.stubbable == row.stubbable);
        std.debug.assert(full.notes.complete == row.notes.complete);
    }

    /// The row of a function in a section stored as it was: what the readers of a produced table ask of every function.
    fn lightRow(self: *const Plan, instance: usize) summary.Summary {
        const ast_index = self.prepared.ordinary_ast[instance];
        const position = self.stand_ins[instance].?;
        const previous = self.request.previous.?;
        const flags = previous.flagsAt(position);
        return .{
            .key = self.prepared.keys[ast_index],
            .context = self.prepared.contexts[ast_index],
            .region = .{ .len = @intCast(self.regionOf(instance).end - self.regionOf(instance).start), .digest = self.prepared.recalled.digests[ast_index] },
            .fact = previous.factAt(position),
            .notes = .{ .complete = flags.complete },
            .stubbable = flags.stubbable,
        };
    }

    /// How the table is cut into sections: one per module group, in module order, then one for the functions no module could be told for.
    /// None when the request has no module groups (the stored table then cuts by the module the keys name). A section is marked `reuse`
    /// when it is the previous table's section for the module and every function of it stands in at its place and is not stale.
    fn layoutSections(self: *Plan, allocator: std.mem.Allocator) error{OutOfMemory}![]const summary.OutSection {
        const grouping = self.request.prepared.?.grouping;
        if (grouping.modules.len == 0) return &.{};
        const extra = std.mem.count(u32, grouping.module_of, &.{semantic_key.no_group});
        const out = try allocator.alloc(summary.OutSection, grouping.modules.len + @intFromBool(extra != 0));
        const previous = self.request.previous;
        var kept: u32 = 0;
        defer self.request.prepared.?.grouping.kept = kept;
        for (grouping.modules, out[0..grouping.modules.len], 0..) |group, *section, index| {
            section.* = .{ .name = group.module, .signature = group.signature, .members = group.members };
            const view = (previous orelse continue).sections orelse continue;
            // A pool that has outgrown what it held when it was built is not carried over: the table is written afresh.
            if (view.needsRebuild()) continue;
            const matched = if (self.history.modules.matched.len != 0) self.history.modules.matched[index] else no_section;
            if (matched == no_section or !self.keepsSection(view, matched, group.members)) continue;
            section.reuse = matched;
            kept += 1;
        }
        if (extra != 0) {
            const members = try allocator.alloc(u32, extra);
            var next: usize = 0;
            for (grouping.module_of, 0..) |group, instance| {
                if (group != semantic_key.no_group) continue;
                members[next] = @intCast(instance);
                next += 1;
            }
            var hasher = sections_mod.SignatureHasher.init(sections_mod.ungrouped, members.len);
            for (members) |instance| {
                const ast_index = self.prepared.ordinary_ast[instance];
                hasher.add(self.prepared.contexts[ast_index], self.prepared.recalled.digests[ast_index]);
            }
            out[grouping.modules.len] = .{ .name = sections_mod.ungrouped, .signature = hasher.final(), .members = members };
        }
        return out;
    }

    /// Whether every function of `members` stands in at its place in `section` and none was made stale (a stale consumer of a function that
    /// is gone is written afresh, without the callee).
    fn keepsSection(self: *const Plan, view: *sections_mod.Sections, section: u32, members: []const u32) bool {
        const first = view.firstOf(section);
        for (members, 0..) |instance, k| {
            const position = first + @as(u32, @intCast(k));
            if ((self.stand_ins[instance] orelse return false) != position) return false;
            if (position < self.history.affected.len and self.history.affected[position]) return false;
        }
        return true;
    }

    /// The record names of the table being produced, and the checked specializations by function index.
    const Production = struct {
        names: RecordNames = .{},
        instances: std.AutoHashMapUnmanaged(usize, usize) = .empty,
    };

    /// Record the catalog records one checked body's tree touched and their
    /// combined shape; a tree that touched a record without a stable name or
    /// shape is not stubbable. A tree that names a specialization or a type interned while checking records what a fresh catalog needs to
    /// have them again (G2m), and its callees include those of the specializations it reaches.
    fn touched(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, record: Checked, production: *Production, entry: *summary.Summary) error{ OutOfMemory, InternalError }!void {
        const names = &production.names;
        const initial = self.session.remap.initial_record_count;
        var refs: ?summary.Refs = null;
        const indices = (try treeRecords(allocator, program, record, self.prepared.ordinary_ast.len, initial)) orelse blk: {
            const found = (try self.session.summaryRefs(allocator, program, record.instance, .{ .nodes = record.nodes, .statements = record.statements })) orelse {
                entry.stubbable = false;
                return;
            };
            var declared: std.ArrayList(usize) = .empty;
            for (found.records) |reference| if (reference.index < initial) try declared.append(allocator, reference.index);
            refs = found;
            break :blk declared.items;
        };
        const positions = try allocator.alloc(u32, indices.len);
        for (indices, positions) |index, *position| {
            const name = (try self.session.recordIdentity(allocator, index)) orelse {
                entry.stubbable = false;
                return;
            };
            const digest = (try self.session.shapeOf(name)) orelse {
                entry.stubbable = false;
                return;
            };
            position.* = try names.intern(allocator, name, digest);
        }
        entry.uses.records = positions;
        const found = refs orelse return;
        const through = try self.throughInstances(allocator, program, record, production, found);
        entry.uses.refs = through.refs;
        if (through.callees.len != 0) entry.uses.callees = try std.mem.concat(allocator, u32, &.{ entry.uses.callees, through.callees });
        if (!through.complete) entry.stubbable = false;
    }

    const Through = struct { refs: summary.Refs, callees: []const u32, complete: bool };

    /// The ordinary functions the specializations a body names call, directly or through further specializations, and the templates
    /// those come from: the body is stale when any of them is, as it would be if it called them itself. Incomplete when a
    /// specialization it reaches was not checked in this request.
    fn throughInstances(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, record: Checked, production: *const Production, found: summary.Refs) error{ OutOfMemory, InternalError }!Through {
        const count = self.prepared.ordinary_ast.len;
        var callees: std.ArrayList(u32) = .empty;
        var templates: std.ArrayList(summary.Template) = .empty;
        try templates.appendSlice(allocator, found.templates);
        var visited: std.AutoHashMapUnmanaged(usize, void) = .empty;
        var pending: std.ArrayList(usize) = .empty;
        var complete = true;
        for (try callTargets(allocator, program, record)) |target| if (target >= count) try pending.append(allocator, target);
        while (pending.pop()) |id| {
            if ((try visited.getOrPut(allocator, id)).found_existing) continue;
            const position = production.instances.get(id) orelse {
                complete = false;
                continue;
            };
            for (try callTargets(allocator, program, self.checked.items[position])) |target| {
                if (target >= count) {
                    try pending.append(allocator, target);
                } else if (std.mem.indexOfScalar(u32, callees.items, target) == null and target != record.instance) try callees.append(allocator, target);
            }
            const resolver = self.session.reuse.resolver orelse {
                complete = false;
                continue;
            };
            const reference = (try resolver.capture(resolver.context, @fromBackingInt(id))) orelse {
                complete = false;
                continue;
            };
            const template = reference.template orelse continue;
            for (templates.items) |known| if (std.mem.eql(u8, known.key, template)) break else {
                const at = self.session.templateAst(allocator, template) orelse {
                    complete = false;
                    break;
                };
                try templates.append(allocator, .{ .key = template, .context = self.prepared.contexts[at], .digest = self.prepared.recalled.digests[at] });
                break;
            };
        }
        return .{ .refs = .{ .functions = found.functions, .records = found.records, .templates = templates.items }, .callees = callees.items, .complete = complete };
    }

    /// Register the specializations and intern the types every body that stands in whole names, as the bodies would have: the body is
    /// neither checked nor replayed, so nothing else would. A body whose references do not resolve (a template or a record changed in
    /// a way its context does not show, a specialization the store no longer holds) does not stand in, and is checked like any other.
    pub fn resolveStandIns(self: *Plan, allocator: std.mem.Allocator) error{ OutOfMemory, InternalError }!void {
        const previous = self.request.previous orelse return;
        for (self.stand_ins, 0..) |stand, instance| {
            const position = stand orelse continue;
            if (!previous.flagsAt(position).holds.refs) continue;
            const refs = previous.refsAt(position) orelse continue;
            if (!self.bodyStandsIn(instance)) continue;
            if (try self.resolves(allocator, instance, refs)) continue;
            self.stand_ins[instance] = null;
            self.request.stood_in -= 1;
            if (self.request.policy.demand) |*demand| {
                if (instance < demand.omitted.len) demand.omitted[instance] = false;
            }
            self.uncover(instance);
        }
    }

    fn resolves(self: *Plan, allocator: std.mem.Allocator, instance: usize, refs: summary.Refs) error{ OutOfMemory, InternalError }!bool {
        // The function stands in, so its key, context and region are those the summary was stored under.
        const ast_index = self.prepared.ordinary_ast[instance];
        const region = self.regionOf(instance);
        const old: source.Span = .{ .start = 0, .end = region.end - region.start };
        var last: usize = 0;
        for (refs.records) |reference| last = @max(last, reference.index + 1);
        const meta: entry_types.Metadata = .{
            .identity = .{ .key = self.prepared.keys[ast_index], .context = self.prepared.contexts[ast_index], .body = old, .region = old },
            .old_function_count = 0,
            .old_record_count = last,
            .function_refs = refs.functions,
            .record_refs = refs.records,
        };
        if (!entry_types.validTypeRecipes(meta, semantic_store.max_declarations)) return false;
        return switch (try self.session.resolveRefs(allocator, refs.functions, refs.records, old, self.regionOf(instance))) {
            .ok => true,
            .miss => false,
        };
    }

    /// One checked ordinary instance's summary.
    fn checkedSummary(self: *const Plan, allocator: std.mem.Allocator, program: typed.Program, checked: CheckedInstance, pass: []const diagnostic.Diagnostic, outputs: Outputs) error{ OutOfMemory, InternalError }!summary.Summary {
        const ast_index = self.prepared.ordinary_ast[checked.instance];
        const region = self.prepared.regions[ast_index];
        // The module-local part of the flag: the function was checked here, is not the entry point and every diagnostic inside it is stored.
        // Whole stand-in adds the declaration kind and the types the tree names. A stored repair, or a site a waiver silenced, holds only
        // while the waivers that decide the idiom warnings are the ones it was made under (the guard).
        var standable = checked.instance != self.main and checked.record != null;
        // A body that kept a typed hole as a trap (a debug build, `selka test`) is never stood in, whole or for its passes: a check that
        // refuses holes must meet the hole again (`E_TYPED_HOLE`), and the summary this request publishes outlives its hole mode.
        if (checked.record) |record| if (holdsHole(program, record.nodes)) {
            standable = false;
        };
        const silenced = anyStartsIn(outputs.silenced, region);
        const reads_file = anyStartsIn(outputs.file_reads, region);
        const body_notes = try notesIn(allocator, if (checked.record) |record| record.diagnostics else &.{}, region, &standable);
        const pass_notes = try notesIn(allocator, passItemsIn(pass, region), region, &standable);
        // Any stored warning holds only while the waivers of its file are the ones it was made under, an edit or none (a warning
        // with no edit was once left unguarded, and a file waiver added later did not silence it: FX13). A site decided by
        // reading the rest of its file holds only while the whole file is as it was.
        const noted = silenced or body_notes.len != 0 or pass_notes.len != 0;
        const guard: ?[32]u8 = if (!standable)
            null
        else if (reads_file)
            try wideGuardOf(allocator, self.history.guards.?, self.session.src, region.start)
        else if (noted)
            try guardOf(allocator, self.history.guards.?, self.session.src, region.start)
        else
            null;
        var stubbable = standable;
        if (checked.record != null and !admitsStandIn(program.functions[checked.instance])) stubbable = false;
        const fact = summary.fromFact(checked.fact);
        return .{
            .key = self.prepared.keys[ast_index],
            .context = self.prepared.contexts[ast_index],
            .region = .{
                .len = @intCast(region.end - region.start),
                .digest = self.prepared.recalled.digests[ast_index],
                .names = self.prepared.recalled.names[ast_index],
            },
            .fact = fact,
            .notes = .{ .body = body_notes, .pass = pass_notes, .complete = standable, .guard = guard, .keeps = if (checked.instance < outputs.keeps.len) outputs.keeps[checked.instance] else &.{} },
            .uses = .{
                .callees = if (checked.record) |record| try storedCallTargets(allocator, program, record, self.prepared.ordinary_ast.len) else &.{},
                .values = if (checked.record) |record| try storedValueTargets(allocator, program, record, self.prepared.ordinary_ast.len) else &.{},
            },
            .stubbable = stubbable,
        };
    }

    fn regionOf(self: *const Plan, i: usize) source.Span {
        return self.prepared.regions[self.prepared.ordinary_ast[i]];
    }
};

/// What a changed bounded body can name: the modules of the project, which imports reach which. Built when the first changed
/// bounded body asks, so a request with no such body costs nothing.
const ModuleScope = struct {
    allocator: std.mem.Allocator,
    names: ?*Names,
    /// The module of each ordinary instance, once built.
    module_of: []u32 = &.{},
    /// Whether the functions of a module are already kept concrete.
    done: []bool = &.{},

    fn deinit(self: *ModuleScope) void {
        self.allocator.free(self.module_of);
        self.allocator.free(self.done);
    }

    /// Keep concrete every ordinary function of the module of `instance` and of every module it imports, transitively. False when
    /// the program has no module graph to say what it can name.
    fn markReachable(self: *ModuleScope, plan: *const Plan, syntax: ast.Program, instance: usize, needed: []bool) error{OutOfMemory}!bool {
        const names = self.names orelse return false;
        const modules = names.index.project.modules.items;
        if (self.module_of.len == 0) {
            self.module_of = try self.allocator.alloc(u32, plan.prepared.ordinary_ast.len);
            for (plan.prepared.ordinary_ast, self.module_of) |ast_index, *owner| {
                const original = names.src.originalSpan(syntax.functions[ast_index].name) catch return false;
                owner.* = @intCast(original.input);
            }
            self.done = try self.allocator.alloc(bool, modules.len);
            @memset(self.done, false);
        }
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(self.allocator);
        const start = self.module_of[instance];
        if (start >= modules.len) return false;
        try pending.append(self.allocator, start);
        while (pending.pop()) |module| {
            if (self.done[module]) continue;
            self.done[module] = true;
            for (modules[module].imports) |imported| if (imported.target < modules.len and !self.done[imported.target]) try pending.append(self.allocator, @intCast(imported.target));
        }
        for (self.module_of, 0..) |module, member| {
            if (module < self.done.len and self.done[module]) needed[member] = true;
        }
        return true;
    }
};

/// Propagate invalidation through direct calls and function-value consumers in
/// linear graph work; removed declarations begin as changed nodes too.
/// A diagnostic as the `W_COPY_MOVE` judge reads it: its code, message and place.
const Hint = struct { code: []const u8, message: []const u8, span: source.Span };

/// One judged hint's names (`Plan.targetName`), and whether it is a `W_COPY_FOR_STORE` warning's.
const TargetName = struct { callee: []const u8, parameter: []const u8, key: []const u8, store: bool = false };

/// What `Plan.judgeCopyMoves` found: the targets' names in order, the targets some caller keeps (by key), each checked caller's
/// answers to store (by instance), how many targets are fresh, and whether a stood-in caller lacked an answer.
const CopyMoves = struct {
    names: std.ArrayList(TargetName) = .empty,
    seen: std.StringHashMapUnmanaged(void) = .empty,
    kept: std.StringHashMapUnmanaged(void) = .empty,
    /// The targets some caller answered, checked or stood in: a `W_COPY_FOR_STORE` warning no caller answered is left out.
    answered: std.StringHashMapUnmanaged(void) = .empty,
    keeps: []const []const summary.Keep = &.{},
    /// The `own ` marks each `W_COPY_FOR_STORE` target's callers need (by key), as starts in the program's source.
    marks: std.StringHashMapUnmanaged(std.ArrayList(u32)) = .empty,
    /// How many of the targets (the first ones) are hints of functions checked in this check rather than replayed.
    fresh: usize = 0,
    missing: bool = false,

    /// Add one caller's `own ` marks for the target `key`, each `offset` after the start it was stored relative to.
    fn mark(self: *CopyMoves, allocator: std.mem.Allocator, key: []const u8, marks: []const u32, offset: u32) error{OutOfMemory}!void {
        if (marks.len == 0) return;
        const entry = try self.marks.getOrPut(allocator, key);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        for (marks) |at| try entry.value_ptr.append(allocator, at + offset);
    }

    /// Remove from `sink` every judged hint a caller keeps what it would take, and give each `W_COPY_FOR_STORE` repair that
    /// stays its callers' `own ` marks (`copy_for_store.withMarks`): what `check` prints is then what a check of every body
    /// prints.
    fn leaveOut(self: CopyMoves, plan: *const Plan, program: typed.Program, sink: *diagnostic.Sink) error{OutOfMemory}!void {
        const stores = for (self.names.items) |name| {
            if (name.store) break true;
        } else false;
        // A `W_COPY_RETURNED` warning that stays stands for the hint beside it.
        defer copy_from_repair.dropHintsBeside(&sink.items);
        // A `W_COPY_FOR_STORE` warning of a list parameter that stays stands for the loop hint at its copy.
        defer copy_loop_repair.dropHintsBeside(&sink.items);
        if (self.kept.count() == 0 and !stores) return;
        var index: usize = 0;
        while (index < sink.items.items.len) {
            const item = sink.items.items[index];
            // With no keeper only the `W_COPY_FOR_STORE` warnings no caller answered can go.
            if (self.kept.count() == 0 and !std.mem.eql(u8, item.code, copy_for_store.code)) {
                index += 1;
                continue;
            }
            const target = plan.hintTarget(program, item.code, item.message, item.span) orelse {
                index += 1;
                continue;
            };
            const name = try plan.targetName(sink.allocator, program, target);
            if (self.kept.contains(name.key) or (target.store and !self.answered.contains(name.key))) {
                _ = sink.items.orderedRemove(index);
                continue;
            }
            if (target.store) if (self.marks.get(name.key)) |marks| if (item.provenance.fix) |fix| {
                sink.items.items[index].provenance.fix = try copy_for_store.withMarks(sink.allocator, fix, marks.items);
            };
            index += 1;
        }
    }
};

/// The one string a target is known by: callee key, advice and parameter.
fn keepKey(allocator: std.mem.Allocator, callee: []const u8, parameter: []const u8, result: bool) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}\x00{s}\x00{s}", .{ callee, if (result) "r" else "a", parameter });
}

/// Whether `stored` holds an answer for the target `name` with advice `result`.
fn answered(stored: []const summary.Keep, name: TargetName, result: bool) bool {
    for (stored) |keep| {
        if (keep.result == result and std.mem.eql(u8, keep.callee, name.callee) and std.mem.eql(u8, keep.parameter, name.parameter)) return true;
    }
    return false;
}

fn invalidateConsumers(allocator: std.mem.Allocator, previous: *const summary.Index, affected: []bool) error{OutOfMemory}!void {
    const consumers = try allocator.alloc(std.ArrayList(u32), previous.count());
    defer allocator.free(consumers);
    @memset(consumers, .empty);
    defer for (consumers) |*list| list.deinit(allocator);
    var pending: std.ArrayList(u32) = .empty;
    defer pending.deinit(allocator);
    for (0..previous.count()) |instance| {
        if (affected[instance]) try pending.append(allocator, @intCast(instance));
        for (previous.calleesAt(@intCast(instance))) |callee| {
            if (callee < consumers.len) try consumers[callee].append(allocator, @intCast(instance));
        }
    }
    var next: usize = 0;
    while (next < pending.items.len) : (next += 1) {
        for (consumers[pending.items[next]].items) |consumer| {
            if (affected[consumer]) continue;
            affected[consumer] = true;
            try pending.append(allocator, consumer);
        }
    }
}

/// One checked ordinary instance, its check record when it has one, and the
/// facts the passes inferred for it.
const CheckedInstance = struct { instance: usize, record: ?Checked, fact: origins.Fact };

/// Whether the typed nodes in `nodes` include a typed hole kept as a trap (`Node.data == .hole`).
fn holdsHole(program: typed.Program, nodes: source.Span) bool {
    for (program.nodes[nodes.start..nodes.end]) |node| if (std.meta.activeTag(node.data) == .hole) return true;
    return false;
}

/// Whether verify sampling withholds the function with stable key `key` (one in `every`, by a hash of the key; never when `every` is 0).
fn sampled(key: []const u8, every: u32) bool {
    return every != 0 and std.hash.Wyhash.hash(0, key) % every == 0;
}

/// Whether a stored guard is the one the function whose region starts at `region_start` has now: the digest of its file's
/// waivers, or, for a function stored with a site that read its whole file, of the whole file. The two digests are of different
/// domains (`Guards.of`, `Guards.wide`), so a stored guard can equal only the kind it was made as, and the whole file is digested
/// only when the waivers' digest does not match.
fn guardHolds(allocator: std.mem.Allocator, cell: *?syntax_hints.Guards, src: source.Source, region_start: usize, expected: [32]u8) error{OutOfMemory}!bool {
    if (std.mem.eql(u8, &expected, &(try guardOf(allocator, cell, src, region_start)))) return true;
    return std.mem.eql(u8, &expected, &(try wideGuardOf(allocator, cell, src, region_start)));
}

/// The guard of a function with a site whose warning read its whole file (`Outputs.file_reads`).
fn wideGuardOf(allocator: std.mem.Allocator, cell: *?syntax_hints.Guards, src: source.Source, region_start: usize) error{OutOfMemory}![32]u8 {
    if (cell.* == null) cell.* = try syntax_hints.Guards.read(allocator, src);
    return cell.*.?.wide(region_start);
}

/// The digest of the waivers that decide the idiom warnings of the function whose region starts at `region_start`.
fn guardOf(allocator: std.mem.Allocator, cell: *?syntax_hints.Guards, src: source.Source, region_start: usize) error{OutOfMemory}![32]u8 {
    if (cell.* == null) cell.* = try syntax_hints.Guards.read(allocator, src);
    return cell.*.?.of(region_start);
}

fn sameNotes(left: []const summary.Note, right: []const summary.Note) bool {
    if (left.len != right.len) return false;
    for (left, right) |was, is| {
        if (!std.mem.eql(u8, was.code, is.code) or !std.mem.eql(u8, was.message, is.message)) return false;
        if (was.severity != is.severity or was.start != is.start or was.end != is.end) return false;
        if (was.fix.len != is.fix.len) return false;
        for (was.fix, is.fix) |old, new| {
            if (old.start != new.start or old.end != new.end or !std.mem.eql(u8, old.text, new.text)) return false;
        }
    }
    return true;
}

/// Whether two lists of instances hold the same ones, in either order (each list has no repeats).
fn sameTargets(left: []const u32, right: []const u32) bool {
    if (left.len != right.len) return false;
    for (left) |target| if (std.mem.indexOfScalar(u32, right, target) == null) return false;
    return true;
}

/// Whether the references a body names now are those its summary holds: the same specializations, and among the stored templates each one
/// it names. The records are left out: which of them a body's
/// summary lists beyond the ones its tree names depends on which body interned a type first, so two checks of the same body in another
/// order list different ones; what a stand-in needs of them it learns by resolving them, and a replay has the same dependence.
fn sameRefs(fresh: ?summary.Refs, right: summary.Refs) bool {
    const left = fresh orelse return false;
    // The stored templates also hold those of the specializations that the body's specializations reach.
    if (left.functions.len != right.functions.len or left.templates.len > right.templates.len) return false;
    // The order is that of the instance numbers, which are the order the specializations were registered in.
    for (left.functions) |was| {
        for (right.functions) |is| {
            if (std.mem.eql(u8, was.key, is.key)) break;
        } else return false;
    }
    for (left.templates) |was| {
        for (right.templates) |is| {
            if (std.mem.eql(u8, was.key, is.key) and std.mem.eql(u8, &was.digest, &is.digest)) break;
        } else return false;
    }
    return true;
}

fn startsBefore(_: void, a: diagnostic.Diagnostic, b: diagnostic.Diagnostic) bool {
    return a.span.start < b.span.start;
}

/// Whether any of `spans` (sorted by start) starts inside `region`.
fn anyStartsIn(spans: []const source.Span, region: source.Span) bool {
    var low: usize = 0;
    var high = spans.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (spans[mid].start < region.start) low = mid + 1 else high = mid;
    }
    return low < spans.len and spans[low].start < region.end;
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

/// Whether a function's declaration kind lets a summary stand in for it: conversions and host or foreign declarations are checked fresh.
fn admitsStandIn(function: typed.Function) bool {
    return function.policy.host == null and !function.policy.c_abi and !function.policy.conversion;
}

/// The ordinary instances one checked body calls directly, deduplicated.
fn callTargets(allocator: std.mem.Allocator, program: typed.Program, record: Checked) error{OutOfMemory}![]u32 {
    var targets: std.ArrayList(u32) = .empty;
    const end = @min(record.nodes.end, program.nodes.len);
    var index = @min(record.nodes.start, end);
    while (index < end) : (index += 1) {
        const node = program.nodes[index];
        const callee: u32 = switch (node.data) {
            .call => |call| @intCast(@backingInt(call.function)),
            .function_value => |id| @intCast(@backingInt(id)),
            else => continue,
        };
        if (callee == record.instance) continue;
        if (std.mem.indexOfScalar(u32, targets.items, callee) == null) try targets.append(allocator, callee);
    }
    return targets.toOwnedSlice(allocator);
}

/// Persist ordinary declaration edges only. Concrete instances and lambdas
/// have no position in the summary table; their callers remain unstubbable.
fn storedCallTargets(allocator: std.mem.Allocator, program: typed.Program, record: Checked, ordinary_count: usize) error{OutOfMemory}![]const u32 {
    const targets = try callTargets(allocator, program, record);
    var count: usize = 0;
    for (targets) |target| {
        if (target >= ordinary_count) continue;
        targets[count] = target;
        count += 1;
    }
    return targets[0..count];
}

/// The ordinary instances one checked body names as function values, deduplicated: what `callTargets` finds under `function_value`.
fn storedValueTargets(allocator: std.mem.Allocator, program: typed.Program, record: Checked, ordinary_count: usize) error{OutOfMemory}![]const u32 {
    var targets: std.ArrayList(u32) = .empty;
    const end = @min(record.nodes.end, program.nodes.len);
    var index = @min(record.nodes.start, end);
    while (index < end) : (index += 1) {
        const callee: u32 = switch (program.nodes[index].data) {
            .function_value => |id| @intCast(@backingInt(id)),
            else => continue,
        };
        if (callee >= ordinary_count or callee == record.instance) continue;
        if (std.mem.indexOfScalar(u32, targets.items, callee) == null) try targets.append(allocator, callee);
    }
    return targets.toOwnedSlice(allocator);
}

/// Map stored callee positions to this request's instances; a callee that no
/// longer exists is dropped (the caller then records the entry unstubbable).
fn remapCallees(allocator: std.mem.Allocator, callees: []const u32, current: []const ?u32) error{OutOfMemory}![]const u32 {
    if (unchangedCallees(callees, current)) return callees;
    var out: std.ArrayList(u32) = .empty;
    for (callees) |position| {
        if (position < current.len) if (current[position]) |instance| try out.append(allocator, instance);
    }
    return out.toOwnedSlice(allocator);
}

fn unchangedCallees(callees: []const u32, current: []const ?u32) bool {
    for (callees) |position| {
        if (position >= current.len) return false;
        const instance = current[position] orelse return false;
        if (instance != position) return false;
    }
    return true;
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
        try notes.append(allocator, try summary.noteOf(allocator, item, region.start));
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

/// Whether a record a stored table lists still has the shape the table holds for it, once asked.
const ShapeState = enum { unknown, match, mismatch };

/// The answers to "does this record still have its shape", per record of the table's list. A record is asked once however many bodies and
/// sections touched it.
const ShapeMemo = struct {
    allocator: std.mem.Allocator,
    list: []ShapeState,

    fn init(allocator: std.mem.Allocator, previous: *const summary.Index) ShapeMemo {
        const list = allocator.alloc(ShapeState, previous.recordCount()) catch @panic("out of memory");
        @memset(list, .unknown);
        return .{ .allocator = allocator, .list = list };
    }

    fn deinit(self: *ShapeMemo) void {
        self.allocator.free(self.list);
    }
};

/// What the decision for every function of one request shares: the previous table and the fresh shapes of its records (resolved on first use).
const Decision = struct {
    allocator: std.mem.Allocator,
    previous: *const summary.Index,
    body_changes: bool,
    shapes: ShapeMemo,

    fn init(allocator: std.mem.Allocator, previous: *const summary.Index, demand: ?summary.Demand) Decision {
        return .{
            .allocator = allocator,
            .previous = previous,
            .body_changes = if (demand) |host| host.body_dependencies else false,
            .shapes = ShapeMemo.init(allocator, previous),
        };
    }

    fn deinit(self: *Decision) void {
        self.shapes.deinit();
    }
};

/// A module group with no section of the previous table that is exactly its functions.
const no_section = std.math.maxInt(u32);

/// An exclusive phase window on the request's profile; a request with none costs nothing.
const Lap = struct {
    profile: ?*timings.Profile,
    mark: timings.Mark,

    fn start(profile: ?*timings.Profile) Lap {
        return .{ .profile = profile, .mark = if (profile) |p| p.mark() else .{ .start = .zero } };
    }

    fn end(self: Lap, name: []const u8) void {
        if (self.profile) |p| p.addMark(name, self.mark, false);
    }
};

/// Whether the record at index `local` of a section's list has the shape the table holds for it: asked of the catalog once.
fn recordStands(session: *semantic_cache.Session, previous: *const summary.Index, position: u32, local: u32, states: []ShapeState) error{OutOfMemory}!bool {
    if (local >= states.len) return false;
    if (states[local] == .unknown) {
        const stored = previous.recordShape(position, local);
        states[local] = if (try session.shapeOf(previous.recordName(position, local))) |digest|
            (if (std.mem.eql(u8, &digest, &stored)) ShapeState.match else .mismatch)
        else
            .mismatch;
    }
    return states[local] == .match;
}

/// Whether every record a stored body touched still exists with the shape it had when the table was made. The fresh shape of a record is
/// taken once, however many bodies touched it, and compared with the digest the table holds for it.
fn touchedShapesMatch(session: *semantic_cache.Session, previous: *const summary.Index, position: u32, uses: summary.Uses, memo: *ShapeMemo) error{OutOfMemory}!bool {
    for (uses.records) |local| if (!try recordStands(session, previous, position, local, memo.list)) return false;
    return true;
}

/// Whether every record the functions of a section touched still has the shape the table holds for it, which makes every body of the
/// section pass the record test of `candidate`.
fn sectionShapesMatch(session: *semantic_cache.Session, view: *sections_mod.Sections, section: u32, memo: *ShapeMemo) error{OutOfMemory}!bool {
    for (view.sectionRecords(section)) |id| {
        if (id >= memo.list.len) return false;
        if (memo.list[id] == .unknown) {
            const record = view.recordById(id);
            memo.list[id] = if (try session.shapeOf(record.name)) |digest|
                (if (std.mem.eql(u8, &digest, &record.shape)) ShapeState.match else .mismatch)
            else
                .mismatch;
        }
        if (memo.list[id] != .match) return false;
    }
    return true;
}

/// The record-name list of the table being produced, with the shape digest each record had.
const RecordNames = struct {
    list: std.ArrayList([]const u8) = .empty,
    shapes: std.ArrayList([32]u8) = .empty,
    positions: std.StringHashMapUnmanaged(u32) = .empty,

    fn intern(self: *RecordNames, allocator: std.mem.Allocator, name: []const u8, shape: [32]u8) error{OutOfMemory}!u32 {
        const entry = try self.positions.getOrPut(allocator, name);
        if (!entry.found_existing) {
            entry.value_ptr.* = @intCast(self.list.items.len);
            try self.list.append(allocator, name);
            try self.shapes.append(allocator, shape);
        }
        return entry.value_ptr.*;
    }

    /// Positions in this table of records another table named by position, with the shapes that table held for them (a body that stands in
    /// touches only records whose fresh shape is the one it held).
    fn carry(self: *RecordNames, allocator: std.mem.Allocator, previous: *const summary.Index, summary_position: u32, locals: []const u32) error{OutOfMemory}![]const u32 {
        const out = try allocator.alloc(u32, locals.len);
        for (locals, out) |local, *carried| carried.* = try self.intern(allocator, previous.recordName(summary_position, local), previous.recordShape(summary_position, local));
        return out;
    }
};
