//! The core's object, program and replay caches, through `selka-core build`
//! on a multi-module project (docs/design/new-core-s4.md §7, cache tests).
const std = @import("std");
const tools = @import("core_test_options");
const support = @import("test_support.zig");
const number_runtime = @import("number_runtime.zig");
const fast_blake3 = @import("fast_blake3.zig");
const unit_cache = @import("unit_cache.zig");
const runtime_seed = @import("runtime_seed.zig");
const stage_roots = @import("stage_roots.zig");
const stage_store = @import("stage_store.zig");
const stage_pack = @import("stage_pack.zig");
const io = std.testing.io;
const cwd = std.Io.Dir.cwd();
const diagnostic = std.debug.print;

const leaf = "\npublic func compute(count: int) -> int:\n    mut sum = 0\n    for i in range(count):\n        sum += i\n    return sum\n";
const other = "\npublic func compute(value: int) -> int:\n    return value + 1\n";

/// One project in a temporary directory, built by the core binary.
const Project = struct {
    arena: std.mem.Allocator,
    root: []const u8,
    environment: std.process.Environ.Map,

    fn prepare(a: std.mem.Allocator, directory: *std.testing.TmpDir, private_store: bool) !Project {
        const root = try directory.dir.realPathFileAlloc(io, ".", a);
        // Program and unit counts are this project's own: no shared compiler store.
        var environment = try tools.privateEnvironment(a);
        // A private store makes reuse counts exact; the shared one serves helper
        // units other programs already compiled.
        if (private_store) try environment.put("SELKA_CORE_RUNTIME_CACHE", try std.fs.path.join(a, &.{ root, "store" }));
        const app = try std.fmt.allocPrint(a, "import leaf\nimport other\n\nfunc main(out: Stream) -> int:\n    print(out, \"{s}\", leaf.compute(6), other.compute(3))\n    return 0\n", .{&directory.sub_path});
        try directory.dir.writeFile(io, .{ .sub_path = "app.selka", .data = app });
        try directory.dir.writeFile(io, .{ .sub_path = "leaf.selka", .data = leaf });
        try directory.dir.writeFile(io, .{ .sub_path = "other.selka", .data = other });
        return .{ .arena = a, .root = root, .environment = environment };
    }

    fn path(self: Project, name: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.root, name });
    }

    /// Start the private store with the runtime object, for a test whose subject is not the cold compile of it.
    fn seedRuntime(self: *Project) !void {
        try runtime_seed.seed(self.arena, &self.environment, try self.path("store"));
    }

    /// Build with `--cache-report`; returns the build's stderr, or fails the test.
    fn build(self: *Project, extra: []const []const u8) ![]const u8 {
        const result = try self.attempt(extra);
        if (result.term != .exited or result.term.exited != 0) diagnostic("core build failed: {s}\n", .{result.stderr});
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        return result.stderr;
    }

    fn attempt(self: *Project, extra: []const []const u8) !std.process.RunResult {
        try support.requireReleaseArgs(extra);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(self.arena, &.{ tools.corePath(), "build", try self.path("app.selka"), "-o", try self.path("program"), "--cache-dir", try self.path("cache"), "--cache-report" });
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

    /// Rewrite matching store artifact files with `bytes`, records included or not.
    fn damage(self: Project, relative: []const u8, suffix: []const u8, bytes: []const u8) !usize {
        var directory = try cwd.openDir(io, try self.path(relative), .{ .iterate = true });
        defer directory.close(io);
        var iterator = try directory.walk(self.arena);
        defer iterator.deinit();
        var count: usize = 0;
        while (try iterator.next(io)) |entry| {
            if (entry.kind == .directory and entry.basename.len != 2) {
                iterator.leave(io);
                continue;
            }
            if (entry.kind != .file or std.mem.startsWith(u8, entry.basename, ".")) continue;
            if (!std.mem.endsWith(u8, entry.basename, suffix)) continue;
            // A stored program is read-only (`program_store.protect`); a disk that damages it does not ask.
            try directory.setFilePermissions(io, entry.path, .fromMode(0o644), .{});
            try directory.writeFile(io, .{ .sub_path = entry.path, .data = bytes });
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
        var iterator = try directory.walk(self.arena);
        defer iterator.deinit();
        while (try iterator.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".o")) continue;
            try directory.writeFile(io, .{ .sub_path = entry.path, .data = bytes });
            try directory.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(self.arena, "{s}.sum", .{entry.path}), .data = record });
        }
    }
};

/// The numbers of one `--cache-report` line.
const Report = struct { units: u32, reused: u32, compiled: u32, verified: u32, program: []const u8, processes: u32, replayed: bool };

