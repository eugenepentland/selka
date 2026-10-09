//! Per-function checked-to-Core artifacts. Replay preserves discovery order,
//! including private string allocations, before the normal module transforms.
const std = @import("std");
const language = @import("mylang");
const typed = language.typed;
const codec = language.persist_codec;
const ir = @import("ir.zig");
const snapshot = @import("ir_snapshot.zig");
const stage = @import("stage_store.zig");
const flags = @import("flags.zig");
const render = @import("build_render.zig");

const Error = snapshot.Error;
/// Checked-to-physical type mapping, recorded in discovery order.
pub const TypeBinding = struct { checked: typed.Type, physical: ir.Type };
/// Ordered checked declarations and type discoveries owned by the builder.
pub const Discovery = struct {
    ids: std.AutoHashMapUnmanaged(usize, u32) = .empty,
    pending: std.ArrayList(typed.FunctionId) = .empty,
    types: std.ArrayList(TypeBinding) = .empty,
    enabled: bool = false,
};
/// Borrowed builder state; keeping it explicit avoids a build/cache import cycle.
pub const Context = struct {
    arena: std.mem.Allocator,
    input: struct { program: typed.Program, source: ?language.source.Source, drop_debug: bool },
    module: *ir.Module,
    discovery: *Discovery,
    types: *std.AutoHashMapUnmanaged(typed.Type, ir.Type),
};
const FunctionBinding = struct { checked: typed.FunctionId, physical: u32 };
const Position = union(enum) { zero, local: u32, external: snapshot.Location };
const Function = struct { value: snapshot.Function, positions: []Position };
const Delta = struct {
    declarations: []Function,
    compounds: []const ir.Compound,
    strings: []const []const u8,
    string_start: usize,
    functions: []FunctionBinding,
    types: []TypeBinding,
};
const Wire = struct { function: Function, delta: Delta };
/// Inputs needed to publish one successful function without repeating arguments.
pub const Publication = struct { key: stage.Digest, before: Before, checked: typed.Function };

/// Counters report actual fresh lowering and accepted artifact replay.
/// A durable store and counters for one build; no typed or IR tree is retained.
pub const Cache = struct {
    store: *const stage.Store,
    lowered: usize = 0,
    reused: usize = 0,

    /// Bind immutable durable storage; counters start empty for this build.
    pub fn init(store: *const stage.Store) Cache {
        return .{ .store = store };
    }
};
/// Table lengths before lowering one function.
pub const Before = struct {
    functions: usize,
    compounds: usize,
    strings: usize,
    pending: usize,
    types: usize,

    /// No scans of a growing module are needed to capture its discovery delta.
    pub fn init(mb: Context) Before {
        return .{ .functions = mb.module.functions.items.len, .compounds = mb.module.compounds.items.len, .strings = mb.module.strings.items.len, .pending = mb.discovery.pending.items.len, .types = mb.discovery.types.items.len };
    }
};

