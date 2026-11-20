//! Build the edit check's coverage map from the hit sets of a collection run.
//!
//! Input: one or more run directories written by `scripts/edit_check_collect.py`
//! (`cov/<root>-<index>/<pid>.cov`, `tests-<root>.json`, `results-<root>.jsonl`) and the
//! checkout the instrumented binaries were built from. Each hit counter maps to the
//! source functions of its binary (`dwarf_functions.zig`); each function is named by its
//! file, its name and ordinal, and the token digest of its body in that checkout
//! (`zig_functions.zig`). The map is one JSON document, gzip-compressed when the output
//! path ends in `.gz`:
//!
//!     {"format":"edit-check-coverage-map-v2","commit":C,"roots":{"units":N,...,"guests":M},
//!      "functions":[[file,name,ordinal,digest],...],
//!      "tests":[[root,name,[function ids]],...],     // ids ascending; a guest's name is its path
//!      "unnamed":{"units":[ids],...},                 // the shared set of a root's unnamed blocks
//!      "unstable":[test,...],                         // sets differed between runs
//!      "failed":[test,...],                           // failed or timed out alone
//!      "stats":{...}}
//!
//! The `guests` root (EC2 guest selection) holds one entry per guest file under `tests/lang`: the functions
//! its `selka test FILE` runs execute, cold and warm (`scripts/edit_check_collect.py --guests`). A map with no
//! `guests` root is still read: the impact tool then selects every guest file as new.
const std = @import("std");
const build_id = @import("build_id.zig");
const dwarf_functions = @import("dwarf_functions.zig");
const zig_functions = @import("zig_functions.zig");

/// What to build and from what.
pub const Options = struct {
    /// Absolute checkout root the binaries were built from.
    repo: []const u8,
    /// Commit id recorded in the map.
    commit: []const u8,
    /// Run directories; hit sets of the same test are unioned.
    runs: []const []const u8,
    /// Output path.
    out: []const u8,
};

const none = std.math.maxInt(u32);

/// The root of the guest test files: their names are paths, and a run's list is `tests-guests.json`.
const guest_root = "guests";

/// The functions of the map, in the order they were first seen.
const Functions = struct {
    records: std.ArrayList(Record) = .empty,
    ids: std.StringHashMapUnmanaged(u32) = .empty,

    const Record = struct { file: []const u8, name: []const u8, ordinal: u32, digest: zig_functions.Digest };

    fn intern(self: *Functions, arena: std.mem.Allocator, file: []const u8, name: []const u8, ordinal: u32, digest: zig_functions.Digest) !u32 {
        const key = try std.fmt.allocPrint(arena, "{s}\x00{s}\x00{d}", .{ file, name, ordinal });
        const slot = try self.ids.getOrPut(arena, key);
        if (!slot.found_existing) {
            slot.value_ptr.* = @intCast(self.records.items.len);
            try self.records.append(arena, .{ .file = file, .name = name, .ordinal = ordinal, .digest = digest });
        }
        return slot.value_ptr.*;
    }
};

const SourceFile = struct { parsed: ?zig_functions.File };

/// Counts the build reports about itself.
pub const Stats = struct {
    /// Tests with a hit set.
    tests: usize = 0,
    /// `.cov` files read.
    processes: usize = 0,
    /// Distinct source functions in the map.
    functions: usize = 0,
    /// Function keys the debug information named.
    keys: usize = 0,
    /// Keys whose declaration line is exactly a function's first line.
    keys_exact: usize = 0,
    /// Keys that fell inside a function that starts earlier.
    keys_inside: usize = 0,
    /// Keys in no function of their file (mapped to the file's remainder).
    keys_outside: usize = 0,
    /// Counters read zero at exit that the sampler had seen run.
    wrapped_counters: usize = 0,
    /// Pairs of (test, function) that only the sampler saw.
    sampler_only_pairs: usize = 0,
    /// Tests that differ between runs.
    unstable: usize = 0,
    /// Tests the map names as unrecorded (their process left no hit set).
    unrecorded: usize = 0,
};

