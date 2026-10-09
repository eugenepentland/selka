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
    return std.mem.replaceOwned(u8, arena, ran.stderr, source, "trap_frames.my");
}

/// The report of this trap, byte for byte, after normalizing its fixture path.
/// A single-file entry uses local function names, and the record follows
/// an ASCII record separator.
const old_report =
    "trap_frames.my:5:25: error[R_LIST_BOUNDS]: native execution failed (index 3, length 3)\n" ++
    "  in leaf at trap_frames.my:5:25\n" ++
    "  in mid at trap_frames.my:10:13\n" ++
    "  in main at trap_frames.my:19:15\n" ++
    "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"index\",\"index\":3,\"length\":3}\n";

fn sameFrames(stderr: []const u8) !void {
    try std.testing.expectEqualStrings(old_report, stderr);
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
    try std.testing.expect(contains(stderr, "  in leaf at trap_frames.my:5:25\n\x1eMYLANG-TRAP {"));
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
const trace_modes = [_]support.RunOptions{ .{}, .{ .release = true }, .{ .release = true, .verify = true } };

fn resultOptions(mode: support.RunOptions) support.RunOptions {
    var result = mode;
    result.main = result_main.main;
    return result;
}

// spec: NEW-CORE-ERRTRACE-1
test "main returning Err prints error: VALUE and the aligned trace, origin first, and exits 1; Ok(code) exits with code" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for (trace_modes) |mode| {
        var failing = try resultProgram(arena.allocator(), 5);
        const failed = try support.runOwned(arena.allocator(), &failing, resultOptions(mode));
        try std.testing.expectEqual(@as(u8, 1), failed.status);
        try std.testing.expectEqualStrings("", failed.stdout);
        try std.testing.expectEqualStrings("error: too big\n  hand.my:1:11    inner  Err(...) created\n  hand.my:1:2001  main   try propagated\n", failed.stderr);
        var passing = try resultProgram(arena.allocator(), 1);
        const passed = try support.runOwned(arena.allocator(), &passing, resultOptions(mode));
        try std.testing.expectEqual(@as(u8, 7), passed.status);
        try std.testing.expectEqualStrings("", passed.stderr);
        try std.testing.expect(contains(failed.llvm, "call preserve_mostcc void @myl_core_err_trace_origin_preserve_most(ptr @myl.site.") and contains(failed.llvm, "#1\n"));
        try std.testing.expect(contains(failed.llvm, "call preserve_mostcc void @myl_core_err_trace_append_preserve_most(ptr @myl.site."));
        try std.testing.expect(contains(failed.llvm, "attributes #1 = { \"call-inline-cost\"=\"0\" }"));
    }
}

/// `main() -> Result[int, str]` returning `Err("bad")`, after recording: its origin, a
/// `returned` site on the origin's line (folded into it), a converting `?`
/// (`Wrapped.bad`) and `propagated` propagating `?` sites.
fn kindsProgram(arena: std.mem.Allocator, propagated: usize) !ir.Module {
    var m: ir.Module = .{};
    const result = try m.intern(arena, .{ .@"union" = &.{ .i64, .str } });
    try m.strings.append(arena, "bad");
    try m.strings.append(arena, "Wrapped.bad");
    var h = try Hand.init(arena, &m, "main", .{ .params = &.{}, .ret = result });
    _ = try h.emit(.{ .op = .err_trace, .ty = .void, .data = 0, .span = 10 });
    _ = try h.emit(.{ .op = .err_trace, .ty = .void, .data = 4, .span = 20 });
    const case = try h.loose(.{ .op = .str_const, .ty = .str, .data = 1 });
    _ = try h.emit(.{ .op = .err_trace, .ty = .void, .a = case, .data = 3, .span = 3000 });
    for (0..propagated) |i| _ = try h.emit(.{ .op = .err_trace, .ty = .void, .data = 1, .span = @intCast(4001 + i) });
    const message = try h.loose(.{ .op = .str_const, .ty = .str, .data = 0 });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.emit(.{ .op = .union_make, .ty = result, .data = 1, .a = message }) });
    _ = try h.finish();
    return m;
}

