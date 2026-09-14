//! Build a checked compilation with the native backend and run it in a child process.
//!
//! Unit tests execute guest programs the way `mylang run` does: one
//! content-addressed native build, then one process. Executables are cached by
//! manifest identity under the directory the build script supplies, so a program
//! whose emitted units are unchanged is spawned rather than rebuilt. The
//! toolchain and the cache itself come from the process wiring, resolved once.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const cache_api = @import("qbe_build_cache.zig");
const native_build = @import("qbe_build.zig");
const wiring = @import("wiring/native_session.zig");
const language = @import("compiler.zig");

/// Native build, tool and child-process failures a guest execution can report.
pub const Error = wiring.Error || language.EmitNativeError || std.process.RunError ||
    error{UnreadableNativeResult};

/// One native stack frame the runtime reported beneath a trap.
pub const Frame = struct { function: []const u8, path: []const u8, line: u64, column: u64 };

/// A native trap: the runtime code, the source position, and the reported frames.
pub const Trap = struct {
    code: []const u8,
    path: []const u8 = "",
    line: u64 = 0,
    column: u64 = 0,
    frames: []const Frame = &.{},
};

/// A scalar entry-point result, or the source-located trap that ended the run.
pub const Result = union(enum) { value: i64, trap: Trap };

/// One native execution: the entry outcome, the guest's own streams, and the exit status.
pub const Run = struct {
    result: Result,
    stdout: []const u8,
    stderr: []const u8,
    status: u8,

    /// The trap code, or an empty string when the entry point returned normally.
    pub fn code(self: Run) []const u8 {
        return switch (self.result) {
            .value => "",
            .trap => |trap| trap.code,
        };
    }
};

/// Execution budgets, collection stress, and the working directory for one run.
pub const Options = struct {
    max_steps: ?u64 = null,
    max_frames: ?u64 = null,
    gc_stress: bool = false,
    /// Capability grants and any other switches the native runtime accepts.
    arguments: []const []const u8 = &.{},
    directory: ?[]const u8 = null,
};

/// Build one checked compilation natively and run it once with default budgets.
pub fn run(compilation: *language.Compilation) Error!Run {
    return runWithOptions(compilation, .{});
}

/// Build one checked compilation natively and run it once under explicit options.
pub fn runWithOptions(compilation: *language.Compilation, options: Options) Error!Run {
    return spawn(try program(compilation), options);
}

/// Build one checked compilation natively and return the cached executable's path.
pub fn program(compilation: *language.Compilation) Error![]const u8 {
    const session = try wiring.acquire();
    var scratch = std.heap.ArenaAllocator.init(session.allocator());
    defer scratch.deinit();
    const work = scratch.allocator();
    const manifest = try compilation.emitQbe(work);
    const identity = try fs.hash(work, try std.mem.concat(work, u8, &.{ session.toolchain.environment, manifest }));
    const path = try std.fmt.allocPrint(session.allocator(), "{s}/exe/{s}", .{ session.toolchain.directory, identity });
    if (std.Io.Dir.cwd().access(session.io, path, .{ .execute = true })) |_| return path else |_| {}
    try link(session, manifest, path);
    return path;
}

fn link(session: *wiring.Session, manifest: []const u8, output: []const u8) Error!void {
    var context = try fs.Context.init(session.allocator(), session.io, &session.environ);
    defer context.deinit();
    const temporary = try context.temporary(session.toolchain.directory);
    defer context.remove(temporary);
    const cache: cache_api.Cache = .{
        .context = context,
        .directory = session.toolchain.directory,
        .temporary = temporary,
        .assets = session.toolchain.assets,
        .environment = session.toolchain.environment,
        .zig = session.toolchain.zig,
        .qbe = session.toolchain.qbe,
        .mode = "Debug",
    };
    const document = try std.json.parseFromSlice(std.json.Value, context.allocator, manifest, .{ .allocate = .alloc_always });
    _ = try native_build.assemble(cache, wiring.settings(), document.value, output);
}

fn spawn(executable: []const u8, options: Options) Error!Run {
    const session = try wiring.acquire();
    const allocator = session.allocator();
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ executable, "--print-result" });
    if (options.max_steps) |steps| try argv.append(allocator, try std.fmt.allocPrint(allocator, "--max-steps={d}", .{steps}));
    if (options.max_frames) |frames| try argv.append(allocator, try std.fmt.allocPrint(allocator, "--max-frames={d}", .{frames}));
    if (options.gc_stress) try argv.append(allocator, "--gc-stress");
    try argv.appendSlice(allocator, options.arguments);
    const outcome = try std.process.run(allocator, session.io, .{
        .argv = argv.items,
        .cwd = if (options.directory) |directory| .{ .path = directory } else .inherit,
        .stdout_limit = .limited(64 * 1024 * 1024),
        .stderr_limit = .limited(4 * 1024 * 1024),
    });
    const status = fs.exitCode(outcome.term);
    if (status != 0) {
        const trap = parse(allocator, outcome.stderr) catch Trap{ .code = "" };
        return .{ .result = .{ .trap = trap }, .stdout = outcome.stdout, .stderr = outcome.stderr, .status = status };
    }
    const reported = try divide(outcome.stdout);
    return .{ .result = .{ .value = reported.value }, .stdout = reported.output, .stderr = outcome.stderr, .status = status };
}

