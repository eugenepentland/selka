//! Production consumers and relocatable installations of native Selka components.
const std = @import("std");
const t = std.testing;
const compiler = @import("test_options").compiler_path;
const fixture =
    \\public func helper() -> int:
    \\    return 7
    \\public func middle() -> int:
    \\    return helper()
    \\public func test_direct() -> bool:
    \\    return helper() + helper() == 14
    \\public func test_indirect() -> bool:
    \\    return middle() == 7
    \\func main() -> int:
    \\    return middle()
;

fn run(environment: *const std.process.Environ.Map, command: []const u8, path: []const u8) !std.process.RunResult {
    const context = std.mem.eql(u8, command, "context");
    const args = [_][]const u8{ compiler, command, path, if (context) "--symbol=input::helper" else "input::helper" };
    const length: usize = if (context or std.mem.eql(u8, command, "tests-for")) 4 else 3;
    return std.process.run(t.allocator, t.io, .{ .argv = args[0..length], .environ_map = environment });
}

fn release(result: std.process.RunResult) void {
    t.allocator.free(result.stdout);
    t.allocator.free(result.stderr);
}

fn compareModes(path: []const u8) !void {
    var environment = try std.process.Environ.createMap(t.environ, t.allocator);
    defer environment.deinit();
    for ([_][]const u8{ "tests-for", "lint", "list-interfaces", "context" }) |command| {
        try environment.put("MYLANG_TEST_INDEX_MODE", "reference");
        const expected = try run(&environment, command, path);
        defer release(expected);
        try t.expectEqual(std.process.Child.Term{ .exited = 0 }, expected.term);
        for ([_][]const u8{ "component", "shadow" }) |mode| {
            try environment.put("MYLANG_TEST_INDEX_MODE", mode);
            const actual = try run(&environment, command, path);
            defer release(actual);
            try t.expectEqual(expected.term, actual.term);
            try t.expectEqualStrings(expected.stdout, actual.stdout);
            try t.expectEqualStrings(expected.stderr, actual.stderr);
        }
    }
}

// spec: SELFHOST-COMPONENT-1
test "CLI components agree with reference and shadow in every checked consumer" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(t.io, .{ .sub_path = "input.my", .data = fixture });
    const path = try temp.dir.realPathFileAlloc(t.io, "input.my", t.allocator);
    defer t.allocator.free(path);
    try compareModes(path);
}

// spec: SELFHOST-BOOTSTRAP-1
test "CLI component bootstrap rebuilds and installs without an interpreter on PATH" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDir(t.io, "empty-path", .default_dir);
    const empty_path = try temp.dir.realPathFileAlloc(t.io, "empty-path", t.allocator);
    defer t.allocator.free(empty_path);
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const installation = try std.fs.path.join(t.allocator, &.{ root, "components" });
    defer t.allocator.free(installation);
    var environment = try std.process.Environ.createMap(t.environ, t.allocator);
    defer environment.deinit();
    try environment.put("PATH", empty_path);
    const options = @import("test_options");
    var arguments: std.ArrayList([]const u8) = .empty;
    defer arguments.deinit(t.allocator);
    try arguments.appendSlice(t.allocator, &.{ options.component_builder_path, "--zig", options.zig_path, "--install-dir", installation, "--uncached" });
    if (options.component_owned_compiler_pin.len != 0) try arguments.appendSlice(t.allocator, &.{ "--owned-compiler-pin", options.component_owned_compiler_pin });
    if (options.component_seed_source.len != 0) try arguments.appendSlice(t.allocator, &.{ "--seed-source", options.component_seed_source });
    const result = try std.process.run(t.allocator, t.io, .{
        .argv = arguments.items,
        .environ_map = &environment,
    });
    defer release(result);
    errdefer std.debug.print("component bootstrap without PATH: {s}\n", .{result.stderr});
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    for ([_][]const u8{ "test-index", "cache-plan" }) |component| {
        const filename = try std.fmt.allocPrint(t.allocator, "{s}.json", .{component});
        defer t.allocator.free(filename);
        const manifest_path = try std.fs.path.join(t.allocator, &.{ installation, filename });
        defer t.allocator.free(manifest_path);
        const manifest_bytes = try std.Io.Dir.cwd().readFileAlloc(t.io, manifest_path, t.allocator, .limited(65536));
        defer t.allocator.free(manifest_bytes);
        const manifest = try std.json.parseFromSlice(PackageManifest, t.allocator, manifest_bytes, .{ .ignore_unknown_fields = true });
        defer manifest.deinit();
        try t.expectEqualStrings(component, manifest.value.component);
        try t.expectEqual(@as(usize, 64), manifest.value.sha256.len);
        if (options.component_owned_compiler_pin.len != 0) try t.expectEqualStrings("zero-rc-v1", manifest.value.memory_mode orelse return error.MissingOwnedComponentMarker);
    }
}