fn kindsReport(arena: std.mem.Allocator, propagated: usize, mode: support.RunOptions) ![]const u8 {
    var module = try kindsProgram(arena, propagated);
    const run = try support.runOwned(arena, &module, resultOptions(mode));
    try std.testing.expectEqual(@as(u8, 1), run.status);
    try std.testing.expectEqualStrings("", run.stdout);
    return run.stderr;
}

fn longReport(arena: std.mem.Allocator) ![]const u8 {
    var expected: std.ArrayList(u8) = .empty;
    try expected.appendSlice(arena, "error: bad\n  hand.my:1:11    main  Err(...) created\n  ... 10 more entries dropped ...\n");
    for (4010..4042) |column| try expected.print(arena, "  hand.my:1:{d}  main  try propagated\n", .{column});
    return expected.items;
}

// spec: NEW-CORE-ERRTRACE-2
test "trace modes: a returned site on its origin's line folds, a conversion names its case, and the ring drops the oldest appends" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const expected = try longReport(arena.allocator());
    for (trace_modes) |mode| {
        try std.testing.expectEqualStrings(
            "error: bad\n  hand.my:1:11    main  Err(...) created\n  hand.my:1:3001  main  try converted to Wrapped.bad\n" ++
                "  hand.my:1:4002  main  try propagated\n  hand.my:1:4003  main  try propagated\n",
            try kindsReport(arena.allocator(), 2, mode),
        );
        // 42 appends: the ring keeps the last 32 (propagations 9 to 40).
        try std.testing.expectEqualStrings(expected, try kindsReport(arena.allocator(), 40, mode));
    }
}

fn foreignProgram(arena: std.mem.Allocator) !ir.Module {
    var module: ir.Module = .{};
    try module.functions.append(arena, .{ .name = "myl_core_err_trace", .signature = .{ .params = &.{ .bytes, .i32 }, .ret = .void, .linkage = .extern_c } });
    var unrelated = try Hand.init(arena, &module, "unrelated", .{ .params = &.{.i64}, .ret = .i64 });
    _ = try unrelated.emit(.{ .op = .ret, .ty = .void, .a = try unrelated.param(0) });
    const unrelated_id = try unrelated.finish();
    var main = try Hand.init(arena, &module, "main", .{ .params = &.{}, .ret = .i64 });
    _ = try main.emit(.{ .op = .err_trace, .ty = .void, .data = 0, .span = 10 });
    _ = try main.emit(.{ .op = .call, .ty = .void, .a = @fromBackingInt(0), .data = try main.extra(&.{ try main.loose(.{ .op = .undef, .ty = .bytes }), try main.int(.i32, 0) }) });
    const value = try main.emit(.{ .op = .call, .ty = .i64, .a = @fromBackingInt(unrelated_id), .data = try main.extra(&.{try main.int(.i64, 7)}) });
    _ = try main.emit(.{ .op = .ret, .ty = .void, .a = value });
    module.entry = try main.finish();
    return module;
}

// spec-case: NEW-CORE-ERRTRACE-1
test "the explicit trace operation preserves registers while an ordinary extern trace call and unrelated call keep their ABI" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for (trace_modes) |mode| {
        var module = try foreignProgram(arena.allocator());
        const run = try support.runOwned(arena.allocator(), &module, mode);
        try std.testing.expectEqual(@as(u8, 7), run.status);
        try std.testing.expectEqualStrings("", run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(contains(run.llvm, "declare void @myl_core_err_trace(ptr, i32) nounwind\n"));
        try std.testing.expect(contains(run.llvm, "call void @myl_core_err_trace(ptr null, i32 0)"));
        try std.testing.expect(contains(run.llvm, "call preserve_mostcc void @myl_core_err_trace_origin_preserve_most(ptr @myl.site.0)"));
        try std.testing.expect(contains(run.llvm, "call fastcc i64 @\"my.unrelated\"(i64 7)"));
    }
}
