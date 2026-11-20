//! Persistent developer-loop history. Records are advisory measurements, never
//! cache receipts. Each completed invocation owns one atomic JSON file outside
//! cache directories; concurrent invocations never rewrite one another's records.
const std = @import("std");
const product = @import("product.zig");
const V = std.json.Value;
pub const variable = "SELKA_PROFILE_DIR";
pub const version = "compiler-profile-v1";
pub const record_limit = 32 << 20;
const cache_report_version = "cache-report-v1";
const nanoseconds_key = "nanoseconds";
/// Allocation or missing absolute home directory for local state.
pub const StateError = std.mem.Allocator.Error || error{NoStateDirectory};
/// Filesystem failures while publishing a complete archive record.
pub const WriteError = std.mem.Allocator.Error || std.Io.Dir.CreateDirPathError ||
    std.Io.File.OpenError || std.Io.File.Writer.Error || std.Io.File.SyncError || std.Io.Dir.RenameError;
/// Invalid configuration or failures reading and resolving its destination.
pub const ConfigurationError = StateError || std.Io.Dir.RealPathFileAllocError ||
    std.Io.Dir.ReadFileAllocError || std.json.ParseError(std.json.Scanner) || error{InvalidProfileConfiguration};
/// Failures identifying a stable executable and persisting its digest.
pub const HashError = WriteError || std.Io.Dir.RealPathFileAllocError ||
    std.Io.File.StatError || std.Io.File.ReadPositionalError || error{CompilerChanged};

/// The default archive and configuration location, independent of cache pruning.
pub fn stateDirectory(a: std.mem.Allocator, env: *const std.process.Environ.Map) StateError![]const u8 {
    if (env.get("XDG_STATE_HOME")) |base| if (std.fs.path.isAbsolute(base))
        return std.fs.path.join(a, &.{ base, product.user_dir, "profile" });
    const base = env.get("HOME") orelse return error.NoStateDirectory;
    if (!std.fs.path.isAbsolute(base)) return error.NoStateDirectory;
    return std.fs.path.join(a, &.{ base, ".local", "state", product.user_dir, "profile" });
}

/// Explicit empty environment selection disables even a saved configuration.
pub fn destination(a: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map) ConfigurationError!?[]const u8 {
    if (env.get(variable)) |path| return if (path.len == 0) null else try absolute(a, io, path);
    const base = stateDirectory(a, env) catch |err| switch (err) {
        error.NoStateDirectory => return null,
        else => return err,
    };
    const path = try std.fs.path.join(a, &.{ base, "config.json" });
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(8192)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    const config = try std.json.parseFromSliceLeaky(struct { version: u8, enabled: bool, directory: []const u8 }, a, bytes, .{});
    if (config.version != 1 or !std.fs.path.isAbsolute(config.directory)) return error.InvalidProfileConfiguration;
    return if (config.enabled) config.directory else null;
}

/// Save recording preferences without deleting existing records.
pub fn configure(a: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, enabled: bool, directory: []const u8) (StateError || WriteError)!void {
    const base = try stateDirectory(a, env);
    try std.Io.Dir.cwd().createDirPath(io, base);
    const path = try std.fs.path.join(a, &.{ base, "config.json" });
    const bytes = try std.json.Stringify.valueAlloc(a, .{ .version = 1, .enabled = enabled, .directory = directory }, .{});
    try atomicWrite(a, io, path, bytes);
}

/// Resolve a path against the current process directory.
pub fn absolute(a: std.mem.Allocator, io: std.Io, path: []const u8) std.Io.Dir.RealPathFileAllocError![]const u8 {
    return std.fs.path.resolve(a, &.{ try std.Io.Dir.cwd().realPathFileAlloc(io, ".", a), path });
}

/// Publish a flushed complete file. Readers ignore temporary files.
pub fn atomicWrite(a: std.mem.Allocator, io: std.Io, path: []const u8, bytes: []const u8) WriteError!void {
    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.dirname(path)) |parent| try cwd.createDirPath(io, parent);
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    const temporary = try std.fmt.allocPrint(a, "{s}.{s}.tmp", .{ path, std.fmt.bytesToHex(nonce, .lower) });
    defer removeTemporary(io, temporary);
    const file = try cwd.createFile(io, temporary, .{ .exclusive = true });
    {
        defer file.close(io);
        try file.writeStreamingAll(io, bytes);
        try file.sync(io);
    }
    try cwd.rename(temporary, cwd, path, io);
}

