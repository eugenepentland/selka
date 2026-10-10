//! `mylang run`, `run-project` and `build --run` on the new core (NEW-CORE-S5-RUN-1):
//! build the program with its budget installed by `main`, run it with the grants and
//! `--print-result` in `MYLANG_OPTIONS` and the arguments after `--`, and adopt its
//! exit status. A trap exits 1, a check error 1, a usage or host failure 2.
//! `--no-cache` builds through a private cache (NEW-CORE-S5-NO-CACHE-1) and
//! `--timings` reports the program's run time (NEW-CORE-S5-TIMINGS-1).
const std = @import("std");
const language = @import("mylang");
const pipeline = @import("pipeline.zig");
const cli_args = @import("cli_args.zig");
const run_budget = @import("run_budget.zig");
const memory_budget = @import("memory_budget");
const trap_contract = @import("trap_contract.zig");

/// The machine record line the runtime writes after a trap's text.
const trap_marker = "\x1eMYLANG-TRAP ";
/// Native stack a `--max-frames` budget reserves per frame, as the runtime's tests map it.
const frame_stack: u64 = 32 << 10;
/// The largest entry file a run reads, as the old CLI read it.
const source_limit: u64 = 16 << 20;
/// Native stack beyond the per-frame share.
const stack_slack: u64 = 8 << 20;

/// What stops a run before the program's status is known: memory, or standard
/// error cannot be written.
pub const Error = @import("mylang").frontend_runtime.HostError || error{WriteFailed};

/// `mylang run`'s usage, which a malformed run command line prints.
pub const run_usage =
    \\usage: mylang run <file.my> [options] [-- ARGS...]
    \\       mylang run-project <entry.my> [options] [-- ARGS...]
    \\  builds the program natively and runs it; every value after -- is a guest argument
    \\  budgets (each takes --flag N or --flag=N; N is a positive integer):
    \\    --max-steps N      instruction ceiling (default: unbounded)
    \\    --max-frames N     call-depth ceiling (default: unbounded); each frame reserves 32 KiB of --max-memory
    \\    --timeout N        elapsed-time cap in seconds
    \\    --max-memory SIZE  guest byte ceiling, K/M/G suffixes (default 4G; MYLANG_MEMORY_LIMIT names the same)
    \\  output: --print-result --diagnostics=text|json --timings (the program's run time on stderr)
    \\  build (default: optimized debug): --release | --unoptimized | --optimize-debug; --zig=PATH --cache-dir=DIR --no-cache --report (one cache-report-v1 line on stderr)
    \\  authority: --restrict --allow-read=DIR --allow-write=DIR --allow-endpoint=IP:PORT --allow-clock
    \\             --allow-random[=SEED] --allow-env[=NAME,...] --allow-host --allow-all
    \\  `mylang --help` lists every command
    \\
;

/// The guest `zig`: `ZIG`, else `MYLANG_ZIG`, else `zig` from `PATH`; `--zig` outranks it.
pub fn zigPath(init: std.process.Init) []const u8 {
    return init.environ_map.get("ZIG") orelse init.environ_map.get("MYLANG_ZIG") orelse "zig";
}

/// Parse a `build` or `run` command line, or print `usage` (or the retirement an option
/// names) and return null.
pub fn parseRequest(init: std.process.Init, command: cli_args.Command, args: []const []const u8, usage: []const u8) Error!?cli_args.Request {
    var failure: cli_args.Failure = .usage;
    const request = cli_args.parse(init.arena.allocator(), command, args, zigPath(init), &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Usage => {
            switch (failure) {
                .usage => try writeStderr(init, usage),
                .retired => |message| try writeStderr(init, try std.fmt.allocPrint(init.arena.allocator(), "mylang: {s}\n", .{message})),
            }
            return null;
        },
    };
    return request;
}

/// `mylang run` and `run-project` (`name`): the same command; a project entry is found
/// from the file.
pub fn runCommand(init: std.process.Init, name: []const u8, args: []const []const u8) Error!u8 {
    const request = try parseRequest(init, .run, args, run_usage) orelse return 2;
    return run(init, request, name);
}

fn writeStderr(init: std.process.Init, text: []const u8) Error!void {
    std.Io.File.stderr().writeStreamingAll(init.io, text) catch return error.WriteFailed;
}

/// Build `request.path` and run it as `command` (`run`, `run-project` or `build`).
pub fn run(init: std.process.Init, request: cli_args.Request, command: []const u8) Error!u8 {
    const a = init.arena.allocator();
    const json = request.build.show.diagnostics == .json;
    if (try unreadable(init, command, request.path)) |message| {
        try emit(init, message, json);
        return 2;
    }
    var report: std.ArrayList(u8) = .empty;
    const budget = (try budgetFor(init, request, command, &report)) orelse {
        try emit(init, report.items, json);
        return 2;
    };
    var options = request.build;
    const directory = try std.fmt.allocPrint(a, "{s}/run-{d}", .{ options.cache, std.os.linux.getpid() });
    std.Io.Dir.cwd().createDirPath(init.io, directory) catch |err| return hostFailure(init, command, "create", err);
    defer discard(init.io, directory);
    const absolute = std.Io.Dir.cwd().realPathFileAlloc(init.io, directory, a) catch |err| return hostFailure(init, command, "create", err);
    options.output = try std.fs.path.join(a, &.{ absolute, std.fs.path.stem(request.path) });
    // `--no-cache` builds through a cache private to this run, removed with its directory.
    if (request.no_cache) options.cache = try privateCache(init, absolute);
    _ = pipeline.buildRun(init, request.path, options, budget, &report) catch |err| {
        try emit(init, report.items, json);
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.SourceError, error.Unsupported => 1,
            error.PolicyDenied => 3,
            error.ConfigurationFailed => 2,
            error.ToolFailed, error.WriteFailed, error.InvalidIr, error.CacheMiss => 2,
            else => @import("mylang").frontend_runtime.hostFailure(err).?,
        };
    };
    try emit(init, report.items, json);
    const status = try execute(init, options.output, request.run.?, budget.frames, json);
    return status;
}

