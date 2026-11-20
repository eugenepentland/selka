//! The `selka build`, `build --run`, `run` and `run-project` command lines, in the
//! old CLI's spellings, parsed into a new-core build and an optional run
//! (NEW-CORE-S5-CLI-1, NEW-CORE-S5-RUN-1). Every value after `--` is the program's.
const std = @import("std");
const pipeline = @import("pipeline.zig");
const build_mode = @import("build_mode.zig");
const memory_budget = @import("memory_budget");
const target = @import("target.zig");

/// What one command line asked for.
pub const Request = struct {
    /// The entry file.
    path: []const u8 = "",
    build: pipeline.Options,
    /// Null for `selka build -o OUT`; set for `run`, `run-project` and `build --run`.
    run: ?Run = null,
    /// `--no-cache`: build through a private cache that is removed afterwards, so the
    /// command neither reads nor publishes a cached result (NEW-CORE-S5-NO-CACHE-1), in the work directory or in the shared
    /// compiler-artifact and stage stores; only the content-keyed object store is still used (NO-CACHE-COLD-1).
    no_cache: bool = false,
    /// What the command line named of a device build (MCU-C1): a flag here wins over the project's `selka.json`.
    device: DeviceFlags = .{},
    /// `--cpu MODEL`: the CPU model a hosted build compiles for, already in `build.show.codegen.target`; a device build re-applies
    /// it to the project's target (`device_build.fromConfiguration`).
    cpu: target.Cpu = .native,
};

/// `--target` (whether it was given: the project's `target` applies only without it) and `--device NAME`.
pub const DeviceFlags = struct {
    target_named: bool = false,
    name: ?[]const u8 = null,
};

/// How the built program runs.
pub const Run = struct {
    /// `--max-steps`, `--max-frames`, `--max-memory` and `--timeout`; null when not given.
    limits: Limits = .{},
    /// Grants and `--print-result`, which travel to the program in `SELKA_OPTIONS`.
    options: []const []const u8 = &.{},
    /// The program's own arguments, every value after `--`.
    arguments: []const []const u8 = &.{},
    /// `--timings`: print the program's elapsed time once it exits (NEW-CORE-S5-TIMINGS-1).
    timings: bool = false,
    /// `--threads N`: the program's task threads, set as `SELKA_THREADS` in its environment; null leaves the runtime's default.
    threads: ?u64 = null,
};

/// The most task threads a run may ask for: the runtime's pool limit (`MYL_THREADS_MAX` in core_tasks.c).
pub const max_threads: u64 = 256;

/// The budgets the command line named; null leaves one to the environment, the
/// project's `limits.run` or the default.
pub const Limits = struct {
    steps: ?u64 = null,
    frames: ?u64 = null,
    memory: ?u64 = null,
    timeout: ?u64 = null,
};

/// Why a command line cannot run: a malformed option or value (`usage`), a word the command does not take, as a second file or
/// as an option it does not know (`refused`: the index of that word in the parsed `args`), or an option that names a retired
/// feature or a value it cannot use, such as an unknown `--target` (`retired`: the message says which and what to write).
pub const Failure = union(enum) { usage, retired: []const u8, refused: usize };

/// Which command is being parsed.
pub const Command = enum { build, run };

/// A network grant's prefix: `--allow-endpoint=IP:PORT`.
const endpoint_grant = "--allow-endpoint=";
/// A listening grant's prefix: `--allow-listen=IP:PORT`.
const listen_grant = "--allow-listen=";
/// The address a network grant may be given in place of `IP:PORT`: `*` grants every endpoint (or listener), as the runtime
/// reads it from `SELKA_OPTIONS` (`core_io_scoped_listed`), so `selka run` and a built program take the same grants.
const every_endpoint = "*";

/// The flags that take a value, spelled `--flag VALUE` or `--flag=VALUE`.
const valued = [_][]const u8{
    "-o",          "--output",     "--link",       "--emit-llvm", "--emit-certificates", "--cache-dir", "--zig",           "--qbe",     "--mode",
    "--max-steps", "--max-frames", "--max-memory", "--timeout",   "--threads",           "--target",    "--linker-script", "--include", "--device",
    "--cpu",
};

