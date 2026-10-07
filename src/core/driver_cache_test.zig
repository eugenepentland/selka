//! The core's object, program and replay caches, through `mylang-core build`
//! on a multi-module project (docs/design/new-core-s4.md §7, cache tests).
const std = @import("std");
const tools = @import("core_test_options");
const number_runtime = @import("number_runtime.zig");
const io = std.testing.io;
const cwd = std.Io.Dir.cwd();
const diagnostic = std.debug.print;

const leaf = "module leaf\n\npublic def compute(count: int) -> int:\n    sum = 0\n    for i in range(count):\n        sum += i\n    return sum\n";
const other = "module other\n\npublic def compute(value: int) -> int:\n    return value + 1\n";

/// One project in a temporary directory, built by the core binary.
const Project = struct {
    arena: std.mem.Allocator,
    root: []const u8,
    environment: std.process.Environ.Map,

    fn prepare(a: std.mem.Allocator, directory: *std.testing.TmpDir, private_store: bool) !Project {
        const root = try directory.dir.realPathFileAlloc(io, ".", a);
        var environment = try std.testing.environ.createMap(a);
        // A private store makes reuse counts exact; the shared one serves helper
        // units other programs already compiled.
        if (private_store) try environment.put("MYLANG_CORE_RUNTIME_CACHE", try std.fs.path.join(a, &.{ root, "store" }));
        const app = try std.fmt.allocPrint(a, "module app\nimport leaf\nimport other\n\ndef main(out: Stream) -> int:\n    out.print(\"{s}\", leaf.compute(6), other.compute(3))\n    return 0\n", .{&directory.sub_path});
        try directory.dir.writeFile(io, .{ .sub_path = "app.my", .data = app });
        try directory.dir.writeFile(io, .{ .sub_path = "leaf.my", .data = leaf });
        try directory.dir.writeFile(io, .{ .sub_path = "other.my", .data = other });
        return .{ .arena = a, .root = root, .environment = environment };
    }

    fn path(self: Project, name: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.root, name });
    }

    /// Build with `--cache-report`; returns the build's stderr, or fails the test.
    fn build(self: *Project, extra: []const []const u8) ![]const u8 {
        const result = try self.attempt(extra);
        if (result.term != .exited or result.term.exited != 0) diagnostic("core build failed: {s}\n", .{result.stderr});
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        return result.stderr;
    }

    fn attempt(self: *Project, extra: []const []const u8) !std.process.RunResult {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(self.arena, &.{ tools.core_path, "build", try self.path("app.my"), "-o", try self.path("program"), "--cache-dir", try self.path("cache"), "--cache-report" });
        try argv.appendSlice(self.arena, extra);
        return std.process.run(self.arena, io, .{ .argv = argv.items, .environ_map = &self.environment });
    }

    fn output(self: *Project) ![]const u8 {
        const result = try std.process.run(self.arena, io, .{ .argv = &.{try self.path("program")}, .environ_map = &self.environment });
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        return result.stdout;
    }

    /// Forget the replay records, so the next build reaches the object and program stores.
    fn forgetReplays(self: Project) !void {
        try cwd.deleteTree(io, try self.path("cache/replay-v1"));
    }

    /// Rewrite every file in a store directory with `bytes`, records included or not.
    fn damage(self: Project, relative: []const u8, suffix: []const u8, bytes: []const u8) !usize {
        var directory = try cwd.openDir(io, try self.path(relative), .{ .iterate = true });
        defer directory.close(io);
        var iterator = directory.iterate();
        var count: usize = 0;
        while (try iterator.next(io)) |entry| {
            if (!std.mem.endsWith(u8, entry.name, suffix)) continue;
            try directory.writeFile(io, .{ .sub_path = entry.name, .data = bytes });
            count += 1;
        }
        return count;
    }

    /// Give every store object `bytes` and a matching record, as a store whose
    /// compiler changed behind its key would.
    fn forge(self: Project, bytes: []const u8) !void {
        var directory = try cwd.openDir(io, try self.path("store/units-v1"), .{ .iterate = true });
        defer directory.close(io);
        var digest: [32]u8 = undefined;
        std.crypto.hash.Blake3.hash(bytes, &digest, .{});
        const record = try std.fmt.allocPrint(self.arena, "core-unit-sum-v1\n{d}\n{s}\n", .{ bytes.len, std.fmt.bytesToHex(digest, .lower) });
        var iterator = directory.iterate();
        while (try iterator.next(io)) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".o")) continue;
            try directory.writeFile(io, .{ .sub_path = entry.name, .data = bytes });
            try directory.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(self.arena, "{s}.sum", .{entry.name}), .data = record });
        }
    }
};

