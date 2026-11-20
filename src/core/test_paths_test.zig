//! The core test binary carries no absolute path of its build tree (TEST-PATHS-1).
const std = @import("std");
const paths = @import("core_test_options");

// spec-case: TEST-PATHS-1
// spec: CORE-SUITE-CACHE-1
test "the core suite cache outlives private test outputs and resolves to one absolute path" {
    const a = std.testing.allocator;
    const first = try paths.suiteCache(a, @src());
    defer a.free(first);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const private = try tmp.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(private);
    const second = try paths.suiteCache(a, @src());
    defer a.free(second);
    try std.testing.expect(std.fs.path.isAbsolute(first));
    try std.testing.expectEqualStrings(first, second);
    try std.testing.expect(!std.mem.eql(u8, first, private));
    try std.testing.expect(!std.mem.startsWith(u8, first, private));
    try std.Io.Dir.cwd().access(std.testing.io, first, .{});
}

/// Occurrences of `needle` outside the debug sections of this test executable.
fn inThisBinary(a: std.mem.Allocator, needle: []const u8) !usize {
    const self = try std.process.executablePathAlloc(std.testing.io, a);
    defer a.free(self);
    return paths.occurrencesOutsideDebug(std.testing.io, std.Io.Dir.cwd(), self, needle);
}

// spec: TEST-PATHS-1
test "the core test binary names neither its build tree nor its compiler outside debug sections" {
    const a = std.testing.allocator;
    const root = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(root);
    try std.testing.expectEqual(@as(usize, 0), try inThisBinary(a, root));
    try std.testing.expectEqual(@as(usize, 0), try inThisBinary(a, std.fs.path.dirname(paths.corePath()).?));
    try std.testing.expect(try inThisBinary(a, paths.compiler_variable) > 0);
    try std.testing.expect(!std.fs.path.isAbsolute(paths.fixtures));
    try std.testing.expect(!std.fs.path.isAbsolute(paths.lang_tests));
    try std.testing.expect(!std.fs.path.isAbsolute(paths.clock_path));
    try std.Io.Dir.cwd().access(std.testing.io, paths.clock_path, .{});
    try std.testing.expect(std.fs.path.isAbsolute(paths.corePath()));
}

// spec-case: TEST-PATHS-1
test "test paths read a non-empty executable variable and refuse a file that is not ELF" {
    try std.testing.expect(paths.lookup(std.testing.environ, paths.compiler_variable) != null);
    try std.testing.expect(paths.lookup(std.testing.environ, "SELKA_TEST_PATHS_UNSET_PROBE") == null);
    try std.testing.expectError(error.NotElf64, paths.occurrencesOutsideDebug(std.testing.io, std.Io.Dir.cwd(), paths.clock_path, "x"));
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    // An ELF64 header whose section table starts past the end of the file.
    var header: [64]u8 = @splat(0);
    @memcpy(header[0..5], "\x7fELF\x02");
    std.mem.writeInt(u64, header[0x28..0x30], 4096, .little);
    std.mem.writeInt(u16, header[0x3c..0x3e], 1, .little);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "truncated", .data = &header });
    try std.testing.expectError(error.TruncatedElf, paths.occurrencesOutsideDebug(std.testing.io, tmp.dir, "truncated", "x"));
}

/// How many of the engine's variables `environment` still names.
fn engineSettingsIn(environment: *const std.process.Environ.Map) usize {
    var named: usize = 0;
    for (paths.engine_variables) |name| named += @intFromBool(environment.get(name) != null);
    return named;
}

test "the environment a test builds for a compiler child drops the engine's settings and keeps the rest" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    for (paths.engine_variables) |name| try environment.put(name, "16");
    try environment.put("SELKA_JOBS", "3");
    try std.testing.expectEqual(paths.engine_variables.len, engineSettingsIn(&environment));
    try paths.privateStores(&environment);
    try std.testing.expectEqual(@as(usize, 0), engineSettingsIn(&environment));
    try std.testing.expectEqualStrings("3", environment.get("SELKA_JOBS").?);
    try std.testing.expectEqualStrings("", environment.get("SELKA_TEST_SHARED_CACHE").?);
}
