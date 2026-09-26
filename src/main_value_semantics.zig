//! The `--value-semantics` switch at the command line (`VALUE-SEMANTICS-1`).
//!
//! The switch is settled before any command runs. It is on when the command
//! line names `--value-semantics` (before any `--` that starts guest
//! arguments), when the entry's `mylang.json` says `"value_semantics": true`,
//! or when the environment carries `MYLANG_VALUE_SEMANTICS=1`. The environment
//! variable is the one carrier every child compiler a command spawns inherits
//! (the build driver's frontend, the test runner's builds, a directory test's
//! per-file runs), so a command turned on any other way first replaces itself
//! with the same command, flag removed, and the variable set. From then on
//! every process of the command sees the same switch, and the environment
//! fingerprint that keys cached test results sees it too.
const std = @import("std");
const language = @import("mylang");
const project_config = @import("project_config.zig");

const values = language.value_semantics;

/// The commands that accept `--value-semantics`: every command that checks,
/// builds or runs a program, and the inspection commands that show its IL.
const commands = [_][]const u8{ "check", "check-project", "build", "run", "run-project", "test", "emit-qbe", "emit-project-qbe", "dump-bytecode" };

/// Failures settling the switch: memory, and writing a refusal to stderr.
pub const Error = std.mem.Allocator.Error || std.Io.File.Writer.Error;

/// What `settle` decided: run the command with these arguments (the switch is
/// set when `enabled`), or exit with `status` because the command was replaced
/// or refused.
pub const Settled = union(enum) {
    run: struct { args: []const [:0]const u8, enabled: bool },
    status: u8,
};

/// Settle the switch for this process; see the module comment.
pub fn settle(process: std.process.Init, args: []const [:0]const u8) Error!Settled {
    const flag = position(args);
    const inherited = values.environmentEnables(process.environ_map.get(values.variable));
    if (flag != null and !accepts(args[1])) {
        try std.Io.File.stderr().writeStreamingAll(process.io, "mylang: --value-semantics applies to check, check-project, build, run, run-project, test, emit-qbe, emit-project-qbe and dump-bytecode\n");
        return .{ .status = 2 };
    }
    if (!inherited) {
        const configured = flag == null and args.len >= 2 and accepts(args[1]) and configuredOn(process, args);
        if (flag == null and !configured) return .{ .run = .{ .args = args, .enabled = false } };
        return .{ .status = try replace(process, args, flag) };
    }
    values.setEnabled(true);
    return .{ .run = .{ .args = if (flag) |index| try without(process.arena.allocator(), args, index) else args, .enabled = true } };
}

/// The index of `--value-semantics` before any `--`, or null.
fn position(args: []const [:0]const u8) ?usize {
    if (args.len < 3) return null;
    for (args[2..], 2..) |arg, index| {
        if (std.mem.eql(u8, arg, "--")) return null;
        if (std.mem.eql(u8, arg, values.option)) return index;
    }
    return null;
}

fn accepts(command: []const u8) bool {
    for (commands) |name| if (std.mem.eql(u8, name, command)) return true;
    return false;
}

/// Whether the `mylang.json` nearest the command's first path argument turns
/// the switch on. A configuration that does not load is not read here: the
/// command itself reports it.
fn configuredOn(process: std.process.Init, args: []const [:0]const u8) bool {
    const a = process.arena.allocator();
    const entry = firstPath(args) orelse return false;
    const found = project_config.discover(a, process.io, entry) catch return false;
    const path = found orelse return false;
    var failure: project_config.Failure = .{};
    var config = project_config.load(a, process.io, path, &failure) catch return false;
    defer config.deinit();
    return config.document.value_semantics;
}

/// The first argument after the command that is not an option.
fn firstPath(args: []const [:0]const u8) ?[]const u8 {
    if (args.len < 3) return null;
    for (args[2..]) |arg| {
        if (std.mem.eql(u8, arg, "--")) return null;
        if (arg.len != 0 and arg[0] != '-') return arg;
    }
    return null;
}

fn without(a: std.mem.Allocator, args: []const [:0]const u8, index: usize) Error![]const [:0]const u8 {
    const kept = try a.alloc([:0]const u8, args.len - 1);
    @memcpy(kept[0..index], args[0..index]);
    @memcpy(kept[index..], args[index + 1 ..]);
    return kept;
}

/// Replace this process with the same command, `--value-semantics` removed
/// and `MYLANG_VALUE_SEMANTICS=1` in its environment. Returns only when the
/// replacement fails.
fn replace(process: std.process.Init, args: []const [:0]const u8, flag: ?usize) Error!u8 {
    const a = process.arena.allocator();
    try process.environ_map.put(values.variable, "1");
    const self = std.Io.Dir.cwd().realPathFileAlloc(process.io, "/proc/self/exe", a) catch |err| return failed(process, err);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(a, self);
    for (args[1..], 1..) |arg, index| if (flag == null or index != flag.?) try argv.append(a, arg);
    const err = std.process.replace(process.io, .{ .argv = argv.items, .environ_map = process.environ_map });
    return failed(process, err);
}

fn failed(process: std.process.Init, err: anyerror) Error!u8 {
    var buffer: [160]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, "mylang: --value-semantics: cannot restart the compiler ({s})\n", .{@errorName(err)}) catch "mylang: --value-semantics: cannot restart the compiler\n";
    try std.Io.File.stderr().writeStreamingAll(process.io, message);
    return 2;
}
