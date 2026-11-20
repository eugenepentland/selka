//! Canonical Core IR hashing independent of test execution and pipeline options.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const equality = @import("build_equality.zig");
const ir = @import("ir.zig");
const source_location = @import("source_location.zig");
const flags = @import("flags.zig");
const render = @import("build_render.zig");

/// Structural function, type, or callee identity.
pub const Digest = [32]u8;
/// Allocation failure or lowering metadata the canonical form does not recognize.
pub const Error = error{ OutOfMemory, UnknownMetadata };

const copy_prefix = @import("stable_names.zig").owned_copy_prefix;
const show_prefix = "myl_core_show_";

fn put(hash: *fast_blake3.Blake3, comptime T: type, value: T) void {
    var encoded: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &encoded, value, .little);
    hash.update(&encoded);
}

fn text(hash: *fast_blake3.Blake3, bytes: []const u8) void {
    put(hash, u64, bytes.len);
    hash.update(bytes);
}

/// A type's digest and the lowest walk-stack position it refers back to, if any.
const Walked = struct { digest: Digest, low: ?usize = null };
const CachedType = struct { digest: Digest, cyclic: bool };

/// Digests computed once per module: compound and builtin types, callee references,
/// and the location of the last span asked for.
const Memo = struct {
    types: []?CachedType,
    builtins: [ir.Type.first_compound + 4]?Digest = @splat(null),
    callees: []?Digest,
    span: ?struct { start: u32, at: source_location.Location } = null,
};

