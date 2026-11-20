//! S3 number-runtime ports and the prebuilt number-text object.
const std = @import("std");
const runtime = @import("number_runtime.zig");
const formatting = @import("runtime/core_number_format.zig");
const grammar = @import("runtime/core_number_parse.zig");
const options = @import("core_test_options");
const build_identity = @import("build_identity");
const support = @import("test_support.zig");
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
test "the compiler identity digests the bytes of the number-text object the compiler embeds" {
    // `build.zig` hands the identity tool the file it embeds as `core_number_text_object`; a change to how that object is
    // built (its CPU, optimize mode, strip) changes these bytes and so the identity, with no source file edited.
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(runtime.prebuilt, &digest, .{});
    const expected = std.fmt.bytesToHex(digest, .lower);
    try std.testing.expectEqual(@as(usize, 1), build_identity.embedded_products.len);
    try std.testing.expectEqualStrings("core_number_text_object", build_identity.embedded_products[0].name);
    try std.testing.expectEqualStrings(&expected, build_identity.embedded_products[0].digest);
}

// spec-case: NEW-CORE-S3-NUMBER-1
test "the number helper scan finds every helper name wherever it starts and no prefix of one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "myl_core_str_from_f64", "myl_core_buffer_append_f64", "myl_core_format_number", "myl_core_format_float", "myl_core_format_text", "myl_core_parse_float_range", "myl_core_round_float" }) |name| {
        try std.testing.expect(runtime.needed(name));
        try std.testing.expect(runtime.needed(try std.fmt.allocPrint(a, " call @{s}(double)", .{name})));
        try std.testing.expect(!runtime.needed(try std.fmt.allocPrint(a, " call @{s}", .{name[0 .. name.len - 1]})));
    }
    try std.testing.expect(runtime.needed("myl_core_myl_core_round_float"));
    try std.testing.expect(runtime.needed("@myl_core_list_new @myl_core_x\n@myl_core_format_text"));
    try std.testing.expect(!runtime.needed("@myl_core_list_new @myl_core_ @myl_core_format @myl_core_"));
    try std.testing.expect(!runtime.needed(""));
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
        var environment = try options.privateEnvironment(a);
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        const argv = try std.mem.concat(a, []const u8, &.{
            &.{ options.corePath(), "test", "--force", try std.fs.path.join(a, &.{ options.fixtures, "numeric_matrix.selka" }), "--json", "--cache-dir", try options.suiteCache(a, @src()) },
            flags,
        });
        try support.requireReleaseArgs(flags);
        const result = try std.process.run(a, std.testing.io, .{ .argv = argv, .environ_map = &environment });
        if (result.term != .exited or result.term.exited != 0) {
            report("numeric matrix, flags {any}, term {any}\nstdout:\n{s}\nstderr:\n{s}\n", .{ flags, result.term, result.stdout, result.stderr });
        }
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        try std.testing.expectEqualStrings("", result.stderr);
        try expectMatrix(a, result.stdout);
    }
}

/// Every original fixture contributes exactly its fresh passing tests. A missing,
/// repeated, cached, skipped or unsupported verdict cannot satisfy the matrix.
fn expectMatrix(a: std.mem.Allocator, text: []const u8) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, a, text, .{});
    defer parsed.deinit();
    const value = parsed.value;
    try std.testing.expectEqual(@as(i64, 12), value.object.get("passed").?.integer);
    for ([_][]const u8{ "cached", "failed", "skipped", "unsupported" }) |field| {
        try std.testing.expectEqual(@as(i64, 0), value.object.get(field).?.integer);
    }
    const fixtures = [_][]const u8{ "n_float_text", "b_buffer_values", "b_packet_decode", "n_scalar_parse_abi", "v_buffer_format", "v_dynamic_repeat", "v_nested_places", "v_nested_lengths" };
    var counts: [fixtures.len]usize = @splat(0);
    var names: std.StringHashMapUnmanaged(void) = .empty;
    defer names.deinit(a);
    const tests = value.object.get("tests").?.array.items;
    try std.testing.expectEqual(@as(usize, 12), tests.len);
    for (tests) |test_case| {
        try std.testing.expectEqualStrings("passed", test_case.object.get("status").?.string);
        const name = test_case.object.get("name").?.string;
        try std.testing.expect(!(try names.getOrPut(a, name)).found_existing);
        const module_end = std.mem.indexOf(u8, name, "::");
        try std.testing.expect(module_end != null);
        var found = false;
        for (fixtures, 0..) |fixture, index| {
            if (!std.mem.eql(u8, fixture, name[0..module_end.?])) continue;
            counts[index] += 1;
            found = true;
        }
        try std.testing.expect(found);
    }
    try std.testing.expectEqualSlices(usize, &.{ 3, 2, 1, 2, 1, 1, 1, 1 }, &counts);
}