/// Build the map; returns what it measured about itself.
pub fn build(gpa: std.mem.Allocator, io: std.Io, options: Options) !Stats {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var stats: Stats = .{};
    var functions: Functions = .{};
    var sources: std.StringHashMapUnmanaged(SourceFile) = .empty;
    defer {
        var parsed = sources.valueIterator();
        while (parsed.next()) |source| if (source.parsed) |*file| file.deinit(gpa);
    }
    var binaries: std.StringHashMapUnmanaged(Binary) = .empty;
    defer {
        var loaded = binaries.valueIterator();
        while (loaded.next()) |binary| binary.table.deinit(gpa);
    }

    var runs: std.ArrayList(Run) = .empty;
    for (options.runs) |directory| try runs.append(arena, try readRun(arena, io, directory));
    // The unrecorded tests come from the traced runs only: a map of untraced runs alone would miss every such test.
    var traced_runs: usize = 0;
    for (runs.items) |run| traced_runs += @intFromBool(run.traced);
    if (traced_runs == 0) return error.NoTracedRun;
    // A binary is loaded before it is cached: a failed load leaves no entry behind for the cleanup to free.
    for (runs.items) |run| for (run.processes) |process| {
        const key = try binaryKey(arena, process);
        if (binaries.contains(key)) continue;
        const bytes = try readBinary(gpa, arena, io, options.repo, process);
        defer gpa.free(bytes);
        const loaded = try loadBinary(gpa, arena, io, bytes, options.repo, &sources, &functions, &stats);
        try binaries.put(arena, key, loaded);
    };
    const function_count = functions.records.items.len;

    var names: std.StringArrayHashMapUnmanaged(Test) = .empty;
    for (runs.items, 0..) |run, run_index| {
        for (run.processes) |process| {
            const binary = binaries.get(try binaryKey(arena, process)).?;
            stats.processes += 1;
            const entry = try names.getOrPut(arena, process.token);
            if (!entry.found_existing) entry.value_ptr.* = try Test.init(arena, function_count, runs.items.len);
            const seen = &entry.value_ptr.runs[run_index];
            try mark(seen, binary, process.hits, process.sampler_only, &stats);
        }
    }

    var out_bytes: std.Io.Writer.Allocating = .init(arena);
    const w = &out_bytes.writer;
    try writeDocument(w, arena, options, runs.items, &functions, &names, &stats);
    try writeFile(io, options.out, out_bytes.written());
    stats.functions = function_count;
    return stats;
}

/// A binary's counters resolved to function ids.
const Binary = struct {
    table: dwarf_functions.Table,
    /// For each key of the table, the id in the map, or `none`.
    function_of_key: []u32,
};

/// The hit sets of one test across runs, as bitsets over function ids.
const Test = struct {
    runs: []Seen,

    const Seen = struct {
        /// Whether the run held any process of this test.
        present: bool = false,
        /// Functions executed (counters ran, wrapped ones included).
        all: std.DynamicBitSetUnmanaged,
        /// Functions executed by counters nonzero at exit.
        plain: std.DynamicBitSetUnmanaged,
    };

    fn init(arena: std.mem.Allocator, function_count: usize, run_count: usize) !Test {
        const runs = try arena.alloc(Seen, run_count);
        for (runs) |*run| run.* = .{
            .present = false,
            .all = try .initEmpty(arena, function_count),
            .plain = try .initEmpty(arena, function_count),
        };
        return .{ .runs = runs };
    }
};

fn mark(seen: *Test.Seen, binary: Binary, hits: []const u32, sampler_only: []const u32, stats: *Stats) !void {
    seen.present = true;
    for (hits) |index| for (binary.table.keysOf(index)) |key| {
        const function = binary.function_of_key[key];
        if (function != none) seen.all.set(function);
    };
    var skip: usize = 0;
    for (hits) |index| {
        while (skip < sampler_only.len and sampler_only[skip] < index) skip += 1;
        if (skip < sampler_only.len and sampler_only[skip] == index) continue;
        for (binary.table.keysOf(index)) |key| {
            const function = binary.function_of_key[key];
            if (function != none) seen.plain.set(function);
        }
    }
    stats.wrapped_counters += sampler_only.len;
}

/// The directory of this checkout's instrumented binaries: a process whose recorded path is gone ran one of them.
const instrumented_dir = "zig-out/coverage/bin";

/// One process's hit set.
const Process = struct {
    token: []const u8,
    exe: []const u8,
    /// The GNU build id of the binary the process ran (empty when the binary has none).
    build_id: []const u8,
    hits: []const u32,
    sampler_only: []const u32,
};