/// The numbers of one `--cache-report` line.
const Report = struct { units: u32, reused: u32, compiled: u32, verified: u32, program: []const u8, processes: u32, replayed: bool };

fn report(stderr: []const u8) !Report {
    if (std.mem.indexOf(u8, stderr, "mylang-core: cache: replayed") != null) return .{ .units = 0, .reused = 0, .compiled = 0, .verified = 0, .program = "replayed", .processes = 0, .replayed = true };
    const start = std.mem.indexOf(u8, stderr, "mylang-core: cache: ") orelse return error.NoCacheReport;
    const line = std.mem.sliceTo(stderr[start + "mylang-core: cache: ".len ..], '\n');
    var words = std.mem.tokenizeAny(u8, line, " ,;");
    var numbers: [5]u32 = undefined;
    var program: []const u8 = "";
    var index: usize = 0;
    while (words.next()) |word| {
        const number = std.fmt.parseInt(u32, word, 10) catch {
            if (std.mem.eql(u8, word, "reused") or std.mem.eql(u8, word, "linked")) program = word;
            continue;
        };
        if (index == numbers.len) return error.BadCacheReport;
        numbers[index] = number;
        index += 1;
    }
    if (index != numbers.len) return error.BadCacheReport;
    return .{ .units = numbers[0], .reused = numbers[1], .compiled = numbers[2], .verified = numbers[3], .program = program, .processes = numbers[4], .replayed = false };
}

// spec: NEW-CORE-S4-REPLAY-1
test "an unchanged build replays, a lost record reuses every object and the program, and an edit compiles one unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(arena.allocator(), &directory, true);
    const expected = try std.fmt.allocPrint(arena.allocator(), "{s} 15 4\n", .{&directory.sub_path});
    const cold = try report(try project.build(&.{}));
    try std.testing.expect(cold.units >= 4 and cold.compiled == cold.units and cold.reused == 0);
    try std.testing.expectEqualStrings("linked", cold.program);
    try std.testing.expectEqualStrings(expected, try project.output());
    try std.testing.expect((try report(try project.build(&.{}))).replayed);
    try std.testing.expectEqualStrings(expected, try project.output());
    try project.forgetReplays();
    const warm = try report(try project.build(&.{}));
    try std.testing.expectEqual(Report{ .units = cold.units, .reused = cold.units, .compiled = 0, .verified = 0, .program = warm.program, .processes = 0, .replayed = false }, warm);
    try std.testing.expectEqualStrings("reused", warm.program);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "leaf.my", .data = "module leaf\n\npublic def compute(count: int) -> int:\n    sum = 0\n    for i in range(count):\n        sum += i * 2\n    return sum\n" });
    const edited = try report(try project.build(&.{}));
    try std.testing.expectEqual(@as(u32, 1), edited.compiled);
    try std.testing.expectEqual(cold.units - 1, edited.reused);
    try std.testing.expectEqual(@as(u32, 2), edited.processes);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{s} 30 4\n", .{&directory.sub_path}), try project.output());
    try expectNoStaging(project);
}