/// Parse `args` (the words after the command name) for `command`.
pub fn parse(allocator: std.mem.Allocator, command: Command, args: []const []const u8, zig: []const u8, failure: *Failure) error{ OutOfMemory, Usage }!Request {
    // `build`, `run` and `run-project` start from the lean debug build; `selka test` starts from -O0 (`main.zig` `testCommand`).
    var request: Request = .{ .build = .{ .zig = zig, .mode = build_mode.Mode.plain } };
    request.build.show.diagnostics = .text;
    var parser: Parser = .{ .allocator = allocator, .request = &request, .failure = failure };
    var runs = command == .run;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        parser.at = index;
        if (std.mem.eql(u8, arg, "--")) {
            parser.pending.arguments = args[index + 1 ..];
            if (!runs) return parser.usage();
            break;
        }
        if (std.mem.eql(u8, arg, "--run") and command == .build) {
            if (runs) return parser.usage();
            runs = true;
            continue;
        }
        if (!std.mem.startsWith(u8, arg, "-")) {
            if (request.path.len != 0) return parser.refuse();
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
        if (request.build.show.codegen.harness_steps) return parser.usage();
        if (request.build.output.len != 0 or request.build.show.llvm != null or request.build.show.certificates != null) return parser.usage();
        if (!request.build.show.codegen.target.runsHere()) return parser.retire(try onlyBuilds(allocator, request.build.show.codegen.target.name));
        request.run = parser.pending;
        request.run.?.options = parser.options.items;
    } else {
        // Grants, budgets and `--timings` describe a run.
        const runs_only = parser.options.items.len != 0 or !parser.unlimited() or parser.pending.timings;
        if (request.build.output.len == 0 or runs_only or parser.pending.threads != null) return parser.usage();
        // The project's `target` and `device` may still supply the target and the script: `device_build.apply` refuses.
    }
    request.build.links = parser.links.items;
    try parser.applyCpu();
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
    /// The index in `args` of the word being read, for `refuse`.
    at: usize = 0,
    /// The run settings collected so far; `options` joins them at the end.
    pending: Run = .{},
    explicit_mode: bool = false,
    links: std.ArrayList([]const u8) = .empty,
    options: std.ArrayList([]const u8) = .empty,

    fn usage(self: *Parser) error{Usage} {
        self.failure.* = .usage;
        return error.Usage;
    }

    /// The word being read is one the command does not take.
    fn refuse(self: *Parser) error{Usage} {
        self.failure.* = .{ .refused = self.at };
        return error.Usage;
    }

    fn retire(self: *Parser, message: []const u8) error{Usage} {
        self.failure.* = .{ .retired = message };
        return error.Usage;
    }

    fn unlimited(self: *const Parser) bool {
        return self.pending.limits.steps == null and self.pending.limits.frames == null and self.pending.limits.memory == null and self.pending.limits.timeout == null;
    }

    fn option(self: *Parser, name: []const u8, value: []const u8) error{ OutOfMemory, Usage }!void {
        const build = &self.request.build;
        if (eql(name, "-o") or eql(name, "--output")) {
            build.output = value;
        } else if (eql(name, "--link")) {
            try self.links.append(self.allocator, value);
        } else if (eql(name, "--linker-script")) {
            build.show.codegen.device.linker_script = value;
        } else if (eql(name, "--include")) {
            const device = &build.show.codegen.device;
            device.include = try std.mem.concat(self.allocator, []const u8, &.{ device.include, &.{value} });
        } else if (eql(name, "--device")) {
            self.request.device.name = value;
        } else if (eql(name, "--emit-llvm")) {
            build.show.llvm = value;
        } else if (eql(name, "--emit-certificates")) {
            build.show.certificates = value;
        } else if (eql(name, "--cache-dir")) {
            build.cache = value;
        } else if (eql(name, "--zig")) {
            build.zig = value;
        } else if (eql(name, "--target")) {
            build.show.codegen.target = try namedTarget(self.allocator, value, self);
            self.request.device.target_named = true;
        } else if (eql(name, "--cpu")) {
            self.request.cpu = target.Cpu.parse(value) orelse return self.retire(try target.Cpu.unknown(self.allocator, value));
        } else if (eql(name, "--qbe")) {
            // The new core builds with LLVM; a QBE path names a tool it never runs.
        } else if (eql(name, "--mode")) {
            if (eql(value, "ReleaseFast")) {
                try build.mode.select(&self.explicit_mode, .release);
            } else if (eql(value, "Debug")) {
                try build.mode.select(&self.explicit_mode, build_mode.Mode.plain);
            } else return self.usage();
        } else if (eql(name, "--max-memory")) {
            if (self.pending.limits.memory != null) return self.usage();
            self.pending.limits.memory = memory_budget.parse(value) catch return self.usage();
        } else if (eql(name, "--threads")) {
            if (self.pending.threads != null) return self.usage();
            const count = positive(value) orelse return self.usage();
            if (count > max_threads) return self.usage();
            self.pending.threads = count;
        } else {
            const slot = if (eql(name, "--max-steps")) &self.pending.limits.steps else if (eql(name, "--max-frames")) &self.pending.limits.frames else &self.pending.limits.timeout;
            if (slot.* != null) return self.usage();
            slot.* = positive(value) orelse return self.usage();
        }
    }

    /// Put the CPU model `--cpu` named into the target, whichever of `--cpu` and `--target` came first: the one place a hosted
    /// command line chooses the flags every unit, runtime object, link and replay key then hashes (`Target.forCpu`).
    fn applyCpu(self: *Parser) error{ OutOfMemory, Usage }!void {
        const codegen = &self.request.build.show.codegen;
        codegen.target = codegen.target.forCpu(self.request.cpu) orelse
            return self.retire(try std.fmt.allocPrint(self.allocator, "--cpu {s} is for the hosted target; the target `{s}` has no CPU model to choose", .{ self.request.cpu.spelling(), codegen.target.name }));
    }

    /// A build-mode option: select its mode, refusing a different one already selected. False when `arg` is none.
    fn modeFlag(self: *Parser, arg: []const u8) error{Usage}!bool {
        const flags = [_]struct { []const u8, build_mode.Mode }{
            .{ "--release", .release },
            .{ "--optimize-debug", .optimized_o2 },
            .{ "--unoptimized", .debug },
            .{ "--debug-o0", .optimized_debug },
            .{ "--debug-lean", .lean_debug },
        };
        for (flags) |entry| if (eql(arg, entry[0])) {
            try self.request.build.mode.select(&self.explicit_mode, entry[1]);
            return true;
        };
        return false;
    }

    fn flag(self: *Parser, arg: []const u8) error{ OutOfMemory, Usage }!void {
        const build = &self.request.build;
        if (try self.modeFlag(arg)) return;
        if (eql(arg, "--test-step-budget")) {
            if (build.show.codegen.harness_steps) return self.usage();
            build.show.codegen.harness_steps = true;
        } else if (eql(arg, "--print-result") or grant(arg)) {
            // A repeated grant or switch is refused, as the old CLI refused it.
            if (contains(self.options.items, arg)) return self.usage();
            try self.options.append(self.allocator, arg);
        } else if (eql(arg, "--diagnostics=json")) {
            build.show.diagnostics = .json;
        } else if (eql(arg, "--diagnostics=text")) {
            build.show.diagnostics = .text;
        } else if (eql(arg, "--cache-report")) {
            build.show.cache_report = .text;
        } else if (eql(arg, "--report")) {
            // The old work report is retired; `--report` is the cache report as JSON (S5-D6).
            build.show.cache_report = .json;
        } else if (eql(arg, "--local-stdlib")) {
            build.show.codegen.local_stdlib = true;
        } else if (eql(arg, "--no-cache")) {
            self.request.no_cache = true;
            // A cold build also keeps out of the shared stage store (NO-CACHE-COLD-1).
            build.show.compiler_cache_disabled = true;
        } else if (eql(arg, "--timings")) {
            if (self.pending.timings) return self.usage();
            self.pending.timings = true;
        } else if (eql(arg, "--verify-cache")) {
            build.show.verify_cache = true;
        } else if (build.show.verify.ask(arg)) {} else if (eql(arg, "--stats")) {
            build.show.stats = true;
        } else if (eql(arg, "--counters")) {
            if (build.show.codegen.counters) return self.usage();
            build.show.codegen.counters = true;
        } else if (eql(arg, "--no-facts")) {
            build.facts = .off;
        } else if (eql(arg, "--verify-facts")) {
            build.facts = .verify;
        } else if (eql(arg, "--verify-written-copies")) {
            build.facts = .verify_written;
        } else if (eql(arg, "--project") or eql(arg, "--whole-program")) {
            // A project entry is found from the file itself, and every build of the new
            // core plans its own units (S5-D6), so these ask for nothing more.
        } else if (unported(arg)) |message| {
            return self.retire(message);
        } else return self.refuse();
    }
};