// Each layout's runtime object is seeded (`runtime_seed.zig`) rather than compiled here; the
// store ending with one runtime object per layout shows that each layout keys its own.
// spec: LAYOUT-SWITCH-1
test "layout changes rebuild units and key their own runtime, and returning to a layout reuses objects programs and replay" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(arena.allocator(), &directory, true);
    try project.environment.put("SELKA_CORE_LAYOUT", "4");
    try project.seedRuntime();
    const four = try report(try project.build(&.{}));
    const expected = try project.output();
    try std.testing.expectEqual(four.units, four.compiled);
    try std.testing.expectEqual(four.compiled + 1, four.processes);
    try std.testing.expect((try report(try project.build(&.{}))).replayed);
    try project.environment.put("SELKA_CORE_LAYOUT", "5");
    try project.seedRuntime();
    const five = try report(try project.build(&.{}));
    try std.testing.expectEqual(five.units, five.compiled);
    try std.testing.expectEqual(five.compiled + 1, five.processes);
    try std.testing.expectEqualStrings(expected, try project.output());
    try project.environment.put("SELKA_CORE_LAYOUT", "6");
    try project.seedRuntime();
    const six = try report(try project.build(&.{}));
    try std.testing.expectEqual(six.units, six.compiled);
    try std.testing.expectEqual(six.compiled + 1, six.processes);
    try std.testing.expectEqualStrings(expected, try project.output());
    try std.testing.expectEqual(@as(usize, 3), try runtimeObjects(project));
    try project.environment.put("SELKA_CORE_LAYOUT", "4");
    try std.testing.expect((try report(try project.build(&.{}))).replayed);
    try project.forgetReplays();
    const reused = try report(try project.build(&.{}));
    try std.testing.expectEqual(@as(u32, 0), reused.processes);
    try std.testing.expectEqual(four.units, reused.reused);
    try std.testing.expectEqualStrings("reused", reused.program);
    try std.testing.expectEqualStrings(expected, try project.output());
}

fn report(stderr: []const u8) !Report {
    if (std.mem.indexOf(u8, stderr, "selka-core: cache: replayed") != null) return .{ .units = 0, .reused = 0, .compiled = 0, .verified = 0, .program = "replayed", .processes = 0, .replayed = true };
    const start = std.mem.indexOf(u8, stderr, "selka-core: cache: ") orelse return error.NoCacheReport;
    const line = std.mem.sliceTo(stderr[start + "selka-core: cache: ".len ..], '\n');
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
    try project.seedRuntime();
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
    // A build whose program was reused from the store records itself, so the next identical build replays.
    try std.testing.expect((try report(try project.build(&.{}))).replayed);
    try std.testing.expectEqualStrings(expected, try project.output());
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "leaf.selka", .data = "\npublic func compute(count: int) -> int:\n    mut sum = 0\n    for i in range(count):\n        sum += i * 2\n    return sum\n" });
    const edited = try report(try project.build(&.{}));
    try std.testing.expectEqual(@as(u32, 1), edited.compiled);
    try std.testing.expectEqual(cold.units - 1, edited.reused);
    try std.testing.expectEqual(@as(u32, 2), edited.processes);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{s} 30 4\n", .{&directory.sub_path}), try project.output());
    try expectNoStaging(project);
}

// A replay record is keyed by the variables the identity contract keys, not the whole
// environment, and an entry keeps a record per set of inputs, so an undone edit replays.
// spec-case: NEW-CORE-S4-REPLAY-1
test "a placement variable keeps the replay, and undoing an edit replays the earlier build" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(arena.allocator(), &directory, true);
    try project.seedRuntime();
    const expected = try std.fmt.allocPrint(arena.allocator(), "{s} 15 4\n", .{&directory.sub_path});
    const cold = try report(try project.build(&.{}));
    try std.testing.expectEqualStrings("linked", cold.program);
    try project.environment.put("SELKA_ADMISSION_KIND", "timing");
    try project.environment.put("UNRELATED_TOOL_SETTING", "1");
    try std.testing.expect((try report(try project.build(&.{}))).replayed);
    try directory.dir.writeFile(io, .{ .sub_path = "leaf.selka", .data = "\npublic func compute(count: int) -> int:\n    mut sum = 0\n    for i in range(count):\n        sum += i * 2\n    return sum\n" });
    const edited = try report(try project.build(&.{}));
    try std.testing.expect(!edited.replayed);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{s} 30 4\n", .{&directory.sub_path}), try project.output());
    try directory.dir.writeFile(io, .{ .sub_path = "leaf.selka", .data = leaf });
    try std.testing.expect((try report(try project.build(&.{}))).replayed);
    try std.testing.expectEqualStrings(expected, try project.output());
    // A keyed variable is part of the key: the build runs again.
    try project.environment.put("SOURCE_DATE_EPOCH", "1");
    try std.testing.expect(!(try report(try project.build(&.{}))).replayed);
    try std.testing.expectEqualStrings(expected, try project.output());
}

