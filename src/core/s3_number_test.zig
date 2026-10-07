//! S3 number-runtime ports and content/toolchain cache identity.
const std = @import("std");
const runtime = @import("number_runtime.zig");
const formatting = @import("runtime/core_number_format.zig");
const grammar = @import("runtime/core_number_parse.zig");
const options = @import("core_test_options");
comptime {
    _ = @import("runtime/core_number_text.zig");
}

// spec: NEW-CORE-S3-NUMBER-1
test "S3 numeric runtime key includes Zig version and complete helper sources" {
    try std.testing.expectEqual(@as(usize, 3), runtime.sources.len);
    try std.testing.expect(!std.mem.eql(u8, &runtime.key("0.16.0-a"), &runtime.key("0.16.0-b")));
    try std.testing.expect(runtime.needed("call ptr @myl_core_str_from_f64(double %value)"));
    try std.testing.expect(!runtime.needed("declare ptr @myl_core_str_from_i64(i64)"));
}

// spec-case: NEW-CORE-S3-NUMBER-1
test "S3 numeric grammar keeps special values signed zero and rounded subnormals" {
    try std.testing.expect(std.math.signbit(grammar.floatingBytes("-0.0").?));
    try std.testing.expect(std.math.isInf(grammar.floatingBytes("-INFINITY").?));
    try std.testing.expect(std.math.isNan(grammar.floatingBytes("NaN").?));
    try std.testing.expectEqual(@as(u64, 1), @as(u64, @bitCast(grammar.floatingBytes("4.9406564584124654e-324").?)));
    try std.testing.expectEqual(@as(?f64, null), grammar.floatingBytes("1e+"));
    try std.testing.expectEqual(@as(f64, 0.13), formatting.roundFloat(0.125, 2));
}

// spec-case: NEW-CORE-S3-NUMBER-1
test "S3 numeric runtime cache invalidates changed helper bytes and build settings" {
    const original = [_]runtime.SourceUnit{.{ .name = "helper.zig", .bytes = "const value = 1;" }};
    const changed = [_]runtime.SourceUnit{.{ .name = "helper.zig", .bytes = "const value = 2;" }};
    const base = runtime.fingerprint("zig-v1", &original, &.{ "ReleaseFast", "x86_64-linux-gnu" });
    try std.testing.expect(!std.mem.eql(u8, &base, &runtime.fingerprint("zig-v1", &changed, &.{ "ReleaseFast", "x86_64-linux-gnu" })));
    try std.testing.expect(!std.mem.eql(u8, &base, &runtime.fingerprint("zig-v1", &original, &.{ "ReleaseSafe", "x86_64-linux-gnu" })));
    try std.testing.expect(!std.mem.eql(u8, &base, &runtime.fingerprint("zig-v1", &original, &.{ "ReleaseFast", "aarch64-linux-gnu" })));
}

fn nativeFixtures(allocator: std.mem.Allocator, flags: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const one = "1 passed";
    const fixtures = [_][]const u8{ "n_float_text.my", "b_buffer_values.my", "b_packet_decode.my", "n_scalar_parse_abi.my", "v_buffer_format.my", "v_dynamic_repeat.my", "v_nested_places.my", "v_nested_lengths.my" };
    for (fixtures, [_][]const u8{ "3 passed", "2 passed", one, "2 passed", one, one, one, one }) |fixture, expected| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.core_path, "test", try std.fs.path.join(a, &.{ options.fixtures, fixture }), "--cache-dir", root });
        try argv.appendSlice(a, flags);
        const result = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        try std.testing.expectEqualStrings("", result.stderr);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, expected) != null);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "unsupported") == null);
    }
}

// spec-case: NEW-CORE-S3-NUMBER-1
// spec: PY-REPEAT-2
// spec: NEW-CORE-BUFFER-S4-1
// spec: NEW-CORE-PLACE-S4-1
// spec: NEW-CORE-FILL-S4-1
test "S3 numeric text and S4 nested values match at every core level" {
    try nativeFixtures(std.testing.allocator, &.{});
    try nativeFixtures(std.testing.allocator, &.{"--release"});
    try nativeFixtures(std.testing.allocator, &.{ "--release", "--verify-facts" });
}