/// The message for an option of `build`, `run` and `test` that the old back end
/// answered and the new core retired (NEW-CORE-S5-RETIRED-1), or null for any other argument.
pub fn unported(arg: []const u8) ?[]const u8 {
    const name = arg[0 .. std.mem.indexOfScalar(u8, arg, '=') orelse arg.len];
    for ([_][]const u8{ "--backend", "--llvm-opt", "--lto", "--keep-symbols", "--step-accounting" }) |old| {
        if (eql(name, old)) return "the new core always builds with LLVM: builds default to optimized debug; use --release or --unoptimized; this QBE/LLVM build control was retired";
    }
    if (eql(name, "--explain-invalidation")) return "--explain-invalidation compared the old back end's nine stage fingerprints (retired, S5-B2); `--report` says what the new core's caches served";
    if (eql(name, "--timings") and name.len != arg.len) return "--timings=json reported the old back end's phase profile (retired, S5-B2); `--timings` prints the program's run time";
    return null;
}

/// The target `--target` names, or the refusal that lists the known names.
fn namedTarget(allocator: std.mem.Allocator, name: []const u8, parser: *Parser) error{ OutOfMemory, Usage }!*const target.Target {
    return target.byName(name) orelse parser.retire(try unknownTarget(allocator, name));
}