// A work directory keeps the records and programs a build used last, not the ones it wrote last: the tree an edit is undone to is
// the one every build in between returned to, so it replays however many other states were built since (F58).
// spec-case: NEW-CORE-S4-REPLAY-1
test "undoing an edit replays the earlier build, however many other states were built in between" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(a, &directory, true);
    try project.seedRuntime();
    const expected = try std.fmt.allocPrint(a, "{s} 15 4\n", .{&directory.sub_path});
    try std.testing.expectEqualStrings("linked", (try report(try project.build(&.{}))).program);
    // Six states the base never was, more than the four records and the four programs an entry keeps; each one built, then undone.
    for (2..8) |step| {
        try editLeaf(a, &directory, step);
        try std.testing.expect(!(try report(try project.build(&.{}))).replayed);
        try directory.dir.writeFile(io, .{ .sub_path = "leaf.selka", .data = leaf });
        try std.testing.expect((try report(try project.build(&.{}))).replayed);
    }
    try std.testing.expectEqualStrings(expected, try project.output());
}

/// A leaf module whose enum `area` matches and `compute` reaches; the type edit adds a variant and its arm.
const shaped =
    \\
    \\enum Shape:
    \\    round
    \\    square
    \\
    \\func area(shape: Shape) -> int:
    \\    match shape:
    \\        case round:
    \\            return 3
    \\        case square:
    \\            return 4
    \\
    \\public func compute(count: int) -> int:
    \\    mut sum = area(Shape.round)
    \\    for i in range(count):
    \\        sum += i
    \\    return sum
;
const shaped_edit =
    \\
    \\enum Shape:
    \\    round
    \\    square
    \\    triangle
    \\
    \\func area(shape: Shape) -> int:
    \\    match shape:
    \\        case round:
    \\            return 3
    \\        case square:
    \\            return 4
    \\        case triangle:
    \\            return 5
    \\
    \\public func compute(count: int) -> int:
    \\    mut sum = area(Shape.round)
    \\    for i in range(count):
    \\        sum += i
    \\    return sum
;

/// Assert the demand generation pointer of the project's cache names `current` and has published `high`
/// (`demand_generation.zig`): one file, since the project has one entry and one settings scope.
fn expectGenerations(a: std.mem.Allocator, project: Project, current: u64, high: u64) !void {
    const directory_name = "cache/demand-generation-v3";
    var directory = try cwd.openDir(io, try project.path(directory_name), .{ .iterate = true });
    defer directory.close(io);
    var entries = directory.iterate();
    const entry = (try entries.next(io)) orelse return error.TestUnexpectedResult;
    try std.testing.expect((try entries.next(io)) == null);
    const bytes = try cwd.readFileAlloc(io, try std.fs.path.join(a, &.{ try project.path(directory_name), entry.name }), a, .limited(256));
    var words = std.mem.tokenizeAny(u8, bytes, " \n");
    try std.testing.expectEqualStrings("selka-demand-generation-v3", words.next() orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(current, try std.fmt.parseInt(u64, words.next() orelse return error.TestUnexpectedResult, 10));
    try std.testing.expectEqual(high, try std.fmt.parseInt(u64, words.next() orelse return error.TestUnexpectedResult, 10));
}

// Undoing an edit replays the earlier build, and the replay publishes that build's demand generation, so the next
// real build reads the state of the tree it serves (`demand_generation.zig`). A debug compiler never takes the demand
// path (`useDemandBodies`), so the generations are what this test can observe; the optimizer's bypass counts need a
// release compiler and are measured on the edit-loop trees.
// spec-case: NEW-CORE-S4-REPLAY-1
test "undoing a type edit replays and publishes the replayed build's demand generation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(a, &directory, true);
    try project.seedRuntime();
    try directory.dir.writeFile(io, .{ .sub_path = "leaf.selka", .data = shaped });
    try std.testing.expect(!(try report(try project.build(&.{}))).replayed);
    try expectGenerations(a, project, 1, 1);
    // Ownership proofs are records of their own inputs and name no generation, so no ownership pointer exists to read.
    try std.testing.expectError(error.FileNotFound, cwd.statFile(io, try project.path("cache/ownership-generation-v2"), .{}));
    // An unchanged rebuild replays and names the generation already current: no pointer moves.
    try std.testing.expect((try report(try project.build(&.{}))).replayed);
    try expectGenerations(a, project, 1, 1);
    try directory.dir.writeFile(io, .{ .sub_path = "leaf.selka", .data = shaped_edit });
    try std.testing.expect(!(try report(try project.build(&.{}))).replayed);
    try expectGenerations(a, project, 2, 2);
    try directory.dir.writeFile(io, .{ .sub_path = "leaf.selka", .data = shaped });
    try std.testing.expect((try report(try project.build(&.{}))).replayed);
    try expectGenerations(a, project, 1, 2);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{s} 18 4\n", .{&directory.sub_path}), try project.output());
    try directory.dir.writeFile(io, .{ .sub_path = "leaf.selka", .data = shaped ++ "\npublic func extra() -> int:\n    return 7\n" });
    try std.testing.expect(!(try report(try project.build(&.{}))).replayed);
    try expectGenerations(a, project, 3, 3);
}