/// Separate the guest's own output from the entry result line `--print-result` appends.
fn divide(text: []const u8) Error!struct { output: []const u8, value: i64 } {
    if (text.len == 0 or text[text.len - 1] != '\n') return error.UnreadableNativeResult;
    const body = text[0 .. text.len - 1];
    const start = if (std.mem.lastIndexOfScalar(u8, body, '\n')) |index| index + 1 else 0;
    const value = std.fmt.parseInt(i64, body[start..], 10) catch return error.UnreadableNativeResult;
    return .{ .output = text[0..start], .value = value };
}

/// Recover the trap code, its source position and the reported frames from stderr.
fn parse(allocator: std.mem.Allocator, text: []const u8) Error!Trap {
    var lines = std.mem.splitScalar(u8, text, '\n');
    const first = lines.first();
    var frames: std.ArrayList(Frame) = .empty;
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "  in ")) continue;
        const split = std.mem.lastIndexOf(u8, line, " at ") orelse continue;
        const place = position(line[split + 4 ..]) orelse continue;
        try frames.append(allocator, .{ .function = line[5..split], .path = place.path, .line = place.line, .column = place.column });
    }
    if (std.mem.indexOf(u8, first, ": error[")) |marker| {
        const rest = first[marker + 8 ..];
        const close = std.mem.indexOfScalar(u8, rest, ']') orelse return error.UnreadableNativeResult;
        const place = position(first[0..marker]) orelse return error.UnreadableNativeResult;
        return .{ .code = rest[0..close], .path = place.path, .line = place.line, .column = place.column, .frames = frames.items };
    }
    const colon = std.mem.indexOfScalar(u8, first, ':') orelse return error.UnreadableNativeResult;
    return .{ .code = first[0..colon], .frames = frames.items };
}

/// Split a trailing `path:line:column` locator, which paths may themselves contain colons.
fn position(text: []const u8) ?struct { path: []const u8, line: u64, column: u64 } {
    const last = std.mem.lastIndexOfScalar(u8, text, ':') orelse return null;
    const previous = std.mem.lastIndexOfScalar(u8, text[0..last], ':') orelse return null;
    const line = std.fmt.parseInt(u64, text[previous + 1 .. last], 10) catch return null;
    const column = std.fmt.parseInt(u64, text[last + 1 ..], 10) catch return null;
    return .{ .path = text[0..previous], .line = line, .column = column };
}

test "native execution reports entry results, guest output and located traps" {
    const source =
        \\def main() -> i64:
        \\    print("hello")
        \\    return 7
    ;
    var compilation = try language.Compilation.init(std.testing.allocator, "run.my", source);
    defer compilation.deinit();
    const outcome = try run(&compilation);
    try std.testing.expectEqual(@as(i64, 7), outcome.result.value);
    try std.testing.expectEqualStrings("hello\n", outcome.stdout);
    try std.testing.expectEqual(@as(u8, 0), outcome.status);
    var trapped = try language.Compilation.init(std.testing.allocator, "trap.my",
        \\def main() -> i64:
        \\    return divtrunc(1, 0)
    );
    defer trapped.deinit();
    const failure = try run(&trapped);
    try std.testing.expectEqualStrings("R_DIVISION_BY_ZERO", failure.result.trap.code);
    try std.testing.expectEqual(@as(u64, 2), failure.result.trap.line);
    try std.testing.expectEqual(@as(u8, 1), failure.status);
}

test "native execution honours step budgets and separates the result line from output" {
    var compilation = try language.Compilation.init(std.testing.allocator, "budget.my",
        \\def main() -> i64:
        \\    while True:
        \\        pass
        \\    return 0
    );
    defer compilation.deinit();
    const limited = try runWithOptions(&compilation, .{ .max_steps = 17 });
    try std.testing.expectEqualStrings("R_STEP_LIMIT", limited.code());
    try std.testing.expectEqualStrings("", limited.stdout);
    const divided = try divide("a\nb\n12\n");
    try std.testing.expectEqualStrings("a\nb\n", divided.output);
    try std.testing.expectEqual(@as(i64, 12), divided.value);
    try std.testing.expectError(error.UnreadableNativeResult, divide("no newline"));
}
