//! Compiler-issued closure identities resolved through actual callable pointers.
const std = @import("std");
const ir = @import("ir.zig");
const canonical = @import("canonical_ir.zig");
const identity = @import("canonical_closure.zig");
const llvm = @import("emit_llvm.zig");
const unit_cache = @import("unit_cache.zig");

/// Compiler-only declarations; an unresolved declaration never yields an identity.
pub const prefix = @import("callable_digest_contract.zig").prefix;
/// Actual toolchain and CPU content authority plus canonical build/runtime options.
pub const Context = struct { tool: ?identity.Digest = null, cpu: identity.Digest = @splat(0), build: []const u8 = "" };

/// Whether raw IR still contains an identity declaration requiring finalization.
pub fn needed(module: *const ir.Module) bool {
    for (module.functions.items) |function| if (marker(function)) return true;
    return false;
}

fn marker(function: ir.Function) bool {
    return function.signature.linkage == .runtime_c and std.mem.startsWith(u8, function.name, prefix);
}

/// Freeze pre-optimization implementation evidence, then synthesize pointer dispatch.
/// Missing authority, self-digest dependencies or unknown external implementations
/// produce empty text. Raw demand bodies are loaded before any digest is authorized.
pub fn prepare(a: std.mem.Allocator, module: *ir.Module, locator: llvm.Locator, context: Context, demand: ?*@import("demand_ir.zig").Context) error{ OutOfMemory, CacheMiss }!void {
    if (!needed(module)) return;
    if (demand) |raw| for (0..module.functions.items.len) |index| try raw.ensureRaw(@intCast(index));
    const shared: ?identity.Shared = if (context.tool != null) graph(a, module, locator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnknownMetadata => null,
    } else null;
    const original = module.functions.items.len;
    for (0..original) |index| {
        if (!marker(module.functions.items[index])) continue;
        const declaration = module.functions.items[index];
        module.functions.items[index] = try dispatch(a, module, declaration, shared, context);
    }
}

fn graph(a: std.mem.Allocator, module: *const ir.Module, locator: llvm.Locator) identity.Error!identity.Shared {
    const shared = try identity.Shared.build(a, module, locator);
    const edges = @constCast(shared.callees);
    for (module.functions.items, edges) |function, *targets| {
        var extended: std.ArrayList(u32) = .empty;
        try extended.appendSlice(a, targets.*);
        for (function.insts.items) |inst| {
            if (inst.op != .call_indirect) continue;
            if (inst.a == .none or inst.a.index() >= function.insts.items.len) return error.UnknownMetadata;
            const callback = function.inst(function.resolve(inst.a)).ty;
            if (module.kind(callback) != .@"fn") return error.UnknownMetadata;
            const expected = module.compound(callback).@"fn";
            for (module.functions.items, 0..) |candidate, target| {
                if (!matches(expected, candidate.signature)) continue;
                if (std.mem.indexOfScalar(u32, extended.items, @intCast(target)) == null) try extended.append(a, @intCast(target));
            }
        }
        targets.* = extended.items;
    }
    return shared;
}

fn matches(expected: ir.Signature, actual: ir.Signature) bool {
    if (actual.linkage != .internal or expected.ret != actual.ret) return false;
    if (expected.owned != actual.owned or expected.views != actual.views) return false;
    return std.mem.eql(ir.Type, expected.params, actual.params);
}

fn eligible(a: std.mem.Allocator, module: *const ir.Module, shared: identity.Shared, root: u32) std.mem.Allocator.Error!bool {
    const seen = try a.alloc(bool, module.functions.items.len);
    @memset(seen, false);
    var queue: std.ArrayList(u32) = .empty;
    try queue.append(a, root);
    seen[root] = true;
    var next: usize = 0;
    while (next < queue.items.len) : (next += 1) {
        const index = queue.items[next];
        const function = module.functions.items[index];
        if (std.mem.startsWith(u8, function.name, prefix)) return false;
        if (function.signature.linkage != .internal and !std.mem.startsWith(u8, function.name, "myl_core_")) return false;
        for (shared.callees[index]) |target| {
            if (seen[target]) continue;
            seen[target] = true;
            try queue.append(a, target);
        }
    }
    return true;
}