/// One collection run: its processes, test lists and outcomes.
const Run = struct {
    directory: []const u8,
    processes: []const Process,
    /// Tokens whose test started an instrumented process that left no hit set (`unrecorded.json`, written by the collector).
    unrecorded: []const []const u8,
    /// Whether the run traced its execs: its `unrecorded.json` is a list, not `{"traced": false}`.
    traced: bool,
    /// Names of the tests of each root, in registration order.
    lists: std.StringHashMapUnmanaged([]const []const u8),
    /// Tokens of the tests that failed or timed out alone in this run.
    failed: []const []const u8,
    /// Tokens of the tests that passed alone in this run.
    passed: []const []const u8,
};

fn readRun(arena: std.mem.Allocator, io: std.Io, directory: []const u8) !Run {
    var processes: std.ArrayList(Process) = .empty;
    const cov_path = try std.fs.path.join(arena, &.{ directory, "cov" });
    var cov = try std.Io.Dir.cwd().openDir(io, cov_path, .{ .iterate = true });
    defer cov.close(io);
    var tokens = cov.iterate();
    while (try tokens.next(io)) |token| {
        if (token.kind != .directory) continue;
        var inner = try cov.openDir(io, token.name, .{ .iterate = true });
        defer inner.close(io);
        var files = inner.iterate();
        while (try files.next(io)) |file| {
            if (!std.mem.endsWith(u8, file.name, ".cov")) continue;
            const bytes = try inner.readFileAlloc(io, file.name, arena, .limited(256 << 20));
            var process = try parseCov(arena, bytes);
            process.token = try arena.dupe(u8, token.name);
            try processes.append(arena, process);
        }
    }
    // A run without the list was collected without tracing: the map cannot know which tests started a process it
    // does not record, so it refuses the run rather than map it.
    // A traced run lists its unrecorded tokens; an untraced run (`{"traced": false}`) is read for its hit sets only, and a
    // map needs at least one traced run (`build`). A run with no file was not collected by the collector: it is refused.
    const unrecorded_text = std.Io.Dir.cwd().readFileAlloc(io, try std.fmt.allocPrint(arena, "{s}/unrecorded.json", .{directory}), arena, .limited(64 << 20)) catch return error.RunWithoutTrace;
    const unrecorded_value = try std.json.parseFromSliceLeaky(std.json.Value, arena, unrecorded_text, .{});
    const traced = unrecorded_value == .array;
    var unrecorded: std.ArrayList([]const u8) = .empty;
    if (traced) for (unrecorded_value.array.items) |item| try unrecorded.append(arena, item.string);
    var run: Run = .{ .directory = directory, .processes = try processes.toOwnedSlice(arena), .unrecorded = try unrecorded.toOwnedSlice(arena), .traced = traced, .lists = .empty, .failed = &.{}, .passed = &.{} };
    var failed: std.ArrayList([]const u8) = .empty;
    var passed_list: std.ArrayList([]const u8) = .empty;
    for ([_][]const u8{ "units", "cli", "core", guest_root }) |root| {
        const list_path = try std.fmt.allocPrint(arena, "{s}/tests-{s}.json", .{ directory, root });
        const text = std.Io.Dir.cwd().readFileAlloc(io, list_path, arena, .limited(64 << 20)) catch continue;
        const parsed = try std.json.parseFromSliceLeaky([]const []const u8, arena, text, .{});
        try run.lists.put(arena, root, parsed);
        const results_path = try std.fmt.allocPrint(arena, "{s}/results-{s}.jsonl", .{ directory, root });
        const results = std.Io.Dir.cwd().readFileAlloc(io, results_path, arena, .limited(256 << 20)) catch continue;
        var lines = std.mem.splitScalar(u8, results, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const row = try std.json.parseFromSliceLeaky(std.json.Value, arena, line, .{});
            const status = row.object.get("status").?;
            const passed = status == .integer and status.integer == 0;
            const token = try arena.dupe(u8, row.object.get("token").?.string);
            if (passed) try passed_list.append(arena, token) else try failed.append(arena, token);
        }
    }
    run.failed = try failed.toOwnedSlice(arena);
    run.passed = try passed_list.toOwnedSlice(arena);
    return run;
}

