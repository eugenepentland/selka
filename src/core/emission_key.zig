//! Canonical inputs of one independently emitted LLVM unit.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const ir = @import("ir.zig");
const llvm = @import("emit_llvm.zig");
const identity = @import("canonical_ir.zig");
const constants = @import("emit_constants.zig");
const values = @import("emit_values.zig");
const deferred_facts = @import("deferred_facts.zig");
const testcount_runtime = @import("testcount_runtime.zig");

/// Canonical digest shared with persistent stage keys.
pub const Digest = identity.Digest;
/// Unknown semantic metadata disables caching; render errors remain unchanged.
pub const Error = identity.Error || llvm.Error;

/// Program-wide immutable function identities; per-unit graph walks use local scratch.
pub const Prepared = struct {
    canon: identity.Canon,
    digests: []const Digest,
    options: llvm.Options,
    catalog: *const constants.Catalog,
    deferred: ?*const deferred_facts.Table = null,
    ready: []bool = &.{},

    /// Prepare immutable function identities before individual unit graph walks.
    pub fn init(a: std.mem.Allocator, module: *const ir.Module, options: llvm.Options, catalog: *const constants.Catalog) Error!Prepared {
        var canon = try identity.Canon.prepare(a, module, options.locator);
        const digests = try a.alloc(Digest, module.functions.items.len);
        errdefer a.free(digests);
        for (digests, 0..) |*digest, index| digest.* = try canon.functionDigest(@intCast(index));
        return .{ .canon = canon, .digests = digests, .options = options, .catalog = catalog };
    }

    /// Demand emission hashes only bodies whose compact receipt missed.
    pub fn initLazy(a: std.mem.Allocator, module: *const ir.Module, options: llvm.Options, catalog: *const constants.Catalog) Error!Prepared {
        const ready = try a.alloc(bool, module.functions.items.len);
        @memset(ready, false);
        return .{ .canon = try identity.Canon.prepare(a, module, options.locator), .digests = try a.alloc(Digest, ready.len), .options = options, .catalog = catalog, .ready = ready };
    }

    /// Hash exactly the immutable inputs a render can consult, without global IR IDs.
    pub fn key(self: *Prepared, a: std.mem.Allocator, selection: llvm.Selection) Error!Digest {
        var hash = fast_blake3.Blake3.init(.{});
        value(&hash, "core-emission-input-v3");
        value(&hash, "zero-rc");
        value(&hash, "zero-rc");
        value(&hash, self.options.target);
        value(&hash, self.options.verify);
        value(&hash, self.options.counters);
        value(&hash, self.options.forced_inline);
        value(&hash, @import("emit_survey.zig").testCounts(selection.survey, self.canon.module));
        value(&hash, self.options.source_path);
        value(&hash, selection.source_path);
        value(&hash, selection.entry);
        var graph: Graph = .{ .a = a, .prepared = self };
        value(&hash, selection.functions.len);
        for (selection.functions) |index| try self.functionInputs(&hash, &graph, selection, index);
        if (selection.entry) {
            const entry = self.canon.module.entry;
            hash.update(&try self.canon.callee(entry));
            value(&hash, selection.symbols[entry]);
            value(&hash, self.options.main);
            // Which runtime start the entry calls (BIN-CEILING): `main`'s own key does not show that it installs a budget.
            value(&hash, @import("run_budget.zig").installs(self.canon.module));
            try graph.signature(&hash, self.canon.module.functions.items[entry].signature);
            // The functions the device's hooks bind (`main.hooks`, in order, at the indices after `main`): the entry unit writes a
            // call to each, and `main.hooks` names the hooks, not the functions they bind.
            for (self.options.main.hooks, 1..) |_, bound| try self.hookInputs(&hash, &graph, selection, bound);
        }
        // Local descriptor IDs encode aliasing as well as contents. The closure
        // includes source rendering labels, offsets and authorized child graphs.
        value(&hash, try self.catalog.finish(a, graph.descriptors.items));
        var digest: Digest = undefined;
        hash.final(&digest);
        return digest;
    }

    /// What the entry unit's C-ABI function for one device hook reads of the Selka function `index` it binds: the callee's name and
    /// signature, and the symbol the unit calls it by.
    fn hookInputs(self: *Prepared, hash: *fast_blake3.Blake3, graph: *Graph, selection: llvm.Selection, index: usize) Error!void {
        if (index >= self.digests.len or index >= selection.symbols.len) return error.UnknownMetadata;
        hash.update(&try self.canon.callee(@intCast(index)));
        value(hash, selection.symbols[index]);
        try graph.signature(hash, self.canon.module.functions.items[index].signature);
    }

    fn functionInputs(self: *Prepared, hash: *fast_blake3.Blake3, graph: *Graph, selection: llvm.Selection, index: u32) Error!void {
        const function = self.canon.module.functions.items[index];
        if (self.ready.len != 0 and !self.ready[index]) {
            @constCast(self.digests)[index] = try self.canon.functionDigest(index);
            self.ready[index] = true;
        }
        hash.update(&self.digests[index]);
        value(hash, selection.exported[index]);
        value(hash, selection.symbols[index]);
        try graph.signature(hash, function.signature);
        try graph.renderRoot(function);
        value(hash, try self.factIdentity(graph.a, index));
        if (index < self.options.analysis.vectors.len) value(hash, self.options.analysis.vectors[index]) else value(hash, @as([]const u8, &.{}));
        try self.effectsInput(hash, index);
        for (function.insts.items) |inst| {
            // Zero spans have a special counter fallback to the declaration.
            value(hash, inst.span == 0);
            try graph.ty(hash, inst.ty);
            const target: u32 = switch (inst.op) {
                .call => @intCast(inst.a.index()),
                .func_ref => @intCast(inst.data),
                else => continue,
            };
            if (target >= self.digests.len) return error.UnknownMetadata;
            hash.update(&try self.canon.callee(target));
            value(hash, selection.symbols[target]);
            try graph.signature(hash, self.canon.module.functions.items[target].signature);
            try self.effectsInput(hash, target);
        }
        if (self.options.analysis.provenance) |table| {
            for (function.blocks.items, 0..) |block, b| {
                try self.ancestry(hash, table.block(index, @intCast(b)));
                for (block.insts.items) |ref| try self.ancestry(hash, table.instruction(index, @intCast(b), ref));
            }
        } else value(hash, @as(?u8, null));
    }

    fn factIdentity(self: *Prepared, a: std.mem.Allocator, index: usize) Error!?Digest {
        if (self.deferred) |table| if (table.identity(index)) |digest| return digest;
        const known = if (index < self.options.analysis.facts.len) self.options.analysis.facts[index] else null;
        return deferred_facts.fingerprint(a, known);
    }

    fn effectsInput(self: *Prepared, hash: *fast_blake3.Blake3, index: u32) Error!void {
        const summaries = self.options.analysis.effects orelse return error.UnknownMetadata;
        if (index >= summaries.params.len or index >= summaries.may.len) return error.UnknownMetadata;
        value(hash, summaries.may[index]);
        value(hash, summaries.params[index].len);
        for (summaries.params[index]) |effect| {
            for ([_]@import("effects.zig").Paths{ effect.reads, effect.writes, effect.when_true, effect.when_false }) |paths| {
                value(hash, paths.whole);
                value(hash, paths.items.items);
            }
        }
    }

    fn ancestry(self: *Prepared, hash: *fast_blake3.Blake3, first: ?u32) Error!void {
        var current = first;
        var depth: usize = 0;
        while (current) |id| {
            const table = self.options.analysis.provenance.?;
            if (id >= table.frames.items.len or depth >= @import("inline_origins.zig").max_depth) return error.UnknownMetadata;
            const frame = table.frames.items[id];
            if (frame.function >= self.digests.len) return error.UnknownMetadata;
            const function = self.canon.module.functions.items[frame.function];
            value(hash, true);
            value(hash, function.name);
            self.canon.locate(hash, function.span);
            self.canon.locate(hash, frame.call_span);
            current = frame.parent;
            depth += 1;
        }
        value(hash, false);
    }
};

