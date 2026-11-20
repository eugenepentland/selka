//! `selka native` through the installed compiler (GH-3b). `native show` prints the system closure builds key their native
//! results by; `native approve` is gone and says so. A build reuses on any machine with no step and no package manager:
//! the last test builds twice with a `PATH` that holds only the Zig toolchain's directory (no `dpkg`), in private stores.
const std = @import("std");
const testing = std.testing;

fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

const Run = struct { status: u8, stdout: []const u8, stderr: []const u8 };

const Fixture = struct {
    temp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,

    fn init() Fixture {
        return .{ .temp = testing.tmpDir(.{}), .arena = std.heap.ArenaAllocator.init(testing.allocator) };
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
        self.temp.cleanup();
    }

    fn root(self: *Fixture) ![]const u8 {
        return self.temp.dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
    }

    /// The test's environment with private stores below the fixture, and, when `bare` is set, a `PATH` that names only the
    /// Zig toolchain's directory.
    fn environment(self: *Fixture, bare: bool) !std.process.Environ.Map {
        const a = self.arena.allocator();
        var map = try std.process.Environ.createMap(testing.environ, a);
        try @import("test_paths").privateStores(&map);
        try map.put("XDG_CACHE_HOME", try std.fs.path.join(a, &.{ try self.root(), "cache" }));
        try map.put("SELKA_CORE_RUNTIME_CACHE", try std.fs.path.join(a, &.{ try self.root(), "runtime" }));
        // No approvals file can be found: `HOME` is the fixture and neither placement of the retired file is named. A
        // compiler from before GH-3b reused nothing here unless this machine's libraries matched its compiled-in list.
        try map.put("HOME", try self.root());
        _ = map.swapRemove("XDG_CONFIG_HOME");
        _ = map.swapRemove("SELKA_NATIVE_APPROVALS");
        if (bare) {
            const zig = try zigPath(a, &map);
            try map.put("SELKA_ZIG", zig);
            try map.put("ZIG", zig);
            try map.put("PATH", std.fs.path.dirname(zig).?);
        }
        return map;
    }

    fn run(self: *Fixture, args: []const []const u8, bare: bool) !Run {
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), self.arena.allocator());
        var map = try self.environment(bare);
        return self.runWith(compiler, &map, args);
    }

    /// `compiler` run with `args` in `map`, from the fixture's folder.
    fn runWith(self: *Fixture, compiler: []const u8, map: *std.process.Environ.Map, args: []const []const u8) !Run {
        const a = self.arena.allocator();
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.append(a, compiler);
        try argv.appendSlice(a, args);
        const result = try std.process.run(a, testing.io, .{ .argv = argv.items, .environ_map = map, .cwd = .{ .path = try self.root() } });
        const status: u8 = switch (result.term) {
            .exited => |code| code,
            else => 255,
        };
        return .{ .status = status, .stdout = result.stdout, .stderr = result.stderr };
    }
};

/// The Zig toolchain a compiler with no bundled Zig would run: `SELKA_ZIG`, else `ZIG`, else the first `zig` on `PATH`.
fn zigPath(a: std.mem.Allocator, map: *const std.process.Environ.Map) ![]const u8 {
    if (map.get("SELKA_ZIG")) |zig| if (zig.len != 0) return std.Io.Dir.cwd().realPathFileAlloc(testing.io, zig, a);
    if (map.get("ZIG")) |zig| if (zig.len != 0) return std.Io.Dir.cwd().realPathFileAlloc(testing.io, zig, a);
    var directories = std.mem.tokenizeScalar(u8, map.get("PATH") orelse "", ':');
    while (directories.next()) |directory| {
        const candidate = try std.fs.path.join(a, &.{ directory, "zig" });
        return std.Io.Dir.cwd().realPathFileAlloc(testing.io, candidate, a) catch continue;
    }
    return error.FileNotFound;
}