// spec: NEW-CORE-S4-COLD-1
// spec: NEW-CORE-S5-RUNTIME-LAYOUT-1
test "a cold build compiles the runtime without debug info, cache-line aligned, and links the prebuilt number object" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(a, &directory, true);
    try directory.dir.writeFile(io, .{ .sub_path = "app.selka", .data = "\nfunc main(out: Stream) -> int:\n    print(out, 2.5)\n    return 0\n" });
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
        // GH-3f: the runtime source is compiled in the build's staging directory, as `core_rt.c`, and none is kept here.
        try std.testing.expect(!(std.mem.startsWith(u8, entry.name, "core_rt-") and std.mem.endsWith(u8, entry.name, ".c")));
        if (!std.mem.startsWith(u8, entry.name, "core_rt-") or !std.mem.endsWith(u8, entry.name, ".o")) continue;
        const bytes = try store.readFileAlloc(io, entry.name, a, .limited(64 << 20));
        try std.testing.expect(std.mem.indexOf(u8, bytes, "core_rt-") == null);
        try std.testing.expect(std.mem.indexOf(u8, bytes, "core_rt.c") != null);
        try std.testing.expect(!hasSection(bytes, ".debug_info"));
        // Functions start on cache lines, and no 256 KiB static array moves the heap
        // (the stream buffers are 128 KiB of it).
        try std.testing.expect((section(bytes, ".text") orelse return error.TestNoText).alignment >= 64);
        try std.testing.expect((section(bytes, ".bss") orelse Section{ .size = 0, .alignment = 0 }).size < 256 << 10);
        runtime_objects += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), runtime_objects);
    // The key of the runtime object holds the toolchain identity: it must not be in the program.
    const program = try cwd.readFileAlloc(io, try project.path("program"), a, .limited(256 << 20));
    try std.testing.expect(std.mem.indexOf(u8, program, "core_rt-") == null);
}

/// A section of an ELF64 relocatable object: its size and alignment.
const Section = struct { size: u64, alignment: u64 };

/// The section of `bytes` named `name`, or null.
fn section(bytes: []const u8, name: []const u8) ?Section {
    const offset = std.mem.readInt(u64, bytes[0x28..][0..8], .little);
    const count = std.mem.readInt(u16, bytes[0x3c..][0..2], .little);
    const names_index = std.mem.readInt(u16, bytes[0x3e..][0..2], .little);
    const names = std.mem.readInt(u64, bytes[offset + names_index * 64 + 0x18 ..][0..8], .little);
    for (0..count) |index| {
        const header = bytes[offset + index * 64 ..][0..64];
        const start = names + std.mem.readInt(u32, header[0..4], .little);
        if (!std.mem.eql(u8, std.mem.sliceTo(bytes[start..], 0), name)) continue;
        return .{ .size = std.mem.readInt(u64, header[0x20..][0..8], .little), .alignment = std.mem.readInt(u64, header[0x30..][0..8], .little) };
    }
    return null;
}

/// Whether the ELF64 relocatable object `bytes` has a section named `name`.
fn hasSection(bytes: []const u8, name: []const u8) bool {
    return section(bytes, name) != null;
}