const Graph = struct {
    a: std.mem.Allocator,
    prepared: *Prepared,
    nodes: std.AutoHashMapUnmanaged(ir.Type, u32) = .empty,
    descriptors: std.ArrayList(u8) = .empty,

    fn signature(self: *Graph, hash: *fast_blake3.Blake3, sig: ir.Signature) Error!void {
        value(hash, sig.params.len);
        for (sig.params) |param| try self.ty(hash, param);
        try self.ty(hash, sig.ret);
        value(hash, sig.passing);
        value(hash, sig.borrow);
    }

    fn ty(self: *Graph, hash: *fast_blake3.Blake3, raw: ir.Type) Error!void {
        const fresh = try self.nodes.getOrPut(self.a, raw);
        value(hash, fresh.found_existing);
        if (fresh.found_existing) return value(hash, fresh.value_ptr.*);
        fresh.value_ptr.* = @intCast(self.nodes.count() - 1);
        value(hash, fresh.value_ptr.*);
        hash.update(&try self.prepared.canon.typeDigest(raw));
        const descriptor = try std.fmt.allocPrint(self.a, "myl.value.{s}", .{self.prepared.catalog.ids.text(raw)});
        if (self.prepared.catalog.globals.contains(descriptor)) try self.descriptors.print(self.a, "@{s}\n", .{descriptor});
        if (!raw.isCompound()) return;
        const shape = self.prepared.canon.module.compound(raw);
        switch (shape) {
            .list, .box, .list_view, .borrowed => |child| try self.ty(hash, child),
            .record, .@"union" => |children| for (children) |child| try self.ty(hash, child),
            .dict => |pair| {
                try self.ty(hash, pair.key);
                try self.ty(hash, pair.value);
            },
            .array => |array| try self.ty(hash, array.elem),
            .@"fn" => |sig| try self.signature(hash, sig),
        }
    }

    fn renderRoot(self: *Graph, function: ir.Function) Error!void {
        const prefix = "myl_core_show_";
        if (!values.generated(&function) or !std.mem.startsWith(u8, function.name, prefix)) return;
        try self.descriptors.print(self.a, "@myl.render.{s}\n", .{function.name[prefix.len..]});
    }
};

