//! Portable function-stage snapshots. Function/type ordinals are guarded by the
//! complete declaration catalog; strings and source offsets relocate on restore.
const std = @import("std");
const language = @import("mylang");
const codec = language.persist_codec;
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const render = @import("build_render.zig");

/// Allocation or a stale/malformed snapshot; callers recompute invalid entries.
pub const Error = error{ OutOfMemory, InvalidSnapshot };
/// A normalized snapshot or declaration-layout digest.
pub const Digest = [32]u8;

/// Original line/column survives earlier same-line edits in a source file.
/// Raw offsets are reserved for source-less IR and the zero-span sentinel.
pub const Location = struct {
    origin: ?u32 = null,
    offset: u32,
    point: ?struct { line: u32, column: u32 } = null,
};

/// Lazily index literal bytes already in the live module, avoiding duplicate strings.
pub const StringIndex = struct {
    values: std.StringHashMapUnmanaged(u32) = .empty,
    scanned: usize = 0,
};

/// Current catalogs and optional shared string index. Restores run on the owning
/// coordinator because they may append strings to the mutable module.
pub const Context = struct {
    module: *ir.Module,
    source: ?language.source.Source = null,
    strings: ?*StringIndex = null,

    /// Allocate an index on the build arena for repeated function restorations.
    pub fn init(a: std.mem.Allocator, module: *ir.Module, source: ?language.source.Source) std.mem.Allocator.Error!Context {
        const strings = try a.create(StringIndex);
        strings.* = .{};
        return .{ .module = module, .source = source, .strings = strings };
    }
};

/// A block uses owned slices, never a persisted ArrayList capacity.
pub const Block = struct { insts: []ir.Ref, preds: []ir.BlockId };
/// Function data with exactly-sized slices and local string/location indices.
pub const Function = struct {
    name: []const u8,
    signature: ir.Signature,
    insts: []ir.Inst,
    blocks: []Block,
    extra: []ir.Ref,
    loops: []ir.Loop,
    span: u32,
};
/// One self-owned stage result, valid after its input arena is destroyed.
pub const Wire = struct { function: Function, strings: []const []const u8, locations: []Location };

/// Normalize a source offset without retaining merged-source starts in a key.
pub fn locate(context: Context, span: u32) Error!Location {
    const source = context.source orelse return .{ .offset = span };
    if (span == 0) return .{ .offset = 0 };
    if (source.origins.len == 0) {
        return sourceLocation(source, span, null);
    }
    const original = source.originalSpan(.{ .start = span, .end = span }) catch return error.InvalidSnapshot;
    return sourceLocation(source.origins[original.input].original, original.span.start, @intCast(original.input));
}

fn sourceLocation(source: language.source.Source, offset: usize, origin: ?u32) Error!Location {
    if (offset > source.bytes.len or source.line_starts.len == 0) return error.InvalidSnapshot;
    const at = source.physicalLocation(offset);
    return .{ .origin = origin, .offset = 0, .point = .{
        .line = std.math.cast(u32, at.line) orelse return error.InvalidSnapshot,
        .column = std.math.cast(u32, at.column) orelse return error.InvalidSnapshot,
    } };
}

fn sourceOffset(source: language.source.Source, location: Location) Error!usize {
    const point = location.point orelse return error.InvalidSnapshot;
    if (location.offset != 0 or point.line == 0 or point.column == 0) return error.InvalidSnapshot;
    if (point.line > source.line_starts.len) return error.InvalidSnapshot;
    const index = point.line - 1;
    const start = source.line_starts[index];
    const end = if (point.line < source.line_starts.len) source.line_starts[point.line] - 1 else source.bytes.len;
    if (start > end or point.column - 1 > end - start) return error.InvalidSnapshot;
    return start + point.column - 1;
}

/// Restore a normalized location only when it fits the current source mapping.
pub fn relocate(context: Context, location: Location) Error!u32 {
    const source = context.source orelse {
        if (location.origin != null or location.point != null) return error.InvalidSnapshot;
        return location.offset;
    };
    if (location.origin) |index| {
        if (index >= source.origins.len) return error.InvalidSnapshot;
        const original = source.origins[index];
        const offset = try sourceOffset(original.original, location);
        return std.math.cast(u32, original.start + offset) orelse error.InvalidSnapshot;
    }
    if (location.point == null and location.offset == 0) return 0;
    if (source.origins.len != 0) return error.InvalidSnapshot;
    return std.math.cast(u32, try sourceOffset(source, location)) orelse error.InvalidSnapshot;
}

