//! Pure, dependency-free stable identity primitives.
//!
//! A file may belong to only one Zig module, so the checked-body cache cannot
//! import `incremental.zig` (which pulls in project checking). This module holds
//! the canonical hash encodings so the cache and the reporting manifest derive
//! the same declaration identities without an import cycle. Identities are
//! derived only from canonical names and content, never from source offsets.
const std = @import("std");

/// Identity allocation failure.
pub const Error = error{OutOfMemory};
/// Raw SHA-256 identity bytes.
pub const Hash = [32]u8;

/// Derive a module identity from its canonical module name.
pub fn moduleIdentity(allocator: std.mem.Allocator, name: []const u8) Error![]const u8 {
    return hashFields(allocator, "mylang-module-v1", &.{name});
}

/// Derive a declaration identity from module, kind, owner and local name.
pub fn declarationIdentity(allocator: std.mem.Allocator, module: []const u8, kind: []const u8, owner: ?[]const u8, name: []const u8) Error![]const u8 {
    return hashFields(allocator, "mylang-declaration-v1", &.{ module, kind, owner orelse "", name });
}

/// Derive a body identity from its declaration identity and exact body bytes.
pub fn bodyIdentity(allocator: std.mem.Allocator, declaration: []const u8, bytes: []const u8) Error![]const u8 {
    return hashFields(allocator, "mylang-body-v1", &.{ declaration, bytes });
}

/// Derive an exported-interface item identity from module, kind, owner and name.
pub fn interfaceItemIdentity(allocator: std.mem.Allocator, module: []const u8, kind: []const u8, owner: ?[]const u8, name: []const u8) Error![]const u8 {
    return hashFields(allocator, "mylang-interface-item-v1", &.{ module, kind, owner orelse "", name });
}

/// Derive a nominal type or generic-template identity; `kind` separates the two.
pub fn typeIdentity(allocator: std.mem.Allocator, module: []const u8, kind: []const u8, name: []const u8) Error![]const u8 {
    return hashFields(allocator, "mylang-type-v1", &.{ module, kind, name });
}

/// Derive a generic specialization identity from its canonical cache key.
pub fn specializationIdentity(allocator: std.mem.Allocator, template_identity: []const u8, arguments_sha256: []const u8, provider_sha256: []const u8, target_abi: []const u8, compiler_sha256: []const u8) Error![]const u8 {
    return hashFields(allocator, "mylang-specialization-v1", &.{ template_identity, arguments_sha256, provider_sha256, target_abi, compiler_sha256 });
}

/// Derive an emitted function/data fragment identity.
pub fn fragmentIdentity(allocator: std.mem.Allocator, symbol_identity: []const u8, kind: []const u8, normalized_bytes: []const u8) Error![]const u8 {
    return hashFields(allocator, "mylang-fragment-v1", &.{ symbol_identity, kind, normalized_bytes });
}

/// SHA-256 hex over a domain tag and length-prefixed fields.
pub fn hashFields(allocator: std.mem.Allocator, domain: []const u8, fields: []const []const u8) Error![]const u8 {
    const digest = digestFields(domain, fields);
    return hex(allocator, digest);
}

/// SHA-256 over a domain tag and length-prefixed fields.
pub fn digestFields(domain: []const u8, fields: []const []const u8) Hash {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(domain);
    hash.update("\x00");
    for (fields) |field| {
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, field.len, .little);
        hash.update(&length);
        hash.update(field);
    }
    return hash.finalResult();
}

fn hex(allocator: std.mem.Allocator, digest: Hash) Error![]const u8 {
    return allocator.dupe(u8, &std.fmt.bytesToHex(digest, .lower)) catch error.OutOfMemory;
}