/// Return a lowercase SHA-256 digest of the supplied bytes.
pub fn hash(a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}

/// Hash the exact running executable once per filesystem generation. This keeps
/// hashing a large compiler binary out of every warm command's startup cost.
pub fn binaryHash(a: std.mem.Allocator, io: std.Io, directory: []const u8) HashError![]const u8 {
    const cwd = std.Io.Dir.cwd();
    const path = try cwd.realPathFileAlloc(io, "/proc/self/exe", a);
    const file = try cwd.openFile(io, "/proc/self/exe", .{});
    defer file.close(io);
    const before = try file.stat(io);
    const stamp = try std.json.Stringify.valueAlloc(a, .{ .path = path, .inode = before.inode, .size = before.size, .mtime = before.mtime.nanoseconds, .ctime = before.ctime.nanoseconds }, .{});
    const memo = try std.fs.path.join(a, &.{ directory, "compilers", try hash(a, stamp) });
    if (cwd.readFileAlloc(io, memo, a, .limited(65))) |cached| {
        if (cached.len == 64 and std.mem.indexOfNone(u8, cached, "0123456789abcdef") == null) return cached;
    } else |_| {}
    const hex = fastBinaryHash(a, io) orelse try streamBinaryHash(a, io, file);
    const after = try file.stat(io);
    try unchangedCompiler(before, after);
    try atomicWrite(a, io, memo, hex);
    return hex;
}

fn unchangedCompiler(before: std.Io.File.Stat, after: std.Io.File.Stat) error{CompilerChanged}!void {
    if (before.size != after.size or before.mtime.nanoseconds != after.mtime.nanoseconds or before.ctime.nanoseconds != after.ctime.nanoseconds)
        return error.CompilerChanged;
}

fn removeTemporary(io: std.Io, path: []const u8) void {
    // Successful publication already renamed the file. Failed cleanup leaves an
    // ignored temporary file and must not hide the original publication error.
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}

fn placementArgument(arg: []const u8) bool {
    for ([_][]const u8{ "--cache-dir=", "--output=", "-o=" }) |prefix|
        if (std.mem.startsWith(u8, arg, prefix)) return true;
    for ([_][]const u8{ "--report", "--cache-report", "--timings", "--timings=json" }) |flag|
        if (std.mem.eql(u8, arg, flag)) return true;
    return false;
}

/// Linux's optimized system hasher avoids tens of seconds of software SHA in a
/// Debug compiler on first use. It hashes this process's loaded image, not argv0
/// or a potentially replaced install path. The stdlib fallback needs no helper.
fn fastBinaryHash(a: std.mem.Allocator, io: std.Io) ?[]const u8 {
    const path = std.fmt.allocPrint(a, "/proc/{d}/exe", .{std.os.linux.getpid()}) catch return null;
    const result = std.process.run(a, io, .{
        .argv = &.{ "sha256sum", path },
        .timeout = .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    }) catch return null;
    if (result.term != .exited or result.term.exited != 0 or result.stdout.len < 65 or result.stdout[64] != ' ') return null;
    const hex = result.stdout[0..64];
    return if (std.mem.indexOfNone(u8, hex, "0123456789abcdef") == null) hex else null;
}

fn streamBinaryHash(a: std.mem.Allocator, io: std.Io, file: std.Io.File) ![]const u8 {
    var digest = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [64 << 10]u8 = undefined;
    var offset: u64 = 0;
    while (true) {
        const count = try file.readPositionalAll(io, &buffer, offset);
        digest.update(buffer[0..count]);
        offset += count;
        if (count < buffer.len) break;
    }
    return a.dupe(u8, &std.fmt.bytesToHex(digest.finalResult(), .lower));
}