test "native without a subcommand, or show with an unknown flag, is a usage error with exit status 2" {
    var fixture = Fixture.init();
    defer fixture.deinit();
    const bare = try fixture.run(&.{"native"}, false);
    try testing.expectEqual(@as(u8, 2), bare.status);
    try testing.expect(std.mem.indexOf(u8, bare.stderr, "usage: selka native show [--zig PATH]") != null);
    const unknown = try fixture.run(&.{ "native", "show", "--everything" }, false);
    try testing.expectEqual(@as(u8, 2), unknown.status);
    try testing.expect(std.mem.indexOf(u8, unknown.stderr, "usage:") != null);
}

test "native approve says it is no longer needed and exits 0" {
    var fixture = Fixture.init();
    defer fixture.deinit();
    const gone = try fixture.run(&.{ "native", "approve", "--dry-run" }, false);
    try testing.expectEqual(@as(u8, 0), gone.status);
    try testing.expect(std.mem.indexOf(u8, gone.stdout, "selka native approve is no longer needed") != null);
    try testing.expectError(error.FileNotFound, fixture.temp.dir.statFile(testing.io, "native-approvals", .{}));
}

test "native show prints the closure, its digest and whether results are reused" {
    var fixture = Fixture.init();
    defer fixture.deinit();
    const shown = try fixture.run(&.{ "native", "show" }, true);
    try testing.expectEqual(@as(u8, 0), shown.status);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "/lib64/ld-linux-x86-64.so.2 -> ") != null);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "libc.so.6") != null);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "closure digest: ") != null);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "\ntoolchain: ") != null);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "toolchain identity: ") != null);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "\nreuse: on\n") != null);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "test build:") == null);
}

// GH-3f: the component builder keys its receipts by the line this prints.
test "native show --digest prints the toolchain identity alone, the one native show prints" {
    var fixture = Fixture.init();
    defer fixture.deinit();
    const shown = try fixture.run(&.{ "native", "show" }, true);
    const alone = try fixture.run(&.{ "native", "show", "--digest" }, true);
    try testing.expectEqual(@as(u8, 0), alone.status);
    try testing.expectEqual(@as(usize, 65), alone.stdout.len);
    try testing.expectEqual(@as(u8, '\n'), alone.stdout[64]);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, alone.stdout[0..64]) != null);
    try testing.expectEqualStrings("", alone.stderr);
    const dangling = try fixture.run(&.{ "native", "show", "--digest", "--zig" }, false);
    try testing.expectEqual(@as(u8, 2), dangling.status);
}

// GH-3b: no machine needs a step or a package manager before builds reuse. What this proves on any machine: with no
// `dpkg` on `PATH` and no approvals file to find, the second build replays. It fails with a compiler from before GH-3b
// on every machine whose libraries are not the ones its compiled-in list names (this one since its 18 November
// `ld.so.cache` rewrite), because that compiler reused nothing without an approval.
test "a build with no dpkg on PATH replays on the second run" {
    var fixture = Fixture.init();
    defer fixture.deinit();
    try fixture.temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "func main(out: Stream) -> int:\n    print(out, \"hi\")\n    return 0\n" });
    const build_args = [_][]const u8{ "build", "main.selka", "-o", "main.bin", "--report" };
    const first = try fixture.run(&build_args, true);
    try testing.expectEqual(@as(u8, 0), first.status);
    const second = try fixture.run(&build_args, true);
    try testing.expectEqual(@as(u8, 0), second.status);
    try testing.expect(std.mem.indexOf(u8, second.stderr, "\"program\":\"replayed\"") != null);
}

/// A file that stands in for a Zig: it is a script, so no toolchain is "reviewed" by it, but it is found and named.
fn standIn(fixture: *Fixture, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| try fixture.temp.dir.createDirPath(testing.io, parent);
    try fixture.temp.dir.writeFile(testing.io, .{ .sub_path = path, .data = "#!/bin/sh\nexit 0\n", .flags = .{ .permissions = .executable_file } });
}

/// The environment of a made-up install's compiler: no Zig named, and a `PATH` with none on it.
fn emptyEnvironment(fixture: *Fixture) !std.process.Environ.Map {
    var map = try fixture.environment(false);
    _ = map.swapRemove("ZIG");
    _ = map.swapRemove("SELKA_ZIG");
    try map.put("PATH", try std.fs.path.join(fixture.arena.allocator(), &.{ try fixture.root(), "nowhere" }));
    return map;
}