/// The refusal of a `--target` name that is not known: it lists the names that are.
pub fn unknownTarget(allocator: std.mem.Allocator, name: []const u8) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, "unknown target `{s}`; the targets are {s}", .{ name, target.names });
}

/// The refusal of a build whose linker script does not fit its target: a bare target's image is laid out by the linker
/// script `--linker-script` names, and a hosted program takes none. Null when the build may go on.
pub fn linkerScriptRefusal(allocator: std.mem.Allocator, codegen: pipeline.Codegen) error{OutOfMemory}!?[]const u8 {
    const name = codegen.target.name;
    if (codegen.target.runsHere()) {
        if (codegen.device.linker_text != null) {
            const described = try std.fmt.allocPrint(allocator, "the device describes its memory for a bare target; the target `{s}` links with its C library", .{name});
            return described;
        }
        if (codegen.device.linker_script == null) return null;
        const hosted = try std.fmt.allocPrint(allocator, "`--linker-script` is for a bare target; the target `{s}` links with its C library", .{name});
        return hosted;
    }
    if (codegen.device.linker_script != null or codegen.device.linker_text != null) return null;
    const bare = try std.fmt.allocPrint(allocator, "a build for the target `{s}` needs a linker script: add `--linker-script SCRIPT.ld` and the platform's C file, `--link PLATFORM.c`", .{name});
    return bare;
}

/// The refusal of a run (`run`, `run-project`, `build --run`, `test`) for a target that only builds.
pub fn onlyBuilds(allocator: std.mem.Allocator, name: []const u8) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, "the target `{s}` only builds: its programs cannot run here; use `selka build --target {s} FILE.selka -o OUT`", .{ name, name });
}

