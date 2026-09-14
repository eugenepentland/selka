//! Exercise the native byte boundary: copied-block ABI, budgets and grants.
const std = @import("std");
const t = std.testing;
const bulk = @import("bulk.zig");
const limits = @import("limits.zig");
/// One emitted native host manifest whose copied block has the supplied shape.
fn manifest(block: []const u8, element: []const u8, width: usize) ![]const u8 {
    return std.fmt.allocPrint(t.allocator,
        \\{{"host":{{"declarations":[
        \\{{"name":"io::put","parameters":["u8"],"result":"i64","effects":32}},
        \\{{"name":"io::read_block","parameters":["i64"],"result":"{s}","effects":32}},
        \\{{"name":"io::write_block","parameters":["{s}"],"result":"i64","effects":32}}],
        \\"types":[
        \\{{"name":"{s}","kind":"record","count":2,"fields":[{{"type":"{s}"}},{{"type":"i64"}}]}},
        \\{{"name":"{s}","kind":"array","count":{d},"fields":[{{"type":"u8"}}]}}]}}}}
    , .{ block, block, block, element, element, width });
}
/// A manifest declaring only the scalar boundary keeps copied blocks unused.
const scalar =
    \\{"host":{"declarations":[{"name":"io::put","parameters":["u8"],"result":"i64","effects":32}],
    \\"types":[{"name":"i64","kind":"scalar","count":0,"fields":[]}]}}
