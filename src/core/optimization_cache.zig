//! Function-stage reuse keyed by actual optimizer inputs, in original mutation order.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const vector = @import("vector.zig");
const own = @import("own.zig");
const effects = @import("effects.zig");
const origins = @import("inline_origins.zig");
const identity = @import("canonical_ir.zig");
const snapshot = @import("ir_snapshot.zig");
const store = @import("stage_store.zig");
const deferred_facts = @import("deferred_facts.zig");
const codec = @import("mylang").persist_codec;

/// Ordered optimizer artifacts, plus the independent debug ownership stage.
pub const Stage = enum { inline_leaf, inline_cfg, unswitch, first_facts, parameter_inline, final, debug };
const stage_count = @typeInfo(Stage).@"enum".field_names.len;
/// Observed store lookups; no reuse is inferred from unchanged source bytes.
pub const Statistics = struct {
    hits: [stage_count]usize = @splat(0),
    misses: [stage_count]usize = @splat(0),
    bypassed: usize = 0,
    active_functions: usize = 0,
    fresh_work: usize = 0,
    restores: struct { final: usize = 0, checkpoints: usize = 0 } = .{},
    final_loaded: usize = 0,
};
/// Outside facts and earlier pass events consulted by the requested stage.
pub const Inputs = struct {
    parameters: []const ?facts.Interval = &.{},
    returns: []const ?facts.Interval = &.{},
    effects: ?*const effects.Summaries = null,
    events: [2]u32 = .{ 0, 0 },
};

/// One physical function's stage and its current analysis dependencies.
pub const Request = struct {
    stage: Stage,
    function: u32,
    mode: u8,
    provenance: *const origins.Table,
    inputs: Inputs = .{},
};

/// Exact output identity of an ordered mutation checkpoint.
pub const Checkpoint = struct {
    key: [32]u8,
    output: [32]u8,
    provenance: Provenance,
    changed: u32,
    graph: struct { calls: []const u32, references: []const u32 },
};
/// Compact callee identities avoid decoding a body merely to form a stage key.
pub const CheckpointProvider = struct {
    pointer: *anyopaque,
    identity_fn: *const fn (*anyopaque, Stage, u32, u32) ?CheckpointIdentity,
};
/// Body and local ancestry observed by an inlining stage.
pub const CheckpointIdentity = struct { digest: [32]u8, ancestry: Provenance };