/// An empty private cache under `base` for `build --no-cache` and `test --no-cache`; the
/// build and the runner create its directories, and the caller removes it with `discard`.
pub fn privateCache(init: std.process.Init, base: []const u8) error{OutOfMemory}![]const u8 {
    const directory = try std.fmt.allocPrint(init.arena.allocator(), "{s}/no-cache-{d}", .{ base, std.os.linux.getpid() });
    // A directory a killed run with the same process id left behind must not be read.
    discard(init.io, directory);
    return directory;
}

/// Report a failure of the host around the program (its directory, its process) and
/// return the host-failure status.
fn hostFailure(init: std.process.Init, command: []const u8, what: []const u8, err: anyerror) Error!u8 {
    const message = try std.fmt.allocPrint(init.arena.allocator(), "mylang {s}: host failure: cannot {s} the program: {s}\n", .{ command, what, @errorName(err) });
    std.Io.File.stderr().writeStreamingAll(init.io, message) catch return error.WriteFailed;
    return 2;
}

/// Remove a run's private directory; one left behind costs disk, not correctness.
pub fn discard(io: std.Io, directory: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, directory) catch return;
}

/// The refusal of an entry that is missing, unreadable or a directory, worded as the
/// old CLI words it, or null when the file can be read.
pub fn unreadable(init: std.process.Init, command: []const u8, path: []const u8) error{OutOfMemory}!?[]const u8 {
    const why: []const u8 = why: {
        var file = std.Io.Dir.cwd().openFile(init.io, path, .{}) catch |err| break :why switch (err) {
            error.FileNotFound => "no such file or directory",
            error.AccessDenied, error.PermissionDenied => "permission denied",
            else => @errorName(err),
        };
        defer file.close(init.io);
        const stat = file.stat(init.io) catch |err| break :why @errorName(err);
        if (stat.kind == .directory) break :why "is a directory, not a file";
        if (stat.size <= source_limit) return null;
        const message = try std.fmt.allocPrint(init.arena.allocator(), "mylang {s}: host failure: '{s}' is larger than 16 MiB (FileTooBig)\n", .{ command, path });
        return message;
    };
    const message = try std.fmt.allocPrint(init.arena.allocator(), "mylang {s}: cannot read '{s}': {s}\n", .{ command, path, why });
    return message;
}

