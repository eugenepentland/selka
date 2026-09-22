//! Build a checked compilation with the native backend and run it in a child process.
//!
//! Unit tests execute guest programs the way `mylang run` does: one
//! content-addressed native build, then one process. Executables are cached by
//! manifest identity in the session's executable generation — one directory per
//! compiler build under the cache the build script supplies, swept when the
//! compiler or its runtime changes — so a program whose emitted units are unchanged is
//! spawned rather than rebuilt and a rebuilt compiler leaves no stale programs
//! behind. The toolchain and the cache itself come from the process wiring,
//! resolved once.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const cache_api = @import("qbe_build_cache.zig");
const native_build = @import("qbe_build.zig");
const wiring = @import("wiring/native_session.zig");
const budget = @import("memory_budget");
const language = @import("compiler.zig");
const trap_detail = @import("native_trap_detail.zig");

/// Native build, tool and child-process failures a guest execution can report.
pub const Error = wiring.Error || language.EmitNativeError ||
    @import("project_compile.zig").EmitNativeError || std.process.RunError ||
    error{UnreadableNativeResult};

/// One native stack frame the runtime reported beneath a trap.
pub const Frame = struct { function: []const u8, path: []const u8, line: u64, column: u64 };

/// A native trap: the runtime code, the source position, the reported frames,
/// and the bounded detail the runtime captured at the failing operation.
pub const Trap = struct {
    code: []const u8,
    path: []const u8 = "",
    line: u64 = 0,
    column: u64 = 0,
    frames: []const Frame = &.{},
    detail: trap_detail.Detail = .{},
};

/// One native execution: the entry point's result, the trap that ended the run,
/// the guest's own streams and the process exit status. A successful run leaves
/// `trap.code` empty and `failed` false; a trapped one leaves `value` at zero.
/// The status is the program's own exit code — the entry `int` truncated to the
/// low 8 bits on a normal return, or the diagnostic status on a trap — so it no
/// longer distinguishes success from failure on its own; `failed` does.
pub const Run = struct {
    value: i64 = 0,
    trap: Trap = .{ .code = "" },
    stdout: []const u8 = "",
    stderr: []const u8 = "",
    status: u8 = 0,
    failed: bool = false,

    /// Whether the native runtime ended this program with a trap rather than a
    /// normal return. A nonzero status alone no longer implies a trap, because a
    /// program that returns a nonzero value exits with it.
    pub fn trapped(self: Run) bool {
        return self.failed;
    }
};

/// Execution budgets, collection stress, and the working directory for one run.
pub const Options = struct {
    max_steps: ?u64 = null,
    max_frames: ?u64 = null,
    gc_stress: bool = false,
    /// Capability grants and any other switches the native runtime accepts,
    /// which travel in `MYLANG_OPTIONS`; values after a `--` are the program's.
    arguments: []const []const u8 = &.{},
    directory: ?[]const u8 = null,
    /// Replaces the inherited environment, which `Environment` capabilities read.
    environment: ?*const std.process.Environ.Map = null,
    /// The guest's address-space ceiling; the per-test default bounds every run.
    max_memory: ?u64 = null,
};

/// Build one checked compilation natively and run it once with the runtime's
/// defaults, which impose no instruction or frame ceiling.
/// The argument is a single-file or a project compilation; both emit QBE units.
pub fn run(compilation: anytype) Error!Run {
    return runWithOptions(compilation, .{});
}

/// Build one checked compilation natively and run it once under explicit options.
pub fn runWithOptions(compilation: anytype, options: Options) Error!Run {
    const session = try wiring.acquire();
    var scratch = std.heap.ArenaAllocator.init(session.allocator());
    defer scratch.deinit();
    const manifest = try compilation.emitQbe(scratch.allocator());
    return spawn(try program(session, manifest), options);
}