/// Rolling declaration guard avoids quadratic catalog hashing on large projects.
pub const Session = struct {
    cache: *Cache,
    catalog: stage.Digest,
    assets: stage.Digest,
    guard: stage.Digest = @splat(0),

    /// Hash the complete checked declaration/type graph once, excluding bodies
    /// and absolute source positions. Numeric IDs are accepted only under this
    /// exact ordered catalog, including generic instances and inferred summaries.
    pub fn prepare(cache: *Cache, mb: Context) Error!Session {
        var h = TreeHash.init(mb.input.program, .{ .module = mb.module, .source = mb.input.source }, null);
        try h.value(mb.input.program.records);
        try h.value(mb.input.program.functions.len);
        for (mb.input.program.functions) |f| {
            try h.value(f.id);
            try h.value(f.name);
            try h.value(f.type_arguments);
            try h.value(f.policy);
            try h.value(f.signature);
            try h.value(f.scope.parameter_labels);
            for (f.scope.locals[0..f.signature.parameter_count]) |local| try h.value(local.ty);
        }
        if (mb.input.source) |source| {
            try h.value(source.path);
            for (source.origins) |origin| try h.value(origin.original.path);
        }
        var assets = std.crypto.hash.Blake3.init(.{});
        if (mb.input.source) |source| for (source.embeds) |embed| {
            frame(&assets, @tagName(embed.status));
            frame(&assets, &embed.digest);
            frame(&assets, embed.contents);
        };
        var result: Session = .{ .cache = cache, .catalog = h.finish(), .assets = undefined };
        assets.final(&result.assets);
        return result;
    }

    /// Include new physical discoveries, never another function's lowered body.
    pub fn advance(self: *Session, a: std.mem.Allocator, before: Before, mb: Context) std.mem.Allocator.Error!void {
        if (before.functions == mb.module.functions.items.len and before.compounds == mb.module.compounds.items.len and before.pending == mb.discovery.pending.items.len and before.types == mb.discovery.types.items.len) return;
        var w = codec.Writer.init(a);
        defer w.deinit();
        try w.write(stage.Digest, self.guard);
        try w.write([]const ir.Compound, mb.module.compounds.items[before.compounds..]);
        try w.write(u64, mb.module.functions.items.len - before.functions);
        for (mb.module.functions.items[before.functions..]) |f| {
            try w.write([]const u8, normalizedName(f.name));
            try w.write(ir.Signature, f.signature);
        }
        try w.write([]const typed.FunctionId, mb.discovery.pending.items[before.pending..]);
        try w.write([]const TypeBinding, mb.discovery.types.items[before.types..]);
        std.crypto.hash.Blake3.hash(w.bytes.items, &self.guard, .{});
    }

    /// Checked nodes/statements are dereferenced, so allocator order and global
    /// node ordinals cannot invalidate unrelated bodies. Local spans relocate.
    pub fn key(self: *const Session, mb: Context, checked: typed.Function) Error!stage.Digest {
        var h = TreeHash.init(mb.input.program, .{ .module = mb.module, .source = mb.input.source }, checked);
        try h.value(checked);
        const body = h.finish();
        const debug = [_]u8{@intFromBool(mb.input.drop_debug)};
        return self.cache.store.key("lowered-function-v1", &.{ &self.catalog, &self.guard, &self.assets, &body, &debug });
    }

    /// Decode and validate with private scratch and temporary discovery deltas.
    /// Every accepted pointer is then copied onto the result arena.
    pub fn restore(self: *Session, scratch: std.mem.Allocator, key_value: stage.Digest, mb: Context, checked: typed.Function, declared: ir.Function) std.mem.Allocator.Error!?ir.Function {
        const wire = try self.cache.store.loadValue(scratch, key_value, Wire) orelse return null;
        const before = Before.init(mb);
        // Temporarily expose only the discovery delta, using the result arena
        // for table capacity. Roll back lengths before decoded scratch expires
        // on every miss/error. Never copy the module's growing catalog prefix.
        const candidate = mb.module;
        var committed = false;
        defer if (!committed) {
            candidate.compounds.shrinkRetainingCapacity(before.compounds);
            candidate.functions.shrinkRetainingCapacity(before.functions);
            candidate.strings.shrinkRetainingCapacity(before.strings);
        };
        try candidate.compounds.appendSlice(mb.arena, wire.delta.compounds);
        for (wire.delta.compounds) |compound| if (!validCompound(candidate, compound)) return null;
        try candidate.strings.appendSlice(mb.arena, wire.delta.strings);
        const context: snapshot.Context = .{ .module = candidate, .source = mb.input.source };
        for (wire.delta.declarations) |f| {
            const restored = restoreFunction(scratch, context, checked, f, wire.delta.string_start, before.strings) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return null;
            };
            try candidate.functions.append(mb.arena, restored);
        }
        for (wire.delta.functions) |binding| {
            if (@backingInt(binding.checked) >= mb.input.program.functions.len or mb.discovery.ids.contains(@backingInt(binding.checked))) return null;
            if (binding.physical < before.functions or binding.physical >= candidate.functions.items.len) return null;
            const fresh = mb.input.program.functions[@backingInt(binding.checked)];
            const f = candidate.functions.items[binding.physical];
            if (!std.mem.eql(u8, fresh.name, f.name)) return null;
            candidate.functions.items[binding.physical].span = std.math.cast(u32, fresh.declaration.start) orelse return null;
        }
        for (wire.delta.types) |binding| {
            if (!binding.checked.isAggregate() or binding.checked.recordIndex() >= mb.input.program.records.len) return null;
            if (!candidate.valid(binding.physical) or mb.types.contains(binding.checked)) return null;
        }
        const built = restoreFunction(scratch, context, checked, wire.function, wire.delta.string_start, before.strings) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
        if (!std.mem.eql(u8, built.name, declared.name) or !sameSignature(built.signature, declared.signature)) return null;
        if (!try safeFunction(scratch, candidate, built)) return null;
        // Clone slice-owned wire tables before scratch disappears. Function DTOs
        // are already validated; their raw string slots are relocated below.
        for (wire.delta.compounds, 0..) |compound, i| candidate.compounds.items[before.compounds + i] = try clone(mb.arena, ir.Compound, compound);
        for (wire.delta.strings, 0..) |bytes, i| candidate.strings.items[before.strings + i] = try mb.arena.dupe(u8, bytes);
        const live: snapshot.Context = .{ .module = mb.module, .source = mb.input.source };
        for (wire.delta.declarations, 0..) |f, i| {
            const restored = restoreFunction(mb.arena, live, checked, f, wire.delta.string_start, before.strings) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidSnapshot => unreachable,
            };
            candidate.functions.items[before.functions + i] = restored;
        }
        for (wire.delta.functions) |binding| {
            try mb.discovery.ids.put(mb.arena, @backingInt(binding.checked), binding.physical);
            try mb.discovery.pending.append(mb.arena, binding.checked);
            mb.module.functions.items[binding.physical].span = @intCast(mb.input.program.functions[@backingInt(binding.checked)].declaration.start);
        }
        for (wire.delta.types) |binding| try mb.types.put(mb.arena, binding.checked, binding.physical);
        try mb.discovery.types.appendSlice(mb.arena, wire.delta.types);
        const result = restoreFunction(mb.arena, live, checked, wire.function, wire.delta.string_start, before.strings) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => unreachable,
        };
        committed = true;
        self.cache.reused += 1;
        return result;
    }

    /// Capture exact table deltas while successful lowering is still untransformed.
    pub fn remember(self: *Session, a: std.mem.Allocator, mb: Context, publication: Publication, built: ir.Function) std.mem.Allocator.Error!void {
        const before = publication.before;
        const checked = publication.checked;
        const context: snapshot.Context = .{ .module = mb.module, .source = mb.input.source };
        const function = captureFunction(a, context, mb.input.program, checked, built) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return;
        };
        const declarations = try a.alloc(Function, mb.module.functions.items.len - before.functions);
        for (declarations, mb.module.functions.items[before.functions..]) |*dto, f| dto.* = captureFunction(a, context, mb.input.program, checked, f) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return;
        };
        const functions = try a.alloc(FunctionBinding, mb.discovery.pending.items.len - before.pending);
        for (functions, mb.discovery.pending.items[before.pending..]) |*binding, id| binding.* = .{ .checked = id, .physical = mb.discovery.ids.get(@backingInt(id)).? };
        try self.cache.store.storeValue(publication.key, Wire, .{
            .function = function,
            .delta = .{
                .declarations = declarations,
                .compounds = mb.module.compounds.items[before.compounds..],
                .strings = mb.module.strings.items[before.strings..],
                .string_start = before.strings,
                .functions = functions,
                .types = mb.discovery.types.items[before.types..],
            },
        });
    }
};