/// The run's budget: each limit from the command line, else (memory) from
/// `MYLANG_MEMORY_LIMIT`, else from the project's `limits.run`, else the default:
/// unbounded steps and frames, a 4 GiB byte ceiling, no wall-clock limit. Null, with
/// the reason in `report`, when the budget cannot be honoured.
fn budgetFor(init: std.process.Init, request: cli_args.Request, command: []const u8, report: *std.ArrayList(u8)) error{OutOfMemory}!?run_budget.RunBudget {
    const a = init.arena.allocator();
    const limits = request.run.?.limits;
    var configured: language.project_config.CommandLimits = .{};
    var scratch: std.ArrayList(u8) = .empty;
    if (pipeline.resolveEntry(init, request.path, &scratch)) |entry| {
        if (entry.configuration) |found| configured = found.document.limits.run;
    } else |err| if (err == error.OutOfMemory) return error.OutOfMemory;
    const fallback = configured.max_memory orelse memory_budget.run_default;
    const memory = memory_budget.resolve(limits.memory, init.environ_map, memory_budget.variable, fallback) catch {
        try report.print(a, "mylang {s}: {s} is not a byte size\n", .{ command, memory_budget.variable });
        return null;
    };
    const steps = limits.steps orelse configured.max_steps orelse 0;
    const frames = limits.frames orelse configured.max_frames orelse 0;
    const timeout = limits.timeout orelse 0;
    if (frames != 0) if (try memory_budget.frameRefusal(a, init.environ_map, command, "a guest", frames, memory)) |refusal| {
        try report.appendSlice(a, refusal);
        return null;
    };
    if (frames > std.math.maxInt(u32) or timeout > std.math.maxInt(u32)) {
        try report.print(a, "mylang {s}: a budget is too large\n", .{command});
        return null;
    }
    return .{ .steps = steps, .frames = @intCast(frames), .memory = memory, .timeout_seconds = @intCast(timeout) };
}

/// Run the built program and return its status: its own exit status, or 128 plus
/// the signal that ended it.
fn execute(init: std.process.Init, program: []const u8, settings: cli_args.Run, frames: u32, json: bool) Error!u8 {
    const a = init.arena.allocator();
    var environment = init.environ_map.clone(a) catch return error.OutOfMemory;
    if (settings.options.len == 0) {
        _ = environment.swapRemove("MYLANG_OPTIONS");
    } else {
        try environment.put("MYLANG_OPTIONS", try cli_args.encodeOptions(a, settings.options));
    }
    const argv = try std.mem.concat(a, []const u8, &.{ &.{program}, settings.arguments });
    // The program inherits the caller's address space, not the compiler's own
    // ceiling, and a stack deep enough for its frame budget.
    restoreAddressSpace(init.environ_map);
    deepenStack(frames);
    const started = std.Io.Timestamp.now(init.io, .awake);
    const options: @import("process_spawn.zig").Options = .{ .argv = argv, .environment = .{ .map = &environment }, .stdin = .inherit, .stderr = .pipe };
    var child = @import("process_spawn.zig").spawn(init.gpa, options) catch |err| return hostFailure(init, "run", "start", err);
    if (json) {
        var buffer: [4096]u8 = undefined;
        var reader = child.stderr.?.readerStreaming(init.io, &buffer);
        const captured = reader.interface.allocRemaining(a, .limited(4 << 20)) catch "";
        std.Io.File.stderr().writeStreamingAll(init.io, try translate(a, captured)) catch return error.WriteFailed;
    } else try forward(init, &child);
    const term = child.wait(init.io) catch |err| return hostFailure(init, "run", "wait for", err);
    if (settings.timings) {
        const elapsed: u64 = @intCast(@max(started.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds, 0));
        const line = try std.fmt.allocPrint(a, "timings: native_ns={d}\n", .{elapsed});
        std.Io.File.stderr().writeStreamingAll(init.io, line) catch return error.WriteFailed;
    }
    return switch (term) {
        .exited => |code| code,
        .signal => |signal| @intCast(@min(255, 128 + @as(u32, @backingInt(signal)))),
        else => 2,
    };
}

