//! Native policy CLI emission, replay and selective-cache boundaries.
const std = @import("std");
const t = std.testing;
const compiler_path = @import("test_options").compiler_path;
const source =
    \\module policy_program
    \\public union Choice:
    \\    empty,
    \\    number: int,
    \\    values: list[int]
    \\public def change(value: Choice) -> Choice:
    \\    result = value
    \\    result = Choice.number(3)
    \\    return result
    \\public def snapshot(n: int) -> int:
    \\    value = [n]
    \\    saved = value
    \\    value.append(n + 1)
    \\    return saved[0] + len(value)
    \\def main() -> int:
    \\    value = Choice.values([1, 2])
    \\    value = change(value)
    \\    return snapshot(1)
;
const marker = "# RC-NATIVE-VARIANT-1";

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    directory: t.TmpDir,
    entry: []const u8,
    cache: []const u8,
    select: []const u8,

    fn init() !Fixture {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        errdefer arena.deinit();
        var directory = t.tmpDir(.{});
        errdefer directory.cleanup();
        try directory.dir.writeFile(t.io, .{ .sub_path = "policy_program.my", .data = source });
        try directory.dir.writeFile(t.io, .{ .sub_path = "select.txt", .data = "policy_program::change\n" });
        const a = arena.allocator();
        const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
        return .{
            .arena = arena,
            .directory = directory,
            .entry = try std.fs.path.join(a, &.{ root, "policy_program.my" }),
            .cache = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{root}),
            .select = try std.fmt.allocPrint(a, "--select-file={s}/select.txt", .{root}),
        };
    }

    fn deinit(self: *Fixture) void {
        self.directory.cleanup();
        self.arena.deinit();
    }

    fn emit(self: *Fixture, flags: []const []const u8) !std.process.RunResult {
        return self.emitEnvironment(flags, null);
    }

    fn emitEnvironment(self: *Fixture, flags: []const []const u8, environment: ?*const std.process.Environ.Map) !std.process.RunResult {
        return self.emitRuntimeEnvironment(flags, environment, "--rc-runtime");
    }

    fn emitRuntimeEnvironment(self: *Fixture, flags: []const []const u8, environment: ?*const std.process.Environ.Map, runtime: []const u8) !std.process.RunResult {
        const a = self.arena.allocator();
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ compiler_path, "emit-project-qbe", self.entry, runtime, self.cache });
        try argv.appendSlice(a, flags);
        return std.process.run(a, t.io, .{ .argv = argv.items, .environ_map = environment });
    }
};

fn passed(result: std.process.RunResult) !void {
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try t.expectEqualStrings("", result.stderr);
}

// spec-case: RC-NATIVE-VARIANT-BACKEND-1
test "RC-NATIVE-VARIANT-BACKEND-1 alternating emission policies cannot reuse another policy's units" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const original = try fixture.emit(&.{});
    try passed(original);
    try t.expect(std.mem.indexOf(u8, original.stdout, marker) == null);
    const selected = try fixture.emit(&.{"--native-variants=qbe-v2"});
    try passed(selected);
    try t.expect(std.mem.indexOf(u8, selected.stdout, marker) != null);
    const original_again = try fixture.emit(&.{"--native-variants=original"});
    try passed(original_again);
    try t.expectEqualStrings(original.stdout, original_again.stdout);
    const selected_again = try fixture.emit(&.{"--native-variants=qbe-v2"});
    try passed(selected_again);
    try t.expectEqualStrings(selected.stdout, selected_again.stdout);
    const lean_original = try fixture.emit(&.{"--lean-manifest"});
    try passed(lean_original);
    const lean_selected = try fixture.emit(&.{ "--lean-manifest", "--native-variants=qbe-v2" });
    try passed(lean_selected);
    try t.expect(!std.mem.eql(u8, lean_original.stdout, lean_selected.stdout));
    const replay_original = try fixture.emit(&.{"--lean-manifest"});
    try passed(replay_original);
    try t.expectEqualStrings(lean_original.stdout, replay_original.stdout);
    const replay_selected = try fixture.emit(&.{ "--lean-manifest", "--native-variants=qbe-v2" });
    try passed(replay_selected);
    try t.expectEqualStrings(lean_selected.stdout, replay_selected.stdout);
}

// spec-case: RC-NATIVE-VARIANT-BACKEND-1
test "RC-NATIVE-VARIANT-BACKEND-1 selective emission carries policy and rejects malformed internal flags" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const original = try fixture.emit(&.{fixture.select});
    try passed(original);
    try t.expect(std.mem.indexOf(u8, original.stdout, marker) == null);
    const selected = try fixture.emit(&.{ fixture.select, "--native-variants=qbe-v2" });
    try passed(selected);
    try t.expect(std.mem.indexOf(u8, selected.stdout, marker) != null);
    const invalid = try fixture.emit(&.{"--native-variants=unchecked"});
    try t.expectEqual(std.process.Child.Term{ .exited = 2 }, invalid.term);
    const duplicate = try fixture.emit(&.{ "--native-variants=original", "--native-variants=qbe-v2" });
    try t.expectEqual(std.process.Child.Term{ .exited = 2 }, duplicate.term);
}

// spec-case: RC-NATIVE-VARIANT-BACKEND-1
test "RC-NATIVE-VARIANT-BACKEND-1 selective emission retains original counting and check defaults" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.directory.dir.writeFile(t.io, .{ .sub_path = "select.txt", .data = "policy_program::snapshot\n" });
    var environment = try std.process.Environ.createMap(t.environ, t.allocator);
    defer environment.deinit();
    try environment.put("MYLANG_COW_COUNTING", "0");
    const original = try fixture.emitRuntimeEnvironment(&.{fixture.select}, &environment, "--gc-runtime");
    try passed(original);
    try environment.put("MYLANG_COW_COUNTING", "1");
    const full = try fixture.emitRuntimeEnvironment(&.{}, &environment, "--gc-runtime");
    try passed(full);
    try t.expect(std.mem.indexOf(u8, full.stdout, "call $myl_native_cow_tally") != null);
    const selected = try fixture.emitRuntimeEnvironment(&.{fixture.select}, &environment, "--gc-runtime");
    try passed(selected);
    try t.expectEqualStrings(original.stdout, selected.stdout);
    const dropped = try fixture.emitRuntimeEnvironment(&.{ fixture.select, "--drop-step-checks", "--drop-frame-checks", "--drop-debug" }, &environment, "--gc-runtime");
    try passed(dropped);
    try t.expectEqualStrings(original.stdout, dropped.stdout);
}