/// Guard the numeric function/type catalogs and source-file ordering. Ordinary
/// body/literal edits and changes to another file's byte length leave this stable.
pub fn layout(a: std.mem.Allocator, context: Context) std.mem.Allocator.Error!Digest {
    var writer = codec.Writer.init(a);
    defer writer.deinit();
    try writer.write([]const u8, "source-line-column-v2");
    try writer.write(bool, context.module.single_owner);
    try writer.write(bool, context.module.zero_rc);
    try writer.write([]const ir.Type, context.module.shared_lists.items);
    try writer.write([]const ir.Compound, context.module.compounds.items);
    try writer.write(u64, context.module.functions.items.len);
    for (context.module.functions.items) |function| {
        const name = function.name;
        if (function.signature.linkage == .runtime_c and std.mem.startsWith(u8, name, render.declaration_prefix)) {
            const tail = name[render.declaration_prefix.len..];
            const separator = std.mem.indexOfScalar(u8, tail, '_');
            // The authorization's string slot is relocated separately and does
            // not change the declaration's IR function ordinal or signature.
            try writer.write([]const u8, render.declaration_prefix);
            try writer.write([]const u8, if (separator) |at| tail[at + 1 ..] else tail);
        } else {
            try writer.write([]const u8, name);
            try writer.write([]const u8, "");
        }
        try writer.write(ir.Signature, function.signature);
    }
    try writer.write(u32, context.module.entry);
    if (context.source) |source| {
        try writer.write(bool, true);
        try writer.write([]const u8, source.path);
        try writer.write(u64, source.origins.len);
        for (source.origins) |origin| try writer.write([]const u8, origin.original.path);
    } else try writer.write(bool, false);
    var out: Digest = undefined;
    std.crypto.hash.Blake3.hash(writer.bytes.items, &out, .{});
    return out;
}

fn stringIndex(a: std.mem.Allocator, context: Context, values: *std.ArrayList([]const u8), raw: u64) Error!u32 {
    if (raw >= context.module.strings.items.len) return error.InvalidSnapshot;
    const text = context.module.strings.items[@intCast(raw)];
    for (values.items, 0..) |previous, index| if (std.mem.eql(u8, previous, text)) return @intCast(index);
    try values.append(a, try a.dupe(u8, text));
    return @intCast(values.items.len - 1);
}

/// Capture a complete function while relocating string references and source spans.
pub fn capture(a: std.mem.Allocator, context: Context, function: ir.Function) Error!Wire {
    const insts = try a.dupe(ir.Inst, function.insts.items);
    const locations = try a.alloc(Location, insts.len + 1);
    locations[0] = try locate(context, function.span);
    var strings: std.ArrayList([]const u8) = .empty;
    for (insts, 0..) |*inst, index| {
        locations[index + 1] = try locate(context, inst.span);
        inst.span = @intCast(index + 1);
        if (inst.op == .str_const) {
            inst.data = try stringIndex(a, context, &strings, inst.data);
        } else if (inst.op == .@"unreachable" and inst.data & flags.assertion_trap != 0) {
            inst.data = (inst.data & 0xffffffff00000000) | try stringIndex(a, context, &strings, @as(u32, @truncate(inst.data)));
        }
    }
    const blocks = try a.alloc(Block, function.blocks.items.len);
    for (blocks, function.blocks.items) |*block, original| block.* = .{
        .insts = try a.dupe(ir.Ref, original.insts.items),
        .preds = try a.dupe(ir.BlockId, original.preds.items),
    };
    var signature = function.signature;
    signature.params = try a.dupe(ir.Type, signature.params);
    return .{
        .function = .{
            .name = try a.dupe(u8, function.name),
            .signature = signature,
            .insts = insts,
            .blocks = blocks,
            .extra = try a.dupe(ir.Ref, function.extra.items),
            .loops = try a.dupe(ir.Loop, function.loops.items),
            .span = 0,
        },
        .strings = try strings.toOwnedSlice(a),
        .locations = locations,
    };
}

fn internString(a: std.mem.Allocator, context: Context, bytes: []const u8) std.mem.Allocator.Error!u32 {
    if (context.strings) |index| {
        while (index.scanned < context.module.strings.items.len) : (index.scanned += 1) {
            const value = context.module.strings.items[index.scanned];
            const slot = try index.values.getOrPut(a, value);
            if (!slot.found_existing) slot.value_ptr.* = @intCast(index.scanned);
        }
        if (index.values.get(bytes)) |found| return found;
    } else {
        for (context.module.strings.items, 0..) |value, i| if (std.mem.eql(u8, value, bytes)) return @intCast(i);
    }
    const text = try a.dupe(u8, bytes);
    try context.module.strings.append(a, text);
    return @intCast(context.module.strings.items.len - 1);
}

