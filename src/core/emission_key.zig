//! Canonical inputs of one independently emitted LLVM unit.
const std = @import("std");
const ir = @import("ir.zig");
const llvm = @import("emit_llvm.zig");
const identity = @import("canonical_ir.zig");
const constants = @import("emit_constants.zig");
const values = @import("emit_values.zig");
const deferred_facts = @import("deferred_facts.zig");

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

    /// Prepare immutable function identities before individual unit graph walks.
    pub fn init(a: std.mem.Allocator, module: *const ir.Module, options: llvm.Options, catalog: *const constants.Catalog) Error!Prepared {
        var canon = try identity.Canon.prepare(a, module, options.locator);
        const digests = try a.alloc(Digest, module.functions.items.len);
        errdefer a.free(digests);
        for (digests, 0..) |*digest, index| digest.* = try canon.functionDigest(@intCast(index));
        return .{ .canon = canon, .digests = digests, .options = options, .catalog = catalog };
    }

    /// Hash exactly the immutable inputs a render can consult, without global IR IDs.
    pub fn key(self: *Prepared, a: std.mem.Allocator, selection: llvm.Selection) Error!Digest {
        var hash = std.crypto.hash.Blake3.init(.{});
        value(&hash, "core-emission-input-v2");
        value(&hash, self.options.target);
        value(&hash, self.options.verify);
        value(&hash, self.options.counters);
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
            try graph.signature(&hash, self.canon.module.functions.items[entry].signature);
        }
        // Local descriptor IDs encode aliasing as well as contents. The closure
        // includes source rendering labels, offsets and authorized child graphs.
        value(&hash, try self.catalog.finish(a, graph.descriptors.items));
        var digest: Digest = undefined;
        hash.final(&digest);
        return digest;
    }

    fn functionInputs(self: *Prepared, hash: *std.crypto.hash.Blake3, graph: *Graph, selection: llvm.Selection, index: u32) Error!void {
        const function = self.canon.module.functions.items[index];
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

    fn effectsInput(self: *Prepared, hash: *std.crypto.hash.Blake3, index: u32) Error!void {
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

    fn ancestry(self: *Prepared, hash: *std.crypto.hash.Blake3, first: ?u32) Error!void {
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

    fn signature(self: *Graph, hash: *std.crypto.hash.Blake3, sig: ir.Signature) Error!void {
        value(hash, sig.params.len);
        for (sig.params) |param| try self.ty(hash, param);
        try self.ty(hash, sig.ret);
    }

    fn ty(self: *Graph, hash: *std.crypto.hash.Blake3, raw: ir.Type) Error!void {
        const fresh = try self.nodes.getOrPut(self.a, raw);
        value(hash, fresh.found_existing);
        if (fresh.found_existing) return value(hash, fresh.value_ptr.*);
        fresh.value_ptr.* = @intCast(self.nodes.count() - 1);
        value(hash, fresh.value_ptr.*);
        hash.update(&try self.prepared.canon.typeDigest(raw));
        const descriptor = try std.fmt.allocPrint(self.a, "myl.value.{d}", .{@backingInt(raw)});
        if (self.prepared.catalog.globals.contains(descriptor)) try self.descriptors.print(self.a, "@{s}\n", .{descriptor});
        if (!raw.isCompound()) return;
        const shape = self.prepared.canon.module.compound(raw);
        switch (shape) {
            .list, .box => |child| try self.ty(hash, child),
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

/// Typed serialization avoids pointer addresses, allocation capacities and padding.
fn value(hash: *std.crypto.hash.Blake3, item: anytype) void {
    const T = @TypeOf(item);
    if (T == ir.Loop) {
        inline for (.{ "header", "body", "latch", "exit" }) |name| value(hash, @field(item, name));
        return;
    }
    switch (@typeInfo(T)) {
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
        else => @compileError("unsupported emission-key input: " ++ @typeName(T)),
    }
}
