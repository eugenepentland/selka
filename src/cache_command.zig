//! Native cache policy management and collection, with preview as the default.
const std = @import("std");
const retention = @import("compiler_root").compiler_language.native_cache_retention;

const usage =
    \\usage: mylang cache gc --shared-cache-dir DIR --kind compiler|tests [--max-bytes N] [--max-entries N] [--max-age-seconds N] [--apply]
    \\       mylang cache configure --shared-cache-dir DIR --kind compiler|tests [--max-bytes N] [--max-entries N] [--max-age-seconds N] [--interval-seconds N]
    \\gc previews collection unless --apply is supplied. configure persists policy immediately.
    \\Both require an initialized v2 namespace; first build/test use initializes it.
    \\Age zero disables expiry. Limits and intervals are unsigned decimal integers.
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
const Request = struct {
    configure: bool,
    root: []const u8,
    kind: retention.Kind,
    overrides: Overrides = .{},
    apply: bool = false,
};

/// Run the native cache subcommand and return a usage, host, or success status.
pub fn run(process: std.process.Init, args: []const []const u8) u8 {
    return dispatch(process.arena.allocator(), process.io, args) catch |err| {
        if (err == error.Usage) {
            std.Io.File.stderr().writeStreamingAll(process.io, usage) catch return 2;
        } else {
            const message = std.fmt.allocPrint(process.arena.allocator(), "cache: {s}; requires an initialized, valid v2 cache namespace\n", .{@errorName(err)}) catch "cache: failure\n";
            std.Io.File.stderr().writeStreamingAll(process.io, message) catch return 2;
        }
        return 2;
    };
}

fn dispatch(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !u8 {
    if (isHelp(args)) {
        try std.Io.File.stdout().writeStreamingAll(io, usage);
        return 0;
    }
    const request = try parse(args);
    const namespace = try std.fs.path.join(allocator, &.{ request.root, request.kind.namespace() });
    defer allocator.free(namespace);
    const context = retention.Context.init(allocator, io, namespace, request.kind);
    const policy = request.overrides.apply(try context.policy());
    try policy.validate();
    if (request.configure) {
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
                .unmet_budget = result.unmet_budget,
                .inventory_complete = result.inventory_complete,
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
    const configure = std.mem.eql(u8, args[0], "configure");
    if (!configure and !std.mem.eql(u8, args[0], "gc")) return error.Usage;
    var root: ?[]const u8 = null;
    var kind: ?retention.Kind = null;
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
            if (kind != null) return error.Usage;
            kind = std.meta.stringToEnum(retention.Kind, value) orelse return error.Usage;
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
    return .{ .configure = configure, .root = root orelse return error.Usage, .kind = kind orelse return error.Usage, .overrides = overrides, .apply = apply };
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
    try std.testing.expect(configured.configure);
    try std.testing.expectEqual(@as(?u64, 60), configured.overrides.interval);
}