/// How many runtime objects (`core_rt-*.o`) the project's private store holds.
fn runtimeObjects(project: Project) !usize {
    var store = try cwd.openDir(io, try project.path("store"), .{ .iterate = true });
    defer store.close(io);
    var count: usize = 0;
    var iterator = store.iterate();
    while (try iterator.next(io)) |entry| {
        if (std.mem.startsWith(u8, entry.name, "core_rt-") and std.mem.endsWith(u8, entry.name, ".o")) count += 1;
    }
    return count;
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
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "other.selka", .data = "\npublic func compute(value: int) -> int:\n    return value + 2\n" });
    try std.testing.expect(!(try report(try project.build(&.{"--release"}))).replayed);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{s} 15 5\n", .{&directory.sub_path}), try project.output());
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "other.selka", .data = other });
    // The reverted sources are the first build's inputs, whose record is still kept.
    const reverted = try report(try project.build(&.{"--release"}));
    try std.testing.expect(reverted.replayed);
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
    try project.seedRuntime();
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
    try std.testing.expect((try project.damage("cache/programs-v2", "", "damaged")) == 2);
    try project.forgetReplays();
    try std.testing.expectEqualStrings("linked", (try report(try project.build(&.{}))).program);
    try std.testing.expectEqualStrings(expected, try project.output());
    try project.forge("forged object");
    const refused = try project.attempt(&.{"--verify-cache"});
    // `selka build` reports a refused cached object as a tool failure, status 2.
    try std.testing.expect(refused.term == .exited and refused.term.exited == 2);
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
    try directory.dir.writeFile(io, .{ .sub_path = "app.selka", .data = "extern func linked_value(host: Host) -> i32\nfunc main(host: Host) -> int:\n    return int(linked_value(host))\n" });
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

const linked_app = "extern func linked_value(host: Host) -> i32\nfunc main(host: Host) -> int:\n    return int(linked_value(host))\n";

/// The status of the program `project` last built: `linked_value`'s result.
fn linkedStatus(project: *Project) !u8 {
    const status = try std.process.run(project.arena, io, .{ .argv = &.{try project.path("program")}, .environ_map = &project.environment });
    try std.testing.expect(status.term == .exited);
    return status.term.exited;
}

/// Build `value.c` until its object is published (the first build may not pin a header written in the same clock tick), then
/// once more with no replay record: that build's report.
fn warmLinkedBuild(project: *Project) !Report {
    _ = try linkedBuild(project);
    try project.forgetReplays();
    _ = try linkedBuild(project);
    try project.forgetReplays();
    return report(try linkedBuild(project));
}

// spec-case: NEW-CORE-S4-CACHE-1
test "a --link source that names its header through a macro is served by its preprocessed text, at one process a build" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(arena.allocator(), &directory, false);
    try directory.dir.writeFile(io, .{ .sub_path = "app.selka", .data = linked_app });
    try directory.dir.writeFile(io, .{ .sub_path = "value.c", .data = "#define HEADER \"value.h\"\n#include HEADER\nint linked_value(void) { return VALUE; }\n" });
    try directory.dir.writeFile(io, .{ .sub_path = "value.h", .data = "#define VALUE 7\n" });
    // The depfile check cannot read the name, so the object is keyed by the preprocessed text: a warm build runs the
    // preprocessor and nothing else, and does not replay.
    const warm = try warmLinkedBuild(&project);
    try std.testing.expectEqual(@as(u32, 1), warm.processes);
    try std.testing.expectEqualStrings("reused", warm.program);
    try std.testing.expectEqual(@as(usize, 1), try forgeForeign(&project, null));
    try std.testing.expectEqual(@as(u8, 7), try linkedStatus(&project));
    try std.testing.expect(!(try report(try linkedBuild(&project))).replayed);
    // The header the macro names changes the text, with its mtime kept.
    const before = try directory.dir.statFile(io, "value.h", .{});
    try directory.dir.writeFile(io, .{ .sub_path = "value.h", .data = "#define VALUE 8\n" });
    try directory.dir.setTimestamps(io, "value.h", .{ .modify_timestamp = .{ .new = before.mtime } });
    try std.testing.expectEqualStrings("linked", (try report(try linkedBuild(&project))).program);
    try std.testing.expectEqual(@as(u8, 8), try linkedStatus(&project));
}

// spec-case: NEW-CORE-S4-CACHE-1
test "a --link source whose header names another through a macro is keyed by its preprocessed text from its second build" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(arena.allocator(), &directory, false);
    try directory.dir.writeFile(io, .{ .sub_path = "app.selka", .data = linked_app });
    try directory.dir.writeFile(io, .{ .sub_path = "value.c", .data = "#include \"wrap.h\"\nint linked_value(void) { return VALUE; }\n" });
    try directory.dir.writeFile(io, .{ .sub_path = "wrap.h", .data = "#define HEADER \"value.h\"\n#include HEADER\n" });
    try directory.dir.writeFile(io, .{ .sub_path = "value.h", .data = "#define VALUE 7\n" });
    // The source's own text reads; the first compile that pins its headers finds the macro in `wrap.h` and marks the
    // source, and from then on the preprocessed text keys it.
    _ = try linkedBuild(&project);
    try project.forgetReplays();
    const warm = try warmLinkedBuild(&project);
    try std.testing.expectEqual(@as(u32, 1), warm.processes);
    try std.testing.expectEqual(@as(usize, 1), try forgeForeign(&project, null));
    try std.testing.expectEqual(@as(u8, 7), try linkedStatus(&project));
    try directory.dir.writeFile(io, .{ .sub_path = "value.h", .data = "#define VALUE 9\n" });
    try std.testing.expectEqualStrings("linked", (try report(try linkedBuild(&project))).program);
    try std.testing.expectEqual(@as(u8, 9), try linkedStatus(&project));
}