fn sameSignature(a: ir.Signature, b: ir.Signature) bool {
    return a.ret == b.ret and a.linkage == b.linkage and a.owned == b.owned and a.views == b.views and std.mem.eql(ir.Type, a.params, b.params);
}

fn validSignature(module: *const ir.Module, sig: ir.Signature) bool {
    if (!module.valid(sig.ret)) return false;
    for (sig.params) |ty| if (!module.valid(ty)) return false;
    return true;
}

fn validCompound(module: *const ir.Module, compound: ir.Compound) bool {
    return switch (compound) {
        .box, .list => |ty| module.valid(ty),
        .dict => |d| module.valid(d.key) and module.valid(d.value),
        .array => |array| module.valid(array.elem),
        .record, .@"union" => |fields| blk: {
            for (fields) |ty| if (!module.valid(ty)) break :blk false;
            break :blk true;
        },
        .@"fn" => |sig| validSignature(module, sig),
    };
}

fn safeFunction(a: std.mem.Allocator, module: *const ir.Module, f: ir.Function) std.mem.Allocator.Error!bool {
    if (!validSignature(module, f.signature) or f.blocks.items.len == 0) return false;
    for (f.blocks.items) |block| {
        for (block.insts.items) |ref| if (ref.index() >= f.insts.items.len) return false;
        for (block.preds.items) |pred| if (pred.index() >= f.blocks.items.len) return false;
    }
    for (f.insts.items) |inst| {
        if (inst.op.hasExtra()) {
            const slice = ir.ExtraSlice.unpack(inst.data);
            if (slice.start > f.extra.items.len or slice.len > f.extra.items.len - slice.start) return false;
        }
        if (inst.op == .call) {
            if (inst.a.index() >= module.functions.items.len or !validSignature(module, module.functions.items[inst.a.index()].signature)) return false;
        } else if (inst.a != .none and inst.a.index() >= f.insts.items.len) return false;
        if (inst.op == .func_ref and inst.data >= module.functions.items.len) return false;
        if (inst.op == .jump and inst.data >= f.blocks.items.len) return false;
        if (inst.op == .branch) {
            const targets = ir.unpackTargets(inst.data);
            if (targets.then.index() >= f.blocks.items.len or targets.otherwise.index() >= f.blocks.items.len) return false;
        }
        if (inst.b != .none and inst.b.index() >= f.insts.items.len) return false;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |i| if (operands.get(i).index() >= f.insts.items.len) return false;
    }
    for (f.loops.items) |loop| {
        const blocks = [_]ir.BlockId{ loop.header, loop.body, loop.latch, loop.exit };
        for (blocks) |block| if (block.index() >= f.blocks.items.len) return false;
    }
    return acyclicCopies(a, f);
}

