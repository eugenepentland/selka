//! Native profile enablement, history and compatible trend summaries.
const std = @import("std");
const h = @import("profile_history.zig");
const V = std.json.Value;
const usage =
    \\usage: selka profile on [--dir DIRECTORY]
    \\       selka profile off | status
    \\       selka profile history|trends [--dir DIRECTORY] [--limit N] [--command NAME] [--entry PATH] [--json]
    \\Once enabled, check/run/build/test invocations save local history automatically.
    \\History lives under XDG_STATE_HOME/selka/profile (or ~/.local/state/selka/profile).
    \\SELKA_PROFILE_DIR overrides the destination; an empty value disables recording.
    \\Disabling recording retains every saved record. No automatic pruning is performed.
    \\History defaults to the newest 20 matches; trends to the newest 1000 matches.
    \\Trends separate CPU/workload/cache state/day/compiler/revision; failures remain in history.
    \\Ordinary-command timings include instrumentation and are not isolated benchmarks.
    \\
;

/// Execute profile configuration and history commands, reporting usage failures.
pub fn run(init: std.process.Init, args: []const []const u8) (std.mem.Allocator.Error || std.Io.File.Writer.Error)!u8 {
    if (args.len == 0 or (args.len == 1 and std.mem.eql(u8, args[0], "--help"))) {
        try std.Io.File.stdout().writeStreamingAll(init.io, usage);
        return 0;
    }
    return runImpl(init, args) catch |err| {
        const message = try std.fmt.allocPrint(init.arena.allocator(), "selka profile: {s}\n", .{@errorName(err)});
        try std.Io.File.stderr().writeStreamingAll(init.io, message);
        return 2;
    };
}

fn runImpl(init: std.process.Init, args: []const []const u8) !u8 {
    const a = init.arena.allocator();
    const options = try parseOptions(a, args);
    const mode = @tagName(options.mode);
    const trending = options.mode == .trends;
    const on = options.mode == .on;
    const off = options.mode == .off;
    const status = options.mode == .status;
    const json = options.json;
    const directory = if (options.directory) |path| try h.absolute(a, init.io, path) else null;
    const selection = options.selection;
    const configured = h.destination(a, init.io, init.environ_map) catch |err| if (on or off) null else return err;
    // An off configuration still remembers the prior archive for history reads.
    const archive = directory orelse configured orelse try savedArchive(a, init.io, init.environ_map);
    if (on or off) {
        try h.configure(a, init.io, init.environ_map, on, archive);
        try std.Io.File.stdout().writeStreamingAll(init.io, try std.fmt.allocPrint(a, "Developer profile recording {s}. History: {s}\n", .{ if (on) "enabled" else "disabled", archive }));
        if (init.environ_map.get(h.variable) != null) try std.Io.File.stdout().writeStreamingAll(init.io, "SELKA_PROFILE_DIR is set and takes precedence over this saved setting.\n");
        return 0;
    }
    if (status) {
        const value = .{ .enabled = configured != null, .directory = archive, .environment_override = init.environ_map.get(h.variable) != null };
        if (json) return printJson(init, value);
        try std.Io.File.stdout().writeStreamingAll(init.io, try std.fmt.allocPrint(a, "Developer profile recording: {s}\nHistory: {s}\n", .{ if (configured != null) "enabled" else "disabled", archive }));
        return 0;
    }
    const found = try h.read(a, init.io, archive, selection);
    const rows = if (trending) try h.trends(a, found.records) else found.records;
    if (json) return printJson(init, .{ .version = "profile-history-v1", .view = mode, .directory = archive, .selected_records = found.records.len, .invalid_records = found.invalid_records, .rows = rows });
    var text: std.ArrayList(u8) = .empty;
    try text.print(a, "{s}: {s} ({d} selected records; {d} unreadable/invalid)\n", .{ mode, archive, found.records.len, found.invalid_records });
    if (trending) {
        try text.appendSlice(a, "UTC day     n    median ms      p95 ms      min ms      max ms  command / cache / commit / entry\n");
        for (rows) |row| {
            const metric = h.field(row, "elapsed_ns");
            const median = h.field(metric, "median");
            const median_ns: f64 = if (median == .float) median.float else @floatFromInt(median.integer);
            const commit = h.string(h.field(row, "git"), "commit");
            try text.print(a, "{s} {d:>5} {d:>12.3} {d:>11.3} {d:>11.3} {d:>11.3}  {s} / {s} / {s} / {s}\n", .{
                h.string(row, "day"),                                     h.number(metric, "count").?,                              median_ns / 1e6,
                @as(f64, @floatFromInt(h.number(metric, "p95").?)) / 1e6, @as(f64, @floatFromInt(h.number(metric, "min").?)) / 1e6, @as(f64, @floatFromInt(h.number(metric, "max").?)) / 1e6,
                h.string(row, "command"),                                 h.string(row, "cache_state"),                             commit[0..@min(12, commit.len)],
                h.string(row, "entry"),
            });
        }
        try text.appendSlice(a, "Nearest-rank p95; successful complete samples only. JSON retains comparison identities.\n");
    } else {
        try text.appendSlice(a, "UTC timestamp          exit   elapsed ms  command / cache / commit / entry\n");
        for (rows) |row| {
            const commit = h.string(h.field(row, "git"), "commit");
            try text.print(a, "{s} {d:>6} {d:>12.3}  {s} / {s} / {s} / {s}\n", .{
                h.string(row, "captured_utc"),                                h.number(row, "exit_code").?,
                @as(f64, @floatFromInt(h.number(row, "elapsed_ns").?)) / 1e6, h.string(row, "command"),
                h.cacheState(row),                                            commit[0..@min(12, commit.len)],
                h.string(row, "entry"),
            });
        }
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, text.items);
    return 0;
}

