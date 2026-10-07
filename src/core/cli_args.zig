//! The `mylang build`, `build --run`, `run` and `run-project` command lines, in the
//! old CLI's spellings, parsed into a new-core build and an optional run
//! (NEW-CORE-S5-CLI-1, NEW-CORE-S5-RUN-1). Every value after `--` is the program's.
const std = @import("std");
const pipeline = @import("pipeline.zig");
const memory_budget = @import("memory_budget");

/// What one command line asked for.
pub const Request = struct {
    /// The entry file.
    path: []const u8 = "",
    build: pipeline.Options,
    /// Null for `mylang build -o OUT`; set for `run`, `run-project` and `build --run`.
    run: ?Run = null,
};

/// How the built program runs.
pub const Run = struct {
    /// `--max-steps`, `--max-frames`, `--max-memory` and `--timeout`; null when not given.
    limits: Limits = .{},
    /// Grants and `--print-result`, which travel to the program in `MYLANG_OPTIONS`.
    options: []const []const u8 = &.{},
    /// The program's own arguments, every value after `--`.
    arguments: []const []const u8 = &.{},
};

/// The budgets the command line named; null leaves one to the environment, the
/// project's `limits.run` or the default.
pub const Limits = struct {
    steps: ?u64 = null,
    frames: ?u64 = null,
    memory: ?u64 = null,
    timeout: ?u64 = null,
};

/// Why a command line cannot run: a malformed or unknown option, or one that names
/// a retired feature (`message` says which and what replaces it).
pub const Failure = union(enum) { usage, retired: []const u8 };

/// Which command is being parsed.
pub const Command = enum { build, run };

/// A network grant's prefix: `--allow-endpoint=IP:PORT`.
const endpoint_grant = "--allow-endpoint=";

/// The flags that take a value, spelled `--flag VALUE` or `--flag=VALUE`.
const valued = [_][]const u8{ "-o", "--output", "--link", "--emit-llvm", "--cache-dir", "--zig", "--qbe", "--mode", "--max-steps", "--max-frames", "--max-memory", "--timeout" };

/// Parse `args` (the words after the command name) for `command`.
pub fn parse(allocator: std.mem.Allocator, command: Command, args: []const []const u8, zig: []const u8, failure: *Failure) error{ OutOfMemory, Usage }!Request {
    var request: Request = .{ .build = .{ .zig = zig } };
    request.build.show.diagnostics = .text;
    var parser: Parser = .{ .allocator = allocator, .request = &request, .failure = failure };
    var runs = command == .run;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--")) {
            parser.arguments = args[index + 1 ..];
            if (!runs) return parser.usage();
            break;
        }
        if (std.mem.eql(u8, arg, "--run") and command == .build) {
            if (runs) return parser.usage();
            runs = true;
            continue;
        }
        if (!std.mem.startsWith(u8, arg, "-")) {
            if (request.path.len != 0) return parser.usage();
            request.path = arg;
            continue;
        }
        const split = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
        const name = arg[0..split];
        if (isValued(name)) {
            const value = if (split < arg.len) arg[split + 1 ..] else value: {
                index += 1;
                if (index == args.len) return parser.usage();
                break :value args[index];
            };
            if (value.len == 0) return parser.usage();
            try parser.option(name, value);
            continue;
        }
        try parser.flag(arg);
    }
    if (request.path.len == 0 or !validGrants(parser.options.items)) return parser.usage();
    if (runs) {
        if (request.build.output.len != 0 or request.build.show.llvm != null) return parser.usage();
        request.run = .{ .limits = parser.limits, .options = parser.options.items, .arguments = parser.arguments };
    } else {
        if (request.build.output.len == 0 or parser.options.items.len != 0 or !parser.unlimited()) return parser.usage();
    }
    request.build.links = parser.links.items;
    return request;
}

fn isValued(name: []const u8) bool {
    for (valued) |flag| if (std.mem.eql(u8, flag, name)) return true;
    return false;
}