/// Whether `arg` is one of the capability grants the runtime reads from `SELKA_OPTIONS`.
/// Endpoints and directories must name something; a seed must be a number.
fn grant(arg: []const u8) bool {
    for ([_][]const u8{ "--restrict", "--allow-clock", "--allow-host", "--allow-all", "--allow-random", "--allow-env", "--allow-process" }) |bare| {
        if (eql(arg, bare)) return true;
    }
    for ([_][]const u8{ "--allow-read=", "--allow-write=", endpoint_grant, listen_grant, "--allow-env=" }) |prefix| {
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
    var listens: usize = 0;
    var singles: usize = 0;
    var all = false;
    for (options) |arg| {
        if (std.mem.startsWith(u8, arg, "--allow-read=") or std.mem.startsWith(u8, arg, "--allow-write=")) {
            directories += 1;
        } else if (std.mem.startsWith(u8, arg, endpoint_grant)) {
            if (!eql(arg[endpoint_grant.len..], every_endpoint)) {
                const address = std.Io.net.IpAddress.parseLiteral(arg[endpoint_grant.len..]) catch return false;
                if (address == .ip6 or address.getPort() == 0) return false;
            }
            endpoints += 1;
        } else if (std.mem.startsWith(u8, arg, listen_grant)) {
            // A listen grant may name port 0: the kernel then chooses the port (NETWORK-POLL-1).
            if (!eql(arg[listen_grant.len..], every_endpoint)) {
                const address = std.Io.net.IpAddress.parseLiteral(arg[listen_grant.len..]) catch return false;
                if (address == .ip6) return false;
            }
            listens += 1;
        } else if (eql(arg, "--allow-all")) {
            if (singles != 0 or directories != 0 or endpoints != 0 or listens != 0) return false;
            all = true;
        } else if (std.mem.startsWith(u8, arg, "--allow-")) {
            // Clock, host, entropy and environment: each once, and none after `--allow-all`.
            const family = arg[0 .. std.mem.indexOfScalar(u8, arg, '=') orelse arg.len];
            for (options) |other| if (other.ptr != arg.ptr and std.mem.startsWith(u8, other, family) and (other.len == family.len or other[family.len] == '=')) return false;
            if (all) return false;
            singles += 1;
        }
    }
    return directories <= 8 and endpoints <= 8 and listens <= 8;
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

test "a word the command does not take is reported by its index, a malformed value is not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: Failure = .usage;
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "app.selka", "--max-steps", "5", "ing$" }, "zig", &failure));
    try std.testing.expectEqual(Failure{ .refused = 3 }, failure);
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "app.selka", "--bogus=1", "x" }, "zig", &failure));
    try std.testing.expectEqual(Failure{ .refused = 1 }, failure);
    failure = .usage;
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "app.selka", "--max-steps", "5", "--max-steps", "6" }, "zig", &failure));
    try std.testing.expectEqual(Failure.usage, failure);
    const guest = try parse(a, .run, &.{ "app.selka", "--", "ing$", "--bogus" }, "zig", &failure);
    try std.testing.expectEqual(@as(usize, 2), guest.run.?.arguments.len);
}

// spec: DEBUG-OPTIMIZE-1
test "optimized debug is the default and unoptimized remains explicit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: Failure = .usage;
    const built = try parse(a, .build, &.{ "app.selka", "-o", "out" }, "zig", &failure);
    try std.testing.expectEqual(.lean_debug, built.build.mode);
    for ([_][]const []const u8{ &.{"app.selka"}, &.{ "app.selka", "--mode", "Debug" }, &.{ "app.selka", "--debug-lean" } }) |args| {
        const ran = try parse(a, .run, args, "zig", &failure);
        try std.testing.expectEqual(.lean_debug, ran.build.mode);
    }
    const o2 = try parse(a, .run, &.{ "app.selka", "--optimize-debug" }, "zig", &failure);
    try std.testing.expectEqual(.optimized_o2, o2.build.mode);
    try std.testing.expectEqualStrings("-O2", o2.build.mode.level());
    try std.testing.expectEqualStrings("-O0", built.build.mode.level());
    const unoptimized = try parse(a, .run, &.{ "app.selka", "--unoptimized", "--unoptimized" }, "zig", &failure);
    try std.testing.expectEqual(.debug, unoptimized.build.mode);
    const released = try parse(a, .run, &.{ "app.selka", "--release", "--mode=ReleaseFast" }, "zig", &failure);
    try std.testing.expectEqual(.release, released.build.mode);
    const verified = try parse(a, .run, &.{ "app.selka", "--verify-facts" }, "zig", &failure);
    try std.testing.expect(verified.build.mode == .lean_debug and verified.build.facts == .verify);
    const guest = try parse(a, .run, &.{ "app.selka", "--", "--unoptimized" }, "zig", &failure);
    try std.testing.expectEqual(.lean_debug, guest.build.mode);
    try std.testing.expectEqualStrings("--unoptimized", guest.run.?.arguments[0]);
}