// Later passes follow forwarding copies. Each instruction is visited at most
// twice here, rejecting malformed cycles before accepting decoded artifacts.
fn acyclicCopies(a: std.mem.Allocator, f: ir.Function) std.mem.Allocator.Error!bool {
    const colors = try a.alloc(u8, f.insts.items.len);
    @memset(colors, 0);
    for (f.insts.items, 0..) |_, start| {
        var current = start;
        while (colors[current] == 0 and f.insts.items[current].op == .copy) {
            colors[current] = 1;
            const next = f.insts.items[current].a;
            if (next == .none) return false;
            current = next.index();
        }
        if (colors[current] == 1) return false;
        current = start;
        while (colors[current] == 1) {
            colors[current] = 2;
            current = f.insts.items[current].a.index();
        }
    }
    return true;
}

fn normalizedName(name: []const u8) []const u8 {
    if (std.mem.startsWith(u8, name, render.declaration_prefix)) {
        const tail = name[render.declaration_prefix.len..];
        if (std.mem.indexOfScalar(u8, tail, '_')) |at| return tail[at..];
    }
    return name;
}

fn position(context: snapshot.Context, program: typed.Program, checked: typed.Function, span: u32) Error!Position {
    if (span == 0) return .zero;
    // Declaration spans are headers; local scope/body nodes can extend past them.
    const start = checked.declaration.start;
    const end = @max(checked.declaration.end, program.statements[@backingInt(checked.scope.body)].span.end);
    if (span >= start and span <= end) return .{ .local = @intCast(span - start) };
    return .{ .external = try snapshot.locate(context, span) };
}