fn parseCov(arena: std.mem.Allocator, bytes: []const u8) !Process {
    if (bytes.len < 36 or !std.mem.eql(u8, bytes[0..8], "MYLCOV03")) return error.BadCoverageFile;
    var pos: usize = 8;
    const counters = std.mem.readInt(u32, bytes[pos..][0..4], .little);
    const hits = std.mem.readInt(u32, bytes[pos + 4 ..][0..4], .little);
    const wrapped = std.mem.readInt(u32, bytes[pos + 8 ..][0..4], .little);
    const bias = std.mem.readInt(u64, bytes[pos + 12 ..][0..8], .little);
    if (bias != 0) return error.PositionIndependentBinary;
    pos += 4 + 4 + 4 + 8 + 8;
    const exe_len = std.mem.readInt(u16, bytes[pos..][0..2], .little);
    pos += 2;
    if (pos + exe_len + 1 > bytes.len) return error.BadCoverageFile;
    const exe = try arena.dupe(u8, bytes[pos..][0..exe_len]);
    pos += exe_len;
    const id_len = bytes[pos];
    pos += 1;
    if (pos + id_len > bytes.len) return error.BadCoverageFile;
    const id = try arena.dupe(u8, bytes[pos..][0..id_len]);
    pos += id_len;
    const first = try arena.alloc(u32, hits);
    pos = try readDeltas(bytes, pos, first, counters);
    const second = try arena.alloc(u32, wrapped);
    _ = try readDeltas(bytes, pos, second, counters);
    return .{ .token = "", .exe = exe, .build_id = id, .hits = first, .sampler_only = second };
}

fn readDeltas(bytes: []const u8, start: usize, out: []u32, limit: u32) !usize {
    var pos = start;
    var value: u64 = 0;
    for (out) |*slot| {
        var delta: u64 = 0;
        var shift: u6 = 0;
        while (true) {
            if (pos >= bytes.len) return error.BadCoverageFile;
            const byte = bytes[pos];
            pos += 1;
            delta |= @as(u64, byte & 0x7f) << shift;
            if (byte & 0x80 == 0) break;
            shift += 7;
        }
        value += delta;
        if (value >= limit) return error.BadCoverageFile;
        slot.* = @intCast(value);
    }
    return pos;
}

/// The key a process's binary is cached under: its build id when it has one (a copy of a binary shares it), else its path.
fn binaryKey(arena: std.mem.Allocator, process: Process) ![]const u8 {
    if (process.build_id.len == 0) return std.fmt.allocPrint(arena, "path:{s}", .{process.exe});
    return std.fmt.allocPrint(arena, "id:{x}", .{process.build_id});
}

/// The bytes of the binary a process ran from: the file at its recorded path or, when that is gone, the instrumented
/// binary of `repo` with the same build id (a test copies the compiler into a scratch tree and deletes the copy).
fn readBinary(gpa: std.mem.Allocator, arena: std.mem.Allocator, io: std.Io, repo: []const u8, process: Process) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, process.exe, gpa, .limited(2 << 30)) catch |err| {
        if (err != error.FileNotFound or process.build_id.len == 0) return err;
        return findInstrumented(gpa, arena, io, repo, process.build_id);
    };
}

/// The bytes of the instrumented binary of `repo` whose build id is `id`.
fn findInstrumented(gpa: std.mem.Allocator, arena: std.mem.Allocator, io: std.Io, repo: []const u8, id: []const u8) ![]u8 {
    const directory = try std.fs.path.join(arena, &.{ repo, instrumented_dir });
    var binaries = try std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true });
    defer binaries.close(io);
    var entries = binaries.iterate();
    while (try entries.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const bytes = try binaries.readFileAlloc(io, entry.name, gpa, .limited(2 << 30));
        var found: [build_id.max_length]u8 = undefined;
        const length = build_id.fileBuildId(bytes, &found);
        if (std.mem.eql(u8, found[0..length], id)) return bytes;
        gpa.free(bytes);
    }
    return error.MissingBinary;
}

fn loadBinary(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    io: std.Io,
    bytes: []const u8,
    repo: []const u8,
    sources: *std.StringHashMapUnmanaged(SourceFile),
    functions: *Functions,
    stats: *Stats,
) !Binary {
    var table = try dwarf_functions.load(gpa, bytes, repo);
    errdefer table.deinit(gpa);
    const resolved = try arena.alloc(u32, table.keys.len);
    for (table.keys, resolved) |key, *slot| {
        slot.* = try resolveKey(gpa, arena, io, repo, table.files[key.file], key.line, sources, functions, stats);
    }
    stats.keys += table.keys.len;
    return .{ .table = table, .function_of_key = resolved };
}