// spec-case: DEBUG-OPTIMIZE-1
test "--debug-o0 gives build, run and build --run the -O0 debug build, and may repeat" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: Failure = .usage;
    const built = try parse(a, .build, &.{ "app.selka", "-o", "out", "--debug-o0" }, "zig", &failure);
    try std.testing.expectEqual(.optimized_debug, built.build.mode);
    try std.testing.expectEqualStrings("-O0", built.build.mode.keyed());
    const ran = try parse(a, .run, &.{ "app.selka", "--debug-o0", "--debug-o0" }, "zig", &failure);
    try std.testing.expectEqual(.optimized_debug, ran.build.mode);
    const through = try parse(a, .build, &.{ "app.selka", "--run", "--debug-o0", "--", "--debug-o0" }, "zig", &failure);
    try std.testing.expect(through.build.mode == .optimized_debug and through.run.?.arguments.len == 1);
}

// spec-case: DEBUG-OPTIMIZE-1
test "select refuses conflicting explicit build modes in either order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: Failure = .usage;
    for ([_][]const []const u8{
        &.{ "app.selka", "--optimize-debug", "--release" },
        &.{ "app.selka", "--release", "--optimize-debug" },
        &.{ "app.selka", "--unoptimized", "--release" },
        &.{ "app.selka", "--release", "--unoptimized" },
        &.{ "app.selka", "--unoptimized", "--optimize-debug" },
        &.{ "app.selka", "--optimize-debug", "--unoptimized" },
        &.{ "app.selka", "--mode=ReleaseFast", "--mode=Debug" },
        &.{ "app.selka", "--mode=Debug", "--mode=ReleaseFast" },
        &.{ "app.selka", "--unoptimized", "--mode=Debug" },
        &.{ "app.selka", "--mode=Debug", "--unoptimized" },
        &.{ "app.selka", "--debug-o0", "--debug-lean" },
        &.{ "app.selka", "--debug-lean", "--debug-o0" },
        &.{ "app.selka", "--debug-o0", "--release" },
        &.{ "app.selka", "--optimize-debug", "--debug-o0" },
        &.{ "app.selka", "--unoptimized", "--debug-lean" },
        &.{ "app.selka", "--debug-o0", "--mode=Debug" },
        &.{ "app.selka", "--mode=Debug", "--debug-o0" },
    }) |args| try std.testing.expectError(error.Usage, parse(a, .run, args, "zig", &failure));
}