/// Clock formatting shared by saved records and the history table.
pub fn utc(a: std.mem.Allocator, nanoseconds: i96) std.mem.Allocator.Error![]const u8 {
    const seconds: std.time.epoch.EpochSeconds = .{ .secs = @intCast(@max(0, @divFloor(nanoseconds, std.time.ns_per_s))) };
    const year = seconds.getEpochDay().calculateYearDay();
    const month = year.calculateMonthDay();
    const day = seconds.getDaySeconds();
    return std.fmt.allocPrint(a, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year.year, @backingInt(month.month), month.day_index + 1, day.getHoursIntoDay(), day.getMinutesIntoHour(), day.getSecondsIntoMinute(),
    });
}

/// Drop output/cache/report placement arguments from the comparison identity;
/// retain modes, filters, budgets and all other compilation settings. Guest argv
/// is omitted from logs but its digest still separates different workloads.
pub fn workloadArguments(a: std.mem.Allocator, args: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var skip = false;
    for (args) |arg| {
        if (skip) {
            skip = false;
            continue;
        }
        if (std.mem.eql(u8, arg, "--")) break;
        if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "--cache-dir")) {
            skip = true;
            continue;
        }
        if (placementArgument(arg)) continue;
        try result.append(a, arg);
    }
    return result.toOwnedSlice(a);
}

/// Read an optional object field; absent or non-object inputs yield null.
pub fn field(value: V, key: []const u8) V {
    return if (value == .object) value.object.get(key) orelse .null else .null;
}
/// Read a string field, using an empty string for missing or invalid fields.
pub fn string(value: V, key: []const u8) []const u8 {
    const found = field(value, key);
    return if (found == .string) found.string else "";
}
/// Read a nonnegative integer field without treating missing values as zero.
pub fn number(value: V, key: []const u8) ?u64 {
    const found = field(value, key);
    return if (found == .integer and found.integer >= 0) @intCast(found.integer) else null;
}

/// History filters applied before the result limit.
pub const Selection = struct { limit: usize = 20, command: ?[]const u8 = null, entry: ?[]const u8 = null };
/// Parsed history and the number of invalid records encountered.
pub const History = struct { records: []V, invalid_records: usize = 0 };

/// Newest matching complete records first. Corrupt/foreign files are counted,
/// not treated as zero-duration runs. All owned history stays on disk.
pub fn read(a: std.mem.Allocator, io: std.Io, directory: []const u8, selection: Selection) (std.mem.Allocator.Error || std.Io.Dir.OpenError || std.Io.Dir.Iterator.Error)!History {
    const root = try std.fs.path.join(a, &.{ directory, "runs" });
    var dir = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return .{ .records = &.{} },
        else => return err,
    };
    defer dir.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) try names.append(a, try a.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.order(u8, left, right) == .gt;
        }
    }.less);
    var result: std.ArrayList(V) = .empty;
    var invalid: usize = 0;
    for (names.items) |name| {
        if (result.items.len == selection.limit) break;
        const bytes = dir.readFileAlloc(io, name, a, .limited(record_limit)) catch {
            invalid += 1;
            continue;
        };
        const row = std.json.parseFromSliceLeaky(V, a, bytes, .{}) catch {
            invalid += 1;
            continue;
        };
        if (!std.mem.eql(u8, string(row, "version"), version) or number(row, "elapsed_ns") == null or number(row, "exit_code") == null) {
            invalid += 1;
            continue;
        }
        if (selection.command) |command| if (!std.mem.eql(u8, command, string(row, "command"))) continue;
        if (selection.entry) |entry| if (!std.mem.eql(u8, entry, string(row, "entry"))) continue;
        try result.append(a, row);
    }
    return .{ .records = try result.toOwnedSlice(a), .invalid_records = invalid };
}

/// Descriptive statistics for a nonempty sample collection.
pub const Distribution = struct { count: usize, median: f64, p95: u64, min: u64, max: u64 };
/// Sort samples in place and compute the median and nearest-rank p95.
pub fn distribution(values: []u64) ?Distribution {
    if (values.len == 0) return null;
    std.mem.sort(u64, values, {}, std.sort.asc(u64));
    const middle = values.len / 2;
    const median = if (values.len % 2 == 0)
        @as(f64, @floatFromInt(values[middle - 1])) / 2 + @as(f64, @floatFromInt(values[middle])) / 2
    else
        @as(f64, @floatFromInt(values[middle]));
    return .{ .count = values.len, .median = median, .p95 = values[(values.len * 95 + 99) / 100 - 1], .min = values[0], .max = values[values.len - 1] };
}