/// Give the program the caller's address space back: the compiler bounds its own
/// (`MYLANG_HOST_MEMORY_LIMIT`), and the runtime lowers it to the run's ceiling.
/// `mylang test` restores it for its test processes the same way.
pub fn restoreAddressSpace(environment: *const std.process.Environ.Map) void {
    if (environment.get(memory_budget.checkpoint_variable) == null) return;
    const current = std.posix.getrlimit(.AS) catch return;
    const restored = memory_budget.guestAddressSpaceLimit(environment) orelse std.math.maxInt(u64);
    std.posix.setrlimit(.AS, .{ .cur = @min(restored, current.max), .max = current.max }) catch return;
}

/// A stack deep enough for a frame budget: 32 KiB per frame plus 8 MiB, as a test's.
fn deepenStack(frames: u32) void {
    if (frames == 0) return;
    const wanted = @as(u64, frames) * frame_stack + stack_slack;
    const current = std.posix.getrlimit(.STACK) catch return;
    if (current.cur == std.math.maxInt(u64) or current.cur >= wanted) return;
    std.posix.setrlimit(.STACK, .{ .cur = @min(wanted, current.max), .max = current.max }) catch return;
}

/// Pass the program's standard error through, without the runtime's machine record
/// lines; with `--diagnostics=json`, a trap's text becomes one `diagnostic-v1` record.
fn forward(init: std.process.Init, child: *std.process.Child) Error!void {
    var buffer: [65536]u8 = undefined;
    var reader = child.stderr.?.readerStreaming(init.io, &buffer);
    const stderr = std.Io.File.stderr();
    while (true) {
        const line = reader.interface.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => {
                stderr.writeStreamingAll(init.io, reader.interface.buffered()) catch return error.WriteFailed;
                break;
            },
            error.StreamTooLong => {
                const rest = reader.interface.allocRemaining(init.arena.allocator(), .limited(64 << 20)) catch break;
                stderr.writeStreamingAll(init.io, rest) catch return error.WriteFailed;
                break;
            },
            error.ReadFailed => break,
        };
        if (std.mem.startsWith(u8, line, trap_marker)) continue;
        stderr.writeStreamingAll(init.io, line) catch return error.WriteFailed;
    }
}