// spec-case: SELFHOST-COMPONENT-1
test "CLI components preserve syntax fallback and never silently recover a missing package" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(t.io, .{ .sub_path = "input.my", .data = fixture });
    const path = try temp.dir.realPathFileAlloc(t.io, "input.my", t.allocator);
    defer t.allocator.free(path);
    const absent = try std.fmt.allocPrint(t.allocator, "{s}.missing", .{path});
    defer t.allocator.free(absent);
    var environment = try std.process.Environ.createMap(t.environ, t.allocator);
    defer environment.deinit();
    try environment.put("MYLANG_COMPONENT_DIR", absent);
    _ = environment.swapRemove("MYLANG_TEST_INDEX_MODE");
    for ([_][]const u8{ "tests-for", "lint", "list-interfaces", "context" }) |command| {
        const result = try run(&environment, command, path);
        defer release(result);
        try t.expectEqual(std.process.Child.Term{ .exited = 2 }, result.term);
        try t.expect(std.mem.indexOf(u8, result.stderr, "test-index component") != null);
        try t.expectEqualStrings("", result.stdout);
    }
    // A type error still exposes the syntax-derived graph to the component.
    try temp.dir.writeFile(t.io, .{ .sub_path = "input.my", .data = fixture ++ "\nfunc broken() -> int:\n    return missing\n" });
    try environment.put("MYLANG_TEST_INDEX_MODE", "reference");
    const expected = try run(&environment, "tests-for", path);
    defer release(expected);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, expected.term);
    try t.expect(std.mem.indexOf(u8, expected.stdout, "basis: syntax") != null);
    _ = environment.swapRemove("MYLANG_COMPONENT_DIR");
    // Restore the package override inherited by uninstalled test executables.
    var inherited = try std.process.Environ.createMap(t.environ, t.allocator);
    defer inherited.deinit();
    if (inherited.get("MYLANG_COMPONENT_DIR")) |directory| try environment.put("MYLANG_COMPONENT_DIR", directory);
    try environment.put("MYLANG_TEST_INDEX_MODE", "shadow");
    const actual = try run(&environment, "tests-for", path);
    defer release(actual);
    try t.expectEqual(expected.term, actual.term);
    try t.expectEqualStrings(expected.stdout, actual.stdout);
}

const PackageManifest = struct {
    format: u32,
    component: []const u8,
    protocol: u32,
    schema: u32,
    artifact: []const u8,
    sha256: []const u8,
    memory_mode: ?[]const u8 = null,
};

/// Stage a relocatable bin/libexec installation from the build's component package.
/// Returns an allocator-owned host path; copies retain executable permissions.
pub fn stageInstalledHost(a: std.mem.Allocator, io: std.Io, root: []const u8, source_host: []const u8) ![]u8 {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const arena = scratch.allocator();
    var inherited = try std.process.Environ.createMap(t.environ, arena);
    defer inherited.deinit();
    const source_components = inherited.get("MYLANG_COMPONENT_DIR") orelse return error.MissingComponentFixture;
    const destination = try std.fs.path.join(arena, &.{ root, "installation", "libexec", "mylang", "components" });
    for ([_][]const u8{ "test-index", "cache-plan" }) |component| try stageComponent(arena, io, source_components, destination, component);
    const host = try std.fs.path.join(a, &.{ root, "installation", "bin", "mylang" });
    errdefer a.free(host);
    try std.Io.Dir.cwd().copyFile(source_host, .cwd(), host, io, .{ .make_path = true });
    return host;
}

fn stageComponent(arena: std.mem.Allocator, io: std.Io, source: []const u8, destination: []const u8, component: []const u8) !void {
    const filename = try std.fmt.allocPrint(arena, "{s}.json", .{component});
    const source_manifest = try std.fs.path.join(arena, &.{ source, filename });
    const cwd = std.Io.Dir.cwd();
    const manifest_bytes = try cwd.readFileAlloc(io, source_manifest, arena, .limited(65536));
    const manifest = try std.json.parseFromSlice(PackageManifest, arena, manifest_bytes, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    const m = manifest.value;
    const version: u32 = if (std.mem.eql(u8, component, "cache-plan")) 2 else 1;
    if (m.format != 1 or m.protocol != version or m.schema != version) return error.InvalidComponentFixture;
    if (!std.mem.eql(u8, m.component, component) or m.sha256.len != 64) return error.InvalidComponentFixture;
    if (m.artifact.len == 0 or std.mem.indexOfAny(u8, m.artifact, "/\\") != null) return error.InvalidComponentFixture;
    if (std.mem.eql(u8, m.artifact, ".") or std.mem.eql(u8, m.artifact, "..")) return error.InvalidComponentFixture;
    const destination_manifest = try std.fs.path.join(arena, &.{ destination, filename });
    const destination_binary = try std.fs.path.join(arena, &.{ destination, m.artifact });
    const source_binary = try std.fs.path.join(arena, &.{ source, m.artifact });
    try cwd.copyFile(source_binary, cwd, destination_binary, io, .{ .make_path = true });
    const binary = try cwd.readFileAlloc(io, destination_binary, arena, .limited(64 << 20));
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(binary, &digest, .{});
    var expected: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, m.sha256);
    if (!std.mem.eql(u8, &digest, &expected)) return error.InvalidComponentFixture;
    try cwd.writeFile(io, .{ .sub_path = destination_manifest, .data = manifest_bytes });
}
