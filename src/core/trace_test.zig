//! Trap frames (DWARF line tables and inline records, docs/design/new-core-s1.md
//! §13 R-1) and error traces of a `main` returning `Err` (ERROR-TRACE-1..4).
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const options = @import("core_test_options");

const Hand = support.Hand;

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// Build `test/core/trap_frames.my` with the new core and run it with two arguments.
fn trapped(arena: std.mem.Allocator, root: []const u8, release: bool) ![]const u8 {
    return trappedWith(arena, root, release, &.{});
}

/// `trapped` with extra build flags.
fn trappedWith(arena: std.mem.Allocator, root: []const u8, release: bool, flags: []const []const u8) ![]const u8 {
    const source = try std.fmt.allocPrint(arena, "{s}/trap_frames.my", .{options.fixtures});
    const output = try std.fmt.allocPrint(arena, "{s}/trap_frames-{s}", .{ root, if (release) "release" else "debug" });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.core_path, "build", source, "-o", output, "--cache-dir", cache });
    if (release) try argv.append(arena, "--release");
    try argv.appendSlice(arena, flags);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = &.{ output, "a", "b" } });
    try std.testing.expectEqualStrings("2\n", ran.stdout);
    return ran.stderr;
}

/// The frames the old core prints for this trap, innermost first (its names are module-qualified).
fn sameFrames(stderr: []const u8) !void {
    const first = std.mem.indexOf(u8, stderr, "trap_frames.my:6:25: error[R_LIST_BOUNDS]: native execution failed (index 3, length 3)\n  in leaf at ") orelse return error.TestUnexpectedResult;
    const leaf = std.mem.indexOfPos(u8, stderr, first, "/trap_frames.my:6:25\n  in mid at ") orelse return error.TestUnexpectedResult;
    const mid = std.mem.indexOfPos(u8, stderr, leaf, "/trap_frames.my:11:9\n  in main at ") orelse return error.TestUnexpectedResult;
    const main = std.mem.indexOfPos(u8, stderr, mid, "/trap_frames.my:20:15\nMYLANG-TRAP {") orelse return error.TestUnexpectedResult;
    try std.testing.expect(main > mid and mid > leaf);
}

// spec: NEW-CORE-TRAP-2
test "a trap names every caller frame like the old core, at debug and at -O3 where the calls are inlined" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    try sameFrames(try trapped(arena.allocator(), root, false));
    try sameFrames(try trapped(arena.allocator(), root, true));
}

// spec-case: NEW-CORE-TRAP-2
test "a build without the line tables names only the trapping frame and emits no debug sections" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const stderr = try trappedWith(arena.allocator(), root, true, &.{"--trap-frames=posix_exit"});
    try std.testing.expect(contains(stderr, "/trap_frames.my:6:25\nMYLANG-TRAP {"));
    try std.testing.expect(!contains(stderr, "  in mid at "));
}

/// `inner(n) -> Result[int, str]`: `Err("too big")` (a trace origin) when `n > 2`, else
/// `Ok(n)`; `main` propagates an `Err` with `?` (an appended site) and returns `Ok(7)`.
fn resultProgram(arena: std.mem.Allocator, n: i64) !ir.Module {
    var m: ir.Module = .{};
    const result = try m.intern(arena, .{ .@"union" = &.{ .i64, .str } });
    try m.strings.append(arena, "too big");
    m.entry = 1;
    var inner = try Hand.init(arena, &m, "inner", .{ .params = try arena.dupe(ir.Type, &.{.i64}), .ret = result });
    const big = try inner.emit(.{ .op = .cmp, .ty = .bool, .a = try inner.param(0), .b = try inner.int(.i64, 2), .data = @backingInt(ir.Predicate.gt) });
    const failing = try inner.newBlock();
    const fine = try inner.newBlock();
    try inner.branch(big, failing, fine);
    inner.block = failing;
    _ = try inner.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.origin), .span = 10 });
    const message = try inner.loose(.{ .op = .str_const, .ty = .str, .data = 0 });
    _ = try inner.emit(.{ .op = .ret, .ty = .void, .a = try inner.emit(.{ .op = .union_make, .ty = result, .data = 1, .a = message }) });
    inner.block = fine;
    _ = try inner.emit(.{ .op = .ret, .ty = .void, .a = try inner.emit(.{ .op = .union_make, .ty = result, .data = 0, .a = try inner.param(0) }) });
    _ = try inner.finish();
    var h = try Hand.init(arena, &m, "main", .{ .params = &.{}, .ret = result });
    const got = try h.emit(.{ .op = .call, .ty = result, .a = @fromBackingInt(0), .data = try h.extra(&.{try h.int(.i64, n)}), .span = 200 });
    const tag = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = got });
    const is_error = try h.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try h.int(.u32, 1), .data = @backingInt(ir.Predicate.eq) });
    const propagate = try h.newBlock();
    const done = try h.newBlock();
    try h.branch(is_error, propagate, done);
    h.block = propagate;
    _ = try h.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.append), .span = 2000 });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = got });
    h.block = done;
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.emit(.{ .op = .union_make, .ty = result, .data = 0, .a = try h.int(.i64, 7) }) });
    _ = try h.finish();
    return m;
}

const result_main: support.RunOptions = .{ .main = .{ .result = .{ .ok_tag = 0, .error_tag = 1 } } };

// spec: NEW-CORE-ERRTRACE-1
test "main returning Err prints error: VALUE and the aligned trace, origin first, and exits 1; Ok(code) exits with code" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var failing = try resultProgram(arena.allocator(), 5);
    const failed = try support.runOwned(arena.allocator(), &failing, result_main);
    try std.testing.expectEqual(@as(u8, 1), failed.status);
    try std.testing.expectEqualStrings("error: too big\n  hand.my:1:11    inner  Err(...) created\n  hand.my:1:2001  main   ? propagated\n", failed.stderr);
    var passing = try resultProgram(arena.allocator(), 1);
    const passed = try support.runOwned(arena.allocator(), &passing, result_main);
    try std.testing.expectEqual(@as(u8, 7), passed.status);
    try std.testing.expectEqualStrings("", passed.stderr);
    try std.testing.expect(contains(failed.llvm, "call void @myl_core_err_trace(i32 ") and contains(failed.llvm, "#1\n"));
    try std.testing.expect(contains(failed.llvm, "attributes #1 = { \"call-inline-cost\"=\"0\" }"));
}