/// One build's portable source/catalog context and mutable body digest memo.
pub const Context = struct {
    store: *store.Store,
    source: snapshot.Context,
    locator: @import("emit_llvm.zig").Locator,
    prepared: ?struct { layout: [32]u8, canon: identity.Canon, digests: []?[32]u8, before: []?[32]u8 } = null,
    statistics: Statistics = .{},
    /// Optional lowering handles for development optimizer demand loading.
    lazy: struct { raw: ?*@import("demand_ir.zig").Context = null, finals: []?FinalMetadata = &.{}, loaded: []bool = &.{}, checkpoints: ?CheckpointProvider = null } = .{},
    /// Deferred tables keep verified encoded facts for development emission misses.
    deferred: ?*deferred_facts.Table = null,

    /// Create a cache context without preparing the mutable function catalog.
    pub fn init(storage: *store.Store, source: snapshot.Context, locator: @import("emit_llvm.zig").Locator) Context {
        return .{ .store = storage, .source = source, .locator = locator };
    }

    /// Call after prepass fusions have finished declaring their runtime helpers.
    pub fn prepare(self: *Context, a: std.mem.Allocator) std.mem.Allocator.Error!void {
        if (self.deferred) |table| {
            const count = self.source.module.functions.items.len;
            if (table.entries.len != count) table.* = try deferred_facts.Table.init(a, count);
        }
        const layout = try snapshot.layout(a, self.source);
        const canon = identity.Canon.prepare(a, self.source.module, self.locator) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnknownMetadata => return,
        };
        const digests = try a.alloc(?[32]u8, self.source.module.functions.items.len);
        @memset(digests, null);
        const before = try a.alloc(?[32]u8, digests.len);
        @memset(before, null);
        self.prepared = .{ .layout = layout, .canon = canon, .digests = digests, .before = before };
    }

    /// Invalidate the body memo immediately after a physical function changes.
    pub fn changed(self: *Context, function: usize) void {
        if (self.prepared) |*state| {
            state.before[function] = state.digests[function];
            state.digests[function] = null;
        }
    }

    fn body(self: *Context, function: u32) identity.Error![32]u8 {
        const state = &self.prepared.?;
        if (state.digests[function]) |known| return known;
        const digest = try state.canon.functionDigest(function);
        state.digests[function] = digest;
        return digest;
    }

    /// Expose the guarded catalog identity to compact whole-pipeline indexes.
    pub fn layoutDigest(self: *const Context) ?[32]u8 {
        return if (self.prepared) |state| state.layout else null;
    }

    /// Read the current canonical body memo, disabling shortcuts for unknown metadata.
    pub fn bodyDigest(self: *Context, function: u32) std.mem.Allocator.Error!?[32]u8 {
        if (self.prepared == null) return null;
        return self.body(function) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnknownMetadata => null,
        };
    }

    /// Hash body, ancestry, and the precise kinds of outside facts this stage reads.
    pub fn key(self: *Context, a: std.mem.Allocator, request: Request) std.mem.Allocator.Error!?[32]u8 {
        const stage = request.stage;
        const function = request.function;
        const inputs = request.inputs;
        const provenance = request.provenance;
        if (self.prepared == null) return null;
        const digest = self.body(function) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnknownMetadata => return null,
        };
        var writer = codec.Writer.init(a);
        defer writer.deinit();
        try writer.write(u8, request.mode);
        try writer.write([2]u32, inputs.events);
        try writer.write([]const ?facts.Interval, inputs.parameters);
        const ancestry = Provenance.capture(a, self.source, provenance, function) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return null,
        };
        try writer.write(Provenance, ancestry);
        const inline_body = stage == .inline_leaf or stage == .inline_cfg or stage == .parameter_inline;
        for (self.source.module.functions.items[function].insts.items) |inst| {
            const target: u32 = switch (inst.op) {
                .call => @intCast(inst.a.index()),
                .func_ref => @intCast(inst.data),
                else => continue,
            };
            try writer.write(u32, target);
            if (inline_body) {
                const saved = if (self.lazy.checkpoints) |provider| provider.identity_fn(provider.pointer, stage, function, target) else null;
                const callee = if (saved) |checkpoint| checkpoint.digest else self.body(target) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.UnknownMetadata => return null,
                };
                try writer.write([32]u8, callee);
                const callee_ancestry = if (saved) |checkpoint| checkpoint.ancestry else Provenance.capture(a, self.source, provenance, target) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidSnapshot => return null,
                };
                try writer.write(Provenance, callee_ancestry);
            }
            if (inputs.returns.len != 0 and inst.op == .call) try writer.write(?facts.Interval, inputs.returns[target]);
            if (inputs.effects) |summaries| {
                try writeEffects(&writer, summaries, target);
            }
        }
        var dependencies: [32]u8 = undefined;
        std.crypto.hash.Blake3.hash(writer.bytes.items, &dependencies, .{});
        return self.store.key(@tagName(stage), &.{ &self.prepared.?.layout, &digest, &dependencies });
    }

    /// Decode on reclaimable storage and count the observed lookup result.
    pub fn load(self: *Context, a: std.mem.Allocator, stage: Stage, input_key: [32]u8, comptime T: type) std.mem.Allocator.Error!?T {
        const value = try self.store.loadValue(a, input_key, T);
        if (value != null) self.statistics.hits[@backingInt(stage)] += 1 else self.statistics.misses[@backingInt(stage)] += 1;
        return value;
    }

    /// Reclassify a decoded artifact that fails stage-specific validation.
    pub fn rejected(self: *Context, stage: Stage) void {
        self.statistics.hits[@backingInt(stage)] -= 1;
        self.statistics.misses[@backingInt(stage)] += 1;
    }

    /// Publish a portable payload; unavailable stores leave computed output usable.
    pub fn save(self: *Context, input_key: [32]u8, comptime T: type, value: T) std.mem.Allocator.Error!void {
        try self.store.storeValue(input_key, T, value);
    }

    /// Capture an intermediate body and its local ancestry on temporary storage.
    pub fn saveTransform(self: *Context, a: std.mem.Allocator, key_value: [32]u8, function: u32, provenance: *const origins.Table, changes: u32) std.mem.Allocator.Error!void {
        const ancestry = Provenance.capture(a, self.source, provenance, function) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return,
        };
        const output = self.body(function) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnknownMetadata => null,
        };
        const before = self.prepared.?.before[function];
        const same = changes == 0 and before != null and output != null and std.mem.eql(u8, &before.?, &output.?);
        const wire: ?snapshot.Wire = if (same) null else snapshot.capture(a, self.source, self.source.module.functions.items[function]) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return,
        };
        try self.save(key_value, Transform, .{ .function = wire, .provenance = ancestry, .changed = changes, .output = output });
    }

    /// Capture the final body together with its retained analysis and pass events.
    pub fn saveFinal(self: *Context, a: std.mem.Allocator, key_value: [32]u8, function: u32, provenance: *const origins.Table, state: FinalState) std.mem.Allocator.Error!void {
        const wire = snapshot.capture(a, self.source, self.source.module.functions.items[function]) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return,
        };
        const ancestry = Provenance.capture(a, self.source, provenance, function) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return,
        };
        const artifact: ?deferred_facts.Artifact = state.artifact orelse if (state.known) |known| try deferred_facts.encode(a, known) else null;
        if (artifact) |encoded| _ = try self.store.save(self.factsKey(encoded.digest), encoded.bytes);
        var stored = state;
        stored.known = null;
        stored.artifact = null;
        try self.save(key_value, Final, .{
            .function = wire,
            .provenance = ancestry,
            .state = stored,
            .analysis = if (artifact) |encoded| .{ .digest = encoded.digest, .loop_ids = encoded.loop_ids } else null,
        });
    }

    /// Bind a canonical fact payload independently of the final metadata record.
    pub fn factsKey(self: *const Context, digest: [32]u8) [32]u8 {
        return self.store.key("final-facts", &.{&digest});
    }

    /// Verify encoded analysis before any cached final IR reaches the module.
    pub fn loadFacts(self: *Context, a: std.mem.Allocator, description: Analysis) std.mem.Allocator.Error!?deferred_facts.Artifact {
        const bytes = try self.store.loadExpected(a, self.factsKey(description.digest), description.digest) orelse return null;
        return .{ .bytes = bytes, .digest = description.digest, .loop_ids = description.loop_ids };
    }

    /// A no-op artifact validates against the live body and ancestry without copying IR.
    pub fn restoreTransform(self: *Context, a: std.mem.Allocator, scratch: std.mem.Allocator, function: u32, value: Transform, table: *origins.Table) std.mem.Allocator.Error!?ir.Function {
        if (value.changed == 0) if (value.output) |digest| {
            const current = self.body(function) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnknownMetadata => null,
            };
            if (current) |body_digest| if (std.mem.eql(u8, &digest, &body_digest)) {
                const ancestry = Provenance.capture(scratch, self.source, table, function) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidSnapshot => return null,
                };
                if (ancestry.equal(value.provenance)) return self.source.module.functions.items[function];
            };
        };
        const wire = value.function orelse return null;
        return self.restore(a, function, wire, value.provenance, table);
    }

    /// Restore owned IR and local ancestry, or report an invalid cache miss.
    pub fn restore(self: *Context, a: std.mem.Allocator, function: u32, wire: snapshot.Wire, ancestry: Provenance, table: *origins.Table) std.mem.Allocator.Error!?ir.Function {
        const restored = snapshot.restore(a, self.source, wire) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return null,
        };
        if (!try ancestry.restore(a, self.source, function, &restored, table)) return null;
        self.changed(function);
        return restored;
    }
};