/// A BLAKE3 hasher that gathers the small writes `value` makes (a unit's key makes about forty per function) in a buffer and passes them
/// to the hasher a buffer at a time. The digest is the one a hasher given the same bytes one by one would give, since BLAKE3 hashes a
/// stream; the calls are what it saves.
pub const Staged = struct {
    hash: fast_blake3.Blake3,
    pending: [1024]u8 = undefined,
    used: usize = 0,

    /// A staged hasher over an empty stream.
    pub fn init() Staged {
        return .{ .hash = fast_blake3.Blake3.init(.{}) };
    }

    /// Consume `bytes`.
    pub fn update(self: *Staged, bytes: []const u8) void {
        if (bytes.len > self.pending.len - self.used) {
            self.flush();
            if (bytes.len > self.pending.len) return self.hash.update(bytes);
        }
        @memcpy(self.pending[self.used..][0..bytes.len], bytes);
        self.used += bytes.len;
    }

    fn flush(self: *Staged) void {
        if (self.used == 0) return;
        self.hash.update(self.pending[0..self.used]);
        self.used = 0;
    }

    /// Finish the 32-byte digest of everything consumed.
    pub fn final(self: *Staged, out: *[32]u8) void {
        self.flush();
        self.hash.final(out);
    }
};

/// Typed serialization avoids pointer addresses, allocation capacities and padding. `hash` is a pointer to anything with `update`.
fn value(hash: anytype, item: anytype) void {
    const T = @TypeOf(item);
    // A host target hashes what the single-target compiler's `Target` was, so its keys keep their values.
    if (T == @import("target.zig").Target) {
        value(hash, item.legacy());
        if (!item.isHost()) value(hash, item.distinct());
        return;
    }
    if (T == ir.Loop) {
        inline for (.{ "header", "body", "latch", "exit" }) |name| value(hash, @field(item, name));
        return;
    }
    switch (@typeInfo(T)) {
        // A union's payload-free variant (`target.Runtime.hosted`): its tag says everything.
        .void => {},
        .bool => hash.update(&.{@intFromBool(item)}),
        .int => |info| {
            var bytes: [16]u8 = undefined;
            const bits: u128 = if (info.signedness == .signed) @bitCast(@as(i128, item)) else @as(u128, item);
            std.mem.writeInt(u128, &bytes, bits, .little);
            hash.update(&bytes);
        },
        .float => |info| value(hash, @as(@Int(.unsigned, info.bits), @bitCast(item))),
        .@"enum" => value(hash, @backingInt(item)),
        .optional => {
            value(hash, item != null);
            if (item) |present| value(hash, present);
        },
        .array => |array| {
            value(hash, item.len);
            if (array.child == u8) hash.update(&item) else for (item) |element| value(hash, element);
        },
        .pointer => |pointer| {
            if (pointer.size == .slice) {
                value(hash, item.len);
                if (pointer.child == u8) hash.update(item) else for (item) |element| value(hash, element);
            } else value(hash, item.*);
        },
        .@"struct" => |structure| inline for (structure.field_names) |name| value(hash, @field(item, name)),
        .@"union" => |shape| {
            const tag = std.meta.activeTag(item);
            value(hash, tag);
            inline for (shape.field_names) |name| {
                if (tag == @field(std.meta.Tag(T), name)) value(hash, @field(item, name));
            }
        },
        else => @compileError("unsupported emission-key input: " ++ @typeName(T)),
    }
}

