//! Per-test receipt keys derived from one lowering of every ready test of a program
//! (NEW-CORE-TEST-KEYS-1). Each function gets a canonical digest: what it means, not
//! where the shared lowering placed it or its types and strings. A test's key hashes
//! the digests of the functions it reaches, so it changes exactly when they do.
const std = @import("std");
const ir = @import("ir.zig");
const emit_llvm = @import("emit_llvm.zig");
const flags = @import("flags.zig");
const render = @import("build_render.zig");

/// A function digest or a receipt key.
pub const Digest = [32]u8;
/// Allocation, or lowering metadata this module does not recognize; on the latter the
/// caller keys each test from its own lowering instead.
pub const Error = error{ OutOfMemory, UnknownMetadata };

const equal_prefix = @import("emit_values.zig").equal_prefix;
const show_prefix = "myl_core_show_";

/// One shared lowering's canonical function digests and call graph.
pub const Shared = struct {
    digests: []const Digest,
    callees: []const []const u32,

    /// Digest every function of `module` (before passes and before the test entry is
    /// added) and record whom each one calls or takes the address of. Everything is
    /// allocated in the caller's arena `a`.
    pub fn build(a: std.mem.Allocator, module: *const ir.Module, locator: emit_llvm.Locator) Error!Shared {
        var canon = try Canon.prepare(a, module, locator);
        const digests = try a.alloc(Digest, module.functions.items.len);
        const callees = try a.alloc([]const u32, module.functions.items.len);
        for (module.functions.items, digests, callees, 0..) |function, *digest, *targets, index| {
            digest.* = try canon.functionDigest(@intCast(index));
            targets.* = try calls(a, function);
        }
        return .{ .digests = digests, .callees = callees };
    }

    /// Feed `hash` the digests of `roots`, in order, and then of every other function
    /// they reach, sorted, so the key does not depend on the shared module's order.
    pub fn reach(self: Shared, a: std.mem.Allocator, roots: []const u32, hash: *std.crypto.hash.Blake3) Error!void {
        const seen = try a.alloc(bool, self.digests.len);
        @memset(seen, false);
        var queue: std.ArrayList(u32) = .empty;
        for (roots) |root| {
            if (root >= self.digests.len) return error.UnknownMetadata;
            hash.update(&self.digests[root]);
            if (seen[root]) continue;
            seen[root] = true;
            try queue.append(a, root);
        }
        var reached: std.ArrayList(Digest) = .empty;
        var next: usize = 0;
        while (next < queue.items.len) : (next += 1) {
            for (self.callees[queue.items[next]]) |callee| {
                if (seen[callee]) continue;
                seen[callee] = true;
                try queue.append(a, callee);
                try reached.append(a, self.digests[callee]);
            }
        }
        std.mem.sort(Digest, reached.items, {}, before);
        put(hash, u64, reached.items.len);
        for (reached.items) |digest| hash.update(&digest);
    }
};

/// What a test's key binds besides the functions it reaches: the run's settings, the
/// test, its entry's inputs, the type schema when its entry generates or encodes
/// values, and its roots in the shared lowering (the test, then its invariants).
pub const Test = struct { base: Digest, name: []const u8, source_path: []const u8, entry: Digest, schema: ?Digest, roots: []const u32 };

/// A test's receipt key from the shared lowering.
pub fn key(shared: Shared, a: std.mem.Allocator, t: Test) Error!Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    text(&hash, "core-test-keys-v1");
    hash.update(&t.base);
    text(&hash, t.name);
    text(&hash, @import("emit_units.zig").native_extension);
    text(&hash, t.source_path);
    hash.update(&t.entry);
    put(&hash, u8, @intFromBool(t.schema != null));
    if (t.schema) |schema| hash.update(&schema);
    try shared.reach(a, t.roots, &hash);
    return final(&hash);
}

fn before(_: void, left: Digest, right: Digest) bool {
    return std.mem.order(u8, &left, &right) == .lt;
}