/// Publish one emitted manifest as an executable, reusing an identical earlier build.
pub fn program(session: *wiring.Session, manifest: []const u8) Error![]const u8 {
    var scratch = std.heap.ArenaAllocator.init(session.allocator());
    defer scratch.deinit();
    const work = scratch.allocator();
    const identity = try fs.hash(work, try std.mem.concat(work, u8, &.{ session.toolchain.environment, manifest }));
    const path = try std.fmt.allocPrint(session.allocator(), "{s}/{s}", .{ session.toolchain.executables, identity });
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
        .mode = "Debug",
        .codegen = .{ .tool = session.toolchain.qbe },
    };
    const document = try std.json.parseFromSlice(std.json.Value, context.allocator, manifest, .{ .allocate = .alloc_always });
    _ = try native_build.assemble(cache, wiring.settings(), document.value, output);
}

fn spawn(executable: []const u8, options: Options) Error!Run {
    const session = try wiring.acquire();
    const allocator = session.allocator();
    const tail = native_build.runtime_options.split(options.arguments);
    var runtime: std.ArrayList([]const u8) = .empty;
    try runtime.append(allocator, "--print-result");
    if (options.max_steps) |steps| try runtime.append(allocator, try std.fmt.allocPrint(allocator, "--max-steps={d}", .{steps}));
    if (options.max_frames) |frames| try runtime.append(allocator, try std.fmt.allocPrint(allocator, "--max-frames={d}", .{frames}));
    if (options.gc_stress) try runtime.append(allocator, "--gc-stress");
    try runtime.appendSlice(allocator, tail.options);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(allocator, executable);
    try argv.appendSlice(allocator, tail.program);
    const environment = try bounded(session, options);
    try native_build.runtime_options.apply(allocator, environment, runtime.items);
    const outcome = try std.process.run(allocator, session.io, .{
        .argv = argv.items,
        .cwd = if (options.directory) |directory| .{ .path = directory } else .inherit,
        .environ_map = environment,
        .stdout_limit = .limited(64 * 1024 * 1024),
        .stderr_limit = .limited(4 * 1024 * 1024),
    });
    const status = fs.exitCode(outcome.term);
    // The exit status is now the entry's own result, so it cannot mark a trap; a
    // native runtime failure instead writes a diagnostic to stderr (and a crash
    // ends the process by signal). A clean return leaves stderr empty and appends
    // its `--print-result` line to stdout, which `divide` reads.
    if (outcome.term != .exited or outcome.stderr.len != 0) {
        const trap = parse(allocator, outcome.stderr) catch Trap{ .code = "" };
        // The machine record is transport, not a diagnostic: keep `stderr` as the
        // human text the caller saw before structured traps existed.
        const cleaned = trap_detail.strip(allocator, outcome.stderr) catch outcome.stderr;
        return .{ .trap = trap, .stdout = outcome.stdout, .stderr = cleaned, .status = status, .failed = true };
    }
    const reported = try divide(outcome.stdout);
    return .{ .value = reported.value, .stdout = reported.output, .stderr = outcome.stderr, .status = status };
}

/// Every test guest runs under a byte ceiling, so a program that allocates without
/// bound traps with `R_MEMORY_BUDGET` instead of exhausting the machine. A test that
/// supplies its own environment keeps it, with the ceiling added.
fn bounded(session: *wiring.Session, options: Options) Error!*std.process.Environ.Map {
    const allocator = session.allocator();
    const map = try allocator.create(std.process.Environ.Map);
    map.* = try (options.environment orelse &session.environ).clone(allocator);
    const limit = options.max_memory orelse budget.test_default;
    try map.put(budget.variable, try std.fmt.allocPrint(allocator, "{d}", .{limit}));
    return map;
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
    const detail = trap_detail.parse(allocator, text) orelse trap_detail.Detail{};
    var frames: std.ArrayList(Frame) = .empty;
    var diagnostic: []const u8 = "";
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "  in ")) {
            const split = std.mem.lastIndexOf(u8, line, " at ") orelse continue;
            const place = position(line[split + 4 ..]) orelse continue;
            try frames.append(allocator, .{ .function = line[5..split], .path = place.path, .line = place.line, .column = place.column });
            continue;
        }
        // A failure-path assert message may precede the located diagnostic on
        // stderr, so find the diagnostic line instead of taking the first one.
        if (diagnostic.len == 0 and (std.mem.indexOf(u8, line, ": error[") != null or std.mem.startsWith(u8, line, "mylang: --restrict is active"))) diagnostic = line;
    }
    const first = if (diagnostic.len == 0) std.mem.sliceTo(text, '\n') else diagnostic;
    if (std.mem.startsWith(u8, first, "mylang: --restrict is active")) return .{ .code = "CapabilityUnavailable", .frames = frames.items, .detail = detail };
    if (std.mem.indexOf(u8, first, ": error[")) |marker| {
        const rest = first[marker + 8 ..];
        const close = std.mem.indexOfScalar(u8, rest, ']') orelse return error.UnreadableNativeResult;
        const place = position(first[0..marker]) orelse return error.UnreadableNativeResult;
        return .{ .code = rest[0..close], .path = place.path, .line = place.line, .column = place.column, .frames = frames.items, .detail = detail };
    }
    const colon = std.mem.indexOfScalar(u8, first, ':') orelse return error.UnreadableNativeResult;
    return .{ .code = first[0..colon], .frames = frames.items, .detail = detail };
}