;
// spec: BYTE-IO-BULK-1
test "copied byte blocks are accepted only as 256 octets followed by a count" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const exact = try manifest("io::Block", "[256]u8", 256);
    defer t.allocator.free(exact);
    const shape = (try bulk.validate(arena.allocator(), exact)).?;
    try t.expectEqualStrings("io::Block", shape.record);
    try t.expectEqualStrings("[256]u8", shape.array);
    try t.expectEqual(@as(?bulk.Shape, null), try bulk.validate(arena.allocator(), scalar));
    const narrow = try manifest("io::Block", "[255]u8", 255);
    defer t.allocator.free(narrow);
    try t.expectError(error.HostSignatureMismatch, bulk.validate(arena.allocator(), narrow));
}
// spec-case: BYTE-IO-BULK-1
test "a copied block without both declarations or with a mismatched signature rejects" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const exact = try manifest("io::Block", "[256]u8", 256);
    defer t.allocator.free(exact);
    const half = try std.mem.replaceOwned(u8, t.allocator, exact, "io::write_block", "io::other");
    defer t.allocator.free(half);
    try t.expectError(error.HostSignatureMismatch, bulk.validate(arena.allocator(), half));
    const untrusted = try std.mem.replaceOwned(u8, t.allocator, exact, "\"effects\":32},\n{\"name\":\"io::write", "\"effects\":0},\n{\"name\":\"io::write");
    defer t.allocator.free(untrusted);
    try t.expectError(error.HostSignatureMismatch, bulk.validate(arena.allocator(), untrusted));
    try t.expectError(error.InvalidNativeManifest, bulk.validate(arena.allocator(), "not a manifest"));
}
// spec: BYTE-IO-1
test "the trusted provider linked into every guest declares only the byte boundary" {
    const provider = @import("host.zig").provider;
    try t.expect(std.mem.indexOf(u8, provider, "MylangNativeProviders mylang_native_providers(void)") != null);
    try t.expect(std.mem.indexOf(u8, provider, "\"io::length\"") != null);
    try t.expect(std.mem.indexOf(u8, provider, "\"io::byte\"") != null);
    try t.expect(std.mem.indexOf(u8, provider, "\"io::put\"") != null);
    // Output is buffered in a private file the driver publishes only on success.
    try t.expect(std.mem.indexOf(u8, provider, "MYLANG_BYTE_IO_OUTPUT") != null);
    try t.expect(std.mem.indexOf(u8, provider, "stdout") == null);
}
// spec: BYTE-IO-LIMITS-1
test "runner limits accept explicit zero storage but reject duplicate overflow and zero execution budgets" {
    const options = try limits.parse(&.{ "io", "--project", ".", "--max-input=0", "--max-output=3", "--max-steps=4", "--max-calls=5", "--max-work=6" });
    try t.expectEqual(@as(usize, 0), options.input);
    try t.expectEqual(@as(usize, 3), options.output);
    try t.expectEqual(@as(u64, 4), options.execution.steps);
    try t.expectEqual(@as(u64, 5), options.execution.calls);
    try t.expectEqual(@as(u64, 6), options.execution.work);
    for ([_][]const u8{ "--unknown=1", "--max-steps=0", "--max-input=-1", "--max-output=+1", "--max-work=18446744073709551616", "--max-calls=" }) |invalid|
        try t.expectError(error.InvalidArguments, limits.parse(&.{ "io", "--project", ".", invalid }));
    try t.expectError(error.InvalidArguments, limits.parse(&.{ "io", "--project", ".", "--max-work=1", "--max-work=2" }));
}
// spec-case: BYTE-IO-LIMITS-1
test "native build tools come from unique explicit paths before the environment" {
    var environment: std.process.Environ.Map = .init(t.allocator);
    defer environment.deinit();
    try environment.put("MYLANG_QBE", "/inherited/qbe");
    try environment.put("MYLANG_ZIG", "/inherited/zig");
    var chosen = try limits.parse(&.{ "io", "--project", ".", "--qbe=/explicit/qbe", "--cache-dir=work" });
    limits.inherit(&chosen, &environment);
    try t.expectEqualStrings("/explicit/qbe", chosen.tools.qbe);
    try t.expectEqualStrings("/inherited/zig", chosen.tools.zig);
    try t.expectEqualStrings("work", chosen.tools.cache.?);
    try t.expectEqual(@as(?[]const u8, null), (try limits.parse(&.{ "io", "--project", "." })).tools.cache);
    try t.expectError(error.InvalidArguments, limits.parse(&.{ "io", "--project", ".", "--qbe=a", "--qbe=b" }));
    try t.expectError(error.InvalidArguments, limits.parse(&.{ "io", "--project", ".", "--zig=" }));
}
// spec: SCOPED-PROVIDERS-4
test "granted directories and endpoints reach the trusted provider and nothing else does" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var environment: std.process.Environ.Map = .init(t.allocator);
    defer environment.deinit();
    const granted = try limits.parse(&.{ "io", "--project", ".", "--allow-dir=data", "--allow-write", "--allow-endpoint=127.0.0.1:8000" });
    try granted.grants.install(arena.allocator(), &environment);
    try t.expectEqualStrings("data", environment.get("MYLANG_BYTE_IO_DIR").?);
    try t.expectEqualStrings("1", environment.get("MYLANG_BYTE_IO_WRITABLE").?);
    try t.expectEqualStrings("127.0.0.1:8000", environment.get("MYLANG_BYTE_IO_ENDPOINTS").?);
    var bare: std.process.Environ.Map = .init(t.allocator);
    defer bare.deinit();
    try (try limits.parse(&.{ "io", "--project", "." })).grants.install(arena.allocator(), &bare);
    try t.expectEqual(@as(?[]const u8, null), bare.get("MYLANG_BYTE_IO_DIR"));
    try t.expectEqual(@as(?[]const u8, null), bare.get("MYLANG_BYTE_IO_ENDPOINTS"));
}
// spec: PHASE-TIMING-1
test "structured timing opt-in accepts JSON and rejects duplicates and unknown formats" {
    try t.expect(!(try limits.parse(&.{ "io", "--project", "." })).timings_json);
    try t.expect((try limits.parse(&.{ "io", "--project", ".", "--timings=json" })).timings_json);
    try t.expectError(error.InvalidArguments, limits.parse(&.{ "io", "--project", ".", "--timings=json", "--timings=json" }));
    try t.expectError(error.InvalidArguments, limits.parse(&.{ "io", "--project", ".", "--timings=text" }));
}
test {
    _ = @import("runner.zig");
}