/// The distinct functions `function` calls directly or takes the address of.
fn calls(a: std.mem.Allocator, function: ir.Function) Error![]const u32 {
    var targets: std.ArrayList(u32) = .empty;
    for (function.insts.items) |inst| {
        const target: u32 = switch (inst.op) {
            .call => @intCast(inst.a.index()),
            .func_ref => @intCast(inst.data),
            else => continue,
        };
        if (std.mem.indexOfScalar(u32, targets.items, target) == null) try targets.append(a, target);
    }
    return targets.items;
}

fn put(hash: *std.crypto.hash.Blake3, comptime T: type, value: T) void {
    var encoded: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &encoded, value, .little);
    hash.update(&encoded);
}

fn text(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
    put(hash, u64, bytes.len);
    hash.update(bytes);
}

/// A type's digest and the lowest walk-stack position it refers back to, if any.
const Walked = struct { digest: Digest, low: ?usize = null };

/// Digests computed once per module: compound and builtin types, callee references,
/// and the location of the last span asked for.
const Memo = struct {
    types: []?Digest,
    builtins: [ir.Type.first_compound + 3]?Digest = @splat(null),
    callees: []?Digest,
    span: ?struct { start: u32, at: emit_llvm.Location } = null,
};

/// The canonical form of one module's types, strings, callees and render metadata.
const Canon = struct {
    a: std.mem.Allocator,
    module: *const ir.Module,
    locator: emit_llvm.Locator,
    memo: Memo,
    stack: std.ArrayList(u32) = .empty,
    shapes: std.StringHashMapUnmanaged(usize) = .empty,
    walking: std.ArrayList([]const u8) = .empty,

    /// The canonical form's tables, in the caller's arena `a`.
    fn prepare(a: std.mem.Allocator, module: *const ir.Module, locator: emit_llvm.Locator) Error!Canon {
        const types = try a.alloc(?Digest, module.compounds.items.len);
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
            try canon.shapes.put(a, authority[split + 1 ..], index);
        }
        return canon;
    }

    fn typeDigest(self: *Canon, ty: ir.Type) Error!Digest {
        return (try self.walk(ty)).digest;
    }

    /// Hash a type by structure. A cycle (closed through a box) hashes as its depth on
    /// the walk; a digest that depends on where the walk entered is not memoized.
    fn walk(self: *Canon, ty: ir.Type) Error!Walked {
        var hash = std.crypto.hash.Blake3.init(.{});
        if (!ty.isCompound()) {
            const raw = @backingInt(ty);
            // The three high builtins (`byte_buffer`, `capability`, `resource`) follow the low ones.
            const slot: usize = if (raw < ir.Type.first_compound) raw else ir.Type.first_compound + (raw - @backingInt(ir.Type.byte_buffer));
            if (slot >= self.memo.builtins.len) return error.UnknownMetadata;
            if (self.memo.builtins[slot]) |known| return .{ .digest = known };
            text(&hash, "builtin");
            put(&hash, u32, raw);
            self.memo.builtins[slot] = final(&hash);
            return .{ .digest = self.memo.builtins[slot].? };
        }
        const index: u32 = @backingInt(ty) - ir.Type.first_compound;
        if (index >= self.memo.types.len) return error.UnknownMetadata;
        if (self.memo.types[index]) |known| return .{ .digest = known };
        if (std.mem.indexOfScalar(u32, self.stack.items, index)) |position| {
            text(&hash, "cycle");
            put(&hash, u64, self.stack.items.len - position);
            return .{ .digest = final(&hash), .low = position };
        }
        const position = self.stack.items.len;
        try self.stack.append(self.a, index);
        defer _ = self.stack.pop();
        var low: ?usize = null;
        const compound = self.module.compounds.items[index];
        text(&hash, @tagName(compound));
        const children: []const ir.Type = switch (compound) {
            .list => |element| &.{element},
            .box => |inner| &.{inner},
            .record => |fields| fields,
            .@"union" => |cases| cases,
            .dict => |pair| &.{ pair.key, pair.value },
            .array => |array| blk: {
                put(&hash, u32, array.n);
                break :blk &.{array.elem};
            },
            .@"fn" => |pointer| blk: {
                put(&hash, u8, @backingInt(pointer.linkage));
                put(&hash, u64, pointer.owned);
                put(&hash, u64, pointer.views);
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
        const context_free = low == null or low.? >= position;
        if (context_free) self.memo.types[index] = digest;
        return .{ .digest = digest, .low = if (context_free) null else low };
    }

    fn signature(self: *Canon, hash: *std.crypto.hash.Blake3, sig: ir.Signature) Error!void {
        put(hash, u64, sig.params.len);
        for (sig.params) |param| hash.update(&try self.typeDigest(param));
        hash.update(&try self.typeDigest(sig.ret));
        put(hash, u8, @backingInt(sig.linkage));
        put(hash, u64, sig.owned);
        put(hash, u64, sig.views);
    }

    fn locate(self: *Canon, hash: *std.crypto.hash.Blake3, span: u32) void {
        const at = if (self.memo.span) |last| if (last.start == span) last.at else self.locator.locate(self.locator.context, span) else self.locator.locate(self.locator.context, span);
        self.memo.span = .{ .start = span, .at = at };
        put(hash, u32, at.line);
        put(hash, u32, at.column);
        text(hash, at.path);
    }

    fn string(self: *Canon, hash: *std.crypto.hash.Blake3, index: u64) Error!void {
        if (index >= self.module.strings.items.len) return error.UnknownMetadata;
        text(hash, self.module.strings.items[@intCast(index)]);
    }

    /// How a reference to function `index` is hashed: its name and signature, except
    /// that the equality and rendering adapters, whose names carry lowering-local type
    /// and source ids, are named by the structure those ids stand for.
    fn callee(self: *Canon, index: u32) Error!Digest {
        if (index >= self.module.functions.items.len) return error.UnknownMetadata;
        if (self.memo.callees[index]) |known| return known;
        self.memo.callees[index] = try self.referenceDigest(index);
        return self.memo.callees[index].?;
    }

    fn referenceDigest(self: *Canon, index: u32) Error!Digest {
        const function = self.module.functions.items[index];
        var hash = std.crypto.hash.Blake3.init(.{});
        try self.signature(&hash, function.signature);
        const name = function.name;
        if (function.signature.linkage == .runtime_c and std.mem.startsWith(u8, name, equal_prefix)) {
            const id = std.fmt.parseInt(u32, name[equal_prefix.len..], 10) catch return error.UnknownMetadata;
            text(&hash, equal_prefix);
            hash.update(&try self.typeDigest(@fromBackingInt(id)));
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
        var hash = std.crypto.hash.Blake3.init(.{});
        for (self.walking.items, 0..) |active, depth| if (std.mem.eql(u8, active, id)) {
            text(&hash, "cycle");
            put(&hash, u64, self.walking.items.len - depth);
            return final(&hash);
        };
        const index = self.shapes.get(id) orelse return error.UnknownMetadata;
        const marker = try std.fmt.allocPrint(self.a, "{s}{s}|", .{ render.prefix, id });
        const stored = self.module.strings.items[index];
        if (!std.mem.startsWith(u8, stored, marker)) return error.UnknownMetadata;
        const parsed = std.json.parseFromSliceLeaky(render.Shape, self.a, stored[marker.len..], .{}) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.UnknownMetadata;
        };
        try self.walking.append(self.a, id);
        defer _ = self.walking.pop();
        for ([_]u32{ parsed.kind, parsed.size, parsed.count, parsed.aux }) |field| put(&hash, u32, field);
        put(&hash, u64, parsed.offsets.len);
        for (parsed.offsets) |offset| put(&hash, u32, offset);
        put(&hash, u64, parsed.names.len);
        for (parsed.names) |name| text(&hash, name);
        put(&hash, u64, parsed.children.len);
        for (parsed.children) |child| hash.update(&try self.shape(child));
        return final(&hash);
    }

    /// Function `index` as its meaning: signature, instructions with canonical
    /// types, callees and strings, blocks, operand lists, loops and positions.
    fn functionDigest(self: *Canon, index: u32) Error!Digest {
        const f = self.module.functions.items[index];
        // A render declaration only authorizes its metadata; nothing calls it.
        if (f.signature.linkage == .runtime_c and std.mem.startsWith(u8, f.name, render.declaration_prefix)) return @splat(0);
        if (f.signature.linkage != .internal) return self.callee(index);
        var hash = std.crypto.hash.Blake3.init(.{});
        text(&hash, f.name);
        try self.signature(&hash, f.signature);
        self.locate(&hash, f.span);
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
        }
        return final(&hash);
    }
};