/// Count the stored `--link` objects, and rewrite each with `bytes`, when given, and a record that vouches for them.
fn forgeForeign(project: *Project, forgery: ?[]const u8) !usize {
    var directory = try cwd.openDir(io, try project.path("cache/foreign-v1"), .{ .iterate = true });
    defer directory.close(io);
    const bytes = forgery orelse "";
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    const record = try std.fmt.allocPrint(project.arena, "core-unit-sum-v1\n{d}\n{s}\n", .{ bytes.len, std.fmt.bytesToHex(digest, .lower) });
    var iterator = try directory.walk(project.arena);
    defer iterator.deinit();
    var forged: usize = 0;
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".o")) continue;
        forged += 1;
        if (forgery == null) continue;
        try directory.writeFile(io, .{ .sub_path = entry.path, .data = bytes });
        try directory.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(project.arena, "{s}.sum", .{entry.path}), .data = record });
    }
    return forged;
}

/// `--verify-cache` on the warm build of `value.c`: it passes, and fails once the stored object is forged.
fn verifyLinked(project: *Project) !void {
    _ = try warmLinkedBuild(project);
    _ = try project.build(&.{ "--link", try project.path("value.c"), "--verify-cache" });
    try std.testing.expectEqual(@as(usize, 1), try forgeForeign(project, "forged object"));
    const refused = try project.attempt(&.{ "--link", try project.path("value.c"), "--verify-cache" });
    try std.testing.expect(refused.term == .exited and refused.term.exited == 2);
    try std.testing.expect(std.mem.indexOf(u8, refused.stderr, "--verify-cache: a --link source") != null);
}

// spec-case: NEW-CORE-S4-VERIFY-CACHE-1
test "verify-cache recompiles a served --link object under either key and refuses a forged one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var plain_directory = std.testing.tmpDir(.{});
    defer plain_directory.cleanup();
    var plain = try Project.prepare(arena.allocator(), &plain_directory, false);
    try plain_directory.dir.writeFile(io, .{ .sub_path = "app.selka", .data = linked_app });
    try plain_directory.dir.writeFile(io, .{ .sub_path = "value.c", .data = "#include \"value.h\"\nint linked_value(void) { return VALUE; }\n" });
    try plain_directory.dir.writeFile(io, .{ .sub_path = "value.h", .data = "#define VALUE 7\n" });
    try verifyLinked(&plain);
    var macro_directory = std.testing.tmpDir(.{});
    defer macro_directory.cleanup();
    var macro = try Project.prepare(arena.allocator(), &macro_directory, false);
    try macro_directory.dir.writeFile(io, .{ .sub_path = "app.selka", .data = linked_app });
    try macro_directory.dir.writeFile(io, .{ .sub_path = "value.c", .data = "#define HEADER \"value.h\"\n#include HEADER\nint linked_value(void) { return VALUE; }\n" });
    try macro_directory.dir.writeFile(io, .{ .sub_path = "value.h", .data = "#define VALUE 7\n" });
    try verifyLinked(&macro);
}