/// Restore onto the result arena; every mutable list's capacity equals its length.
/// The caller must verify `layout` before applying numeric type/function references.
pub fn restore(a: std.mem.Allocator, context: Context, wire: Wire) Error!ir.Function {
    const f = wire.function;
    if (f.span >= wire.locations.len or wire.locations.len != f.insts.len + 1) return error.InvalidSnapshot;
    const strings = try a.alloc(u32, wire.strings.len);
    for (strings, wire.strings) |*index, bytes| index.* = try internString(a, context, bytes);
    var restored: ir.Function = .{
        .name = try a.dupe(u8, f.name),
        .signature = f.signature,
        .span = try relocate(context, wire.locations[f.span]),
    };
    restored.signature.params = try a.dupe(ir.Type, f.signature.params);
    const insts = try a.dupe(ir.Inst, f.insts);
    for (insts) |*inst| {
        if (inst.span >= wire.locations.len or !context.module.valid(inst.ty)) return error.InvalidSnapshot;
        inst.span = try relocate(context, wire.locations[inst.span]);
        if (inst.op == .str_const) {
            if (inst.data >= strings.len) return error.InvalidSnapshot;
            inst.data = strings[@intCast(inst.data)];
        } else if (inst.op == .@"unreachable" and inst.data & flags.assertion_trap != 0) {
            const index: u32 = @truncate(inst.data);
            if (index >= strings.len) return error.InvalidSnapshot;
            inst.data = (inst.data & 0xffffffff00000000) | strings[index];
        }
    }
    restored.insts = .{ .items = insts, .capacity = insts.len };
    const blocks = try a.alloc(ir.Block, f.blocks.len);
    for (blocks, f.blocks) |*block, original| block.* = .{
        .insts = .{ .items = try a.dupe(ir.Ref, original.insts), .capacity = original.insts.len },
        .preds = .{ .items = try a.dupe(ir.BlockId, original.preds), .capacity = original.preds.len },
    };
    restored.blocks = .{ .items = blocks, .capacity = blocks.len };
    restored.extra = .{ .items = try a.dupe(ir.Ref, f.extra), .capacity = f.extra.len };
    restored.loops = .{ .items = try a.dupe(ir.Loop, f.loops), .capacity = f.loops.len };
    try validate(context.module, &restored);
    return restored;
}

/// Hash the normalized snapshot; decoded values never depend on global string slots.
pub fn digest(a: std.mem.Allocator, context: Context, function: ir.Function) Error!Digest {
    const wire = try capture(a, context, function);
    var writer = codec.Writer.init(a);
    defer writer.deinit();
    try writer.write(Wire, wire);
    var result: Digest = undefined;
    std.crypto.hash.Blake3.hash(writer.bytes.items, &result, .{});
    return result;
}

/// Reject invalid local/global indexes before a decoded artifact reaches a pass.
fn validate(module: *const ir.Module, f: *const ir.Function) Error!void {
    if (!module.valid(f.signature.ret)) return error.InvalidSnapshot;
    for (f.signature.params) |ty| if (!module.valid(ty)) return error.InvalidSnapshot;
    for (f.blocks.items) |block| {
        for (block.insts.items) |ref| if (ref == .none or ref.index() >= f.insts.items.len) return error.InvalidSnapshot;
        for (block.preds.items) |pred| if (pred.index() >= f.blocks.items.len) return error.InvalidSnapshot;
    }
    for (f.insts.items) |inst| {
        if (inst.op.hasExtra()) {
            const slice = ir.ExtraSlice.unpack(inst.data);
            if (slice.start > f.extra.items.len or slice.len > f.extra.items.len - slice.start) return error.InvalidSnapshot;
        }
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |at| {
            const ref = operands.get(at);
            if (ref != .none and ref.index() >= f.insts.items.len) return error.InvalidSnapshot;
        }
        switch (inst.op) {
            .call => if (inst.a.index() >= module.functions.items.len) return error.InvalidSnapshot,
            .func_ref => if (inst.data >= module.functions.items.len) return error.InvalidSnapshot,
            .jump => if (inst.data >= f.blocks.items.len) return error.InvalidSnapshot,
            .branch => {
                const targets = ir.unpackTargets(inst.data);
                if (targets.then.index() >= f.blocks.items.len or targets.otherwise.index() >= f.blocks.items.len) return error.InvalidSnapshot;
            },
            else => {},
        }
    }
    for (f.loops.items) |loop| {
        for ([_]ir.BlockId{ loop.header, loop.body, loop.latch, loop.exit }) |block| if (block.index() >= f.blocks.items.len) return error.InvalidSnapshot;
    }
}