const Parser = struct {
    allocator: std.mem.Allocator,
    request: *Request,
    failure: *Failure,
    limits: Limits = .{},
    links: std.ArrayList([]const u8) = .empty,
    options: std.ArrayList([]const u8) = .empty,
    arguments: []const []const u8 = &.{},

    fn usage(self: *Parser) error{Usage} {
        self.failure.* = .usage;
        return error.Usage;
    }

    fn retire(self: *Parser, message: []const u8) error{Usage} {
        self.failure.* = .{ .retired = message };
        return error.Usage;
    }

    fn unlimited(self: *const Parser) bool {
        return self.limits.steps == null and self.limits.frames == null and self.limits.memory == null and self.limits.timeout == null;
    }

    fn option(self: *Parser, name: []const u8, value: []const u8) error{ OutOfMemory, Usage }!void {
        const build = &self.request.build;
        if (eql(name, "-o") or eql(name, "--output")) {
            build.output = value;
        } else if (eql(name, "--link")) {
            try self.links.append(self.allocator, value);
        } else if (eql(name, "--emit-llvm")) {
            build.show.llvm = value;
        } else if (eql(name, "--cache-dir")) {
            build.cache = value;
        } else if (eql(name, "--zig")) {
            build.zig = value;
        } else if (eql(name, "--qbe")) {
            // The new core builds with LLVM; a QBE path names a tool it never runs.
        } else if (eql(name, "--mode")) {
            if (eql(value, "ReleaseFast")) build.release = true else if (eql(value, "Debug")) build.release = false else return self.usage();
        } else if (eql(name, "--max-memory")) {
            if (self.limits.memory != null) return self.usage();
            self.limits.memory = memory_budget.parse(value) catch return self.usage();
        } else {
            const slot = if (eql(name, "--max-steps")) &self.limits.steps else if (eql(name, "--max-frames")) &self.limits.frames else &self.limits.timeout;
            if (slot.* != null) return self.usage();
            slot.* = positive(value) orelse return self.usage();
        }
    }

    fn flag(self: *Parser, arg: []const u8) error{ OutOfMemory, Usage }!void {
        const build = &self.request.build;
        if (eql(arg, "--release")) {
            build.release = true;
        } else if (eql(arg, "--print-result") or grant(arg)) {
            // A repeated grant or switch is refused, as the old CLI refused it.
            if (contains(self.options.items, arg)) return self.usage();
            try self.options.append(self.allocator, arg);
        } else if (eql(arg, "--diagnostics=json")) {
            build.show.diagnostics = .json;
        } else if (eql(arg, "--diagnostics=text")) {
            build.show.diagnostics = .text;
        } else if (eql(arg, "--cache-report")) {
            build.show.cache_report = true;
        } else if (eql(arg, "--verify-cache")) {
            build.show.verify_cache = true;
        } else if (eql(arg, "--stats")) {
            build.show.stats = true;
        } else if (eql(arg, "--no-facts")) {
            build.facts = .off;
        } else if (eql(arg, "--verify-facts")) {
            build.facts = .verify;
        } else if (eql(arg, "--project") or eql(arg, "--whole-program")) {
            // A project entry is found from the file itself, and every build of the new
            // core plans its own units (S5-D6), so these ask for nothing more.
        } else if (unported(arg)) |message| {
            return self.retire(message);
        } else return self.usage();
    }
};

/// The message for an option the old back end answered that the new core does not
/// (yet), or null for any other argument.
pub fn unported(arg: []const u8) ?[]const u8 {
    const name = arg[0 .. std.mem.indexOfScalar(u8, arg, '=') orelse arg.len];
    for ([_][]const u8{ "--backend", "--llvm-opt", "--lto", "--target", "--keep-symbols", "--step-accounting" }) |old| {
        if (eql(name, old)) return "the new core always builds with LLVM: a build is the debug build and --release the optimized one, so this QBE/LLVM build control was retired";
    }
    for ([_][]const u8{ "--no-cache", "--report", "--timings", "--explain-invalidation", "--friction-log", "--affected", "--against" }) |later| {
        if (eql(name, later)) return "this option is not supported by the new core yet (S5-B); run without it";
    }
    return null;
}

/// Whether `arg` is one of the capability grants the runtime reads from `MYLANG_OPTIONS`.
/// Endpoints and directories must name something; a seed must be a number.
fn grant(arg: []const u8) bool {
    for ([_][]const u8{ "--restrict", "--allow-clock", "--allow-host", "--allow-all", "--allow-random", "--allow-env" }) |bare| {
        if (eql(arg, bare)) return true;
    }
    for ([_][]const u8{ "--allow-read=", "--allow-write=", endpoint_grant, "--allow-env=" }) |prefix| {
        if (std.mem.startsWith(u8, arg, prefix)) return arg.len > prefix.len;
    }
    const seed = "--allow-random=";
    if (!std.mem.startsWith(u8, arg, seed) or arg.len == seed.len) return false;
    _ = std.fmt.parseUnsigned(u64, arg[seed.len..], 10) catch return false;
    return true;
}