fn final(hash: *std.crypto.hash.Blake3) Digest {
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

const Lines = struct {
    fn locate(_: *const anyopaque, offset: u32) emit_llvm.Location {
        return .{ .line = offset / 100 + 1, .column = offset % 100 + 1, .path = "app.my" };
    }
};
const lines: u8 = 0;
const test_locator: emit_llvm.Locator = .{ .context = &lines, .locate = Lines.locate };

/// A caller that calls `callee`, reads string `text` and makes a value of type `ty`.
fn caller(a: std.mem.Allocator, callee: u32, text_index: u64, ty: ir.Type) !ir.Function {
    var function: ir.Function = .{ .name = "app::test_one", .signature = .{ .params = &.{}, .ret = .bool }, .span = 100 };
    try function.insts.append(a, .{ .op = .call, .ty = .i64, .a = @fromBackingInt(callee), .span = 110 });
    try function.insts.append(a, .{ .op = .str_const, .ty = .str, .data = text_index, .span = 120 });
    try function.insts.append(a, .{ .op = .undef, .ty = ty, .span = 130 });
    return function;
}

fn helper(a: std.mem.Allocator, value: u64) !ir.Function {
    var function: ir.Function = .{ .name = "app::helper", .signature = .{ .params = &.{}, .ret = .i64 }, .span = 200 };
    try function.insts.append(a, .{ .op = .iconst, .ty = .i64, .data = value, .span = 210 });
    return function;
}

/// The key of root 0 or `root` in `module`, over what it reaches.
fn keyOf(a: std.mem.Allocator, module: *const ir.Module, root: u32) !Digest {
    const shared = try Shared.build(a, module, test_locator);
    return key(shared, a, .{ .base = @splat(1), .name = "app::test_one", .source_path = "app.my", .entry = @splat(2), .schema = null, .roots = &.{root} });
}

// spec: NEW-CORE-TEST-KEYS-1
test "a test's derived key names callees, types and strings by meaning, not by where the shared lowering put them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const list_first: ir.Type = @fromBackingInt(ir.Type.first_compound);
    const list_second: ir.Type = @fromBackingInt(ir.Type.first_compound + 1);
    var first: ir.Module = .{};
    try first.compounds.append(a, .{ .list = .i64 });
    try first.strings.appendSlice(a, &.{ "unused", "hi" });
    try first.functions.appendSlice(a, &.{ try caller(a, 1, 1, list_first), try helper(a, 3) });
    var second: ir.Module = .{};
    try second.compounds.appendSlice(a, &.{ .{ .box = .i64 }, .{ .list = .i64 } });
    try second.strings.append(a, "hi");
    try second.functions.appendSlice(a, &.{ try helper(a, 3), .{ .name = "app::other", .signature = .{ .params = &.{}, .ret = .void } }, try caller(a, 0, 0, list_second) });
    const one = try keyOf(a, &first, 0);
    try std.testing.expectEqualSlices(u8, &one, &try keyOf(a, &second, 2));
    second.functions.items[1] = try helper(a, 9);
    second.functions.items[1].name = "app::other";
    try std.testing.expectEqualSlices(u8, &one, &try keyOf(a, &second, 2));
    second.functions.items[0] = try helper(a, 4);
    try std.testing.expect(!std.mem.eql(u8, &one, &try keyOf(a, &second, 2)));
    second.functions.items[0] = try helper(a, 3);
    second.strings.items[0] = "ho";
    try std.testing.expect(!std.mem.eql(u8, &one, &try keyOf(a, &second, 2)));
    second.strings.items[0] = "hi";
    second.compounds.items[1] = .{ .list = .i32 };
    try std.testing.expect(!std.mem.eql(u8, &one, &try keyOf(a, &second, 2)));
}