/// The program's standard error with its trap, if any, as one `diagnostic-v1` record:
/// the text before the trap's located line passes through, the trap's text and
/// machine record become the record.
fn translate(a: std.mem.Allocator, text: []const u8) error{OutOfMemory}![]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var consumed: usize = 0;
    while (lines.next()) |line| : (consumed = lines.index orelse text.len) {
        var trap = located(line) orelse continue;
        const Frame = struct { function: []const u8, location: Location };
        var frames: std.ArrayList(Frame) = .empty;
        var detail: ?std.json.Value = null;
        while (lines.next()) |rest| {
            if (std.mem.startsWith(u8, rest, trap_marker)) {
                detail = std.json.parseFromSliceLeaky(std.json.Value, a, rest[trap_marker.len..], .{}) catch null;
            } else if (std.mem.startsWith(u8, rest, "  in ")) {
                const split = std.mem.lastIndexOf(u8, rest, " at ") orelse continue;
                const at = place(rest[split + 4 ..]) orelse continue;
                try frames.append(a, .{ .function = rest[5..split], .location = at });
            } else if (trap.location.path.len == 0 and rest.len != 0) {
                // A budget trap's advice line, which the old core reported as the message.
                trap.message = rest;
            }
        }
        const record = std.json.Stringify.valueAlloc(a, .{
            .version = "diagnostic-v1",
            .kind = "diagnostic",
            .diagnostic = .{
                .code = trap.code,
                .severity = "error",
                .message = trap.message,
                .location = trap.location,
                .notes = &[_]u32{},
                .stack = .{ .frames = frames.items, .omitted = 0 },
                .trap_detail = detail,
                .contract = contractOf(trap.code, detail, if (frames.items.len > 1) frames.items[1].location else null),
            },
        }, .{ .emit_null_optional_fields = false }) catch return error.OutOfMemory;
        return std.mem.concat(a, u8, &.{ text[0..consumed], record, "\n" });
    }
    return text;
}

const Location = trap_contract.Location;

/// CONTRACT-TRAP-1: the contract a trap's record names; `caller` is the trap's second frame.
fn contractOf(code: []const u8, detail: ?std.json.Value, caller: ?Location) ?trap_contract.Contract {
    const record = detail orelse return null;
    if (record != .object) return null;
    const operation = record.object.get("operation") orelse return null;
    if (operation != .string) return null;
    return trap_contract.parse(code, operation.string, caller);
}
const Trap = struct { code: []const u8, message: []const u8, location: Location };

/// `PATH:LINE:COLUMN: error[CODE]: MESSAGE`, the first line of a trap's text, or
/// `error[CODE]: MESSAGE` for a budget trap, which has no location.
fn located(line: []const u8) ?Trap {
    if (std.mem.startsWith(u8, line, "error[")) {
        const close = std.mem.indexOf(u8, line, "]: ") orelse return null;
        return .{ .code = line["error[".len..close], .message = line[close + 3 ..], .location = .{ .path = "", .start = .{ .line = 0, .column = 0 } } };
    }
    const marker = std.mem.indexOf(u8, line, ": error[") orelse return null;
    const rest = line[marker + ": error[".len ..];
    const close = std.mem.indexOf(u8, rest, "]: ") orelse return null;
    const at = place(line[0..marker]) orelse return null;
    return .{ .code = rest[0..close], .message = rest[close + 3 ..], .location = at };
}

/// `PATH:LINE:COLUMN`.
fn place(text: []const u8) ?Location {
    const second = std.mem.lastIndexOfScalar(u8, text, ':') orelse return null;
    const first = std.mem.lastIndexOfScalar(u8, text[0..second], ':') orelse return null;
    const line = std.fmt.parseUnsigned(u64, text[first + 1 .. second], 10) catch return null;
    const column = std.fmt.parseUnsigned(u64, text[second + 1 ..], 10) catch return null;
    return .{ .path = text[0..first], .start = .{ .line = line, .column = column } };
}

/// Write the build's report to standard error; in JSON mode every line that is not
/// already a record becomes a `message` record.
fn emit(init: std.process.Init, text: []const u8, json: bool) Error!void {
    const stderr = std.Io.File.stderr();
    if (!json) {
        stderr.writeStreamingAll(init.io, text) catch return error.WriteFailed;
        return;
    }
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const record = if (line[0] == '{') try std.mem.concat(init.arena.allocator(), u8, &.{ line, "\n" }) else try language.diagnostic_output.message(init.arena.allocator(), line, .json);
        stderr.writeStreamingAll(init.io, record) catch return error.WriteFailed;
    }
}