// spec-case: PROJECT-LINKS-1
test "a project's links in selka.json are linked like --link files, and an edit to a listed file or to the list rebuilds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(arena.allocator(), &directory, false);
    try directory.dir.writeFile(io, .{ .sub_path = "app.selka", .data = linked_app });
    try directory.dir.createDirPath(io, "c");
    try directory.dir.writeFile(io, .{ .sub_path = "c/value.c", .data = "#include \"value.h\"\nint linked_value(void) { return VALUE; }\n" });
    try directory.dir.writeFile(io, .{ .sub_path = "c/value.h", .data = "#define VALUE 7\n" });
    try directory.dir.writeFile(io, .{ .sub_path = "c/other.c", .data = "int other_value(void) { return 1; }\n" });
    try directory.dir.writeFile(io, .{ .sub_path = "selka.json", .data = "{\"version\": 1, \"links\": [\"c/value.c\"]}" });
    // No --link: the configuration names the C, and an unchanged build replays.
    _ = try project.build(&.{});
    try std.testing.expectEqual(@as(u8, 7), try linkedStatus(&project));
    _ = try project.build(&.{});
    try std.testing.expect((try report(try project.build(&.{}))).replayed);
    // An edit to a listed file rebuilds, its mtime kept.
    const before = try directory.dir.statFile(io, "c/value.h", .{});
    try directory.dir.writeFile(io, .{ .sub_path = "c/value.h", .data = "#define VALUE 8\n" });
    try directory.dir.setTimestamps(io, "c/value.h", .{ .modify_timestamp = .{ .new = before.mtime } });
    try std.testing.expect(!(try report(try project.build(&.{}))).replayed);
    try std.testing.expectEqual(@as(u8, 8), try linkedStatus(&project));
    // An edit to the list rebuilds.
    try directory.dir.writeFile(io, .{ .sub_path = "selka.json", .data = "{\"version\": 1, \"links\": [\"c/value.c\", \"c/other.c\"]}" });
    try std.testing.expect(!(try report(try project.build(&.{}))).replayed);
    // A --link file comes after the configuration's, and one the configuration already lists is linked once.
    _ = try project.build(&.{ "--link", try project.path("c/value.c") });
    try std.testing.expectEqual(@as(u8, 8), try linkedStatus(&project));
    // A listed file that does not exist names the configuration and the entry.
    try directory.dir.writeFile(io, .{ .sub_path = "selka.json", .data = "{\"version\": 1, \"links\": [\"c/missing.c\"]}" });
    const refused = try project.attempt(&.{});
    try std.testing.expect(refused.term == .exited and refused.term.exited == 2);
    try std.testing.expect(std.mem.indexOf(u8, refused.stderr, "selka.json: error[E_PROJECT_CONFIG]: links entry \"c/missing.c\" names no file") != null);
    // That line says it all: no second line about a refused configuration and a stage store follows.
    try std.testing.expect(std.mem.indexOf(u8, refused.stderr, "build failed") == null);
}

// spec-case: NEW-CORE-S4-REPLAY-1
test "a replay follows the embedded files a build read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(arena.allocator(), &directory, false);
    try directory.dir.writeFile(io, .{ .sub_path = "app.selka", .data = "\nfunc main(out: Stream) -> int:\n    print(out, embed_str(\"data.txt\"))\n    return 0\n" });
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
    try std.testing.expectError(error.BadCacheReport, report("selka-core: cache: 3 units, 1 reused\n"));
    try std.testing.expectError(error.BadCacheReport, report("selka-core: cache: 1 units, 2 reused, 3 compiled, 4 verified; program linked; 5 processes 6\n"));
    try std.testing.expect((try report("selka-core: cache: replayed the last identical build\n")).replayed);
}

// spec-case: TSAN-BUILD-1
// spec-case: ASAN-BUILD-1
test "sanitizers separate runtime units foreign objects programs and replay from ordinary builds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(arena.allocator(), &directory, true);
    _ = project.environment.swapRemove("SELKA_CORE_SANITIZE");
    try directory.dir.writeFile(io, .{ .sub_path = "foreign.c", .data = "int native_probe(int *value) { return *value + 1; }\n" });
    const extra = &[_][]const u8{ "--link", try project.path("foreign.c") };
    // Each runtime object is seeded; the units, the C object and the link are this test's.
    try project.seedRuntime();
    const ordinary = try report(try project.build(extra));
    const expected = try project.output();
    try std.testing.expectEqual(ordinary.units, ordinary.compiled);
    try std.testing.expectEqual(ordinary.compiled + 2, ordinary.processes);
    for ([_][]const u8{ "thread", "address" }) |kind| {
        try project.environment.put("SELKA_CORE_SANITIZE", kind);
        try project.seedRuntime();
        const sanitized = try report(try project.build(extra));
        try std.testing.expectEqual(sanitized.units, sanitized.compiled);
        try std.testing.expectEqual(sanitized.compiled + 2, sanitized.processes);
        try std.testing.expectEqualStrings(expected, try project.output());
        try std.testing.expect((try report(try project.build(extra))).replayed);
        try project.forgetReplays();
        const reused = try report(try project.build(extra));
        try std.testing.expectEqual(@as(u32, 0), reused.processes);
        try std.testing.expectEqual(sanitized.units, reused.reused);
        try std.testing.expectEqualStrings("reused", reused.program);
    }
    _ = project.environment.swapRemove("SELKA_CORE_SANITIZE");
    const normal_again = try report(try project.build(extra));
    try std.testing.expectEqual(@as(u32, 0), normal_again.processes);
    try std.testing.expectEqualStrings(expected, try project.output());
    // The ordinary, thread and address runtimes are three objects under three keys.
    try std.testing.expectEqual(@as(usize, 3), try runtimeObjects(project));
    try project.environment.put("SELKA_CORE_SANITIZE", "invalid");
    const invalid = try project.attempt(extra);
    try std.testing.expect(invalid.term == .exited and invalid.term.exited != 0);
    try std.testing.expect(std.mem.indexOf(u8, invalid.stderr, "SELKA_CORE_SANITIZE must be thread") != null);
}

