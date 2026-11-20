//! Construction and typed JSON retain the guarantees of former scalar domains.
const std = @import("std");
const t = std.testing;
const head =
    \\@invariant(self.value >= 0, "an amount is never negative")
    \\public record Cents:
    \\    value: int
    \\
;

fn expectCommand(source: []const u8, cases: ?[]const u8, command: []const u8, expected_status: u8, text: []const u8) !void {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "amount.selka", .data = source });
    if (cases) |bytes| try temporary.dir.writeFile(t.io, .{ .sub_path = "amount.cases.json", .data = bytes });
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const path = try std.fs.path.join(t.allocator, &.{ root, "amount.selka" });
    defer t.allocator.free(path);
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(t.io, @import("test_paths").corePath(), t.allocator);
    defer t.allocator.free(compiler);
    const run = try std.process.run(t.allocator, t.io, .{ .argv = &.{ compiler, command, path, if (std.mem.eql(u8, command, "test")) "--json" else "--diagnostics=json" }, .cwd = .{ .dir = temporary.dir } });
    defer t.allocator.free(run.stdout);
    defer t.allocator.free(run.stderr);
    errdefer std.debug.print("stdout: {s}\nstderr: {s}\n", .{ run.stdout, run.stderr });
    try t.expectEqual(std.process.Child.Term{ .exited = expected_status }, run.term);
    try t.expect(std.mem.indexOf(u8, run.stdout, text) != null or std.mem.indexOf(u8, run.stderr, text) != null);
}

// spec-case: CONTRACT-INVARIANT-1
test "K2 direct construction refuses negative cents" {
    try expectCommand(head ++ "\nfunc main() -> int:\n    return Cents(value=-5).value\n", null, "run", 1, "R_INVARIANT");
}

// spec-case: CONTRACT-INVARIANT-1
test "K2 typed JSON construction refuses negative cents" {
    try expectCommand(head ++ "\npublic func test_amount(amount: Cents) -> bool:\n    return True\n", "{\"amount::test_amount\":{\"arguments\":{\"amount\":{\"value\":\"-5\"}}}}", "test", 1, "R_INVARIANT");
}

// spec-case: CONTRACT-INVARIANT-1
test "K2 typed JSON preserves positive record object shape" {
    try expectCommand(head ++ "\npublic func test_amount(amount: Cents) -> Cents:\n    return amount\n", "{\"amount::test_amount\":{\"arguments\":{\"amount\":{\"value\":\"5\"}},\"expected\":{\"value\":\"5\"}}}", "test", 0, "passed");
}

// spec-case: CONTRACT-INVARIANT-1
test "K2 field writes refuse negative cents" {
    try expectCommand(head ++ "\nfunc main() -> int:\n    mut amount = Cents(value=5)\n    amount.value = -5\n    return amount.value\n", null, "run", 1, "R_INVARIANT");
}

// spec-case: CONTRACT-INVARIANT-1
test "K2 positive direct construction preserves the value" {
    try expectCommand(head ++ "\nfunc main(out: Stream) -> int:\n    print(out, Cents(value=5).value)\n    return 0\n", null, "run", 0, "5\n");
}

// spec: DOMAIN-REMOVAL-MESSAGE-1
test "K2 deferred diagnostic still states that scalar domains were removed" {
    try expectCommand("domain Cents: int:\n    pass\n\nfunc main() -> int:\n    return missing\n", null, "check", 1, "scalar domains and type-owned operations were removed");
}
