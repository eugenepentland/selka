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
};

/// One validated cache hit and the exact fragment count its manifest records.
pub const Entry = struct { manifest: []u8, fragments: usize };

/// Load a checksum-valid emitted manifest, or return null for absence/corruption.
/// The manifest is never parsed here: its fragment count is stored beside its
/// checksum, and a lean manifest (`QBE-FRAGMENT-REUSE-1`) is a hit only while
/// every unit text it names is still in the fragment store.
pub fn load(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, settings: options.Options, identity: Identity) Error!?Entry {
    var context = try fs.Context.init(allocator, io, environ);
    defer context.deinit();
    const paths = try entryPaths(context, settings, identity);
    const manifest = context.read(paths.manifest) catch return null;
    const recorded = context.read(paths.digest) catch return null;
    if (manifest.len == 0) return null;
    const newline = std.mem.indexOfScalar(u8, recorded, '\n') orelse return null;
    const actual = fs.digest(context.allocator, manifest) catch return null;
    if (!std.mem.eql(u8, recorded[0..newline], actual)) return null;
    const fragments = std.fmt.parseInt(usize, recorded[newline + 1 ..], 10) catch return null;
    if (fragments == 0 or std.mem.indexOf(u8, manifest, version_member) == null) return null;
    if (!storedTextsPresent(context, manifest)) return null;
    return .{ .manifest = try allocator.dupe(u8, manifest), .fragments = fragments };
}

/// The manifest member every accepted manifest carries.
const version_member = "\"version\":\"qbe-units-v1\"";
/// The member that opens one unit's inline text, and one stored unit's text
/// digest. Inside a JSON string every quote is escaped, so neither spelling
/// can occur within a unit's text or any other string member.
const inline_member = "\"il\":\"";
const stored_member = "\"il_digest\":\"";
/// A lean unit's stored metadata digest (`EMIT-META-1`), and the directory
/// the manifest's stored texts and metadata live in.
const meta_member = "\"meta_digest\":\"";
const store_member = "\"store\":\"";

/// How many units a manifest carries, inline or stored.
fn unitCount(manifest: []const u8) usize {
    return std.mem.count(u8, manifest, inline_member) + std.mem.count(u8, manifest, stored_member);
}

/// Whether every unit text and metadata record a lean manifest names still
/// exists in its `store`. A store path that needed JSON escaping is not
/// checked by spelling, so it counts as missing.
fn storedTextsPresent(context: fs.Context, manifest: []const u8) bool {
    const digests = std.mem.count(u8, manifest, stored_member) + std.mem.count(u8, manifest, meta_member);
    if (digests == 0) return true;
    const root = memberText(manifest, store_member) orelse return false;
    if (std.mem.indexOfScalar(u8, root, '\\') != null) return false;
    for ([_][]const u8{ stored_member, meta_member }) |member| {
        var rest = manifest;
        while (std.mem.indexOf(u8, rest, member)) |at| {
            rest = rest[at + member.len ..];
            const digest = memberText(rest, "") orelse return false;
            const path = std.fs.path.join(context.allocator, &.{ root, digest }) catch return false;
            if (std.mem.indexOfScalar(u8, digest, '\\') != null or !context.exists(path)) return false;
        }
    }
    return true;
}

/// The string value after the first `member` of `text`, up to its closing quote.
fn memberText(text: []const u8, member: []const u8) ?[]const u8 {
    const start = (std.mem.indexOf(u8, text, member) orelse return null) + member.len;
    const end = std.mem.indexOfScalarPos(u8, text, start, '"') orelse return null;
    return text[start..end];
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
    const recorded = try std.fmt.allocPrint(context.allocator, "{s}\n{d}", .{ try fs.digest(context.allocator, manifest), unitCount(manifest) });
    try context.atomic(digest_path, recorded);
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

/// BLAKE3 over every source byte of the project (BUILD-KEYS-1): the
/// toolchain's SHA-256 hashed a 200,000-line project's 7.6 MB at about 14 MB/s
/// on some build hosts.
fn keyFor(context: fs.Context, identity: Identity) ![]const u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("native-run-validated-graph-v2");
    frame(&hash, if (identity.step_checks) "steps-on" else "steps-off");
    frame(&hash, if (identity.frame_checks) "frames-on" else "frames-off");
    // VALUE-SEMANTICS-1: value semantics changes every lowered body, and its
    // environment carrier is set in every process a switched command runs.
    // Only a switched run adds the frame, so every other key is unchanged.
    if (context.environ.get("MYLANG_VALUE_SEMANTICS")) |value| frame(&hash, value);
    frame(&hash, identity.policy orelse "");
    for (identity.sources) |source| {
        frame(&hash, source.path);
        frame(&hash, source.bytes);
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return std.fmt.allocPrint(context.allocator, "{s}", .{std.fmt.bytesToHex(digest, .lower)});
}

fn frame(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
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
    const valid_manifest = "{\"version\":\"qbe-units-v1\",\"functions\":[{\"il\":\"\"}]}";
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

// spec-case: QBE-FRAGMENT-REUSE-1
test "a cached lean manifest is a hit only while every stored unit text it names exists" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const text = try std.fs.path.join(context.allocator, &.{ root, "d" });
    try context.write(text, "export function $f() {\n@start\n ret\n}\n");
    const meta = try std.fs.path.join(context.allocator, &.{ root, "m" });
    try context.write(meta, "{\"name\":\"f\"}");
    const sources = [_]Source{.{ .path = "main.my", .bytes = "lean" }};
    const identity: Identity = .{ .sources = &sources };
    const settings: options.Options = .{ .source = "", .run = true, .cache = root };
    const lean = try std.fmt.allocPrint(context.allocator, "{{\"version\":\"qbe-units-v1\",\"store\":\"{s}\",\"functions\":[{{\"il_digest\":\"d\",\"il_facts\":\"\",\"meta_digest\":\"m\"}},{{\"il\":\"x\"}}]}}", .{root});
    try store(std.testing.allocator, std.testing.io, &environment, settings, identity, lean);
    const hit = (try load(std.testing.allocator, std.testing.io, &environment, settings, identity)).?;
    defer std.testing.allocator.free(hit.manifest);
    try std.testing.expectEqual(@as(usize, 2), hit.fragments);
    // EMIT-META-1: a stored metadata record that left the store voids the entry too.
    try std.Io.Dir.cwd().deleteFile(std.testing.io, meta);
    try std.testing.expect((try load(std.testing.allocator, std.testing.io, &environment, settings, identity)) == null);
    try context.write(meta, "{\"name\":\"f\"}");
    try std.Io.Dir.cwd().deleteFile(std.testing.io, text);
    try std.testing.expect((try load(std.testing.allocator, std.testing.io, &environment, settings, identity)) == null);
}