/// A unit's compact receipt key binds what the unit reads and nothing else (G4a step 2b): its functions by name, in the unit's
/// canonical order, each with its final record (key, positioned body digest, analysis, plans, inline ancestry, scopes by name
/// and location), and the symbol and effects of each function it calls. The body digest of a final (`Canon.functionDigest`) binds the
/// function's own name and signature and each callee's reference digest (name and signature; an adapter by what it renders, copies
/// or compares), so the key binds those through it. No ordinal, no module-wide table and no other unit enters it: a function added elsewhere, a
/// type added elsewhere or another function's changed signature leaves the key as it was. The digest of the whole descriptor
/// catalog is not in it either, because a descriptor is a function of the types and render shapes a unit's functions and callees
/// already name: type structure is in every body digest and signature, and a renderer's shape is in its reference digest.
pub const Compact = struct {
    guard: Digest,
    context: @import("emission_cache.zig").Context,
    canon: *identity.Canon,
    /// The digest of each function's effects, once asked.
    effect_digests: []?Digest,
    /// The unit whose key last bound function `i` as a callee: a callee several functions of a unit call is bound once.
    met: []u32,
    unit: u32 = 0,

    /// Prepare the options every unit receipt shares and the memo of effect digests. Null when the build has no effect summaries.
    pub fn init(a: std.mem.Allocator, module: *const ir.Module, options: llvm.Options, canon: *identity.Canon, context: @import("emission_cache.zig").Context) std.mem.Allocator.Error!?Compact {
        if (context.receipts == null) return null;
        if (options.analysis.effects == null) return null;
        var hash = fast_blake3.Blake3.init(.{});
        value(&hash, "core-emission-receipt-v4");
        value(&hash, options.target);
        value(&hash, options.verify);
        value(&hash, options.counters);
        value(&hash, testcount_runtime.needed(module));
        value(&hash, options.source_path);
        value(&hash, options.main);
        var guard: Digest = undefined;
        hash.final(&guard);
        const memo = try a.alloc(?Digest, module.functions.items.len);
        errdefer a.free(memo);
        @memset(memo, null);
        const met = try a.alloc(u32, module.functions.items.len);
        @memset(met, 0);
        return .{ .guard = guard, .context = context, .canon = canon, .effect_digests = memo, .met = met };
    }

    /// The digest of function `index`'s effects: whether it may write, and the paths each parameter reads and writes. Null when unknown.
    fn effectDigest(self: *Compact, options: llvm.Options, index: u32) ?Digest {
        if (index >= self.effect_digests.len) return null;
        if (self.effect_digests[index]) |known| return known;
        const summaries = options.analysis.effects orelse return null;
        if (index >= summaries.params.len or index >= summaries.may.len) return null;
        var hash = fast_blake3.Blake3.init(.{});
        value(&hash, summaries.may[index]);
        value(&hash, summaries.params[index].len);
        for (summaries.params[index]) |effect| {
            for ([_]@import("effects.zig").Paths{ effect.reads, effect.writes, effect.when_true, effect.when_false }) |paths| {
                value(&hash, paths.whole);
                value(&hash, paths.items.items);
            }
        }
        var digest: Digest = undefined;
        hash.final(&digest);
        self.effect_digests[index] = digest;
        return digest;
    }

    /// What a unit reads of function `index`, whichever unit defines it, besides what its body digest binds: its effects and its symbol.
    /// A caller's body digest (`Canon.functionDigest`) binds each callee's name and signature, and a renderer's shape, by reference
    /// digest; a function's own digest binds its own name and signature.
    fn reads(self: *Compact, hash: *Staged, options: llvm.Options, selection: llvm.Selection, index: u32) bool {
        if (index >= selection.symbols.len) return false;
        const effect = self.effectDigest(options, index) orelse return false;
        hash.update(&effect);
        value(hash, selection.symbols[index]);
        return true;
    }

    /// Bind function `index` by its reference digest (name and signature; an adapter by what it renders or copies): for a function with
    /// no final body to bind it, which is a generated adapter, and the entry.
    fn named(self: *Compact, hash: *Staged, index: u32) std.mem.Allocator.Error!bool {
        hash.update(&(self.canon.callee(index) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnknownMetadata => return false,
        }));
        return true;
    }

    /// Bind exact final bodies, ancestry and current source scopes without body walks.
    pub fn key(self: *Compact, _: std.mem.Allocator, module: *const ir.Module, options: llvm.Options, selection: llvm.Selection) std.mem.Allocator.Error!?Digest {
        var hash = Staged.init();
        value(&hash, self.guard);
        value(&hash, selection.source_path);
        value(&hash, selection.entry);
        value(&hash, selection.functions.len);
        // A callee several functions of the unit call is bound once, where it is first met.
        self.unit +%= 1;
        for (selection.functions) |index| {
            const function = module.functions.items[index];
            value(&hash, function.name);
            value(&hash, selection.exported[index]);
            value(&hash, options.locator.locate(options.locator.context, function.span));
            if (!self.reads(&hash, options, selection, index)) return null;
            if (index < self.context.receipts.?.finals.len) if (self.context.receipts.?.finals[index]) |final| {
                const render = final.render orelse return null;
                value(&hash, render.ancestry);
                value(&hash, render.scopes.len);
                for (render.scopes) |scope| {
                    if (scope >= module.functions.items.len) return null;
                    const declaration = module.functions.items[scope];
                    value(&hash, declaration.name);
                    value(&hash, options.locator.locate(options.locator.context, declaration.span));
                }
                value(&hash, final.key);
                value(&hash, final.body.positioned);
                value(&hash, final.analysis.digest);
                value(&hash, final.state.plans);
                for (final.outgoing) |target| {
                    if (target < self.met.len) {
                        if (self.met[target] == self.unit) continue;
                        self.met[target] = self.unit;
                    }
                    if (!self.reads(&hash, options, selection, target)) return null;
                }
                continue;
            };
            // Generated runtime adapters render from their name and descriptor metadata; their placeholder IR is deliberately not
            // visited. Their reference digest binds what they render or copy.
            if (!values.generated(&function)) return null;
            if (!try self.named(&hash, index)) return null;
        }
        if (selection.entry) {
            if (!self.reads(&hash, options, selection, module.entry)) return null;
            if (!try self.named(&hash, module.entry)) return null;
            value(&hash, @import("run_budget.zig").installs(module));
            // The functions the device's hooks bind, as the entry unit calls them (`options.main.hooks` names the hooks only).
            for (options.main.hooks, 1..) |_, bound| {
                if (!self.reads(&hash, options, selection, @intCast(bound))) return null;
                if (!try self.named(&hash, @intCast(bound))) return null;
            }
        }
        var digest: Digest = undefined;
        hash.final(&digest);
        return self.context.store.key("llvm-compact-receipt-v2", &.{&digest});
    }
};
