//! Native driver tests.
const std = @import("std");
const driver = @import("driver.zig");

// spec: NEW-CORE-DRIVER-1
test "a compiler that cannot run fails the build with ToolFailed and says why" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    var environment = std.process.Environ.Map.init(arena.allocator());
    var log: std.ArrayList(u8) = .empty;
    const outcome = driver.link(arena.allocator(), std.testing.io, &environment, .{
        .zig = "/nonexistent/selka-core-test/zig",
        .work = root,
        .output = try std.fs.path.join(arena.allocator(), &.{ root, "p" }),
        .family = .{ .mode = .debug },
        .links = &.{},
    }, &log);
    try std.testing.expectError(error.ToolFailed, outcome);
    try std.testing.expect(std.mem.indexOf(u8, log.items, "cannot run /nonexistent/selka-core-test/zig") != null);
}

// spec: NEW-CORE-S4-RUNTIME-CACHE-1
test "runtime objects share one per-user directory unless the override keeps them local" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const work = try std.fs.path.join(a, &.{ root, "work" });
    var environ: std.process.Environ.Map = .init(a);
    try std.testing.expectEqualStrings(work, try driver.runtimeDirectory(a, std.testing.io, &environ, work));
    try environ.put("HOME", root);
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, ".cache", "selka", "core-runtime" }), try driver.runtimeDirectory(a, std.testing.io, &environ, work));
    try environ.put("XDG_CACHE_HOME", "relative");
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, ".cache", "selka", "core-runtime" }), try driver.runtimeDirectory(a, std.testing.io, &environ, work));
    try environ.put("XDG_CACHE_HOME", root);
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, "selka", "core-runtime" }), try driver.runtimeDirectory(a, std.testing.io, &environ, work));
    const explicit = try std.fs.path.join(a, &.{ root, "explicit" });
    try environ.put("SELKA_CORE_RUNTIME_CACHE", explicit);
    try std.testing.expectEqualStrings(explicit, try driver.runtimeDirectory(a, std.testing.io, &environ, work));
    try environ.put("SELKA_CORE_RUNTIME_CACHE", "");
    try std.testing.expectEqualStrings(work, try driver.runtimeDirectory(a, std.testing.io, &environ, work));
}

/// A module unit whose LLVM text is `text` (the flavours of a bare runtime are chosen from the units' texts alone).
fn textUnit(text: []const u8) @import("emit_units.zig").Unit {
    return .{ .name = "unit", .source_path = "unit.selka", .kind = .module, .llvm = text, .dependencies = .{} };
}

test "the bare runtime's flavours are chosen from what the units hold: the second core by a start of it, the fault decoder by a freestanding fault site, each apart" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const targets = @import("target.zig");
    const start = try std.mem.concat(a, u8, &.{ "define i1 @go() {\n  %r = call i1 @", @import("build_registers.zig").runtime_prefix, "start_core1(i64 1, ptr @spin)\n  ret i1 %r\n}\n" });
    const fault = try std.mem.concat(a, u8, &.{ "define void @pick() {\n  call void ", @import("freestanding_emitted.zig").fault_site, ", \"{r0},{r1},{r2}\"(i32 2, ptr @myl.path.0, i32 7)\n  unreachable\n}\n" });
    const plain = "define i32 @main() {\n  ret i32 0\n}\n";
    const device = &targets.thumbv6m_none;
    try std.testing.expectEqual(driver.BareFlavour{}, try driver.bareFlavour(a, device, &.{ textUnit(plain), textUnit("define void @trap() {\n  call void @llvm.trap()\n  unreachable\n}\n") }));
    try std.testing.expectEqual(driver.BareFlavour{ .freestanding = true }, try driver.bareFlavour(a, device, &.{ textUnit(plain), textUnit(fault) }));
    try std.testing.expectEqual(driver.BareFlavour{ .cores = true }, try driver.bareFlavour(a, device, &.{ textUnit(start), textUnit(plain) }));
    // A program with both gets both, whichever units hold them; a hosted build gets neither.
    try std.testing.expectEqual(driver.BareFlavour{ .cores = true, .freestanding = true }, try driver.bareFlavour(a, device, &.{ textUnit(fault), textUnit(plain), textUnit(start) }));
    try std.testing.expectEqual(driver.BareFlavour{}, try driver.bareFlavour(a, &targets.host, &.{ textUnit(fault), textUnit(start) }));
    try std.testing.expect(try driver.bareCores(a, device, &.{textUnit(start)}) and !try driver.bareCores(a, device, &.{textUnit(fault)}));
}