fn writeEffects(writer: *codec.Writer, summaries: *const effects.Summaries, function: u32) std.mem.Allocator.Error!void {
    try writer.write([2]bool, summaries.may[function]);
    try writer.write(u64, summaries.params[function].len);
    for (summaries.params[function]) |effect| {
        for ([_]effects.Paths{ effect.reads, effect.writes, effect.when_true, effect.when_false }) |paths| {
            try writer.write(bool, paths.whole);
            try writer.write([]const effects.Path, paths.items.items);
        }
    }
}

/// Intermediate mutation result, retaining its exact pass event count.
pub const Transform = struct { function: ?snapshot.Wire, provenance: Provenance, changed: u32, output: ?[32]u8 };
/// Final tables and accounting consumed by emission and statistics.
pub const FinalState = struct {
    known: ?facts.Facts,
    plans: []const vector.Plan,
    counts: @import("pass_statistics.zig").Counts,
    own: own.Stats,
    /// Transient encoding reused by publication; never duplicated in metadata.
    artifact: ?deferred_facts.Artifact = null,
};
/// Compact emission identity and final pass state, without body or fact payloads.
pub const FinalMetadata = struct {
    key: [32]u8,
    body: [32]u8,
    outgoing: []const u32 = &.{},
    emission_effect: ?effects.Reused = null,
    analysis: Analysis,
    state: FinalState,
};
/// Complete final-stage artifact with portable function and inline ancestry.
pub const Final = struct { function: snapshot.Wire, provenance: Provenance, state: FinalState, analysis: ?Analysis = null };
/// Canonical fact identity and the original checker IDs excluded from that identity.
pub const Analysis = struct { digest: [32]u8, loop_ids: []const usize };