/// Cache observations distinguish ordinary warm replays from builds and forced
/// executions. Missing observations remain unknown, never assumed cold.
pub fn cacheState(row: V) []const u8 {
    const reports = field(row, "reports");
    if (reports != .array) return "unknown";
    var index = reports.array.items.len;
    while (index != 0) {
        index -= 1;
        const report = reports.array.items[index];
        const kind = string(report, "version");
        if (std.mem.eql(u8, kind, cache_report_version)) return string(report, "program");
        if (std.mem.eql(u8, kind, "work-report-v1")) {
            if ((number(report, "reused_results") orelse 0) != 0) return "replayed";
            const request = field(report, "request");
            const bodies = field(if (request == .object) request else report, "checked_bodies");
            return if ((number(bodies, "reused") orelse 0) != 0) "partial-reuse" else "checked";
        }
        if (std.mem.eql(u8, kind, "native-tests-v1")) {
            const passed = number(report, "passed") orelse 0;
            const cached = number(report, "cached") orelse 0;
            return if (cached != 0 and passed == 0) "tests-replayed" else if (cached != 0) "partial-reuse" else "tests-executed";
        }
    }
    return "unknown";
}

/// Cache counts separate a partial rebuild from a cold link with the same mode.
fn cacheSignature(a: std.mem.Allocator, row: V) ![]const u8 {
    var counters: std.ArrayList(V) = .empty;
    const reports = field(row, "reports");
    if (reports == .array) for (reports.array.items) |report| {
        const kind = string(report, "version");
        const encoded = if (std.mem.eql(u8, kind, cache_report_version))
            try std.json.Stringify.valueAlloc(a, .{ kind, field(report, "units"), field(report, "reused"), field(report, "compiled"), field(report, "verified") }, .{})
        else if (std.mem.eql(u8, kind, "native-tests-v1"))
            try std.json.Stringify.valueAlloc(a, .{ kind, field(report, "passed"), field(report, "cached"), field(report, "skipped") }, .{})
        else if (std.mem.eql(u8, kind, "work-report-v1"))
            try std.json.Stringify.valueAlloc(a, .{ kind, field(report, "parsed_modules"), field(report, "checked_bodies"), field(report, "instantiated_specializations"), field(report, "reused_results") }, .{})
        else
            continue;
        try counters.append(a, try std.json.parseFromSliceLeaky(V, a, encoded, .{}));
    };
    return std.json.Stringify.valueAlloc(a, counters.items, .{});
}

const Interval = struct { description: V, samples: std.ArrayList(u64) = .empty };
const Intervals = std.array_hash_map.String(Interval);
const count_names = [_][]const u8{ "units", "reused", "compiled", "verified", "processes" };
const Group = struct {
    row: V,
    cache: []const u8,
    samples: std.ArrayList(u64) = .empty,
    intervals: Intervals = .empty,
    counts: [count_names.len]std.ArrayList(u64) = @splat(.empty),
};

fn intervalInto(a: std.mem.Allocator, intervals: *Intervals, description: anytype, duration: u64) !void {
    const key = try std.json.Stringify.valueAlloc(a, description, .{});
    const slot = try intervals.getOrPut(a, key);
    if (!slot.found_existing) slot.value_ptr.* = .{ .description = try std.json.parseFromSliceLeaky(V, a, key, .{}) };
    try slot.value_ptr.samples.append(a, duration);
}