// spec-case: NEW-CORE-TEST-KEYS-1
test "recursive types digest by structure, equality adapters by the type they compare, and unknown render metadata is refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const c0: ir.Type = @fromBackingInt(ir.Type.first_compound);
    const c1: ir.Type = @fromBackingInt(ir.Type.first_compound + 1);
    var tree: ir.Module = .{};
    try tree.compounds.appendSlice(a, &.{ .{ .@"union" = &.{ .i64, c1 } }, .{ .box = c0 } });
    try tree.strings.append(a, "hi");
    const equal_first = equal_prefix ++ std.fmt.comptimePrint("{d}", .{ir.Type.first_compound});
    try tree.functions.appendSlice(a, &.{ try caller(a, 1, 0, c0), .{ .name = equal_first, .signature = .{ .params = &.{ c1, c1 }, .ret = .bool, .linkage = .runtime_c } } });
    var swapped: ir.Module = .{};
    try swapped.compounds.appendSlice(a, &.{ .{ .box = c1 }, .{ .@"union" = &.{ .i64, c0 } } });
    try swapped.strings.append(a, "hi");
    const equal_second = equal_prefix ++ std.fmt.comptimePrint("{d}", .{ir.Type.first_compound + 1});
    try swapped.functions.appendSlice(a, &.{ try caller(a, 1, 0, c1), .{ .name = equal_second, .signature = .{ .params = &.{ c0, c0 }, .ret = .bool, .linkage = .runtime_c } } });
    try std.testing.expectEqualSlices(u8, &try keyOf(a, &tree, 0), &try keyOf(a, &swapped, 0));
    tree.functions.items[1].name = "myl_core_show_7";
    try std.testing.expectError(error.UnknownMetadata, keyOf(a, &tree, 0));
}