/// Split a trailing `path:line:column` locator, which paths may themselves contain colons.
fn position(text: []const u8) ?struct { path: []const u8, line: u64, column: u64 } {
    const last = std.mem.lastIndexOfScalar(u8, text, ':') orelse return null;
    const previous = std.mem.lastIndexOfScalar(u8, text[0..last], ':') orelse return null;
    const line = std.fmt.parseInt(u64, text[previous + 1 .. last], 10) catch return null;
    const column = std.fmt.parseInt(u64, text[last + 1 ..], 10) catch return null;
    return .{ .path = text[0..previous], .line = line, .column = column };
}

/// The name of every section header in an ELF64 image, read through its section
/// name string table, so a test can tell a stripped binary from a debug section
/// name the runtime happens to carry as text in its read-only data.
fn sectionNames(allocator: std.mem.Allocator, bytes: []const u8) ![]const []const u8 {
    const header = std.mem.bytesToValue(std.elf.Elf64_Ehdr, bytes[0..@sizeOf(std.elf.Elf64_Ehdr)]);
    const table = sectionHeader(bytes, header, header.e_shstrndx);
    var names: std.ArrayList([]const u8) = .empty;
    for (0..header.e_shnum) |index| {
        const section = sectionHeader(bytes, header, @intCast(index));
        const start: usize = @intCast(table.sh_offset + section.sh_name);
        const rest = bytes[start..];
        try names.append(allocator, rest[0..std.mem.indexOfScalar(u8, rest, 0).?]);
    }
    return names.items;
}
fn sectionHeader(bytes: []const u8, header: std.elf.Elf64_Ehdr, index: u16) std.elf.Elf64_Shdr {
    const offset: usize = @intCast(header.e_shoff + @as(u64, index) * header.e_shentsize);
    return std.mem.bytesToValue(std.elf.Elf64_Shdr, bytes[offset..][0..@sizeOf(std.elf.Elf64_Shdr)]);
}
fn hasSection(names: []const []const u8, prefix: []const u8) bool {
    for (names) |name| if (std.mem.startsWith(u8, name, prefix)) return true;
    return false;
}

// spec: QBE-STRIP-1
test "a published native executable carries neither debug information nor a symbol table" {
    var compilation = try language.Compilation.init(std.testing.allocator, "lean.my",
        \\def main() -> i64:
        \\    return 3
    );
    defer compilation.deinit();
    const session = try wiring.acquire();
    var scratch = std.heap.ArenaAllocator.init(session.allocator());
    defer scratch.deinit();
    const manifest = try compilation.emitQbe(scratch.allocator());
    const path = try program(session, manifest);
    try std.testing.expect(std.mem.startsWith(u8, path, session.toolchain.executables));
    const bytes = try std.Io.Dir.cwd().readFileAlloc(session.io, path, scratch.allocator(), .unlimited);
    const names = try sectionNames(scratch.allocator(), bytes);
    try std.testing.expect(hasSection(names, ".text"));
    try std.testing.expect(!hasSection(names, ".debug_"));
    try std.testing.expect(!hasSection(names, ".symtab"));
    // Stripping changes nothing the program does: it still runs and returns its value.
    const outcome = try spawn(path, .{});
    try std.testing.expectEqual(@as(i64, 3), outcome.value);
    try std.testing.expect(!outcome.trapped());
}