// twin-drift-ok: `src/runtime_options.zig` belongs to the old back end, which S5-D deletes, and the core cannot import it.
/// Spell `options` as one `SELKA_OPTIONS` value, as the runtime reads it: an option
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
    const built = try parse(a, .build, &.{ "prog.selka", "-o", "out", "--release", "--qbe=/q", "--zig", "/z", "--cache-dir=c", "--whole-program" }, "zig", &failure);
    try std.testing.expectEqualStrings("out", built.build.output);
    try std.testing.expect(built.build.mode == .release and built.run == null);
    try std.testing.expectEqualStrings("/z", built.build.zig);
    try std.testing.expectEqualStrings("c", built.build.cache);
    const ran = try parse(a, .run, &.{ "p.selka", "--max-steps", "9", "--timeout=3", "--restrict", "--allow-read=d", "--print-result", "--", "--release", "x" }, "zig", &failure);
    try std.testing.expectEqual(@as(?u64, 9), ran.run.?.limits.steps);
    try std.testing.expectEqual(@as(?u64, 3), ran.run.?.limits.timeout);
    try std.testing.expect(ran.build.mode == .lean_debug);
    try std.testing.expectEqual(@as(usize, 3), ran.run.?.options.len);
    try std.testing.expectEqual(@as(usize, 2), ran.run.?.arguments.len);
    const through = try parse(a, .build, &.{ "p.selka", "--run", "--max-memory=1G", "--", "a" }, "zig", &failure);
    try std.testing.expectEqual(@as(?u64, 1 << 30), through.run.?.limits.memory);
    try std.testing.expectError(error.Usage, parse(a, .build, &.{ "p.selka", "--max-steps=5", "-o", "out" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--max-frames", "0" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--allow-read=" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--allow-endpoint=localhost:9" }, "zig", &failure));
    // `*` in place of the address grants every endpoint or listener, as a built program's `SELKA_OPTIONS` reads it (FR19); a
    // pattern around it, or beside nothing, is still refused, and each grant counts toward the eight.
    const every = try parse(a, .run, &.{ "p.selka", "--restrict", "--allow-endpoint=*", "--allow-listen=*" }, "zig", &failure);
    try std.testing.expectEqual(@as(usize, 3), every.run.?.options.len);
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--allow-endpoint=127.0.0.1:*" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--allow-endpoint=**" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--allow-listen=*:80" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--allow-endpoint=" }, "zig", &failure));
    const nine = [_][]const u8{
        "p.selka",
        "--allow-endpoint=*",
        "--allow-endpoint=127.0.0.1:1",
        "--allow-endpoint=127.0.0.1:2",
        "--allow-endpoint=127.0.0.1:3",
        "--allow-endpoint=127.0.0.1:4",
        "--allow-endpoint=127.0.0.1:5",
        "--allow-endpoint=127.0.0.1:6",
        "--allow-endpoint=127.0.0.1:7",
        "--allow-endpoint=127.0.0.1:8",
    };
    try std.testing.expectError(error.Usage, parse(a, .run, &nine, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--allow-env=PATH", "--allow-env" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--allow-all", "--allow-clock" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--allow-process", "--allow-process" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--allow-all", "--allow-process" }, "zig", &failure));
    const processing = try parse(a, .run, &.{ "p.selka", "--restrict", "--allow-process" }, "zig", &failure);
    try std.testing.expect(processing.run != null);
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--backend", "qbe" }, "zig", &failure));
    try std.testing.expect(failure == .retired);
    const reported = try parse(a, .run, &.{ "p.selka", "--report", "--no-cache", "--timings" }, "zig", &failure);
    try std.testing.expect(reported.build.show.cache_report == .json and reported.no_cache and reported.run.?.timings);
    // A cold build keeps out of the shared stage store too (NO-CACHE-COLD-1), and only a build that asked for it.
    try std.testing.expect(reported.build.show.compiler_cache_disabled);
    const warm = try parse(a, .run, &.{"p.selka"}, "zig", &failure);
    try std.testing.expect(!warm.build.show.compiler_cache_disabled and !warm.no_cache);
    try std.testing.expectError(error.Usage, parse(a, .build, &.{ "p.selka", "-o", "out", "--timings" }, "zig", &failure));
    try std.testing.expectEqualStrings("--x \"a b\" \"q\\\"\"", try encodeOptions(a, &.{ "--x", "a b", "q\"" }));
}