/// Keep each measured interval as an observation. In particular, never sum
/// parallel per-unit durations or repeated phases from concurrent test roots.
fn observe(a: std.mem.Allocator, group: *Group, row: V) !void {
    const reports = field(row, "reports");
    if (reports != .array) return;
    var counts: [count_names.len]?u64 = @splat(null);
    for (reports.array.items) |report| {
        const kind = string(report, "version");
        if (std.mem.eql(u8, kind, "phase-timings-v1")) {
            if (number(report, "duration_ns")) |duration| try intervalInto(a, &group.intervals, .{
                .kind = "phase",
                .tool = string(report, "tool"),
                .name = string(report, "name"),
                .inclusive = field(report, "inclusive"),
            }, duration);
        }
        if (!std.mem.eql(u8, kind, cache_report_version)) continue;
        for (count_names, &counts) |name, *total| if (number(report, name)) |value| {
            total.* = (total.* orelse 0) +| value;
        };
        const stages = field(field(report, "stages"), nanoseconds_key);
        if (stages == .object) for (stages.object.keys(), stages.object.values()) |name, value| {
            if (value != .integer or value.integer < 0) continue;
            try intervalInto(a, &group.intervals, .{
                .kind = "phase",
                .tool = "compiler",
                .name = try std.fmt.allocPrint(a, "core.{s}", .{name}),
                .inclusive = std.mem.eql(u8, name, "frontend") or std.mem.eql(u8, name, "native"),
            }, @intCast(value.integer));
        };
        const frontend = field(stages, "frontend_phases");
        if (frontend == .array) for (frontend.array.items) |phase| {
            if (number(phase, nanoseconds_key)) |duration| try intervalInto(a, &group.intervals, .{
                .kind = "phase",
                .tool = "compiler",
                .name = try std.fmt.allocPrint(a, "core.frontend.{s}", .{string(phase, "name")}),
                .inclusive = field(phase, "inclusive"),
            }, duration);
        };
        const units = field(report, "unit_timings");
        if (units == .array) for (units.array.items) |unit| {
            if (number(unit, "compile_ns")) |duration| try intervalInto(a, &group.intervals, .{
                .kind = "native_unit_compile",
                .name = string(unit, "name"),
                .source_path = string(unit, "source_path"),
                .unit_kind = string(unit, "kind"),
                .key = string(unit, "key"),
                .action = string(unit, "action"),
                .scope = string(unit, "scope"),
            }, duration);
        };
    }
    for (&group.counts, counts) |*samples, value| if (value) |count| try samples.append(a, count);
}

/// Group only matching workload/CPU/cache-state/day/revision observations. Failed
/// and incomplete invocations remain in history but cannot lower latency stats.
pub fn trends(a: std.mem.Allocator, records: []const V) std.json.ParseError(std.json.Scanner)![]V {
    var groups: std.array_hash_map.String(Group) = .empty;
    for (records) |row| {
        if (number(row, "exit_code") != 0 or field(row, "incomplete") != .bool or field(row, "incomplete").bool) continue;
        const date = string(row, "captured_utc");
        const state = cacheState(row);
        const key = try std.json.Stringify.valueAlloc(a, .{ string(row, "workload_key"), string(row, "compiler_sha256"), field(row, "git"), field(row, "entry_sha256"), date[0..@min(10, date.len)], state, try cacheSignature(a, row) }, .{});
        const slot = try groups.getOrPut(a, key);
        if (!slot.found_existing) slot.value_ptr.* = .{ .row = row, .cache = state };
        try slot.value_ptr.samples.append(a, number(row, "elapsed_ns").?);
        try observe(a, slot.value_ptr, row);
    }
    var result: std.ArrayList(V) = .empty;
    for (groups.values()) |*group| {
        const row = group.row;
        const date = string(row, "captured_utc");
        var intervals: std.ArrayList(V) = .empty;
        for (group.intervals.values()) |*interval| {
            const bytes = try std.json.Stringify.valueAlloc(a, distribution(interval.samples.items), .{});
            try interval.description.object.put(a, nanoseconds_key, try std.json.parseFromSliceLeaky(V, a, bytes, .{}));
            try intervals.append(a, interval.description);
        }
        var counts: std.json.ObjectMap = .empty;
        for (count_names, &group.counts) |name, *samples| {
            const bytes = try std.json.Stringify.valueAlloc(a, distribution(samples.items), .{});
            try counts.put(a, name, try std.json.parseFromSliceLeaky(V, a, bytes, .{}));
        }
        const encoded = try std.json.Stringify.valueAlloc(a, .{
            .intervals = intervals.items,
            .unit_counts = V{ .object = counts },
            .day = date[0..@min(10, date.len)],
            .command = string(row, "command"),
            .entry = string(row, "entry"),
            .workload_key = string(row, "workload_key"),
            .compiler_sha256 = string(row, "compiler_sha256"),
            .git = field(row, "git"),
            .entry_sha256 = field(row, "entry_sha256"),
            .cache_state = group.cache,
            .elapsed_ns = distribution(group.samples.items),
        }, .{});
        try result.append(a, try std.json.parseFromSliceLeaky(V, a, encoded, .{}));
    }
    return result.toOwnedSlice(a);
}

