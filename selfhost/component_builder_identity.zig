//! The `selka-components` builder's own identity, free of its location.
//!
//! A component's cache key must change whenever the builder's behaviour can
//! change, and must not change merely because another worktree compiled the
//! builder (its executable embeds that tree's paths in debug information).
//! The builder therefore identifies itself by the source bytes it was compiled
//! from, embedded at compile time, together with the Zig version, optimize mode,
//! code generation backend and target that turned them into an executable.
//! Every builder source is listed here; a support test fails when one of them
//! imports or embeds a file this list omits.
const std = @import("std");
const builtin = @import("builtin");

/// One builder source, named relative to `selfhost/`, with the bytes compiled.
pub const Source = struct { name: []const u8, bytes: []const u8 };

/// Every source the builder executable compiles besides the Zig standard
/// library, which the Zig version identifies. Sorted by name.
pub const sources = [_]Source{
    .{ .name = "component_archive.zig", .bytes = @embedFile("component_archive.zig") },
    .{ .name = "component_builder_identity.zig", .bytes = @embedFile("component_builder_identity.zig") },
    .{ .name = "component_files.zig", .bytes = @embedFile("component_files.zig") },
    .{ .name = "components.zig", .bytes = @embedFile("components.zig") },
};

/// The identity domain; bump it when the digest's construction changes.
pub const domain = "selka-components-builder-v1";
/// The Zig toolchain version that compiled the builder.
pub const zig_version = builtin.zig_version_string;
/// The builder's optimize mode.
pub const optimize = @tagName(builtin.mode);
/// The code generation backend that compiled the builder.
pub const backend = @tagName(builtin.zig_backend);
/// The builder's operating system and architecture (its CPU model is not
/// behaviour: the builder computes the same bytes on any model of one ISA).
pub const target = @tagName(builtin.os.tag) ++ "-" ++ @tagName(builtin.cpu.arch);

/// SHA-256, as lowercase hexadecimal, over the domain and every source's name,
/// length and bytes. Locations never enter it.
pub fn sourcesDigest() [64]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(domain);
    hash.update("\x00");
    for (sources) |source| {
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, source.name.len, .little);
        hash.update(&length);
        hash.update(source.name);
        std.mem.writeInt(u64, &length, source.bytes.len, .little);
        hash.update(&length);
        hash.update(source.bytes);
    }
    var raw: [32]u8 = undefined;
    hash.final(&raw);
    return std.fmt.bytesToHex(raw, .lower);
}