// spec: NEW-CORE-S4-COLD-1
test "a cold build compiles the runtime without debug info and links the prebuilt number object" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(a, &directory, true);
    try directory.dir.writeFile(io, .{ .sub_path = "app.my", .data = "module app\n\ndef main(out: Stream) -> int:\n    out.print(2.5)\n    return 0\n" });
    const cold = try report(try project.build(&.{}));
    // The units, the runtime object and the link: no number-tool process.
    try std.testing.expectEqual(cold.compiled + 2, cold.processes);
    try std.testing.expectEqualStrings("2.5\n", try project.output());
    const number = try cwd.readFileAlloc(io, try std.fs.path.join(a, &.{ try project.path("store"), try std.fmt.allocPrint(a, "core_number_text-{x}.o", .{number_runtime.digest()}) }), a, .limited(64 << 20));
    try std.testing.expectEqualSlices(u8, number_runtime.prebuilt, number);
    var store = try cwd.openDir(io, try project.path("store"), .{ .iterate = true });
    defer store.close(io);
    var runtime_objects: usize = 0;
    var iterator = store.iterate();
    while (try iterator.next(io)) |entry| {
        if (!std.mem.startsWith(u8, entry.name, "core_rt-") or !std.mem.endsWith(u8, entry.name, ".o")) continue;
        const bytes = try store.readFileAlloc(io, entry.name, a, .limited(64 << 20));
        try std.testing.expect(!hasSection(bytes, ".debug_info"));
        try std.testing.expect(hasSection(bytes, ".text"));
        runtime_objects += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), runtime_objects);
}

/// Whether the ELF64 relocatable object `bytes` has a section named `name`.
fn hasSection(bytes: []const u8, name: []const u8) bool {
    const offset = std.mem.readInt(u64, bytes[0x28..][0..8], .little);
    const count = std.mem.readInt(u16, bytes[0x3c..][0..2], .little);
    const names_index = std.mem.readInt(u16, bytes[0x3e..][0..2], .little);
    const names = std.mem.readInt(u64, bytes[offset + names_index * 64 + 0x18 ..][0..8], .little);
    for (0..count) |index| {
        const start = names + std.mem.readInt(u32, bytes[offset + index * 64 ..][0..4], .little);
        if (std.mem.eql(u8, std.mem.sliceTo(bytes[start..], 0), name)) return true;
    }
    return false;
}

fn expectNoStaging(project: Project) !void {
    var cache = try cwd.openDir(io, try project.path("cache"), .{ .iterate = true });
    defer cache.close(io);
    var iterator = cache.iterate();
    while (try iterator.next(io)) |entry| {
        try std.testing.expect(!std.mem.startsWith(u8, entry.name, "native-link-"));
        try std.testing.expect(!std.mem.startsWith(u8, entry.name, "program-"));
    }
}

// spec-case: NEW-CORE-S4-REPLAY-1
test "an unchanged release build starts no process, and a replay follows a reverted edit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(arena.allocator(), &directory, false);
    const cold = try report(try project.build(&.{"--release"}));
    try std.testing.expectEqual(@as(u32, 1), cold.units);
    try std.testing.expect((try report(try project.build(&.{"--release"}))).replayed);
    try project.forgetReplays();
    const warm = try report(try project.build(&.{"--release"}));
    try std.testing.expectEqual(@as(u32, 0), warm.processes);
    try std.testing.expectEqualStrings("reused", warm.program);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "other.my", .data = "module other\n\npublic def compute(value: int) -> int:\n    return value + 2\n" });
    try std.testing.expect(!(try report(try project.build(&.{"--release"}))).replayed);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{s} 15 5\n", .{&directory.sub_path}), try project.output());
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "other.my", .data = other });
    const reverted = try report(try project.build(&.{"--release"}));
    try std.testing.expect(!reverted.replayed);
    try std.testing.expectEqual(@as(u32, 0), reverted.processes);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{s} 15 4\n", .{&directory.sub_path}), try project.output());
}

// spec: NEW-CORE-S4-VERIFY-CACHE-1
test "verify-cache recompiles served units, damaged entries are rebuilt, and forged ones are refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(arena.allocator(), &directory, true);
    const expected = try std.fmt.allocPrint(arena.allocator(), "{s} 15 4\n", .{&directory.sub_path});
    const cold = try report(try project.build(&.{}));
    try std.testing.expectEqual(cold.units, cold.compiled);
    const verified = try report(try project.build(&.{"--verify-cache"}));
    try std.testing.expectEqual(Report{ .units = cold.units, .reused = cold.units, .compiled = 0, .verified = cold.units, .program = verified.program, .processes = cold.units, .replayed = false }, verified);
    try std.testing.expectEqualStrings("reused", verified.program);
    try std.testing.expect((try project.damage("store/units-v1", ".o", "damaged")) == cold.units);
    try project.forgetReplays();
    const rebuilt = try report(try project.build(&.{}));
    try std.testing.expectEqual(cold.units, rebuilt.compiled);
    try std.testing.expectEqualStrings("reused", rebuilt.program);
    try std.testing.expectEqualStrings(expected, try project.output());
    try std.testing.expect((try project.damage("cache/programs-v1", "", "damaged")) == 2);
    try project.forgetReplays();
    try std.testing.expectEqualStrings("linked", (try report(try project.build(&.{}))).program);
    try std.testing.expectEqualStrings(expected, try project.output());
    try project.forge("forged object");
    const refused = try project.attempt(&.{"--verify-cache"});
    try std.testing.expect(refused.term == .exited and refused.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, refused.stderr, "--verify-cache: unit") != null);
}