test "profile percentiles use nearest rank and retain even medians" {
    var one = [_]u64{9};
    try std.testing.expectEqual(@as(u64, 9), distribution(&one).?.p95);
    var even = [_]u64{ 4, 1, 3, 2 };
    try std.testing.expectEqual(@as(f64, 2.5), distribution(&even).?.median);
    var twenty: [20]u64 = undefined;
    for (&twenty, 1..) |*value, i| value.* = i;
    try std.testing.expectEqual(@as(u64, 19), distribution(&twenty).?.p95);
}

test "profile workload keys omit placement and retain semantic switches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try workloadArguments(arena.allocator(), &.{ "run", "a.selka", "--cache-dir", "private", "--report", "--no-cache", "--", "secret" });
    try std.testing.expectEqualSlices([]const u8, &.{ "run", "a.selka", "--no-cache" }, result);
}

test "profile configuration can be disabled without deleting history" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const path = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var env: std.process.Environ.Map = .init(a);
    try env.put("XDG_STATE_HOME", path);
    try std.testing.expect(try destination(a, std.testing.io, &env) == null);
    try configure(a, std.testing.io, &env, true, path);
    try std.testing.expectEqualStrings(path, (try destination(a, std.testing.io, &env)).?);
    try env.put(variable, "");
    try std.testing.expect(try destination(a, std.testing.io, &env) == null);
    _ = env.swapRemove(variable);
    try configure(a, std.testing.io, &env, false, path);
    try std.testing.expect(try destination(a, std.testing.io, &env) == null);
}

test "profile history skips damaged records and filters before limiting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const samples = [_][]const u8{
        "{\"version\":\"compiler-profile-v1\",\"elapsed_ns\":12,\"exit_code\":0,\"command\":\"check\",\"entry\":\"a.selka\"}",
        "{\"version\":\"compiler-profile-v1\",\"elapsed_ns\":34,\"exit_code\":0,\"command\":\"build\",\"entry\":\"a.selka\"}",
        "{truncated",
        "{\"version\":\"compiler-profile-v1\",\"elapsed_ns\":-1,\"exit_code\":0}",
    };
    for (samples, 0..) |bytes, i| try atomicWrite(a, std.testing.io, try std.fmt.allocPrint(a, "{s}/runs/{d}.json", .{ root, i }), bytes);
    try atomicWrite(a, std.testing.io, try std.fmt.allocPrint(a, "{s}/runs/99.tmp", .{root}), "partial");
    const selected = try read(a, std.testing.io, root, .{ .limit = 1, .command = "check", .entry = "a.selka" });
    try std.testing.expectEqual(@as(usize, 1), selected.records.len);
    try std.testing.expectEqual(@as(usize, 2), selected.invalid_records);
    try std.testing.expectEqual(@as(?u64, 12), number(selected.records[0], "elapsed_ns"));
}