/// The id of the function a (file, line) key names, or `none` when the file cannot be read.
fn resolveKey(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    io: std.Io,
    repo: []const u8,
    path: []const u8,
    line: u32,
    sources: *std.StringHashMapUnmanaged(SourceFile),
    functions: *Functions,
    stats: *Stats,
) !u32 {
    const slot = try sources.getOrPut(arena, path);
    if (!slot.found_existing) {
        slot.value_ptr.* = .{ .parsed = null };
        const full = try std.fs.path.join(arena, &.{ repo, path });
        if (std.Io.Dir.cwd().readFileAlloc(io, full, gpa, .limited(64 << 20))) |source| {
            defer gpa.free(source);
            slot.value_ptr.parsed = zig_functions.parse(gpa, source) catch null;
        } else |_| {}
    }
    const parsed = slot.value_ptr.parsed orelse return none;
    var best: ?usize = null;
    for (parsed.functions, 0..) |function, index| {
        if (function.line > line or function.end_line < line) continue;
        if (best == null or function.line >= parsed.functions[best.?].line) best = index;
    }
    if (best) |index| {
        const function = parsed.functions[index];
        if (function.line == line) stats.keys_exact += 1 else stats.keys_inside += 1;
        return functions.intern(arena, path, function.name, function.ordinal, function.digest);
    }
    stats.keys_outside += 1;
    return functions.intern(arena, path, "<rest>", 0, parsed.rest);
}