test "--cpu names the CPU model of the host target for build, run and build --run, before or after --target, and refuses any other word" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: Failure = .usage;
    const plain = try parse(a, .build, &.{ "p.selka", "-o", "out" }, "zig", &failure);
    try std.testing.expectEqual(target.Cpu.native, plain.build.show.codegen.target.cpuModel());
    try std.testing.expectEqualStrings("-march=native", plain.build.show.codegen.target.cpu_flags[0]);
    const explicit = try parse(a, .build, &.{ "p.selka", "-o", "out", "--cpu=native" }, "zig", &failure);
    try std.testing.expectEqualStrings("-march=native", explicit.build.show.codegen.target.cpu_flags[0]);
    const floor = try parse(a, .build, &.{ "p.selka", "-o", "out", "--cpu=x86-64-v3" }, "zig", &failure);
    try std.testing.expectEqual(target.Cpu.x86_64_v3, floor.build.show.codegen.target.cpuModel());
    try std.testing.expectEqual(target.Cpu.x86_64_v3, floor.cpu);
    try std.testing.expectEqualStrings("-march=x86_64_v3", floor.build.show.codegen.target.cpu_flags[0]);
    const spaced = try parse(a, .run, &.{ "p.selka", "--cpu", "x86-64-v3" }, "zig", &failure);
    try std.testing.expectEqual(target.Cpu.x86_64_v3, spaced.build.show.codegen.target.cpuModel());
    const running = try parse(a, .build, &.{ "p.selka", "--run", "--cpu=x86-64-v3" }, "zig", &failure);
    try std.testing.expect(running.run != null and running.build.show.codegen.target.cpuModel() == .x86_64_v3);
    const either = try parse(a, .build, &.{ "p.selka", "--cpu=x86-64-v3", "--target", "x86_64-linux", "-o", "out" }, "zig", &failure);
    try std.testing.expectEqual(target.Cpu.x86_64_v3, either.build.show.codegen.target.cpuModel());
    try std.testing.expectError(error.Usage, parse(a, .build, &.{ "p.selka", "-o", "out", "--cpu=bogus" }, "zig", &failure));
    try std.testing.expectEqualStrings("unknown --cpu value `bogus`; the values are `native` and `x86-64-v3`", failure.retired);
    try std.testing.expectError(error.Usage, parse(a, .build, &.{ "p.selka", "-o", "out", "--cpu" }, "zig", &failure));
    try std.testing.expect(failure == .usage);
    // A bare target has no x86 CPU model: the model is refused, and `native` changes nothing.
    try std.testing.expectError(error.Usage, parse(a, .build, &.{ "p.selka", "-o", "out", "--target", "thumbv6m-none", "--cpu=x86-64-v3" }, "zig", &failure));
    try std.testing.expect(std.mem.indexOf(u8, failure.retired, "--cpu x86-64-v3 is for the hosted target") != null);
    const bare = try parse(a, .build, &.{ "p.selka", "-o", "out", "--target", "thumbv6m-none", "--cpu=native" }, "zig", &failure);
    try std.testing.expectEqual(&target.thumbv6m_none, bare.build.show.codegen.target);
}

// spec-case: NATIVE-ARGV-1
// spec: QBE-STEP-ACCOUNTING-1
test "--threads is a run setting from 1 to 256, and a build refuses it (E1c)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: Failure = .usage;
    const request = try parse(a, .run, &.{ "p.selka", "--threads", "4" }, "zig", &failure);
    try std.testing.expectEqual(@as(?u64, 4), request.run.?.threads);
    const eight = try parse(a, .run, &.{ "p.selka", "--threads=256" }, "zig", &failure);
    try std.testing.expectEqual(@as(?u64, 256), eight.run.?.threads);
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--threads", "0" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--threads", "257" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--threads", "2", "--threads", "3" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .build, &.{ "p.selka", "-o", "out", "--threads", "2" }, "zig", &failure));
}

test "harness step accounting is build-only and does not enable user build budgets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: Failure = .usage;
    const harness = try parse(a, .build, &.{ "p.selka", "-o", "out", "--test-step-budget" }, "zig", &failure);
    try std.testing.expect(harness.build.show.codegen.harness_steps);
    try std.testing.expectError(error.Usage, parse(a, .run, &.{ "p.selka", "--test-step-budget" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .build, &.{ "p.selka", "--run", "--test-step-budget" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .build, &.{ "p.selka", "-o", "out", "--max-steps=5" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .build, &.{ "p.selka", "-o", "out", "--test-step-budget", "--max-steps=5" }, "zig", &failure));
    try std.testing.expectError(error.Usage, parse(a, .build, &.{ "p.selka", "-o", "out", "--test-step-budget", "--test-step-budget" }, "zig", &failure));
}