const Mode = enum { history, trends, on, off, status };
const Options = struct { mode: Mode, selection: h.Selection, directory: ?[]const u8, json: bool };

fn parseOptions(a: std.mem.Allocator, args: []const []const u8) !Options {
    const mode = std.meta.stringToEnum(Mode, args[0]) orelse return error.InvalidProfileCommand;
    const listing = mode == .history;
    const trending = mode == .trends;
    const off = mode == .off;
    const status = mode == .status;
    var selection: h.Selection = .{ .limit = if (trending) 1000 else 20 };
    var directory: ?[]const u8 = null;
    var json = false;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var at: usize = 1;
    while (at < args.len) : (at += 1) {
        const arg = args[at];
        if ((try seen.getOrPut(a, arg)).found_existing) return error.DuplicateOption;
        if (std.mem.eql(u8, arg, "--json") and (listing or trending or status)) {
            json = true;
            continue;
        }
        if (at + 1 == args.len) return error.MissingOptionValue;
        const value = args[at + 1];
        if (std.mem.eql(u8, arg, "--dir") and !off) {
            if (value.len == 0) return error.InvalidDirectory;
            directory = value;
        } else if (std.mem.eql(u8, arg, "--limit") and (listing or trending)) {
            selection.limit = try std.fmt.parseInt(usize, value, 10);
            if (selection.limit == 0) return error.InvalidLimit;
        } else if (std.mem.eql(u8, arg, "--command") and (listing or trending)) {
            selection.command = value;
        } else if (std.mem.eql(u8, arg, "--entry") and (listing or trending)) {
            selection.entry = value;
        } else return error.UnknownProfileOption;
        at += 1;
    }
    return .{ .mode = mode, .selection = selection, .directory = directory, .json = json };
}

fn savedArchive(a: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map) ![]const u8 {
    const base = try h.stateDirectory(a, env);
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, try std.fs.path.join(a, &.{ base, "config.json" }), a, .limited(8192)) catch return base;
    const config = std.json.parseFromSliceLeaky(V, a, bytes, .{}) catch return base;
    const directory = h.string(config, "directory");
    return if (std.fs.path.isAbsolute(directory)) directory else base;
}

fn printJson(init: std.process.Init, value: anytype) !u8 {
    const bytes = try std.json.Stringify.valueAlloc(init.arena.allocator(), value, .{ .whitespace = .indent_2 });
    try std.Io.File.stdout().writeStreamingAll(init.io, bytes);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
    return 0;
}

test "profile options reject invalid commands duplicate unknown and missing values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectError(error.InvalidProfileCommand, parseOptions(a, &.{"invalid"}));
    try std.testing.expectError(error.DuplicateOption, parseOptions(a, &.{ "history", "--json", "--json" }));
    try std.testing.expectError(error.MissingOptionValue, parseOptions(a, &.{ "history", "--limit" }));
    try std.testing.expectError(error.InvalidDirectory, parseOptions(a, &.{ "on", "--dir", "" }));
    try std.testing.expectError(error.InvalidLimit, parseOptions(a, &.{ "trends", "--limit", "0" }));
    try std.testing.expectError(error.UnknownProfileOption, parseOptions(a, &.{ "off", "--dir", "archive" }));
    try std.testing.expectEqual(@as(usize, 1000), (try parseOptions(a, &.{"trends"})).selection.limit);
}
