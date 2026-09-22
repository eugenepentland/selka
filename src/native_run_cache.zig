//! Persistent emitted-manifest reuse for validated native project runs.
//!
//! A checked project can look up its last QBE manifest before lowering. Entries
//! are scoped to the full compiler identity and keyed by the ordered resolved
//! source graph, policy, and emission controls. The native executable cache adds
//! runtime, backend, toolchain, mode, and target identity when consuming it.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const builder = @import("qbe_build.zig");
const options = @import("qbe_build_options.zig");
const bundled = @import("qbe_build_assets");

/// Filesystem and allocation failures while reading or publishing the cache.
pub const Error = fs.Error;

/// One resolved module contributing to an emitted project manifest.
pub const Source = struct { path: []const u8, bytes: []const u8 };

/// Inputs that can change QBE emitted for one already-validated project.
pub const Identity = struct {
    sources: []const Source,
    policy: ?[]const u8 = null,
    step_checks: bool = false,
    frame_checks: bool = true,
    /// `--unchecked`: the units carry no overflow, cast or bounds guards, so a
    /// checked manifest for the same sources must never be reused for them.
    checks: bool = true,
};

/// One validated cache hit and the exact fragment count its manifest records.
pub const Entry = struct { manifest: []u8, fragments: usize };

/// Load a checksum-valid emitted manifest, or return null for absence/corruption.
pub fn load(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, settings: options.Options, identity: Identity) Error!?Entry {
    var context = try fs.Context.init(allocator, io, environ);
    defer context.deinit();
    const paths = try entryPaths(context, settings, identity);
    const manifest = context.read(paths.manifest) catch return null;
    const expected = context.read(paths.digest) catch return null;
    if (manifest.len == 0) return null;
    const actual = fs.digest(context.allocator, manifest) catch return null;
    if (!std.mem.eql(u8, expected, actual)) return null;
    var parsed = std.json.parseFromSlice(std.json.Value, context.allocator, manifest, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const version = parsed.value.object.get("version") orelse return null;
    if (version != .string or !std.mem.eql(u8, version.string, "qbe-units-v1")) return null;
    const functions = parsed.value.object.get("functions") orelse return null;
    if (functions != .array or functions.array.items.len == 0) return null;
    return .{ .manifest = try allocator.dupe(u8, manifest), .fragments = functions.array.items.len };
}

/// Atomically publish an emitted manifest and its independent checksum.
pub fn store(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, settings: options.Options, identity: Identity, manifest: []const u8) Error!void {
    if (manifest.len == 0) return;
    var context = try fs.Context.init(allocator, io, environ);
    defer context.deinit();
    const root = try builder.cacheRoot(context, settings);
    const directory = try builder.generation(context, root, "run-manifests", manifest_generation);
    const key = try keyFor(context, identity);
    const manifest_path = try std.fs.path.join(context.allocator, &.{ directory, key });
    const digest_path = try std.fmt.allocPrint(context.allocator, "{s}.digest", .{manifest_path});
    try context.atomic(manifest_path, manifest);
    try context.atomic(digest_path, try fs.digest(context.allocator, manifest));
}

const Paths = struct { manifest: []const u8, digest: []const u8 };
const manifest_generation = "native-run-manifest-v1\x00" ++ bundled.compiler_identity;

fn entryPaths(context: fs.Context, settings: options.Options, identity: Identity) !Paths {
    const root = try builder.cacheRoot(context, settings);
    const generation = try fs.hash(context.allocator, manifest_generation);
    const directory = try std.fs.path.join(context.allocator, &.{ root, "run-manifests", generation });
    const manifest = try std.fs.path.join(context.allocator, &.{ directory, try keyFor(context, identity) });
    return .{ .manifest = manifest, .digest = try std.fmt.allocPrint(context.allocator, "{s}.digest", .{manifest}) };
}

fn keyFor(context: fs.Context, identity: Identity) ![]const u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("native-run-validated-graph-v1");
    frame(&hash, if (identity.step_checks) "steps-on" else "steps-off");
    frame(&hash, if (identity.frame_checks) "frames-on" else "frames-off");
    frame(&hash, if (identity.checks) "checks-on" else "checks-off");
    frame(&hash, identity.policy orelse "");
    for (identity.sources) |source| {
        frame(&hash, source.path);
        frame(&hash, source.bytes);
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return std.fmt.allocPrint(context.allocator, "{s}", .{std.fmt.bytesToHex(digest, .lower)});
}

fn frame(hash: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

// spec: NATIVE-RUN-MANIFEST-CACHE-1
test "manifest identity changes with source path bytes policy and emission controls" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const sources = [_]Source{.{ .path = "main.my", .bytes = "def main() -> int:\n    return 0\n" }};
    const base: Identity = .{ .sources = &sources };
    const key = try keyFor(context, base);
    const same = try keyFor(context, base);
    const changed_sources = [_]Source{.{ .path = "main.my", .bytes = "def main() -> int:\n    return 1\n" }};
    const changed = try keyFor(context, .{ .sources = &changed_sources });
    const moved_sources = [_]Source{.{ .path = "other.my", .bytes = sources[0].bytes }};
    try std.testing.expectEqualStrings(key, same);
    try std.testing.expect(!std.mem.eql(u8, key, changed));
    try std.testing.expect(!std.mem.eql(u8, key, try keyFor(context, .{ .sources = &moved_sources })));
    try std.testing.expect(!std.mem.eql(u8, key, try keyFor(context, .{ .sources = &sources, .policy = "policy" })));
    try std.testing.expect(!std.mem.eql(u8, key, try keyFor(context, .{ .sources = &sources, .step_checks = true })));
    try std.testing.expect(!std.mem.eql(u8, key, try keyFor(context, .{ .sources = &sources, .checks = false })));
}

// spec-case: NATIVE-RUN-MANIFEST-CACHE-1
test "manifest cache reuses valid data and treats corruption as a miss" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const sources = [_]Source{.{ .path = "main.my", .bytes = "source" }};
    const identity: Identity = .{ .sources = &sources };
    const settings: options.Options = .{ .source = "", .run = true, .cache = root };
    try std.testing.expect((try load(std.testing.allocator, std.testing.io, &environment, settings, identity)) == null);
    const valid_manifest = "{\"version\":\"qbe-units-v1\",\"functions\":[{}]}";
    try store(std.testing.allocator, std.testing.io, &environment, settings, identity, valid_manifest);
    const hit = (try load(std.testing.allocator, std.testing.io, &environment, settings, identity)).?;
    defer std.testing.allocator.free(hit.manifest);
    try std.testing.expectEqualStrings(valid_manifest, hit.manifest);
    try std.testing.expectEqual(@as(usize, 1), hit.fragments);
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const paths = try entryPaths(context, settings, identity);
    try context.atomic(paths.manifest, "corrupt");
    try std.testing.expect((try load(std.testing.allocator, std.testing.io, &environment, settings, identity)) == null);
}