/// Whether the grants among `options` form a set the old CLI accepted (CAPABILITY-2):
/// at most eight directories and eight endpoints, an endpoint an IPv4 literal with a
/// port, one entropy and one environment grant, and `--allow-all` before none of the
/// grants it already makes. Repeats were refused as they were collected.
fn validGrants(options: []const []const u8) bool {
    var directories: usize = 0;
    var endpoints: usize = 0;
    var singles: usize = 0;
    var all = false;
    for (options) |arg| {
        if (std.mem.startsWith(u8, arg, "--allow-read=") or std.mem.startsWith(u8, arg, "--allow-write=")) {
            directories += 1;
        } else if (std.mem.startsWith(u8, arg, endpoint_grant)) {
            const address = std.Io.net.IpAddress.parseLiteral(arg[endpoint_grant.len..]) catch return false;
            if (address == .ip6 or address.getPort() == 0) return false;
            endpoints += 1;
        } else if (eql(arg, "--allow-all")) {
            if (singles != 0 or directories != 0 or endpoints != 0) return false;
            all = true;
        } else if (std.mem.startsWith(u8, arg, "--allow-")) {
            // Clock, host, entropy and environment: each once, and none after `--allow-all`.
            const family = arg[0 .. std.mem.indexOfScalar(u8, arg, '=') orelse arg.len];
            for (options) |other| if (other.ptr != arg.ptr and std.mem.startsWith(u8, other, family) and (other.len == family.len or other[family.len] == '=')) return false;
            if (all) return false;
            singles += 1;
        }
    }
    return directories <= 8 and endpoints <= 8;
}

fn contains(items: []const []const u8, wanted: []const u8) bool {
    for (items) |item| if (eql(item, wanted)) return true;
    return false;
}

fn positive(digits: []const u8) ?u64 {
    const value = std.fmt.parseUnsigned(u64, digits, 10) catch return null;
    return if (value == 0) null else value;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

// twin-drift-ok: `src/runtime_options.zig` belongs to the old back end, which S5-D deletes, and the core cannot import it.
/// Spell `options` as one `MYLANG_OPTIONS` value, as the runtime reads it: an option
/// holding whitespace, a quote or a backslash is quoted with those two escaped.
pub fn encodeOptions(allocator: std.mem.Allocator, options: []const []const u8) error{OutOfMemory}![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    for (options, 0..) |item, index| {
        if (index != 0) try text.append(allocator, ' ');
        if (item.len != 0 and std.mem.indexOfAny(u8, item, " \t\r\n\"\\") == null) {
            try text.appendSlice(allocator, item);
            continue;
        }
        try text.append(allocator, '"');
        for (item) |byte| {
            if (byte == '"' or byte == '\\') try text.append(allocator, '\\');
            try text.append(allocator, byte);
        }
        try text.append(allocator, '"');
    }
    return text.items;
}

// spec: NEW-CORE-S5-CLI-1
test "build and run command lines parse in the old spellings into one new-core request" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: Failure = .usage;
    const built = try parse(a, .build, &.{ "prog.my", "-o", "out", "--release", "--qbe=/q", "--zig", "/z", "--cache-dir=c", "--whole-program" }, "zig", &failure);
    try std.testing.expectEqualStrings("out", built.build.output);
    try std.testing.expect(built.build.release and built.run == null);
    try std.testing.expectEqualStrings("/z", built.build.zig);
    try std.testing.expectEqualStrings("c", built.build.cache);
    const ran = try parse(a, .run, &.{ "p.my", "--max-steps", "9", "--timeout=3", "--restrict", "--allow-read=d", "--print-result", "--", "--release", "x" }, "zig", &failure);
    try std.testing.expectEqual(@as(?u64, 9), ran.run.?.limits.steps);
    try std.testing.expectEqual(@as(?u64, 3), ran.run.?.limits.timeout);
    try std.testing.expect(!ran.build.release);
    try std.testing.expectEqual(@as(usize, 3), ran.run.?.options.len);
    try std.testing.expectEqual(@as(usize, 2), ran.run.?.arguments.len);
    const through = try parse(a, .build, &.{ "p.my", "--run", "--max-memory=1G", "--", "a" }, "zig", &failure);
    try std.testing.expectEqual(@as(?u64, 1 << 30), through.run.?.limits.memory);
    try std.testing.expectError(error.Usage, parse(a, .build, &.{ "p.my", "--max-steps=5", "-o", "out" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.my", "--max-frames", "0" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.my", "--allow-read=" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.my", "--allow-endpoint=localhost:9" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.my", "--allow-env=PATH", "--allow-env" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.my", "--allow-all", "--allow-clock" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.my", "--backend", "qbe" }, "zig", &failure));
    try std.testing.expect(failure == .retired);
    try std.testing.expectEqualStrings("--x \"a b\" \"q\\\"\"", try encodeOptions(a, &.{ "--x", "a b", "q\"" }));
}
