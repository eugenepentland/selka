//! Canonical pre-pass test facts admitted by validated raw discovery and source keys.
//! Metadata hits keep unrelated instruction payloads unmaterialized.
const std = @import("std");
const ir = @import("ir.zig");
const canonical = @import("canonical_ir.zig");
const identity = @import("test_runner_identity.zig");
const lowering = @import("lowering_cache.zig");
const emit = @import("emit_llvm.zig");
const stage = @import("stage_store.zig");
const render = @import("build_render.zig");

/// Unsupported canonical metadata requests complete lowering; lost bodies request retry.
pub const Error = canonical.Error || error{CacheMiss};
/// Work performed by canonical fact extraction and metadata admission.
pub const Metrics = @import("test_runner_work.zig").Facts;
/// Fresh snapshot indices and their validated stable declaration identities.
pub const Result = struct { shared: identity.Shared, identities: []const ?stage.Digest };

const maximum_inline = 512;
const Fact = struct { identity: stage.Digest, digest: stage.Digest, count: u32, edges: []const stage.Digest, chunks: []const stage.Digest };
const Registry = std.AutoHashMapUnmanaged(stage.Digest, u32);

/// Address facts separately from raw bodies, binding current locator context too.
pub fn factKey(deferred: *const lowering.Deferred, locator: emit.Locator, index: u32) ?stage.Digest {
    if (index >= deferred.tables.keys.items.len) return null;
    const raw = deferred.tables.keys.items[index] orelse return null;
    var hash = std.crypto.hash.Blake3.init(.{});
    location(&hash, locator.locate(locator.context, 0));
    location(&hash, locator.locate(locator.context, deferred.input.module.functions.items[index].span));
    var places: stage.Digest = undefined;
    hash.final(&places);
    return deferred.store.key("core-test-function-facts-v1", &.{ &raw, &places });
}

fn location(hash: *std.crypto.hash.Blake3, at: emit.Location) void {
    const line = std.mem.toBytes(std.mem.nativeToLittle(u32, at.line));
    const column = std.mem.toBytes(std.mem.nativeToLittle(u32, at.column));
    const length = std.mem.toBytes(std.mem.nativeToLittle(u64, at.path.len));
    hash.update(&line);
    hash.update(&column);
    hash.update(&length);
    hash.update(at.path);
}

/// Reuse complete digest/edge records after header discovery validates their inputs.
/// A miss materializes only its own function, using the uncached canonical contract.
pub fn build(a: std.mem.Allocator, module: *ir.Module, locator: emit.Locator, deferred: *lowering.Deferred, metrics: *Metrics) Error!Result {
    var canon = try canonical.Canon.prepare(a, module, locator);
    var registry: Registry = .empty;
    defer registry.deinit(a);
    const identities = try a.alloc(?stage.Digest, module.functions.items.len);
    for (module.functions.items, identities, 0..) |function, *logical, index| {
        logical.* = null;
        if (function.signature.linkage == .runtime_c and std.mem.startsWith(u8, function.name, render.declaration_prefix)) continue;
        const value = try canon.callee(@intCast(index));
        const entry = try registry.getOrPut(a, value);
        if (entry.found_existing) return error.UnknownMetadata;
        entry.value_ptr.* = @intCast(index);
        logical.* = value;
    }
    const digests = try a.alloc(stage.Digest, identities.len);
    const callees = try a.alloc([]const u32, identities.len);
    for (identities, digests, callees, 0..) |logical, *digest, *edges, index| {
        const physical: u32 = @intCast(index);
        const key = if (logical != null) factKey(deferred, locator, physical) else null;
        if (key) |address| if (try deferred.store.loadValue(a, address, Fact)) |fact| {
            metrics.decoded += 1;
            if (std.mem.eql(u8, &fact.identity, &logical.?)) if (try recall(a, deferred.store, fact, &registry, metrics)) |targets| {
                digest.* = fact.digest;
                edges.* = targets;
                metrics.reused += 1;
                continue;
            };
        };
        if (module.functions.items[index].signature.linkage == .internal) metrics.fallback += 1;
        try deferred.context.ensureRaw(physical);
        digest.* = try canon.functionDigest(physical);
        edges.* = try identity.calls(a, module.functions.items[index]);
        metrics.fresh += 1;
        for (edges.*) |target| if (target >= identities.len or identities[target] == null) return error.UnknownMetadata;
        if (key) |address| try remember(a, deferred.store, address, .{ .identity = logical.?, .digest = digest.*, .count = @intCast(edges.*.len), .edges = &.{}, .chunks = &.{} }, edges.*, identities);
    }
    return .{ .shared = .{ .digests = digests, .callees = callees }, .identities = identities };
}

fn recall(a: std.mem.Allocator, store: *const stage.Store, fact: Fact, registry: *const Registry, metrics: *Metrics) std.mem.Allocator.Error!?[]const u32 {
    if (fact.count > registry.count()) return null;
    if (fact.count <= maximum_inline) {
        if (fact.edges.len != fact.count or fact.chunks.len != 0) return null;
        return remap(a, fact.edges, registry);
    }
    if (fact.edges.len != 0 or fact.chunks.len != (fact.count + maximum_inline - 1) / maximum_inline) return null;
    const logical = try a.alloc(stage.Digest, fact.count);
    var offset: usize = 0;
    for (fact.chunks) |key| {
        const chunk = try store.loadValue(a, key, []const stage.Digest) orelse return null;
        metrics.decoded += 1;
        if (chunk.len != @min(maximum_inline, logical.len - offset)) return null;
        if (!std.mem.eql(u8, &key, &chunkKey(store, chunk))) return null;
        @memcpy(logical[offset..][0..chunk.len], chunk);
        offset += chunk.len;
    }
    return remap(a, logical, registry);
}

fn remap(a: std.mem.Allocator, logical: []const stage.Digest, registry: *const Registry) std.mem.Allocator.Error!?[]const u32 {
    const indices = try a.alloc(u32, logical.len);
    var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer seen.deinit(a);
    for (logical, indices) |value, *index| {
        index.* = registry.get(value) orelse return null;
        const found = try seen.getOrPut(a, index.*);
        if (found.found_existing) return null;
    }
    return indices;
}

fn chunkKey(store: *const stage.Store, values: []const stage.Digest) stage.Digest {
    return store.key("core-test-function-edges-v1", &.{std.mem.sliceAsBytes(values)});
}

fn remember(a: std.mem.Allocator, store: *const stage.Store, key: stage.Digest, value: Fact, indices: []const u32, identities: []const ?stage.Digest) std.mem.Allocator.Error!void {
    var fact = value;
    const logical = try a.alloc(stage.Digest, indices.len);
    for (indices, logical) |index, *edge| edge.* = identities[index].?;
    if (logical.len <= maximum_inline) {
        fact.edges = logical;
    } else {
        const keys = try a.alloc(stage.Digest, (logical.len + maximum_inline - 1) / maximum_inline);
        for (keys, 0..) |*address, index| {
            const start = index * maximum_inline;
            const chunk = logical[start..@min(logical.len, start + maximum_inline)];
            address.* = chunkKey(store, chunk);
            try store.storeValue(address.*, []const stage.Digest, chunk);
        }
        fact.chunks = keys;
    }
    try store.storeValue(key, Fact, fact);
}