/// Rewrite the leaf module with a body that differs at each `step`, so each step's records are new.
fn editLeaf(a: std.mem.Allocator, directory: *std.testing.TmpDir, step: usize) !void {
    const text = try std.fmt.allocPrint(a, "\npublic func compute(count: int) -> int:\n    mut sum = 0\n    for i in range(count):\n        sum += i * {d}\n    return sum\n", .{step});
    try directory.dir.writeFile(io, .{ .sub_path = "leaf.selka", .data = text });
}

test "a compacted stage store keeps the records the next build needs, and that build equals a --no-cache build" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(a, &directory, true);
    try project.seedRuntime();
    _ = try project.build(&.{});
    for (1..7) |step| {
        try editLeaf(a, &directory, step);
        _ = try project.build(&.{});
    }
    const work = try project.path("cache");
    const packed_root = try project.path("cache/stages-packed-v1");
    var storage = try stage_store.Store.init(a, io, work);
    defer storage.deinit();
    var ranks = try stage_roots.rank(a, io, work, packed_root);
    // A record no root names is dead: compaction drops it, and it reads as a miss afterwards.
    const dead = storage.key("driver-dead-record", &.{});
    try std.testing.expect(try storage.save(dead, "a record no root names"));
    try std.testing.expect(try storage.flush());
    const compacted = (try storage.storage.compactLive(&ranks, stage_pack.default_band_bytes)) orelse return error.TestUnexpectedResult;
    try std.testing.expect(compacted.before.pack_bytes > compacted.after.pack_bytes);
    try std.testing.expectEqual(@as(?[]u8, null), try storage.load(a, dead));
    try editLeaf(a, &directory, 7);
    _ = try project.build(&.{});
    const cached = try cwd.readFileAlloc(io, try project.path("program"), a, .limited(64 << 20));
    _ = try project.build(&.{"--no-cache"});
    const uncached = try cwd.readFileAlloc(io, try project.path("program"), a, .limited(64 << 20));
    try std.testing.expectEqualSlices(u8, uncached, cached);
}

// spec-case: TOOL-RECIPE-1
test "a store learns the tool command lines on its first build, builds through them after, and goes round a damaged recipe" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var project = try Project.prepare(a, &directory, true);
    try project.seedRuntime();
    const first = try project.build(&.{"--report"});
    try std.testing.expect(std.mem.indexOf(u8, first, "\"recipes\":{\"link\":false,") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"learned\":2}") != null);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{s} 15 4\n", .{&directory.sub_path}), try project.output());
    // The next edit compiles its units with the recipe's `zig clang` and links with its `zig ld.lld`.
    try directory.dir.writeFile(io, .{ .sub_path = "leaf.selka", .data = other });
    const second = try project.build(&.{"--report"});
    try std.testing.expect(std.mem.indexOf(u8, second, "\"recipes\":{\"link\":true,") != null);
    try std.testing.expect(std.mem.indexOf(u8, second, "\"units\":0,") == null);
    try std.testing.expect(std.mem.indexOf(u8, second, "\"learned\":0}") != null);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{s} 7 4\n", .{&directory.sub_path}), try project.output());
    // A damaged recipe is no recipe: the build learns it again, and its link, which has not learned yet, is `zig cc`.
    try std.testing.expectEqual(@as(usize, 2), try project.damage("store/tool-recipes-v1", "", "not a recipe"));
    try directory.dir.writeFile(io, .{ .sub_path = "leaf.selka", .data = "\npublic func compute(count: int) -> int:\n    return count * 3\n" });
    const third = try project.build(&.{"--report"});
    try std.testing.expect(std.mem.indexOf(u8, third, "\"recipes\":{\"link\":false,") != null);
    // The compile recipe is learned before the units compile, so they use it; the link is the one that falls back.
    try std.testing.expect(std.mem.indexOf(u8, third, "\"units\":0,") == null);
    try std.testing.expect(std.mem.indexOf(u8, third, "\"learned\":2}") != null);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{s} 18 4\n", .{&directory.sub_path}), try project.output());
    try directory.dir.writeFile(io, .{ .sub_path = "leaf.selka", .data = "\npublic func compute(count: int) -> int:\n    return count * 5\n" });
    const fourth = try project.build(&.{"--report"});
    try std.testing.expect(std.mem.indexOf(u8, fourth, "\"recipes\":{\"link\":true,") != null);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{s} 30 4\n", .{&directory.sub_path}), try project.output());
}