/// Identity of one root under already-frozen canonical evidence and exact context.
pub fn digest(a: std.mem.Allocator, module: *const ir.Module, shared: identity.Shared, root: u32, declaration: []const u8, context: Context) identity.Error!?identity.Digest {
    const tool = context.tool orelse return null;
    if (root >= module.functions.items.len or shared.callees.len != module.functions.items.len) return error.UnknownMetadata;
    if (!try eligible(a, module, shared, root)) return null;
    var hash = std.crypto.hash.Blake3.init(.{});
    unit_cache.field(&hash, "persistent-callable-closure-v1");
    unit_cache.field(&hash, @import("build_identity").compiler_identity);
    unit_cache.field(&hash, @import("target.zig").native_link_target);
    unit_cache.field(&hash, &tool);
    unit_cache.field(&hash, &context.cpu);
    unit_cache.field(&hash, context.build);
    unit_cache.field(&hash, declaration);
    try shared.reach(a, &.{root}, &hash);
    var result: identity.Digest = undefined;
    hash.final(&result);
    return result;
}

const Builder = struct {
    a: std.mem.Allocator,
    function: ir.Function,
    block: ir.BlockId,

    fn loose(self: *Builder, inst: ir.Inst) !ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@intCast(self.function.insts.items.len));
        try self.function.insts.append(self.a, inst);
        return ref;
    }
    fn emit(self: *Builder, inst: ir.Inst) !ir.Ref {
        const ref = try self.loose(inst);
        try self.function.blocks.items[self.block.index()].insts.append(self.a, ref);
        return ref;
    }
    fn newBlock(self: *Builder) !ir.BlockId {
        const next: ir.BlockId = @fromBackingInt(@intCast(self.function.blocks.items.len));
        try self.function.blocks.append(self.a, .{});
        return next;
    }
    fn result(self: *Builder, module: *ir.Module, bytes: []const u8) !void {
        const string = module.strings.items.len;
        try module.strings.append(self.a, try self.a.dupe(u8, bytes));
        const value = try self.loose(.{ .op = .str_const, .ty = .str, .data = string });
        _ = try self.emit(.{ .op = .ret, .ty = .void, .a = value });
    }
};

fn dispatch(a: std.mem.Allocator, module: *ir.Module, declaration: ir.Function, shared: ?identity.Shared, context: Context) std.mem.Allocator.Error!ir.Function {
    var b: Builder = .{ .a = a, .function = declaration, .block = @fromBackingInt(0) };
    b.function.signature.linkage = .internal;
    _ = try b.newBlock();
    const ty = declaration.signature.params[0];
    const expected = module.compound(ty).@"fn";
    const callback = try b.loose(.{ .op = .param, .ty = ty });
    if (shared) |evidence| for (module.functions.items, 0..) |candidate, root| {
        if (!matches(expected, candidate.signature) or std.mem.startsWith(u8, candidate.name, prefix)) continue;
        const value = digest(a, module, evidence, @intCast(root), declaration.name, context) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            continue;
        } orelse continue;
        const target = try b.loose(.{ .op = .func_ref, .ty = ty, .data = root });
        const equal = try b.emit(.{ .op = .cmp, .ty = .bool, .a = callback, .b = target, .data = @backingInt(ir.Predicate.eq) });
        const yes = try b.newBlock();
        const no = try b.newBlock();
        _ = try b.emit(.{ .op = .branch, .ty = .void, .a = equal, .data = ir.packTargets(yes, no) });
        try b.function.blocks.items[yes.index()].preds.append(a, b.block);
        try b.function.blocks.items[no.index()].preds.append(a, b.block);
        b.block = yes;
        try b.result(module, &std.fmt.bytesToHex(value, .lower));
        b.block = no;
    };
    try b.result(module, "");
    return b.function;
}