fn writeDocument(
    w: *std.Io.Writer,
    arena: std.mem.Allocator,
    options: Options,
    runs: []const Run,
    functions: *const Functions,
    names: *std.StringArrayHashMapUnmanaged(Test),
    stats: *Stats,
) !void {
    try w.writeAll("{\"format\":\"edit-check-coverage-map-v2\",\"commit\":");
    try std.json.Stringify.value(options.commit, .{}, w);
    try w.writeAll(",\"roots\":{");
    var first = true;
    var root_iterator = runs[0].lists.iterator();
    while (root_iterator.next()) |entry| {
        if (!first) try w.writeAll(",");
        first = false;
        try w.print("\"{s}\":{d}", .{ entry.key_ptr.*, entry.value_ptr.len });
    }
    try w.writeAll("},\"functions\":[");
    for (functions.records.items, 0..) |record, index| {
        if (index != 0) try w.writeAll(",");
        try w.writeAll("[");
        try std.json.Stringify.value(record.file, .{}, w);
        try w.writeAll(",");
        try std.json.Stringify.value(record.name, .{}, w);
        try w.print(",{d},\"{s}\"]", .{ record.ordinal, &zig_functions.hex(record.digest) });
    }
    try w.writeAll("],\"tests\":[");
    var unnamed: std.StringHashMapUnmanaged([]const u32) = .empty;
    var unstable: std.ArrayList([]const u8) = .empty;
    var emitted = false;
    var pair_buffer: std.ArrayList(u32) = .empty;
    for (names.keys(), names.values()) |token, test_record| {
        // The union over runs; a test that differs between runs is unstable.
        var union_set = try std.DynamicBitSetUnmanaged.initEmpty(arena, functions.records.items.len);
        var plain_set = try std.DynamicBitSetUnmanaged.initEmpty(arena, functions.records.items.len);
        var differs = false;
        var first_present: ?Test.Seen = null;
        for (test_record.runs) |other| {
            if (!other.present) continue;
            if (first_present) |reference| {
                if (!std.DynamicBitSetUnmanaged.eql(other.all, reference.all)) differs = true;
            } else first_present = other;
            union_set.setUnion(other.all);
            plain_set.setUnion(other.plain);
        }
        pair_buffer.clearRetainingCapacity();
        var it = union_set.iterator(.{});
        while (it.next()) |index| {
            try pair_buffer.append(arena, @intCast(index));
            if (!plain_set.isSet(index)) stats.sampler_only_pairs += 1;
        }
        const dash = std.mem.findScalar(u8, token, '-') orelse continue;
        const root = token[0..dash];
        const suffix = token[dash + 1 ..];
        if (std.mem.eql(u8, suffix, "unnamed")) {
            try unnamed.put(arena, root, try arena.dupe(u32, pair_buffer.items));
            continue;
        }
        const list = runs[0].lists.get(root) orelse continue;
        const index = std.fmt.parseInt(usize, suffix, 10) catch continue;
        // A Zig test's name has a `.test.` part; a guest's name is the path of its file.
        if (index >= list.len or (!std.mem.eql(u8, root, guest_root) and std.mem.find(u8, list[index], ".test.") == null)) continue;
        if (differs) {
            try unstable.append(arena, list[index]);
            stats.unstable += 1;
        }
        if (emitted) try w.writeAll(",");
        emitted = true;
        stats.tests += 1;
        try w.print("[\"{s}\",", .{root});
        try std.json.Stringify.value(list[index], .{}, w);
        try w.writeAll(",[");
        for (pair_buffer.items, 0..) |id, position| {
            if (position != 0) try w.writeAll(",");
            try w.print("{d}", .{id});
        }
        try w.writeAll("]]");
    }
    try w.writeAll("],\"unnamed\":{");
    var unnamed_first = true;
    var unnamed_iterator = unnamed.iterator();
    while (unnamed_iterator.next()) |entry| {
        if (!unnamed_first) try w.writeAll(",");
        unnamed_first = false;
        try w.print("\"{s}\":[", .{entry.key_ptr.*});
        for (entry.value_ptr.*, 0..) |id, position| {
            if (position != 0) try w.writeAll(",");
            try w.print("{d}", .{id});
        }
        try w.writeAll("]");
    }
    try w.writeAll("},\"unstable\":");
    try std.json.Stringify.value(unstable.items, .{}, w);
    try w.writeAll(",\"failed\":");
    var failed_names: std.ArrayList([]const u8) = .empty;
    var latest: std.StringHashMapUnmanaged(bool) = .empty;
    for (runs) |run| {
        for (run.passed) |token| try latest.put(arena, token, true);
        for (run.failed) |token| try latest.put(arena, token, false);
    }
    var latest_iterator = latest.iterator();
    while (latest_iterator.next()) |entry| {
        if (entry.value_ptr.*) continue;
        const token = entry.key_ptr.*;
        const dash = std.mem.findScalar(u8, token, '-') orelse continue;
        const list = runs[0].lists.get(token[0..dash]) orelse continue;
        const index = std.fmt.parseInt(usize, token[dash + 1 ..], 10) catch continue;
        if (index < list.len) try failed_names.append(arena, list[index]);
    }
    try std.json.Stringify.value(failed_names.items, .{}, w);
    // The tests the edit check selects whatever the edit: a token of a run with an unrecorded process is named by its
    // root and test name (an unnamed block, or a token it cannot name, selects the whole root).
    try w.writeAll(",\"unrecorded\":[");
    var unrecorded_emitted = false;
    for (runs) |run| {
    for (run.unrecorded) |token| {
        const dash = std.mem.findScalar(u8, token, '-') orelse continue;
        const root = token[0..dash];
        const name: []const u8 = blk: {
            const list = runs[0].lists.get(root) orelse break :blk "";
            const index = std.fmt.parseInt(usize, token[dash + 1 ..], 10) catch break :blk "";
            if (index >= list.len) break :blk "";
            break :blk list[index];
        };
        if (unrecorded_emitted) try w.writeAll(",");
        unrecorded_emitted = true;
        try w.print("[\"{s}\",", .{root});
        try std.json.Stringify.value(name, .{}, w);
        try w.writeAll("]");
        stats.unrecorded += 1;
    }
    }
    try w.writeAll("]");
    try w.print(",\"stats\":{{\"processes\":{d},\"keys\":{d},\"keys_exact\":{d},\"keys_inside\":{d},\"keys_outside\":{d},\"wrapped_counters\":{d},\"sampler_only_pairs\":{d}}}}}\n", .{
        stats.processes, stats.keys, stats.keys_exact, stats.keys_inside, stats.keys_outside, stats.wrapped_counters, stats.sampler_only_pairs,
    });
}

fn writeFile(io: std.Io, path: []const u8, bytes: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var file_buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &file_buffer);
    if (std.mem.endsWith(u8, path, ".gz")) {
        var window: [std.compress.flate.max_window_len]u8 = undefined;
        var compressor = try std.compress.flate.Compress.init(&file_writer.interface, &window, .gzip, .default);
        try compressor.writer.writeAll(bytes);
        try compressor.finish();
    } else {
        try file_writer.interface.writeAll(bytes);
    }
    try file_writer.interface.flush();
}
