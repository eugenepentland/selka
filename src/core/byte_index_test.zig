//! Byte index normalization keeps its signed semantics and source ABI authority.
const std = @import("std");
const options = @import("core_test_options");
const support = @import("test_support.zig");
const report = std.debug.print;

const program =
    \\def indexed(raw: bytes, index: int) -> int:
    \\    return raw[index]
    \\def mutable_indexed(raw: byte_buffer, index: int) -> int:
    \\    return raw[index]
    \\def main(args: list[str], out: Stream) -> int:
    \\    index = 0
    \\    match int(args[0]):
    \\        case Some(value):
    \\            index = value
    \\        case None:
    \\            return 2
    \\    if args[1] == "bytes":
    \\        out.print(indexed(b"abc", index))
    \\    elif args[1] == "buffer":
    \\        out.print(mutable_indexed(byte_buffer([97, 98, 99]), index))
    \\    else:
    \\        out.print(indexed(b"", index))
    \\    return 0
;

// spec-case: NEW-CORE-TEXT-1
test "byte index runtime adapters inline modular negative normalization with the bounds check retained" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const llvm = try support.llvmText(state.allocator(), program);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i64 @myl_core_bytes_index_offset") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "select i1 %bynegative") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, " = add i64 %p1, %bylen") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "icmp uge i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call void @myl_core_trap") != null);
}

// spec-case: NEW-CORE-TEXT-1
test "a source extern byte index lookalike is rejected by the reserved runtime namespace rule" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const source =
        \\extern def myl_core_bytes_index_offset(host: Host, raw: int, index: int) -> u64 effects(host)
        \\def main(host: Host, out: Stream) -> int:
        \\    out.print(myl_core_bytes_index_offset(host, 3, 1))
        \\    return 0
    ;
    var unit = try @import("mylang").Compilation.init(state.allocator(), "lookalike.my", source);
    defer unit.deinit();
    try std.testing.expectError(error.SourceError, unit.check());
    try std.testing.expectEqualStrings("E_EXTERN_SYMBOL", unit.diagnostics.items[0].code);
}

// spec-case: NEW-CORE-TEXT-1
test "an extern C call with the exact byte adapter ABI lacks compiler runtime authority" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const a = state.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, program, &refusal);
    for (module.functions.items) |*function| {
        if (std.mem.eql(u8, function.name, "myl_core_bytes_index_offset")) function.signature.linkage = .extern_c;
    }
    try support.verified(a, &module, &.{});
    const context: u8 = 0;
    const llvm = try @import("emit_llvm.zig").emitModule(a, &module, .{
        .locator = .{ .context = &context, .locate = location },
        .source_path = "authority.my",
        .main = .{ .parameters = &.{ "args", "out" } },
    });
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i64 @myl_core_bytes_index_offset") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "%bynegative") == null);
}

fn location(_: *const anyopaque, _: u32) @import("emit_llvm.zig").Location {
    return .{ .line = 1, .column = 1 };
}

fn nativeIndices(a: std.mem.Allocator, root: []const u8, mode: []const []const u8) !void {
    const source = try std.fmt.allocPrint(a, "{s}/index.my", .{root});
    const output = try std.fmt.allocPrint(a, "{s}/index", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.core_path, "build", source, "-o", output, "--cache-dir", root });
    try argv.appendSlice(a, mode);
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("{s}{s}", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const cases = [_]struct { index: []const u8, output: []const u8, normalized: []const u8 }{
        .{ .index = "-1", .output = "99\n", .normalized = "" },
        .{ .index = "-3", .output = "97\n", .normalized = "" },
        .{ .index = "0", .output = "97\n", .normalized = "" },
        .{ .index = "2", .output = "99\n", .normalized = "" },
        .{ .index = "-4", .output = "", .normalized = "-4" },
        .{ .index = "3", .output = "", .normalized = "3" },
        .{ .index = "-9223372036854775808", .output = "", .normalized = "-9223372036854775808" },
        .{ .index = "9223372036854775807", .output = "", .normalized = "9223372036854775807" },
    };
    for ([_][]const u8{ "bytes", "buffer" }) |receiver| {
        for (cases) |case| {
            const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{ output, case.index, receiver }, .environ_map = &environment });
            try std.testing.expect(ran.term == .exited);
            try std.testing.expectEqualStrings(case.output, ran.stdout);
            if (case.normalized.len == 0) {
                try std.testing.expectEqual(@as(u8, 0), ran.term.exited);
                try std.testing.expectEqualStrings("", ran.stderr);
            } else {
                try std.testing.expectEqual(@as(u8, 1), ran.term.exited);
                const bounds = try std.fmt.allocPrint(a, "error[R_LIST_BOUNDS]: native execution failed (index {s}, length 3)", .{case.normalized});
                try std.testing.expect(std.mem.indexOf(u8, ran.stderr, bounds) != null);
                try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "MYLANG-TRAP") != null);
                try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "leak") == null);
                try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "R_FACT") == null);
            }
        }
    }
    const empty = try std.process.run(a, std.testing.io, .{ .argv = &.{ output, "-1", "empty" }, .environ_map = &environment });
    try std.testing.expect(empty.term == .exited and empty.term.exited == 1);
    try std.testing.expectEqualStrings("", empty.stdout);
    try std.testing.expect(std.mem.indexOf(u8, empty.stderr, "index -1, length 0") != null);
}

// spec-case: NEW-CORE-TEXT-1
test "bytes and buffers normalize negative and extreme signed indices before their located bounds trap in every mode" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const a = state.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "index.my", .data = program });
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| try nativeIndices(a, root, mode);
}