// GH-7.1: the release bundles Zig at `lib/selka/zig/zig`, and the compiler finds it beside itself.
test "the Zig bundled in an install is found from its executable, after SELKA_ZIG and before ZIG and PATH" {
    var fixture = Fixture.init();
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    const root = try fixture.root();
    const compiler_source = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), a);
    try std.Io.Dir.cwd().copyFile(compiler_source, fixture.temp.dir, "install/bin/selka", testing.io, .{ .make_path = true });
    const compiler = try std.fs.path.join(a, &.{ root, "install", "bin", "selka" });
    var map = try emptyEnvironment(&fixture);
    const missing = try fixture.runWith(compiler, &map, &.{ "native", "show" });
    try testing.expectEqual(@as(u8, 1), missing.status);
    try testing.expect(std.mem.indexOf(u8, missing.stdout, "cannot identify the Zig toolchain `zig` (ToolNotFound)") != null);
    try testing.expect(std.mem.indexOf(u8, missing.stdout, "install Zig 0.17.1 from https://ziglang.org/download/") != null);
    try testing.expect(std.mem.indexOf(u8, missing.stdout, "or use the Selka release that bundles it") != null);
    try standIn(&fixture, "install/lib/selka/zig/zig");
    try standIn(&fixture, "other/zig");
    const bundled = try std.fmt.allocPrint(a, "\ntoolchain: {s}/install/lib/selka/zig/zig\n", .{root});
    const other = try std.fmt.allocPrint(a, "\ntoolchain: {s}/other/zig\n", .{root});
    const found = try fixture.runWith(compiler, &map, &.{ "native", "show" });
    try testing.expect(std.mem.indexOf(u8, found.stdout, bundled) != null);
    // A link to the executable, as `~/.local/bin/selka` is, finds the install the executable is in.
    try fixture.temp.dir.createDirPath(testing.io, "links");
    try fixture.temp.dir.symLink(testing.io, compiler, "links/selka", .{});
    const linked = try fixture.runWith(try std.fs.path.join(a, &.{ root, "links", "selka" }), &map, &.{ "native", "show" });
    try testing.expect(std.mem.indexOf(u8, linked.stdout, bundled) != null);
    try map.put("ZIG", try std.fs.path.join(a, &.{ root, "other", "zig" }));
    const below = try fixture.runWith(compiler, &map, &.{ "native", "show" });
    try testing.expect(std.mem.indexOf(u8, below.stdout, bundled) != null);
    try map.put("SELKA_ZIG", try std.fs.path.join(a, &.{ root, "other", "zig" }));
    const named = try fixture.runWith(compiler, &map, &.{ "native", "show" });
    try testing.expect(std.mem.indexOf(u8, named.stdout, other) != null);
    const flagged = try fixture.runWith(compiler, &map, &.{ "native", "show", "--zig", try std.fs.path.join(a, &.{ root, "install", "lib", "selka", "zig", "zig" }) });
    try testing.expect(std.mem.indexOf(u8, flagged.stdout, bundled) != null);
}

test "a run with no Zig anywhere says to install Zig 0.17.1 or use the release that bundles it" {
    var fixture = Fixture.init();
    defer fixture.deinit();
    try fixture.temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "func main(out: Stream) -> int:\n    print(out, \"hi\")\n    return 0\n" });
    var map = try emptyEnvironment(&fixture);
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), fixture.arena.allocator());
    const ran = try fixture.runWith(compiler, &map, &.{ "run", "main.selka" });
    try testing.expect(ran.status != 0);
    try testing.expect(std.mem.indexOf(u8, ran.stderr, "cannot identify guest toolchain: ToolNotFound") != null);
    try testing.expect(std.mem.indexOf(u8, ran.stderr, "error: no Zig found: install Zig 0.17.1 from https://ziglang.org/download/") != null);
}
