//! Verified native handles survive LLVM loss and recover only from valid inputs.
const std = @import("std");
const stage_loss = @import("stage_loss_test_support.zig");
const driver = @import("driver.zig");
const emission = @import("emission_cache.zig");
const stage = @import("stage_store.zig");
const support = @import("test_support.zig");
const io = std.testing.io;
const cwd = std.Io.Dir.cwd();

fn executes(a: std.mem.Allocator, output: []const u8, environment: *const std.process.Environ.Map) !void {
    const result = try std.process.run(a, io, .{ .argv = &.{output}, .environ_map = environment });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 42 }, result.term);
    try std.testing.expectEqualStrings("native handle\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

fn corruptObjects(a: std.mem.Allocator, shared: []const u8) !void {
    const path = try std.fs.path.join(a, &.{ shared, "units-v1" });
    var directory = try cwd.openDir(io, path, .{ .iterate = true });
    defer directory.close(io);
    var iterator = directory.iterate();
    var changed: usize = 0;
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".o")) continue;
        try directory.writeFile(io, .{ .sub_path = entry.name, .data = "corrupt native object" });
        changed += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), changed);
}

// spec-case: NEW-CORE-DEMAND-1
// spec-case: NEW-CORE-DRIVER-1
// spec: NEW-CORE-STAGE-CACHE-9
test "native artifact handles verify objects recover LLVM and honor verify cache" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    const output = try std.fs.path.join(a, &.{ root, "guest" });
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("MYLANG_CORE_RUNTIME_CACHE", shared);
    var storage = try stage.Store.init(std.testing.allocator, io, root);
    defer storage.deinit();
    const text = try support.llvmText(a, "func main(out: Stream) -> int:\n    out.print(\"native handle\")\n    return 42\n");
    var unit = driver.wholeUnit(text);
    const key = storage.key("native-driver-handle-test", &.{text});
    unit.artifact = .{ .store = &storage, .key = key };
    const artifact: emission.Artifact = .{ .text = text, .number = unit.dependencies.number, .math = unit.dependencies.math, .counting = unit.dependencies.counting };
    try storage.storeValue(key, emission.Artifact, artifact);
    _ = try stage_loss.isolatedPath(a, &storage, key);
    var request: driver.Request = .{ .zig = environment.get("MYLANG_ZIG") orelse "zig", .work = root, .output = output, .mode = .optimized_debug, .links = &.{}, .units = &.{unit} };
    var log: std.ArrayList(u8) = .empty;
    const cold = try driver.link(a, io, &environment, request, &log);
    try std.testing.expectEqual(@as(u32, 1), cold.counts.compiled);
    try executes(a, output, &environment);

    try stage_loss.remove(a, &storage, key);
    unit.llvm = "";
    request.units = &.{unit};
    const warm = try driver.link(a, io, &environment, request, &log);
    try std.testing.expectEqual(@as(u32, 0), warm.counts.compiled);
    try std.testing.expectEqual(@as(u32, 1), warm.counts.reused);
    try executes(a, output, &environment);

    try corruptObjects(a, shared);
    try std.testing.expectError(error.CacheMiss, driver.link(a, io, &environment, request, &log));
    try storage.storeValue(key, emission.Artifact, artifact);
    const repaired = try driver.link(a, io, &environment, request, &log);
    try std.testing.expectEqual(@as(u32, 1), repaired.counts.compiled);
    try executes(a, output, &environment);

    try stage_loss.remove(a, &storage, key);
    request.verify = true;
    try std.testing.expectError(error.CacheMiss, driver.link(a, io, &environment, request, &log));
    try storage.storeValue(key, emission.Artifact, artifact);
    const verified = try driver.link(a, io, &environment, request, &log);
    try std.testing.expectEqual(@as(u32, 1), verified.counts.verified);
    try executes(a, output, &environment);
}
