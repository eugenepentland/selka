//! U2 nested borrows, frame copies, generated destruction and dispatch facts.
const std = @import("std");
const support = @import("test_support.zig");
const options = @import("core_test_options");
const report = std.debug.print;

const borrow_source =
    \\record Chunk:
    \\    values: int[]
    \\    other: int[]
    \\record Function:
    \\    chunk: Chunk
    \\record Frame:
    \\    function: Function
    \\    ip: int
    \\func advance(mut f: Frame) -> int:
    \\    f.ip += 1
    \\    return f.ip
    \\func unchanged(mut f: Frame) -> int:
    \\    return f.function.chunk.values[advance(mut f)]
    \\func change(mut f: Frame) -> int:
    \\    f.function.chunk.values = [90, 91, 92]
    \\    return 1
    \\func snapshot(mut f: Frame) -> int:
    \\    return f.function.chunk.values[change(mut f)]
    \\func main(out: Stream) -> int:
    \\    mut f = Frame(function=Function(chunk=Chunk(values=[10, 11, 12], other=[20])), ip=0)
    \\    const alias = f
    \\    out.print(unchanged(mut f), f.ip)
    \\    out.print(snapshot(mut f), f.function.chunk.values[1])
    \\    out.print(alias.function.chunk.values[1], alias.ip)
    \\    return 0
;

fn functionText(text: []const u8, name: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, text, name) orelse return error.TestUnexpectedResult;
    const end = std.mem.indexOfPos(u8, text, start + name.len, "\nfn ") orelse text.len;
    return text[start..end];
}

// spec: NEW-CORE-U2-BORROW-1
test "U2 nested field borrows cross only updates preserving the complete path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.ownedText(arena.allocator(), borrow_source);
    const body = try functionText(text, "fn unchanged(");
    try std.testing.expect(std.mem.indexOf(u8, body, "retain ") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "release ") == null);
    const changed = try functionText(text, "fn snapshot(");
    try std.testing.expect(std.mem.indexOf(u8, changed, "retain ") != null);
}

const Fixture = struct { source: []const u8, output: []const u8, status: u8 = 0, trap: []const u8 = "" };

fn native(a: std.mem.Allocator, root: []const u8, flags: []const []const u8, fixture: Fixture) !void {
    const source = try std.fmt.allocPrint(a, "{s}/borrow.my", .{root});
    const output = try std.fmt.allocPrint(a, "{s}/borrow", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.core_path, "build", source, "-o", output, "--cache-dir", root });
    try argv.appendSlice(a, flags);
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("{s}{s}", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited and ran.term.exited == fixture.status);
    try std.testing.expectEqualStrings(fixture.output, ran.stdout);
    if (fixture.trap.len == 0) try std.testing.expectEqualStrings("", ran.stderr) else try std.testing.expect(std.mem.indexOf(u8, ran.stderr, fixture.trap) != null);
}

fn nativeModes(a: std.mem.Allocator, fixture: Fixture) !void {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "borrow.my", .data = fixture.source });
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" }, &.{"--optimize-debug"}, &.{ "--optimize-debug", "--verify-facts" } }) |flags| try native(a, root, flags, fixture);
}

// spec-case: NEW-CORE-U2-BORROW-1
test "U2 nested field snapshots and unchanged borrows execute in every build kind" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try nativeModes(arena.allocator(), .{ .source = borrow_source, .output = "11 1\n11 91\n11 0\n" });
}

const borrow_trap =
    \\record Chunk:
    \\    values: int[]
    \\record Frame:
    \\    chunk: Chunk
    \\    ip: int
    \\func index(mut f: Frame, out: Stream) -> int:
    \\    out.print("before")
    \\    f.ip += 1
    \\    assert False, "index failed"
    \\    return 99
    \\func main(out: Stream) -> int:
    \\    mut f = Frame(chunk=Chunk(values=[]), ip=0)
    \\    out.print(f.chunk.values[index(mut f, out)])
    \\    return 0
;

// spec-case: NEW-CORE-U2-BORROW-1
test "U2 borrowing keeps index evaluation output and assertion ahead of the list trap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try nativeModes(arena.allocator(), .{ .source = borrow_trap, .output = "before\n", .status = 1, .trap = "R_ASSERT" });
}
