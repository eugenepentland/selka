//! Native cache policy management and collection, with preview as the default.
const std = @import("std");
const retention = @import("compiler_root").compiler_language.native_cache_retention;
const stage_store = @import("selka_core").stage_store;
const store_settings = @import("compiler_root").compiler_language.store_settings;

const usage =
    \\usage: selka cache gc --shared-cache-dir DIR --kind compiler|tests|stages [--max-bytes N] [--max-entries N] [--max-age-seconds N] [--apply]
    \\       selka cache configure --shared-cache-dir DIR --kind compiler|tests|stages [--max-bytes N] [--max-entries N] [--max-age-seconds N] [--interval-seconds N]
    \\       selka cache init --shared-cache-dir DIR --kind compiler|tests
    \\       selka cache where [ENTRY.selka|DIR]
    \\gc previews collection unless --apply is supplied. configure persists policy immediately.
    \\Both require an initialized v2 namespace; first build/test use initializes it.
    \\init writes the format marker of a namespace that lost it (one that holds only this cache's own directories) and changes
    \\nothing else; it refuses a directory with a different marker or with files that are not this cache's.
    \\Age zero disables expiry. Limits and intervals are unsigned decimal integers.
    \\where prints the place each store and the temporary folder resolve to for the project of ENTRY or DIR (default: the working
    \\directory), and what decided it: the environment, that project's selka.json `stores`, or the default.
    \\--kind stages is the shared stage store (the directory SELKA_STAGE_SHARED_CACHE or the per-user default names): it takes only --max-bytes
    \\and --apply, gc previews the packs a collection would evict, and configure persists the cap in the namespace's policy file.
    \\
;

const Overrides = struct {
    bytes: ?u64 = null,
    entries: ?usize = null,
    age: ?u64 = null,
    interval: ?u64 = null,

    fn apply(self: Overrides, base: retention.Policy) retention.Policy {
        var policy = base;
        if (self.bytes) |value| policy.max_bytes = value;
        if (self.entries) |value| policy.max_entries = value;
        if (self.age) |value| policy.max_age_seconds = value;
        if (self.interval) |value| policy.interval_seconds = value;
        return policy;
    }
};
const Action = enum { gc, configure, init };
const Request = struct {
    action: Action,
    root: []const u8,
    kind: retention.Kind,
    overrides: Overrides = .{},
    apply: bool = false,
    /// `--kind stages`: the shared stage store, which has its own retention (`stage_collector.zig`); `kind` is not read.
    stages: bool = false,
};

/// Run the native cache subcommand and return a usage, host, or success status.
pub fn run(process: std.process.Init, args: []const []const u8) u8 {
    if (args.len >= 1 and std.mem.eql(u8, args[0], "where")) return where(process, args[1..]) catch |err| {
        const message = std.fmt.allocPrint(process.arena.allocator(), "cache: {s}\n", .{@errorName(err)}) catch "cache: failure\n";
        std.Io.File.stderr().writeStreamingAll(process.io, message) catch return 2;
        return 2;
    };
    return dispatch(process.arena.allocator(), process.io, args) catch |err| {
        if (err == error.Usage) {
            std.Io.File.stderr().writeStreamingAll(process.io, usage) catch return 2;
        } else {
            const message = std.fmt.allocPrint(process.arena.allocator(), "cache: {s}\n", .{@errorName(err)}) catch "cache: failure\n";
            std.Io.File.stderr().writeStreamingAll(process.io, message) catch return 2;
        }
        return 2;
    };
}

/// `selka cache where [ENTRY|DIR]`: decide the stores as a build of that entry or directory would
/// (`store_settings.apply`), then print one line per place, with what decided it (FR8).
fn where(process: std.process.Init, args: []const []const u8) !u8 {
    if (args.len > 1 or (args.len == 1 and std.mem.startsWith(u8, args[0], "-"))) {
        try std.Io.File.stderr().writeStreamingAll(process.io, usage);
        return 2;
    }
    const allocator = process.arena.allocator();
    const target = if (args.len == 1) args[0] else ".";
    // A project file the commands refuse is refused here the same way, not described as if it named nothing.
    if (try store_settings.loadFailure(allocator, process.io, target)) |refused| {
        try std.Io.File.stderr().writeStreamingAll(process.io, refused);
        return 2;
    }
    if (try store_settings.apply(allocator, process.io, process.environ_map, target)) |refused| {
        try std.Io.File.stderr().writeStreamingAll(process.io, refused);
        return 2;
    }
    try std.Io.File.stdout().writeStreamingAll(process.io, try store_settings.describe(allocator, process.environ_map));
    return 0;
}

fn dispatch(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !u8 {
    if (isHelp(args)) {
        try std.Io.File.stdout().writeStreamingAll(io, usage);
        return 0;
    }
    const request = try parse(args);
    if (request.stages) return stages(allocator, io, request);
    const namespace = try std.fs.path.join(allocator, &.{ request.root, request.kind.namespace() });
    defer allocator.free(namespace);
    const context = retention.Context.init(allocator, io, namespace, request.kind);
    return execute(allocator, io, request, context) catch |err| {
        if (err == error.OutOfMemory) return err;
        const message = try refusal(allocator, request, context, err);
        defer allocator.free(message);
        std.Io.File.stderr().writeStreamingAll(io, message) catch return 2;
        return 2;
    };
}

/// `gc` and `configure` for the shared stage store: the cap in force and what a collection would evict (a preview) or did (`--apply`).
fn stages(allocator: std.mem.Allocator, io: std.Io, request: Request) !u8 {
    const configure = request.action == .configure;
    const maintained = try stage_store.Store.maintain(allocator, io, request.root, .{ .max_bytes = request.overrides.bytes, .apply = request.apply, .configure = configure }) orelse {
        const message = try std.fmt.allocPrint(allocator, "cache: {s} holds no shared stage namespace; a first build creates it\n", .{request.root});
        defer allocator.free(message);
        std.Io.File.stderr().writeStreamingAll(io, message) catch return 2;
        return 2;
    };
    if (configure) {
        try emit(allocator, io, .{ .schema = "native-cache-configure-v1", .kind = "stages", .configured = true, .policy = .{ .max_bytes = maintained.policy.max_bytes } });
        return 0;
    }
    const report = maintained.report orelse stage_store.collector.Report{};
    try emit(allocator, io, .{ .schema = "native-cache-gc-v1", .kind = "stages", .report = .{
        .dry_run = !request.apply,
        .ran = maintained.report != null,
        .max_bytes = maintained.policy.max_bytes,
        .bytes_before = report.bytes_before,
        .bytes_after = report.bytes_after,
        .evicted_packs = report.evicted,
        .leases = report.leases,
        .unmet_budget = report.unmet,
    } });
    return 0;
}

/// Why a command was refused, for the person running it: the error, then what the namespace is and the command that repairs it.
/// Nothing was changed.
fn refusal(allocator: std.mem.Allocator, request: Request, context: retention.Context, err: anyerror) std.mem.Allocator.Error![]u8 {
    const what = if (request.action == .init) "cannot initialize" else "requires an initialized, valid v2 cache namespace";
    const found = context.condition() catch .initialized;
    const advice = switch (found) {
        .fresh => try std.fmt.allocPrint(
            allocator,
            "{s} is not an initialized namespace: a first build or test initializes it, or `selka cache init --shared-cache-dir {s} --kind {s}` does",
            .{ context.root, request.root, @tagName(request.kind) },
        ),
        .unmarked => try std.fmt.allocPrint(allocator, "{s} has no format marker but holds this cache's directories; {s}`selka cache init --shared-cache-dir {s} --kind {s}` writes the marker and nothing else", .{
            context.root,
            if (request.kind == .compiler) "any build or test adopts it, or " else "",
            request.root,
            @tagName(request.kind),
        }),
        .bad_marker => try std.fmt.allocPrint(allocator, "{s}/format is not this cache's v2 marker; move the directory aside, or delete the file if you know it is damaged", .{context.root}),
        .foreign => try std.fmt.allocPrint(allocator, "{s} holds files that are not this cache's; move it aside", .{context.root}),
        .initialized => try allocator.dupe(u8, "the namespace is initialized"),
    };
    defer allocator.free(advice);
    return std.fmt.allocPrint(allocator, "cache: {s}; {s}\ncache: {s}\n", .{ @errorName(err), what, advice });
}

fn execute(allocator: std.mem.Allocator, io: std.Io, request: Request, context: retention.Context) !u8 {
    if (request.action == .init) {
        const found = try context.adopt();
        try emit(allocator, io, .{ .schema = "native-cache-init-v1", .kind = @tagName(request.kind), .namespace = context.root, .condition = @tagName(found), .initialized = found != .initialized });
        return 0;
    }
    const policy = request.overrides.apply(try context.policy());
    try policy.validate();
    if (request.action == .configure) {
        const applied = try context.configure(policy);
        try emit(allocator, io, .{ .schema = "native-cache-configure-v1", .kind = @tagName(request.kind), .configured = applied, .skipped_active = !applied, .policy = policy });
    } else {
        const result = try context.collect(policy, !request.apply);
        try emit(allocator, io, .{
            .schema = "native-cache-gc-v1",
            .kind = @tagName(request.kind),
            .report = .{
                .dry_run = result.dry_run,
                .scanned = result.inventory,
                .removed = result.removed,
                .retained = result.retained,
                .skipped_active = result.skipped_active,
                .leased = result.walk.leased,
                .unmet_budget = result.unmet_budget,
                .inventory_complete = result.walk.complete,
                .visited = result.walk.visited,
                .unvisited = result.walk.unvisited,
            },
        });
    }
    return 0;
}

fn emit(allocator: std.mem.Allocator, io: std.Io, value: anytype) !void {
    const json = try std.json.Stringify.valueAlloc(allocator, value, .{});
    defer allocator.free(json);
    try std.Io.File.stdout().writeStreamingAll(io, json);
    try std.Io.File.stdout().writeStreamingAll(io, "\n");
}

fn isHelp(args: []const []const u8) bool {
    const flag = if (args.len == 1) args[0] else if (args.len == 2) args[1] else return false;
    return std.mem.eql(u8, flag, "--help") or std.mem.eql(u8, flag, "-h");
}

fn number(comptime T: type, text: []const u8) error{Usage}!T {
    if (text.len == 0) return error.Usage;
    for (text) |byte| if (byte < '0' or byte > '9') return error.Usage;
    return std.fmt.parseInt(T, text, 10) catch error.Usage;
}

fn parse(args: []const []const u8) error{Usage}!Request {
    if (args.len == 0) return error.Usage;
    const action = std.meta.stringToEnum(Action, args[0]) orelse return error.Usage;
    const configure = action == .configure;
    var root: ?[]const u8 = null;
    var kind: ?retention.Kind = null;
    var stages_kind = false;
    var overrides: Overrides = .{};
    var apply = false;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const flag = args[index];
        if (std.mem.eql(u8, flag, "--apply")) {
            if (configure or apply) return error.Usage;
            apply = true;
            continue;
        }
        index += 1;
        if (index == args.len) return error.Usage;
        const value = args[index];
        if (std.mem.eql(u8, flag, "--shared-cache-dir")) {
            if (root != null or value.len == 0) return error.Usage;
            root = value;
        } else if (std.mem.eql(u8, flag, "--kind")) {
            if (kind != null or stages_kind) return error.Usage;
            if (std.mem.eql(u8, value, "stages")) {
                stages_kind = true;
            } else kind = std.meta.stringToEnum(retention.Kind, value) orelse return error.Usage;
        } else if (std.mem.eql(u8, flag, "--max-bytes")) {
            if (overrides.bytes != null) return error.Usage;
            overrides.bytes = try number(u64, value);
        } else if (std.mem.eql(u8, flag, "--max-entries")) {
            if (overrides.entries != null) return error.Usage;
            overrides.entries = try number(usize, value);
        } else if (std.mem.eql(u8, flag, "--max-age-seconds")) {
            if (overrides.age != null) return error.Usage;
            overrides.age = try number(u64, value);
        } else if (std.mem.eql(u8, flag, "--interval-seconds")) {
            if (!configure or overrides.interval != null) return error.Usage;
            overrides.interval = try number(u64, value);
        } else return error.Usage;
    }
    const none = overrides.bytes == null and overrides.entries == null and overrides.age == null;
    if (action == .init and (!none or apply)) return error.Usage;
    // The stage store has a size cap and nothing else to configure, and it is created by a build, never by a command.
    const stage_limits = overrides.entries != null or overrides.age != null or overrides.interval != null;
    if (stages_kind and (action == .init or stage_limits)) return error.Usage;
    return .{ .action = action, .root = root orelse return error.Usage, .kind = kind orelse if (stages_kind) .compiler else return error.Usage, .overrides = overrides, .apply = apply, .stages = stages_kind };
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention CLI rejects malformed and duplicate limits" {
    const testing = std.testing;
    try testing.expectError(error.Usage, parse(&.{}));
    try testing.expectError(error.Usage, parse(&.{ "gc", "--shared-cache-dir", "cache", "--kind", "legacy" }));
    try testing.expectError(error.Usage, parse(&.{ "gc", "--shared-cache-dir", "cache", "--kind", "compiler", "--max-bytes", "-1" }));
    try testing.expectError(error.Usage, parse(&.{ "gc", "--shared-cache-dir", "cache", "--kind", "compiler", "--max-bytes", "18446744073709551616" }));
    try testing.expectError(error.Usage, parse(&.{ "gc", "--shared-cache-dir", "cache", "--kind", "compiler", "--max-entries", "1", "--max-entries", "2" }));
    try testing.expectError(error.Usage, parse(&.{ "gc", "--shared-cache-dir", "cache", "--kind", "tests", "--interval-seconds", "1" }));
    try testing.expectError(error.Usage, parse(&.{ "configure", "--shared-cache-dir", "cache", "--kind", "tests", "--apply" }));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention CLI distinguishes preview apply and persistent configuration" {
    const preview = try parse(&.{ "gc", "--shared-cache-dir", "cache", "--kind", "compiler", "--max-age-seconds", "0" });
    const applied = try parse(&.{ "gc", "--shared-cache-dir", "cache", "--kind", "tests", "--apply" });
    const configured = try parse(&.{ "configure", "--shared-cache-dir", "cache", "--kind", "tests", "--max-bytes", "4096", "--interval-seconds", "60" });
    try std.testing.expect(!preview.apply);
    try std.testing.expectEqual(@as(?u64, 0), preview.overrides.age);
    try std.testing.expect(applied.apply);
    try std.testing.expectEqual(Action.configure, configured.action);
    try std.testing.expectEqual(@as(?u64, 60), configured.overrides.interval);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention CLI takes the shared stage store as a kind with a cap and nothing else" {
    const testing = std.testing;
    const preview = try parse(&.{ "gc", "--shared-cache-dir", "cache", "--kind", "stages" });
    const applied = try parse(&.{ "gc", "--shared-cache-dir", "cache", "--kind", "stages", "--max-bytes", "4096", "--apply" });
    const configured = try parse(&.{ "configure", "--shared-cache-dir", "cache", "--kind", "stages", "--max-bytes", "4096" });
    try testing.expect(preview.stages and !preview.apply);
    try testing.expect(applied.stages and applied.apply);
    try testing.expectEqual(@as(?u64, 4096), configured.overrides.bytes);
    try testing.expectError(error.Usage, parse(&.{ "init", "--shared-cache-dir", "cache", "--kind", "stages" }));
    try testing.expectError(error.Usage, parse(&.{ "gc", "--shared-cache-dir", "cache", "--kind", "stages", "--max-entries", "1" }));
    try testing.expectError(error.Usage, parse(&.{ "configure", "--shared-cache-dir", "cache", "--kind", "stages", "--interval-seconds", "1" }));
    try testing.expectError(error.Usage, parse(&.{ "gc", "--shared-cache-dir", "cache", "--kind", "stages", "--kind", "compiler" }));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention CLI init takes a namespace and a kind and nothing else" {
    const testing = std.testing;
    const initialized = try parse(&.{ "init", "--shared-cache-dir", "cache", "--kind", "compiler" });
    try testing.expectEqual(Action.init, initialized.action);
    try testing.expectError(error.Usage, parse(&.{ "init", "--shared-cache-dir", "cache" }));
    try testing.expectError(error.Usage, parse(&.{ "init", "--shared-cache-dir", "cache", "--kind", "tests", "--apply" }));
    try testing.expectError(error.Usage, parse(&.{ "init", "--shared-cache-dir", "cache", "--kind", "tests", "--max-bytes", "1" }));
    try testing.expectError(error.Usage, parse(&.{ "init", "--shared-cache-dir", "cache", "--kind", "tests", "--interval-seconds", "1" }));
}
