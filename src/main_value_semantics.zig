//! Value semantics by default, with a one-release legacy-sharing opt-out
//! (`VALUE-SEMANTICS-1`). Explicit flags win over the inherited environment,
//! then the entry's project configuration. The resolved mode is carried into
//! child compilers as `MYLANG_VALUE_SEMANTICS=0|1`, including test-cache keys.
const std = @import("std");
const language = @import("mylang");
const project_config = @import("project_config.zig");

const values = language.value_semantics;
const legacy_option = "--legacy-sharing";
const Flag = struct { index: usize, enabled: bool };

/// The commands that accept `--value-semantics`: every command that checks,
/// builds or runs a program, and the inspection commands that show its IL.
const commands = [_][]const u8{ "check", "check-module", "check-project", "build", "run", "run-project", "test", "emit-qbe", "emit-project-qbe", "dump-bytecode", "fix", "invoke" };

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
    const environment = process.environ_map.get(values.variable);
    if (flag) |selected| if (duplicate(args, selected.index)) {
        try std.Io.File.stderr().writeStreamingAll(process.io, "mylang: choose exactly one of --value-semantics and --legacy-sharing\n");
        return .{ .status = 2 };
    };
    if (flag != null and !accepts(args[1])) {
        try std.Io.File.stderr().writeStreamingAll(process.io, "mylang: --value-semantics and --legacy-sharing apply to check, check-module, check-project, " ++
            "build, run, run-project, test, emit-qbe, emit-project-qbe, dump-bytecode, fix and invoke\n");
        return .{ .status = 2 };
    }
    const inherited: ?bool = if (environment) |value| values.environmentEnables(value) else null;
    const enabled = if (flag) |selected| selected.enabled else inherited orelse (try configuredOn(process, args));
    if (inherited == null or inherited.? != enabled) return .{ .status = try replace(process, args, flag, enabled) };
    values.setEnabled(enabled);
    return .{ .run = .{ .args = if (flag) |selected| try without(process.arena.allocator(), args, selected.index) else args, .enabled = enabled } };
}

/// The first mode flag before any `--`, or null.
fn position(args: []const [:0]const u8) ?Flag {
    if (args.len < 3) return null;
    for (args[2..], 2..) |arg, index| {
        if (std.mem.eql(u8, arg, "--")) return null;
        if (std.mem.eql(u8, arg, values.option)) return .{ .index = index, .enabled = true };
        if (std.mem.eql(u8, arg, legacy_option)) return .{ .index = index, .enabled = false };
    }
    return null;
}

fn duplicate(args: []const [:0]const u8, first: usize) bool {
    for (args[first + 1 ..]) |arg| {
        if (std.mem.eql(u8, arg, "--")) return false;
        if (std.mem.eql(u8, arg, values.option) or std.mem.eql(u8, arg, legacy_option)) return true;
    }
    return false;
}

fn accepts(command: []const u8) bool {
    for (commands) |name| if (std.mem.eql(u8, name, command)) return true;
    return false;
}

/// Whether the `mylang.json` nearest the command's first path argument turns
/// the switch on. A configuration that does not load is not read here: the
/// command itself reports it.
fn configuredOn(process: std.process.Init, args: []const [:0]const u8) std.mem.Allocator.Error!bool {
    const a = process.arena.allocator();
    if (args.len < 2 or !accepts(args[1])) return true;
    const entry = (try firstPath(a, args)) orelse return true;
    // `test` and `fix` also accept a directory. Discovery starts at the
    // entry's parent, so give it a virtual child of that directory.
    const stat = std.Io.Dir.cwd().statFile(process.io, entry, .{}) catch null;
    const discovery_entry = if (stat != null and stat.?.kind == .directory)
        try std.fs.path.join(a, &.{ entry, ".mylang-mode-entry" })
    else
        entry;
    const found = project_config.discover(a, process.io, discovery_entry) catch return true;
    const path = found orelse return true;
    var failure: project_config.Failure = .{};
    var config = project_config.load(a, process.io, path, &failure) catch return true;
    defer config.deinit();
    return config.document.value_semantics;
}

/// Find the entry by using each command's parser where options may take a
/// separate value before the path. A malformed command reports its own usage.
fn firstPath(a: std.mem.Allocator, args: []const [:0]const u8) std.mem.Allocator.Error!?[]const u8 {
    if (args.len < 3) return null;
    if (std.mem.eql(u8, args[1], "test") or std.mem.eql(u8, args[1], "build") or std.mem.eql(u8, args[1], "invoke")) {
        const options = try a.alloc([]const u8, args.len - 2);
        for (args[2..], options) |arg, *option| option.* = arg;
        if (std.mem.eql(u8, args[1], "test")) return (@import("native_test_options.zig").parse(options) catch return null).source;
        if (std.mem.eql(u8, args[1], "build")) return (@import("qbe_build_options.zig").parse(options) catch return null).source;
        return (@import("invoke_command.zig").parse(options) catch return null).entry;
    }
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

/// Replace this process with the same command, its mode flag removed,
/// and the resolved environment value. Returns only when the
/// replacement fails.
fn replace(process: std.process.Init, args: []const [:0]const u8, flag: ?Flag, enabled: bool) Error!u8 {
    const a = process.arena.allocator();
    try process.environ_map.put(values.variable, if (enabled) "1" else "0");
    const self = std.Io.Dir.cwd().realPathFileAlloc(process.io, "/proc/self/exe", a) catch |err| return failed(process, err);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(a, self);
    for (args[1..], 1..) |arg, index| if (flag == null or index != flag.?.index) try argv.append(a, arg);
    const err = std.process.replace(process.io, .{ .argv = argv.items, .environ_map = process.environ_map });
    return failed(process, err);
}

fn failed(process: std.process.Init, err: anyerror) Error!u8 {
    var buffer: [160]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, "mylang: --value-semantics: cannot restart the compiler ({s})\n", .{@errorName(err)}) catch "mylang: --value-semantics: cannot restart the compiler\n";
    try std.Io.File.stderr().writeStreamingAll(process.io, message);
    return 2;
}