/// The canonical form of one module's types, strings, callees and render metadata.
pub const Canon = struct {
    a: std.mem.Allocator,
    module: *const ir.Module,
    locator: source_location.Locator,
    memo: Memo,
    /// The type walk's state: the stack of types being walked, the render shapes seen and the names being walked.
    descent: struct {
        stack: std.ArrayList(u32) = .empty,
        shapes: std.StringHashMapUnmanaged(usize) = .empty,
        walking: std.ArrayList([]const u8) = .empty,
    } = .{},
    /// Whether a function's digest covers the original path, line and column of its spans. The optimizer's records and emission's
    /// keys do (the object carries debug information and trap lines); the engine's parts do not (`plainDigest`), so a line shift
    /// moves none of them and consumers relocate positions from the run's lines.
    positions: bool = true,
    /// Whether a nominal compound is digested by its stable name (`ir.Module.nominal`) instead of its structure, so that two
    /// records of one shape are two types (`named`). Function bodies are digested by structure; names find a type again.
    by_name: bool = false,

    /// A second form of this canon for finding types and callees by name: nominal compounds digest as their names, and the
    /// memos start empty. It shares the render shapes, which are read-only once `prepare` has run.
    pub fn named(self: *const Canon) std.mem.Allocator.Error!Canon {
        const types = try self.a.alloc(?CachedType, self.module.compounds.items.len);
        @memset(types, null);
        const callees = try self.a.alloc(?Digest, self.module.functions.items.len);
        @memset(callees, null);
        var out: Canon = .{ .a = self.a, .module = self.module, .locator = self.locator, .memo = .{ .types = types, .callees = callees }, .by_name = true };
        out.descent.shapes = self.descent.shapes;
        return out;
    }

    /// The canonical form's tables, in the caller's arena `a`.
    pub fn prepare(a: std.mem.Allocator, module: *const ir.Module, locator: source_location.Locator) Error!Canon {
        equality.validateModule(a, module) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnsupportedInstruction => return error.UnknownMetadata,
        };
        const types = try a.alloc(?CachedType, module.compounds.items.len);
        @memset(types, null);
        const callees = try a.alloc(?Digest, module.functions.items.len);
        @memset(callees, null);
        var canon: Canon = .{ .a = a, .module = module, .locator = locator, .memo = .{ .types = types, .callees = callees } };
        // `myl_core_render_shape_<string>_<id>` authorizes string `<string>` as id `<id>`'s shape.
        for (module.functions.items) |function| {
            if (function.signature.linkage != .runtime_c or !std.mem.startsWith(u8, function.name, render.declaration_prefix)) continue;
            const authority = function.name[render.declaration_prefix.len..];
            const split = std.mem.indexOfScalar(u8, authority, '_') orelse return error.UnknownMetadata;
            const index = std.fmt.parseInt(usize, authority[0..split], 10) catch return error.UnknownMetadata;
            if (index >= module.strings.items.len) return error.UnknownMetadata;
            try canon.descent.shapes.put(a, authority[split + 1 ..], index);
        }
        return canon;
    }

    /// Digest the structural type graph, memoizing context-independent roots.
    pub fn typeDigest(self: *Canon, ty: ir.Type) Error!Digest {
        return (try self.walk(ty)).digest;
    }

    /// Hash a type by structure. A cycle (closed through a box) hashes as its depth on
    /// the walk; a digest that depends on where the walk entered is not memoized.
    fn walk(self: *Canon, ty: ir.Type) Error!Walked {
        var hash = fast_blake3.Blake3.init(.{});
        if (!ty.isCompound()) {
            const raw = @backingInt(ty);
            // The four high builtins (`byte_buffer`, `capability`, `resource`, `bytes_view`) follow the low ones.
            const slot: usize = if (raw < ir.Type.first_compound) raw else ir.Type.first_compound + (raw - @backingInt(ir.Type.byte_buffer));
            if (slot >= self.memo.builtins.len) return error.UnknownMetadata;
            if (self.memo.builtins[slot]) |known| return .{ .digest = known };
            text(&hash, "builtin");
            put(&hash, u32, raw);
            self.memo.builtins[slot] = final(&hash);
            return .{ .digest = self.memo.builtins[slot].? };
        }
        const index: u32 = @backingInt(ty) - ir.Type.first_compound;
        if (index >= self.memo.types.len) try self.growTypes();
        if (index >= self.memo.types.len) return error.UnknownMetadata;
        if (self.by_name and index < self.module.nominal.len) if (self.module.nominal[index]) |stable| {
            text(&hash, "nominal");
            hash.update(&stable);
            return .{ .digest = final(&hash) };
        };
        if (self.memo.types[index]) |known| {
            // A closed cyclic digest describes this root, not a nested entry into
            // the same cycle. Reusing it there makes the key depend on query order.
            if (!known.cyclic or self.descent.stack.items.len == 0) return .{ .digest = known.digest };
        }
        if (std.mem.indexOfScalar(u32, self.descent.stack.items, index)) |position| {
            text(&hash, "cycle");
            put(&hash, u64, self.descent.stack.items.len - position);
            return .{ .digest = final(&hash), .low = position };
        }
        const position = self.descent.stack.items.len;
        try self.descent.stack.append(self.a, index);
        defer _ = self.descent.stack.pop();
        var low: ?usize = null;
        const compound = self.module.compounds.items[index];
        text(&hash, @tagName(compound));
        if (compound == .list) put(&hash, u8, 1);
        const children: []const ir.Type = switch (compound) {
            .list => |element| &.{element},
            .list_view => |element| &.{element},
            .box => |inner| &.{inner},
            .borrowed => |inner| &.{inner},
            .record => |fields| fields,
            .@"union" => |cases| cases,
            .dict => |pair| &.{ pair.key, pair.value },
            .array => |array| blk: {
                put(&hash, u32, array.n);
                break :blk &.{array.elem};
            },
            .@"fn" => |pointer| blk: {
                put(&hash, u8, @backingInt(pointer.linkage));
                passing(&hash, pointer.passing);
                borrowContract(&hash, pointer.borrow);
                put(&hash, u64, pointer.params.len);
                break :blk try std.mem.concat(self.a, ir.Type, &.{ pointer.params, &.{pointer.ret} });
            },
        };
        put(&hash, u64, children.len);
        for (children) |child| {
            const walked = try self.walk(child);
            hash.update(&walked.digest);
            if (walked.low) |reference| low = @min(low orelse reference, reference);
        }
        const digest = final(&hash);
        if (low == null or position == 0) self.memo.types[index] = .{ .digest = digest, .cyclic = low != null };
        return .{ .digest = digest, .low = low };
    }

    /// Bind ABI modes and canonical parameter and return types.
    pub fn signature(self: *Canon, hash: *fast_blake3.Blake3, sig: ir.Signature) Error!void {
        put(hash, u64, sig.params.len);
        for (sig.params) |param| hash.update(&try self.typeDigest(param));
        hash.update(&try self.typeDigest(sig.ret));
        put(hash, u8, @backingInt(sig.linkage));
        passing(hash, sig.passing);
        borrowContract(hash, sig.borrow);
    }

    /// Bind the original file path, line and column of a source offset.
    pub fn locate(self: *Canon, hash: *fast_blake3.Blake3, span: u32) void {
        if (!self.positions) return;
        const at = if (self.memo.span) |last| if (last.start == span) last.at else self.locator.locate(self.locator.context, span) else self.locator.locate(self.locator.context, span);
        self.memo.span = .{ .start = span, .at = at };
        put(hash, u32, at.line);
        put(hash, u32, at.column);
        text(hash, at.path);
    }

    fn string(self: *Canon, hash: *fast_blake3.Blake3, index: u64) Error!void {
        if (index >= self.module.strings.items.len) return error.UnknownMetadata;
        text(hash, self.module.strings.items[@intCast(index)]);
    }

    /// How a reference to function `index` is hashed: its name and signature, except
    /// that the equality and rendering adapters, whose names carry lowering-local type
    /// and source ids, are named by the structure those ids stand for. A pass may
    /// declare a runtime helper after `prepare`, so the memo grows on demand.
    pub fn callee(self: *Canon, index: u32) Error!Digest {
        if (index >= self.module.functions.items.len) return error.UnknownMetadata;
        if (index >= self.memo.callees.len) try self.growCallees();
        if (self.memo.callees[index]) |known| return known;
        self.memo.callees[index] = try self.referenceDigest(index);
        return self.memo.callees[index].?;
    }

    /// Extend the callee memo to the module's current function count, keeping
    /// every digest already computed.
    fn growCallees(self: *Canon) Error!void {
        const grown = try self.a.alloc(?Digest, self.module.functions.items.len);
        @memset(grown, null);
        @memcpy(grown[0..self.memo.callees.len], self.memo.callees);
        self.memo.callees = grown;
    }

    /// Extend the compound-type memo to the module's current compound count, for
    /// a pass that interns a type after `prepare`.
    fn growTypes(self: *Canon) Error!void {
        const grown = try self.a.alloc(?CachedType, self.module.compounds.items.len);
        @memset(grown, null);
        @memcpy(grown[0..self.memo.types.len], self.memo.types);
        self.memo.types = grown;
    }

    fn referenceDigest(self: *Canon, index: u32) Error!Digest {
        const function = self.module.functions.items[index];
        var hash = fast_blake3.Blake3.init(.{});
        text(&hash, "zero-rc");
        text(&hash, "zero-rc");
        try self.signature(&hash, function.signature);
        const name = function.name;
        if (equality.declaration(self.module, &function) catch return error.UnknownMetadata) {
            text(&hash, equality.prefix);
            hash.update(&try self.typeDigest(function.signature.params[0]));
        } else if (function.signature.linkage == .runtime_c and std.mem.startsWith(u8, name, copy_prefix)) {
            text(&hash, copy_prefix);
            hash.update(&try self.typeDigest(function.signature.ret));
        } else if (function.signature.linkage == .runtime_c and std.mem.startsWith(u8, name, show_prefix)) {
            text(&hash, show_prefix);
            hash.update(&try self.shape(name[show_prefix.len..]));
        } else if (function.signature.linkage == .runtime_c and std.mem.startsWith(u8, name, render.declaration_prefix)) {
            return error.UnknownMetadata;
        } else text(&hash, name);
        return final(&hash);
    }

    /// A rendering descriptor by content: its fields and its children's descriptors.
    fn shape(self: *Canon, id: []const u8) Error!Digest {
        var hash = fast_blake3.Blake3.init(.{});
        for (self.descent.walking.items, 0..) |active, depth| if (std.mem.eql(u8, active, id)) {
            text(&hash, "cycle");
            put(&hash, u64, self.descent.walking.items.len - depth);
            return final(&hash);
        };
        const index = self.descent.shapes.get(id) orelse return error.UnknownMetadata;
        const marker = try std.fmt.allocPrint(self.a, "{s}{s}|", .{ render.prefix, id });
        const stored = self.module.strings.items[index];
        if (!std.mem.startsWith(u8, stored, marker)) return error.UnknownMetadata;
        const parsed = std.json.parseFromSliceLeaky(render.Shape, self.a, stored[marker.len..], .{}) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.UnknownMetadata;
        };
        try self.descent.walking.append(self.a, id);
        defer _ = self.descent.walking.pop();
        for ([_]u32{ parsed.kind, parsed.size, parsed.count, parsed.aux }) |field| put(&hash, u32, field);
        put(&hash, u64, parsed.offsets.len);
        for (parsed.offsets) |offset| put(&hash, u32, offset);
        put(&hash, u64, parsed.names.len);
        for (parsed.names) |name| text(&hash, name);
        put(&hash, u64, parsed.children.len);
        for (parsed.children) |child| hash.update(&try self.shape(child));
        return final(&hash);
    }

    /// `functionDigest` without the original path, line and column of any span: the digest of the function as its meaning, which a
    /// comment above it, or lines added in its module, leaves as it was.
    pub fn plainDigest(self: *Canon, index: u32) Error!Digest {
        const before = self.positions;
        self.positions = false;
        defer self.positions = before;
        return self.functionDigest(index);
    }

    /// Function `index` as its meaning: signature, instructions with canonical
    /// types, callees and strings, blocks, operand lists, loops and positions.
    pub fn functionDigest(self: *Canon, index: u32) Error!Digest {
        const f = self.module.functions.items[index];
        // A render declaration only authorizes its metadata; nothing calls it.
        if (f.signature.linkage == .runtime_c and std.mem.startsWith(u8, f.name, render.declaration_prefix)) return @splat(0);
        if (f.signature.linkage != .internal) return self.callee(index);
        var hash = fast_blake3.Blake3.init(.{});
        text(&hash, f.name);
        text(&hash, "zero-rc");
        text(&hash, "zero-rc");
        try self.signature(&hash, f.signature);
        self.locate(&hash, f.span);
        // A `@freestanding` function emits its failed checks as faults: the promise is part of its meaning.
        if (self.module.isFreestanding(&f)) text(&hash, "freestanding");
        // A `ram` one is placed in `.ramfunc` on a device, with no jump table.
        if (self.module.isRam(&f)) text(&hash, "ram");
        put(&hash, u64, f.insts.items.len);
        for (f.insts.items) |inst| {
            put(&hash, u8, @backingInt(inst.op));
            hash.update(&try self.typeDigest(inst.ty));
            put(&hash, u32, @backingInt(inst.b));
            switch (inst.op) {
                .call => {
                    hash.update(&try self.callee(@intCast(inst.a.index())));
                    put(&hash, u64, inst.data);
                },
                .func_ref => {
                    put(&hash, u32, @backingInt(inst.a));
                    hash.update(&try self.callee(@intCast(inst.data)));
                },
                .str_const => {
                    put(&hash, u32, @backingInt(inst.a));
                    try self.string(&hash, inst.data);
                },
                .@"unreachable" => {
                    put(&hash, u32, @backingInt(inst.a));
                    put(&hash, u64, if (inst.data & flags.assertion_trap != 0) inst.data >> 32 else inst.data);
                    if (inst.data & flags.assertion_trap != 0) try self.string(&hash, @as(u32, @truncate(inst.data)));
                },
                else => {
                    put(&hash, u32, @backingInt(inst.a));
                    put(&hash, u64, inst.data);
                },
            }
            put(&hash, u8, @backingInt(inst.check));
            self.locate(&hash, inst.span);
        }
        put(&hash, u64, f.blocks.items.len);
        for (f.blocks.items) |block| {
            put(&hash, u64, block.insts.items.len);
            for (block.insts.items) |ref| put(&hash, u32, @backingInt(ref));
            put(&hash, u64, block.preds.items.len);
            for (block.preds.items) |pred| put(&hash, u32, @backingInt(pred));
        }
        put(&hash, u64, f.extra.items.len);
        for (f.extra.items) |ref| put(&hash, u32, @backingInt(ref));
        // A loop is its blocks. Its `id` only matched exits while lowering, and it counts
        // the checker's loops program-wide, so it moves with which modules were rechecked.
        put(&hash, u64, f.loops.items.len);
        for (f.loops.items) |loop| {
            for ([_]ir.BlockId{ loop.header, loop.body, loop.latch, loop.exit }) |block| put(&hash, u32, @backingInt(block));
            // `@vectorize` changes the loop's LLVM metadata, so it is part of the loop.
            put(&hash, u8, @intFromBool(loop.vectorize));
        }
        return final(&hash);
    }
};

fn passing(hash: *fast_blake3.Blake3, modes: ir.ParameterPassing) void {
    put(hash, u64, modes.owned);
    put(hash, u64, modes.consumes);
    put(hash, u64, modes.views);
    for ([_][]const u32{ modes.extra_owned, modes.extra_consumes, modes.extra_views }) |positions| {
        put(hash, u64, positions.len);
        for (positions) |position| put(hash, u32, position);
    }
}

fn borrowPath(hash: *fast_blake3.Blake3, path: []const ir.BorrowProjection) void {
    put(hash, u64, path.len);
    for (path) |step| {
        put(hash, u8, @backingInt(std.meta.activeTag(step)));
        switch (step) {
            .field, .payload => |index| put(hash, u32, index),
        }
    }
}

fn borrowContract(hash: *fast_blake3.Blake3, contract: ir.BorrowContract) void {
    borrowPath(hash, contract.path);
    put(hash, u64, contract.sources.len);
    for (contract.sources) |owner| {
        put(hash, u8, @backingInt(std.meta.activeTag(owner)));
        switch (owner) {
            .argument => |index| put(hash, u32, index),
            .result => |path| borrowPath(hash, path),
        }
    }
}

fn final(hash: *fast_blake3.Blake3) Digest {
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