/// Plan slices must outlive the temporary arena used to decode a cache entry.
pub fn retainPlans(a: std.mem.Allocator, plans: []const vector.Plan) std.mem.Allocator.Error![]const vector.Plan {
    const out = try a.dupe(vector.Plan, plans);
    for (out) |*plan| {
        plan.body = try a.dupe(ir.Ref, plan.body);
        plan.selects = try a.dupe(vector.Select, plan.selects);
    }
    return out;
}

/// Compact caller contribution to one callee parameter hull.
pub const Call = struct { callee: u32, ranges: []const ?facts.Interval };
/// Exploratory return interval and reachable direct-call parameter contributions.
pub const Summary = struct {
    returned: ?facts.Interval,
    calls: []const Call,

    /// Reject a contribution whose callee or argument arity no longer matches.
    pub fn valid(self: Summary, module: *const ir.Module) bool {
        for (self.calls) |call| {
            if (call.callee >= module.functions.items.len) return false;
            if (call.ranges.len != module.functions.items[call.callee].signature.params.len) return false;
        }
        return true;
    }
};

/// Decoded table sizes and embedded references must match their physical body.
pub fn validFinal(value: Final, optimized: bool) bool {
    const f = value.function.function;
    const n = f.insts.len;
    const b = f.blocks.len;
    if (!optimized) return value.state.known == null and value.state.plans.len == 0;
    if (value.state.known) |known| {
        if (!validKnown(known, n, b)) return false;
    } else if (value.analysis == null) return false;
    for (value.state.plans) |plan| {
        if (!validLoop(plan.loop, b) or plan.preheader.index() >= b) return false;
        if (plan.bits != 8 and plan.bits != 16 and plan.bits != 32) return false;
        inline for (@typeInfo(vector.Carried).@"struct".field_names) |field| {
            if (!validRef(@field(plan.carried, field), n)) return false;
        }
        for (plan.body) |ref| if (!validRef(ref, n)) return false;
        for (plan.selects) |select| inline for (@typeInfo(vector.Select).@"struct".field_names) |field| {
            if (!validRef(@field(select, field), n)) return false;
        };
    }
    return true;
}