fn linkedBuild(project: *Project) ![]const u8 {
    return project.build(&.{ "--link", try project.path("value.c") });
}

// spec-case: NEW-CORE-S4-CACHE-1
// spec-case: NEW-CORE-S4-REPLAY-1
test "a --link build reuses its C object and program while the source and headers keep their bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(arena.allocator(), &directory, false);
    try directory.dir.writeFile(io, .{ .sub_path = "app.my", .data = "module app\nextern def linked_value(host: Host) -> i32 effects(host)\ndef main(host: Host) -> int:\n    return int(linked_value(host))\n" });
    try directory.dir.writeFile(io, .{ .sub_path = "value.c", .data = "#include \"value.h\"\nint linked_value(void) { return VALUE; }\n" });
    try directory.dir.writeFile(io, .{ .sub_path = "value.h", .data = "#define VALUE 7\n" });
    _ = try linkedBuild(&project);
    // The first build may not pin a header written in the same clock tick; the
    // second records it, and from then on nothing is compiled or linked.
    try project.forgetReplays();
    _ = try linkedBuild(&project);
    try project.forgetReplays();
    const warm = try report(try linkedBuild(&project));
    try std.testing.expectEqual(@as(u32, 0), warm.processes);
    try std.testing.expectEqualStrings("reused", warm.program);
    try std.testing.expect((try report(try linkedBuild(&project))).replayed);
    const before = try directory.dir.statFile(io, "value.h", .{});
    try directory.dir.writeFile(io, .{ .sub_path = "value.h", .data = "#define VALUE 8\n" });
    try directory.dir.setTimestamps(io, "value.h", .{ .modify_timestamp = .{ .new = before.mtime } });
    const edited = try report(try linkedBuild(&project));
    try std.testing.expect(!edited.replayed);
    try std.testing.expectEqualStrings("linked", edited.program);
    const status = try std.process.run(project.arena, io, .{ .argv = &.{try project.path("program")}, .environ_map = &project.environment });
    try std.testing.expect(status.term == .exited and status.term.exited == 8);
}

// spec-case: NEW-CORE-S4-REPLAY-1
test "a replay follows the embedded files a build read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(arena.allocator(), &directory, false);
    try directory.dir.writeFile(io, .{ .sub_path = "app.my", .data = "module app\n\ndef main(out: Stream) -> int:\n    out.print(embed_str(\"data.txt\"))\n    return 0\n" });
    try directory.dir.writeFile(io, .{ .sub_path = "data.txt", .data = "hello" });
    _ = try project.build(&.{});
    try std.testing.expectEqualStrings("hello\n", try project.output());
    try std.testing.expect((try report(try project.build(&.{}))).replayed);
    try directory.dir.writeFile(io, .{ .sub_path = "data.txt", .data = "world" });
    try std.testing.expect(!(try report(try project.build(&.{}))).replayed);
    try std.testing.expectEqualStrings("world\n", try project.output());
}

// spec-case: NEW-CORE-S4-VERIFY-CACHE-1
test "the cache report reader refuses output without a complete cache line" {
    try std.testing.expectError(error.NoCacheReport, report("error: something else\n"));
    try std.testing.expectError(error.BadCacheReport, report("mylang-core: cache: 3 units, 1 reused\n"));
    try std.testing.expectError(error.BadCacheReport, report("mylang-core: cache: 1 units, 2 reused, 3 compiled, 4 verified; program linked; 5 processes 6\n"));
    try std.testing.expect((try report("mylang-core: cache: replayed the last identical build\n")).replayed);
}