fn offset(context: snapshot.Context, checked: typed.Function, value: Position) Error!u32 {
    return switch (value) {
        .zero => 0,
        .local => |delta| std.math.cast(u32, checked.declaration.start + delta) orelse error.InvalidSnapshot,
        .external => |loc| snapshot.relocate(context, loc),
    };
}

fn captureFunction(a: std.mem.Allocator, context: snapshot.Context, program: typed.Program, checked: typed.Function, f: ir.Function) Error!Function {
    const positions = try a.alloc(Position, f.insts.items.len + 1);
    positions[0] = try position(context, program, checked, f.span);
    for (f.insts.items, 0..) |inst, i| positions[i + 1] = try position(context, program, checked, inst.span);
    const blocks = try a.alloc(snapshot.Block, f.blocks.items.len);
    for (blocks, f.blocks.items) |*block, original| block.* = .{ .insts = original.insts.items, .preds = original.preds.items };
    return .{ .value = .{ .name = f.name, .signature = f.signature, .insts = f.insts.items, .blocks = blocks, .extra = f.extra.items, .loops = f.loops.items, .span = f.span }, .positions = positions };
}

fn relocatedString(raw: usize, old: usize, new: usize, count: usize) Error!u32 {
    // Lowering always allocates its literals/private metadata in this function.
    if (raw < old or raw - old >= count) return error.InvalidSnapshot;
    return std.math.cast(u32, new + (raw - old)) orelse error.InvalidSnapshot;
}

fn restoreFunction(a: std.mem.Allocator, context: snapshot.Context, checked: typed.Function, dto: Function, old: usize, new: usize) Error!ir.Function {
    const f = dto.value;
    if (dto.positions.len != f.insts.len + 1 or new > context.module.strings.items.len) return error.InvalidSnapshot;
    const count = context.module.strings.items.len - new;
    var name = f.name;
    if (std.mem.startsWith(u8, name, render.declaration_prefix)) {
        const tail = name[render.declaration_prefix.len..];
        const at = std.mem.indexOfScalar(u8, tail, '_') orelse return error.InvalidSnapshot;
        const original = std.fmt.parseInt(usize, tail[0..at], 10) catch return error.InvalidSnapshot;
        name = try std.fmt.allocPrint(a, "{s}{d}{s}", .{ render.declaration_prefix, try relocatedString(original, old, new, count), tail[at..] });
    }
    const insts = try a.dupe(ir.Inst, f.insts);
    for (insts, 0..) |*inst, i| {
        if (!context.module.valid(inst.ty)) return error.InvalidSnapshot;
        inst.span = try offset(context, checked, dto.positions[i + 1]);
        if (inst.op == .str_const) inst.data = try relocatedString(std.math.cast(usize, inst.data) orelse return error.InvalidSnapshot, old, new, count);
        if (inst.op == .@"unreachable" and inst.data & flags.assertion_trap != 0) inst.data = (inst.data & 0xffffffff00000000) | try relocatedString(@as(u32, @truncate(inst.data)), old, new, count);
    }
    const blocks = try a.alloc(ir.Block, f.blocks.len);
    for (blocks, f.blocks) |*block, original| block.* = .{
        .insts = .{ .items = try a.dupe(ir.Ref, original.insts), .capacity = original.insts.len },
        .preds = .{ .items = try a.dupe(ir.BlockId, original.preds), .capacity = original.preds.len },
    };
    var sig = f.signature;
    if (!validSignature(context.module, sig)) return error.InvalidSnapshot;
    sig.params = try a.dupe(ir.Type, sig.params);
    return .{
        .name = try a.dupe(u8, name),
        .signature = sig,
        .span = try offset(context, checked, dto.positions[0]),
        .insts = .{ .items = insts, .capacity = insts.len },
        .blocks = .{ .items = blocks, .capacity = blocks.len },
        .extra = .{ .items = try a.dupe(ir.Ref, f.extra), .capacity = f.extra.len },
        .loops = .{ .items = try a.dupe(ir.Loop, f.loops), .capacity = f.loops.len },
    };
}