fn validKnown(known: facts.Facts, n: usize, b: usize) bool {
    if (known.ranges.len != n or known.floats.len != n or known.reachable.len != b) return false;
    if (known.aggregates.lists.len != n or known.aggregates.fields.len != n or known.aggregates.dicts.len > n) return false;
    if (known.bounds.len != 0 and known.bounds.len != n) return false;
    for (known.aggregates.lists) |list| {
        if (!validRef(list.length, n) or !validRef(list.child_length, n)) return false;
    }
    for (known.bounds) |slot| if (slot) |bound| {
        if (!validRef(bound.list, n)) return false;
    };
    for (known.counted) |counted| {
        if (!validLoop(counted.loop, b)) return false;
        if (!validRef(counted.counter, n) or !validRef(counted.start, n)) return false;
        if (!validRef(counted.bound, n)) return false;
    }

    return true;
}

fn validRef(ref: ir.Ref, count: usize) bool {
    return ref == .none or ref.index() < count;
}

fn validLoop(loop: ir.Loop, count: usize) bool {
    return loop.header.index() < count and loop.body.index() < count and loop.latch.index() < count and loop.exit.index() < count;
}

/// All argument intervals are copied by value; no first-pass table survives.
pub fn summarize(a: std.mem.Allocator, module: *const ir.Module, function: *const ir.Function, known: *const facts.Facts, sabotage: facts.Sabotage) std.mem.Allocator.Error!Summary {
    var calls: std.ArrayList(Call) = .empty;
    for (function.blocks.items, 0..) |block, index| {
        if (!known.reachable[index]) continue;
        for (block.insts.items) |ref| {
            const inst = function.inst(ref);
            if (inst.op != .call) continue;
            const callee: u32 = @intCast(inst.a.index());
            const arguments = function.operands(inst.data);
            const ranges = try a.alloc(?facts.Interval, module.functions.items[callee].signature.params.len);
            for (ranges, 0..) |*range, position| range.* = if (position < arguments.len) facts.valueRange(known, function, arguments[position]) else null;
            try calls.append(a, .{ .callee = callee, .ranges = ranges });
        }
    }
    return .{ .returned = facts.returnRange(known, function, sabotage), .calls = calls.items };
}