test "profile trends separate cache counts revisions days failures and final guest result" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var records: std.ArrayList(V) = .empty;
    for (0..8) |i| {
        const encoded = try std.json.Stringify.valueAlloc(a, .{
            .exit_code = if (i == 6) @as(u8, 2) else 0,
            .incomplete = i == 7,
            .elapsed_ns = @as(u64, if (i == 1) 20 else 10),
            .workload_key = "same",
            .compiler_sha256 = "same",
            .git = .{ .commit = if (i == 3) "different" else "original" },
            .captured_utc = if (i == 4) "2026-10-18T00:00:00Z" else "2026-10-17T00:00:00Z",
            .reports = .{.{ .version = "cache-report-v1", .program = if (i == 5) "replayed" else "linked", .compiled = if (i == 2) @as(usize, 2) else 1 }},
        }, .{});
        try records.append(a, try std.json.parseFromSliceLeaky(V, a, encoded, .{}));
    }
    const rows = try trends(a, records.items);
    try std.testing.expectEqual(@as(usize, 5), rows.len);
    try std.testing.expectEqual(@as(?u64, 2), number(field(rows[0], "elapsed_ns"), "count"));
    try std.testing.expectEqual(@as(?u64, 15), number(field(rows[0], "elapsed_ns"), "median"));
    const guest = try std.json.parseFromSliceLeaky(V, a, "{\"reports\":[{\"version\":\"cache-report-v1\",\"program\":\"linked\"},{\"version\":\"native-tests-v1\",\"passed\":0,\"cached\":2}]}", .{});
    try std.testing.expectEqualStrings("tests-replayed", cacheState(guest));
}

test "profile trend intervals keep parallel native costs separate and omit reused durations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.json.Stringify.valueAlloc(a, .{
        .exit_code = 0,
        .incomplete = false,
        .elapsed_ns = 100,
        .workload_key = "same",
        .compiler_sha256 = "same",
        .git = .{},
        .captured_utc = "2026-10-17T00:00:00Z",
        .reports = .{.{
            .version = "cache-report-v1",
            .program = "linked",
            .units = 3,
            .compiled = 2,
            .reused = 1,
            .stages = .{ .nanoseconds = .{ .native = 70, .linker = 10 } },
            .unit_timings = .{
                .{ .name = "a", .action = "compiled", .compile_ns = 40 },
                .{ .name = "b", .action = "compiled", .compile_ns = 45 },
                .{ .name = "c", .action = "reused", .compile_ns = @as(?u64, null) },
            },
        }},
    }, .{});
    const record = try std.json.parseFromSliceLeaky(V, a, bytes, .{});
    const rows = try trends(a, &.{ record, record });
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqual(@as(?u64, 2), number(field(field(rows[0], "unit_counts"), "compiled"), "median"));
    const intervals = field(rows[0], "intervals").array.items;
    try std.testing.expectEqual(@as(usize, 4), intervals.len);
    for (intervals) |interval| {
        try std.testing.expectEqual(@as(?u64, 2), number(field(interval, nanoseconds_key), "count"));
        try std.testing.expect(!std.mem.eql(u8, string(interval, "name"), "c"));
    }
}

test "profile configuration rejects NoStateDirectory and InvalidProfileConfiguration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var env: std.process.Environ.Map = .init(a);
    try std.testing.expectError(error.NoStateDirectory, stateDirectory(a, &env));
    try env.put("HOME", "relative-home");
    try std.testing.expectError(error.NoStateDirectory, stateDirectory(a, &env));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    try env.put("XDG_STATE_HOME", root);
    const path = try std.fs.path.join(a, &.{ try stateDirectory(a, &env), "config.json" });
    try atomicWrite(a, std.testing.io, path, "{\"version\":2,\"enabled\":true,\"directory\":\"/archive\"}");
    try std.testing.expectError(error.InvalidProfileConfiguration, destination(a, std.testing.io, &env));
    try configure(a, std.testing.io, &env, true, "relative-archive");
    try std.testing.expectError(error.InvalidProfileConfiguration, destination(a, std.testing.io, &env));
}

test "profile executable digest rejects CompilerChanged generations" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const file = try dir.dir.createFile(std.testing.io, "compiler", .{ .read = true });
    defer file.close(std.testing.io);
    const before = try file.stat(std.testing.io);
    try file.writeStreamingAll(std.testing.io, "replacement executable");
    const after = try file.stat(std.testing.io);
    try std.testing.expectError(error.CompilerChanged, unchangedCompiler(before, after));
    try std.testing.expectEqual({}, try unchangedCompiler(after, after));
}
