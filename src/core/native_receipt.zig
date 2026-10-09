//! Compact mappings from verified LLVM artifacts to existing exact native keys.
const std = @import("std");
const emission = @import("emission_cache.zig");
const units = @import("unit_cache.zig");

/// Missing or corrupt LLVM must trigger the coordinator's eager recovery.
pub const Error = std.mem.Allocator.Error || error{CacheMiss};

fn mapping(handle: emission.NativeArtifact, settings: units.Settings) units.Digest {
    const policy = units.key(settings, "");
    return handle.store.key("native-unit-receipt-v1", &.{ &policy, &handle.key });
}

/// A mapping is only a hint; the caller must verify the native object's checksum.
pub fn lookup(a: std.mem.Allocator, handle: emission.NativeArtifact, settings: units.Settings) std.mem.Allocator.Error!?units.Digest {
    return handle.store.loadValue(a, mapping(handle, settings), units.Digest);
}

/// Preserve the ordinary text-derived native key, including every codegen input.
pub fn remember(handle: emission.NativeArtifact, settings: units.Settings, exact: units.Digest) std.mem.Allocator.Error!void {
    try handle.store.storeValue(mapping(handle, settings), units.Digest, exact);
}

/// Reload LLVM only when a verified native object cannot serve this unit.
pub fn materialize(a: std.mem.Allocator, handle: emission.NativeArtifact) Error!emission.Artifact {
    const artifact = try handle.store.loadValue(a, handle.key, emission.Artifact);
    return artifact orelse error.CacheMiss;
}