test "native execution reports entry results, guest output and located traps" {
    const source =
        \\def main(out: Stream) -> i64:
        \\    out.print("hello")
        \\    return 7
    ;
    var compilation = try language.Compilation.init(std.testing.allocator, "run.my", source);
    defer compilation.deinit();
    const outcome = try run(&compilation);
    try std.testing.expectEqual(@as(i64, 7), outcome.value);
    try std.testing.expectEqualStrings("hello\n", outcome.stdout);
    // The entry returned 7, so the process exits 7; the value is not a trap.
    try std.testing.expect(!outcome.trapped());
    try std.testing.expectEqual(@as(u8, 7), outcome.status);
    var trapped = try language.Compilation.init(std.testing.allocator, "trap.my",
        \\def main() -> i64:
        \\    return divtrunc(1, 0)
    );
    defer trapped.deinit();
    const failure = try run(&trapped);
    try std.testing.expectEqualStrings("R_DIVISION_BY_ZERO", failure.trap.code);
    try std.testing.expect(failure.trapped());
    try std.testing.expectEqual(@as(u64, 2), failure.trap.line);
    try std.testing.expectEqual(@as(u8, 1), failure.status);
    try std.testing.expectEqual(trap_detail.Operation.div, failure.trap.detail.operation);
    try std.testing.expectEqual(@as(i64, 1), failure.trap.detail.values.left);
    try std.testing.expectEqual(@as(i64, 0), failure.trap.detail.values.right);
}

