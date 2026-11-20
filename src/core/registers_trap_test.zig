//! The simulated register bank's traps (MCU-B1): a full write log and a full table of words trap `R_REGISTER_BANK`, and
//! an index outside the log traps `R_LIST_BOUNDS` as a list index does, each report naming the `registers` operation and
//! then the program's line. One program, built once; each case is one run with its argument.
const std = @import("std");
const options = @import("core_test_options");

const program =
    \\import registers
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    const reg = registers.simulated()
    \\    if args[0] == "log":
    \\        for index in range(16385):
    \\            registers.write8(reg, 0, 1)
    \\    if args[0] == "words":
    \\        for index in range(4097):
    \\            registers.poke32(reg, u32(index * 4), 1)
    \\    registers.write8(reg, 0, 1)
    \\    print(out, registers.write_value(reg, 5))
    \\    return 0
    \\
;

/// One trapping run: its argument, the code, the detail and the program line its report names.
const Case = struct { argument: []const u8, code: []const u8, detail: []const u8, at: []const u8 };

const cases = [_]Case{
    .{ .argument = "log", .code = "R_REGISTER_BANK", .detail = "write log is full: it holds 16384 writes", .at = "in bank::main at bank.selka:7:13" },
    .{ .argument = "words", .code = "R_REGISTER_BANK", .detail = "bank is full: it holds 4096 distinct words", .at = "in bank::main at bank.selka:10:13" },
    .{ .argument = "index", .code = "R_LIST_BOUNDS", .detail = "index out of range (index 5, length 1)", .at = "in bank::main at bank.selka:12:16" },
};

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

test "a full register log or bank traps R_REGISTER_BANK, and an index outside the log traps R_LIST_BOUNDS" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "bank.selka", .data = program });
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "bank.selka" });
    const cache = try options.suiteCache(a, @src());
    for (cases) |case| {
        const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{ options.corePath(), "run", source, "--cache-dir", cache, "--", case.argument } });
        const marker = try std.fmt.allocPrint(a, "error[{s}]: ", .{case.code});
        try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
        try std.testing.expect(contains(ran.stderr, marker));
        try std.testing.expect(contains(ran.stderr, case.detail));
        try std.testing.expect(contains(ran.stderr, case.at));
    }
}
