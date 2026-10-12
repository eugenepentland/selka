//! S3 number-runtime ports and the prebuilt number-text object.
const std = @import("std");
const runtime = @import("number_runtime.zig");
const formatting = @import("runtime/core_number_format.zig");
const grammar = @import("runtime/core_number_parse.zig");
const options = @import("core_test_options");
const report = std.debug.print;
comptime {
    _ = @import("runtime/core_number_text.zig");
}

// spec: NEW-CORE-S3-NUMBER-1
test "S3 numeric runtime is a prebuilt object that only number helpers need" {
    try std.testing.expect(std.mem.startsWith(u8, runtime.prebuilt, "\x7fELF"));
    try std.testing.expect(std.mem.indexOf(u8, runtime.prebuilt, "myl_core_str_from_f64") != null);
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
test "S3 numeric runtime object is published under its digest and a damaged copy is rewritten" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try runtime.object(a, std.testing.io, root);
    try std.testing.expect(std.mem.indexOf(u8, path, &std.fmt.bytesToHex(runtime.digest(), .lower)) != null);
    try std.testing.expectEqualSlices(u8, runtime.prebuilt, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(64 << 20)));
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "damaged" });
    try std.testing.expectEqualStrings(path, try runtime.object(a, std.testing.io, root));
    try std.testing.expectEqualSlices(u8, runtime.prebuilt, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(64 << 20)));
}

// spec-case: NEW-CORE-S3-NUMBER-1
// spec: PY-REPEAT-2
// spec: NEW-CORE-BUFFER-S4-1
// spec: NEW-CORE-PLACE-S4-1
// spec: NEW-CORE-FILL-S4-1
test "S3 numeric text and S4 nested values match at every core level" {
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |flags| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
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
            try argv.appendSlice(a, &.{ options.corePath(), "test", try std.fs.path.join(a, &.{ options.fixtures, fixture }), "--cache-dir", root });
            try argv.appendSlice(a, flags);
            const result = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
            if (result.term != .exited or result.term.exited != 0) {
                report("numeric fixture {s}, flags {any}, term {any}\nstdout:\n{s}\nstderr:\n{s}\n", .{ fixture, flags, result.term, result.stdout, result.stderr });
            }
            try std.testing.expect(result.term == .exited and result.term.exited == 0);
            try std.testing.expectEqualStrings("", result.stderr);
            try std.testing.expect(std.mem.indexOf(u8, result.stdout, expected) != null);
            try std.testing.expect(std.mem.indexOf(u8, result.stdout, "unsupported") == null);
        }
    }
}