// spec: QBE-TRAP-DETAIL-1
test "native execution reports original bounds indexes for read write pop array text and bytes" {
    const Case = struct {
        source: []const u8,
        code: []const u8,
        operation: trap_detail.Operation,
        index: ?i64,
        length: u64,
        /// The human text the runtime rendered from the same structured detail.
        text: []const u8,
    };
    const cases = [_]Case{
        .{ .source = "def main() -> i64:\n    xs = [1]\n    return xs[14]\n", .code = "R_LIST_BOUNDS", .operation = .index, .index = 14, .length = 1, .text = "(index 14, length 1)" },
        .{ .source = "def main() -> i64:\n    xs = [1, 2]\n    return xs[-5]\n", .code = "R_LIST_BOUNDS", .operation = .index, .index = -5, .length = 2, .text = "(index -5, length 2)" },
        .{ .source = "def main() -> i64:\n    xs = [1, 2]\n    xs[-5] = 9\n    return 0\n", .code = "R_LIST_BOUNDS", .operation = .index, .index = -5, .length = 2, .text = "(index -5, length 2)" },
        .{ .source = "def main() -> i64:\n    xs: list[i64] = []\n    return xs.pop()\n", .code = "R_LIST_BOUNDS", .operation = .pop, .index = null, .length = 0, .text = "(length 0)" },
        .{ .source = "def main() -> i64:\n    xs = [1, 2]\n    return xs.pop(7)\n", .code = "R_LIST_BOUNDS", .operation = .pop, .index = 7, .length = 2, .text = "(index 7, length 2)" },
        .{ .source = "def main() -> i64:\n    xs: [3]int = [1, 2, 3]\n    return xs[7]\n", .code = "R_INDEX_BOUNDS", .operation = .index, .index = 7, .length = 3, .text = "(index 7, length 3)" },
        .{ .source = "def main() -> i64:\n    xs: [3]int = [1, 2, 3]\n    xs = replace(xs, 7, 9)\n    return xs[0]\n", .code = "R_INDEX_BOUNDS", .operation = .index, .index = 7, .length = 3, .text = "(index 7, length 3)" },
        .{ .source = "def main() -> i64:\n    s = \"abc\"\n    _ = s[9]\n    return 0\n", .code = "R_TEXT_BOUNDS", .operation = .index, .index = 9, .length = 3, .text = "(index 9, length 3)" },
        .{ .source = "def main() -> i64:\n    b = b\"abc\"\n    _ = b[-9]\n    return 0\n", .code = "R_LIST_BOUNDS", .operation = .index, .index = -9, .length = 3, .text = "(index -9, length 3)" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(std.testing.allocator, "bounds.my", case.source);
        defer compilation.deinit();
        const outcome = try run(&compilation);
        try std.testing.expect(outcome.trapped());
        try std.testing.expectEqualStrings(case.code, outcome.trap.code);
        try std.testing.expectEqual(case.operation, outcome.trap.detail.operation);
        try std.testing.expectEqual(case.length, outcome.trap.detail.values.length);
        try std.testing.expect(outcome.trap.detail.has(trap_detail.present_length));
        if (case.index) |index| {
            try std.testing.expect(outcome.trap.detail.has(trap_detail.present_index));
            try std.testing.expectEqual(index, outcome.trap.detail.values.index);
        } else {
            try std.testing.expect(!outcome.trap.detail.has(trap_detail.present_index));
        }
        // The text diagnostic quotes the same values, without the machine record.
        try std.testing.expect(std.mem.indexOf(u8, outcome.stderr, case.text) != null);
        try std.testing.expect(std.mem.indexOf(u8, outcome.stderr, trap_detail.marker) == null);
    }
}

// spec-case: QBE-TRAP-DETAIL-1
test "native execution keeps the first trap detail and leaves budget traps detail-free" {
    var first = try language.Compilation.init(std.testing.allocator, "first.my",
        \\def main() -> i64:
        \\    return divtrunc(1, 0) + (9223372036854775807 + 1)
    );
    defer first.deinit();
    const outcome = try run(&first);
    try std.testing.expectEqualStrings("R_DIVISION_BY_ZERO", outcome.trap.code);
    try std.testing.expectEqual(trap_detail.Operation.div, outcome.trap.detail.operation);
    var loop = try language.Compilation.init(std.testing.allocator, "budget.my",
        \\def main() -> i64:
        \\    while True:
        \\        pass
        \\    return 0
    );
    defer loop.deinit();
    const limited = try runWithOptions(&loop, .{ .max_steps = 17 });
    try std.testing.expectEqualStrings("R_STEP_LIMIT", limited.trap.code);
    try std.testing.expectEqual(@as(u32, 0), limited.trap.detail.version);
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
    try std.testing.expectEqualStrings("R_STEP_LIMIT", limited.trap.code);
    try std.testing.expectEqualStrings("", limited.stdout);
    const divided = try divide("a\nb\n12\n");
    try std.testing.expectEqualStrings("a\nb\n", divided.output);
    try std.testing.expectEqual(@as(i64, 12), divided.value);
    try std.testing.expectError(error.UnreadableNativeResult, divide("no newline"));
}

// spec: RUNTIME-UNBOUNDED-1
test "a native run completes a loop that outgrows the old default step budget" {
    var compilation = try language.Compilation.init(std.testing.allocator, "unbounded.my",
        \\def main() -> i64:
        \\    i = 0
        \\    while i < 3000000:
        \\        i += 1
        \\    return i
    );
    defer compilation.deinit();
    // A 60-second guard keeps a regression from hanging the test runner; an
    // honest loop that needs tens of millions of steps must still finish.
    const outcome = try runWithOptions(&compilation, .{ .arguments = &.{"--timeout=60"} });
    try std.testing.expect(!outcome.trapped());
    try std.testing.expectEqual(@as(i64, 3000000), outcome.value);
}

// spec: RUNTIME-TIMEOUT-1
test "a wall-clock timeout ends an unbounded native run with R_TIMEOUT" {
    var compilation = try language.Compilation.init(std.testing.allocator, "timeout.my",
        \\def main() -> i64:
        \\    while True:
        \\        pass
        \\    return 0
    );
    defer compilation.deinit();
    const outcome = try runWithOptions(&compilation, .{ .arguments = &.{"--timeout=1"} });
    try std.testing.expect(outcome.trapped());
    try std.testing.expectEqualStrings("R_TIMEOUT", outcome.trap.code);
}