// spec: NEW-CORE-TEST-KEYS-2
test "a loop's program-wide checker id is outside both kinds of test key; its blocks are inside" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    try module.strings.append(a, "hi");
    var looped = try caller(a, 1, 0, .i64);
    try looped.loops.append(a, .{ .id = 625, .header = @fromBackingInt(0), .body = @fromBackingInt(1), .latch = @fromBackingInt(2), .exit = @fromBackingInt(3) });
    try module.functions.appendSlice(a, &.{ looped, try helper(a, 3) });
    const receipt = @import("test_runner_receipt.zig");
    const program: receipt.Program = .{ .module = &module, .source_path = "app.my", .locator = test_locator };
    const derived = try keyOf(a, &module, 0);
    const whole = receipt.programKey(@splat(1), "app::test_one", program);
    module.functions.items[0].loops.items[0].id = 631;
    try std.testing.expectEqualSlices(u8, &derived, &try keyOf(a, &module, 0));
    try std.testing.expectEqualSlices(u8, &whole, &receipt.programKey(@splat(1), "app::test_one", program));
    module.functions.items[0].loops.items[0].latch = @fromBackingInt(1);
    try std.testing.expect(!std.mem.eql(u8, &derived, &try keyOf(a, &module, 0)));
    try std.testing.expect(!std.mem.eql(u8, &whole, &receipt.programKey(@splat(1), "app::test_one", program)));
}