fn clone(a: std.mem.Allocator, comptime T: type, value: T) std.mem.Allocator.Error!T {
    return switch (@typeInfo(T)) {
        .pointer => |p| blk: {
            if (p.size != .slice) @compileError("cached tables may only contain slices");
            const out = try a.alloc(p.child, value.len);
            for (out, value) |*copy, original| copy.* = try clone(a, p.child, original);
            break :blk out;
        },
        .@"struct" => |s| blk: {
            var out: T = undefined;
            inline for (s.field_names, s.field_types) |name, F| @field(out, name) = try clone(a, F, @field(value, name));
            break :blk out;
        },
        .@"union" => |u| blk: {
            const tag = std.meta.activeTag(value);
            inline for (u.field_names, u.field_types) |name, F| if (tag == @field(std.meta.Tag(T), name)) break :blk @unionInit(T, name, try clone(a, F, @field(value, name)));
            unreachable;
        },
        else => value,
    };
}

fn frame(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
    var len = std.mem.nativeToLittle(u64, bytes.len);
    hash.update(std.mem.asBytes(&len));
    hash.update(bytes);
}

const TreeHash = struct {
    hash: std.crypto.hash.Blake3 = .init(.{}),
    program: typed.Program,
    context: snapshot.Context,
    checked: ?typed.Function,

    fn init(program: typed.Program, context: snapshot.Context, checked: ?typed.Function) TreeHash {
        return .{ .program = program, .context = context, .checked = checked };
    }

    fn finish(self: *TreeHash) stage.Digest {
        var out: stage.Digest = undefined;
        self.hash.final(&out);
        return out;
    }

    fn value(self: *TreeHash, v: anytype) Error!void {
        const T = @TypeOf(v);
        if (T == typed.NodeId) return self.value(self.program.nodes[@backingInt(v)]);
        if (T == typed.StatementId) return self.value(self.program.statements[@backingInt(v)]);
        if (T == language.source.Span) {
            if (self.checked) |checked| {
                try self.value(try position(self.context, self.program, checked, std.math.cast(u32, v.start) orelse return error.InvalidSnapshot));
                try self.value(v.end - v.start);
            }
            return;
        }
        if (T == typed.Field) {
            try self.value(v.name);
            try self.value(v.ty);
            try self.value(v.boxed);
            // This is a syntax ordinal, not a checked NodeId. Actual defaults
            // are expanded into the caller's checked tree and hashed there.
            try self.value(v.default_value != null);
            return;
        }
        switch (@typeInfo(T)) {
            .int => {
                var little = std.mem.nativeToLittle(T, v);
                self.hash.update(std.mem.asBytes(&little));
            },
            .float => try self.value(@as(@Int(.unsigned, @bitSizeOf(T)), @bitCast(v))),
            .bool => self.hash.update(&.{@intFromBool(v)}),
            .void => {},
            .@"enum" => try self.value(@backingInt(v)),
            .optional => {
                try self.value(v != null);
                if (v) |present| try self.value(present);
            },
            .pointer => |ptr| {
                if (ptr.size != .slice) @compileError("checked cache inputs must own slices");
                try self.value(@as(u64, v.len));
                if (ptr.child == u8) self.hash.update(v) else for (v) |item| try self.value(item);
            },
            .array => for (v) |item| try self.value(item),
            .@"struct" => |s| inline for (s.field_names) |name| try self.value(@field(v, name)),
            .@"union" => |u| {
                const tag = std.meta.activeTag(v);
                try self.value(tag);
                inline for (u.field_names) |name| if (tag == @field(std.meta.Tag(T), name)) try self.value(@field(v, name));
            },
            else => @compileError("checked cache input needs explicit hashing: " ++ @typeName(T)),
        }
    }
};