const Frame = struct { function: u32, call: snapshot.Location, parent: ?u32 };
const Block = struct { id: u32, frame: u32 };
const Instruction = struct { id: u32, frame: ?u32 };
/// Only one physical function's ancestry, with locally numbered frame references.
pub const Provenance = struct {
    frames: []const Frame,
    blocks: []Block,
    instructions: []Instruction,
    present: bool,

    /// Snapshot one physical body's sparse ancestry with local frame numbers.
    pub fn capture(a: std.mem.Allocator, context: snapshot.Context, table: *const origins.Table, function: u32) snapshot.Error!Provenance {
        // Sparse ancestry setters register the physical function before storing
        // any block or instruction entry. Most bodies therefore need no scan.
        if (!table.functions.contains(function)) return .{ .frames = &.{}, .blocks = &.{}, .instructions = &.{}, .present = false };
        var blocks: std.ArrayList(Block) = .empty;
        var instructions: std.ArrayList(Instruction) = .empty;
        const f = context.module.functions.items[function];
        for (0..f.blocks.items.len) |index| {
            const id: u32 = @intCast(index);
            if (table.blocks.get((@as(u64, function) << 32) | id)) |frame| try blocks.append(a, .{ .id = id, .frame = frame });
        }
        for (0..f.insts.items.len) |index| {
            const id: u32 = @intCast(index);
            if (table.instructions.get((@as(u64, function) << 32) | id)) |frame| try instructions.append(a, .{ .id = id, .frame = frame });
        }
        var frame_list: std.ArrayList(Frame) = .empty;
        var remap: std.AutoHashMapUnmanaged(u32, u32) = .empty;
        const capturing: Capture = .{ .context = context, .table = table, .frames = &frame_list, .remap = &remap };
        for (blocks.items) |*block| block.frame = try captureFrame(a, capturing, block.frame);
        for (instructions.items) |*inst| if (inst.frame) |frame| {
            inst.frame = try captureFrame(a, capturing, frame);
        };
        return .{ .frames = frame_list.items, .blocks = blocks.items, .instructions = instructions.items, .present = table.functions.contains(function) };
    }

    /// Compare canonical local ancestry independently of interned global frame IDs.
    pub fn equal(self: Provenance, other: Provenance) bool {
        if (self.present != other.present) return false;
        if (!equalItems(Frame, self.frames, other.frames)) return false;
        if (!equalItems(Block, self.blocks, other.blocks)) return false;
        return equalItems(Instruction, self.instructions, other.instructions);
    }

    fn restore(self: Provenance, a: std.mem.Allocator, context: snapshot.Context, function: u32, f: *const ir.Function, table: *origins.Table) std.mem.Allocator.Error!bool {
        const remap = try a.alloc(u32, self.frames.len);
        const calls = try a.alloc(u32, self.frames.len);
        for (self.frames, 0..) |frame, index| {
            if (frame.function >= context.module.functions.items.len) return false;
            if (frame.parent) |parent| if (parent >= index) return false;
            calls[index] = snapshot.relocate(context, frame.call) catch return false;
        }
        for (self.blocks) |block| if (block.id >= f.blocks.items.len or block.frame >= self.frames.len) return false;
        for (self.instructions) |inst| {
            if (inst.id >= f.insts.items.len) return false;
            if (inst.frame) |frame| if (frame >= self.frames.len) return false;
        }
        // Removing entries via their captured keys avoids invalidating an active iterator.
        const old = Provenance.capture(a, context, table, function) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return false,
        };
        for (old.blocks) |block| _ = table.blocks.remove((@as(u64, function) << 32) | block.id);
        for (old.instructions) |inst| _ = table.instructions.remove((@as(u64, function) << 32) | inst.id);
        _ = table.functions.remove(function);
        for (self.frames, calls, 0..) |frame, call, index| {
            const next: origins.Frame = .{ .function = frame.function, .call_span = call, .parent = if (frame.parent) |parent| remap[parent] else null };
            const entry = try table.interned.getOrPut(a, next);
            if (!entry.found_existing) {
                entry.value_ptr.* = @intCast(table.frames.items.len);
                try table.frames.append(a, next);
            }
            remap[index] = entry.value_ptr.*;
        }
        if (self.present) try table.functions.put(a, function, {});
        for (self.blocks) |block| try table.setBlock(a, function, block.id, remap[block.frame]);
        for (self.instructions) |inst| try table.setInstruction(a, function, @fromBackingInt(inst.id), if (inst.frame) |frame| remap[frame] else null);
        return true;
    }
};

const Capture = struct {
    context: snapshot.Context,
    table: *const origins.Table,
    frames: *std.ArrayList(Frame),
    remap: *std.AutoHashMapUnmanaged(u32, u32),
};

fn captureFrame(a: std.mem.Allocator, capture: Capture, id: u32) snapshot.Error!u32 {
    if (capture.remap.get(id)) |known| return known;
    const frame = capture.table.frames.items[id];
    const parent = if (frame.parent) |next| try captureFrame(a, capture, next) else null;
    const result: u32 = @intCast(capture.frames.items.len);
    try capture.frames.append(a, .{ .function = frame.function, .call = try snapshot.locate(capture.context, frame.call_span), .parent = parent });
    try capture.remap.put(a, id, result);
    return result;
}

fn equalItems(comptime T: type, left: []const T, right: []const T) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!std.meta.eql(a, b)) return false;
    return true;
}
