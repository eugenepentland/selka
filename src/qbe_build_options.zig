//! Dedicated native-build options avoid coupling the semantic CLI to tool policy.
const std = @import("std");
/// Malformed or unsupported command-line build controls.
pub const Error = error{InvalidBuildArguments};
/// The per-project object cache used when no `--cache-dir` selects another; a build
/// left at this default may share its runtime tree with other projects, while an
/// explicit `--cache-dir` keeps every artifact hermetically under that directory.
pub const default_cache = ".mylang-cache/qbe";
/// Optimize mode a native build uses when no `--mode` selects another: `mylang
/// build` and `mylang run` are asked for speed, so the fast mode is the default
/// and an unoptimized build is a deliberate `--mode Debug`.
pub const default_mode = "ReleaseFast";
/// The native driver preserves the Python prototype's build controls.
pub const Options = struct {
    link_arguments: []const []const u8 = &.{},
    source: []const u8 = "",
    output: []const u8 = "",
    project: bool = false,
    library: bool = false,
    provider: ?[]const u8 = null,
    qbe: []const u8 = "qbe",
    zig: []const u8 = "zig",
    mode: []const u8 = default_mode,
    target: []const u8 = "amd64_sysv",
    cache: []const u8 = default_cache,
    report: bool = false,
    run: bool = false,
    max_memory: ?u64 = null,
    arguments: []const []const u8 = &.{},
};
/// Build usage is independent of run-time guest budgets.
pub const usage = "usage: mylang build <file.my> (-o <output> | --run) [--project] [--library]\n" ++
    "  --link FILE --link-library NAME --library-path DIR (repeatable)\n" ++
    "  --provider FILE  trusted native provider (executables only)\n" ++
    "  --qbe PATH --zig PATH --mode Debug|ReleaseFast (default ReleaseFast) --target amd64_sysv\n" ++
    "  --cache-dir DIR --report\n" ++
    "  --max-memory BYTES  byte ceiling for --run (K/M/G suffixes; default 4G)\n" ++
    "  --run instead of -o: execute temporarily; pass runtime options after --\n";
/// Parse explicit build flags, rejecting unknown controls.
pub fn parse(args: []const []const u8) Error!Options {
    var result: Options = .{ .link_arguments = args };
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const argument = args[index];
        if (std.mem.eql(u8, argument, "--")) {
            result.arguments = args[index + 1 ..];
            break;
        }
        if (!std.mem.startsWith(u8, argument, "-")) {
            if (result.source.len != 0) return error.InvalidBuildArguments;
            result.source = argument;
            continue;
        }
        const split = std.mem.indexOfScalar(u8, argument, '=') orelse argument.len;
        const name = argument[0..split];
        const option = std.meta.stringToEnum(Flag, name) orelse return error.InvalidBuildArguments;
        if (boolean(&result, option)) {
            if (split != argument.len) return error.InvalidBuildArguments;
            continue;
        }
        const value = if (split < argument.len) argument[split + 1 ..] else value: {
            index += 1;
            if (index == args.len) return error.InvalidBuildArguments;
            break :value args[index];
        };
        if (value.len == 0) return error.InvalidBuildArguments;
        if (@import("native_link.zig").isFlag(@tagName(option)) and !@import("native_link.zig").valid(@tagName(option), value)) return error.InvalidBuildArguments;
        try assign(&result, option, value);
    }
    if (result.source.len == 0) return error.InvalidBuildArguments;
    if (result.run) {
        if (result.output.len != 0 or result.library) return error.InvalidBuildArguments;
    } else {
        if (result.output.len == 0 or result.arguments.len != 0) return error.InvalidBuildArguments;
    }
    if (result.library and result.provider != null) return error.InvalidBuildArguments;
    if (!std.mem.eql(u8, result.target, "amd64_sysv")) return error.InvalidBuildArguments;
    if (!std.mem.eql(u8, result.mode, "Debug") and !std.mem.eql(u8, result.mode, "ReleaseFast")) return error.InvalidBuildArguments;
    return result;
}
const Flag = enum { @"--link", @"--link-library", @"--library-path", @"-o", @"--output", @"--project", @"--library", @"--provider", @"--qbe", @"--zig", @"--mode", @"--target", @"--cache-dir", @"--report", @"--run", @"--max-memory" };
fn boolean(result: *Options, flag: Flag) bool {
    switch (flag) {
        .@"--project" => result.project = true,
        .@"--library" => result.library = true,
        .@"--report" => result.report = true,
        .@"--run" => result.run = true,
        else => return false,
    }
    return true;
}
fn assign(result: *Options, flag: Flag, value: []const u8) Error!void {
    switch (flag) {
        .@"--link", .@"--link-library", .@"--library-path" => {},
        .@"-o", .@"--output" => {
            result.output = value;
        },
        .@"--provider" => result.provider = value,
        .@"--qbe" => result.qbe = value,
        .@"--zig" => result.zig = value,
        .@"--mode" => result.mode = value,
        .@"--target" => result.target = value,
        .@"--cache-dir" => result.cache = value,
        .@"--max-memory" => result.max_memory = @import("memory_budget").parse(value) catch return error.InvalidBuildArguments,
        else => unreachable,
    }
}

test "build options accept equals syntax and later tool overrides" {
    const parsed = try parse(&.{ "main.my", "-o", "out", "--qbe=first", "--qbe", "second", "--mode=ReleaseFast", "--project", "--report" });
    try std.testing.expectEqualStrings("second", parsed.qbe);
    try std.testing.expectEqualStrings("ReleaseFast", parsed.mode);
    try std.testing.expect(parsed.project and parsed.report);
}
// spec: BUILD-MODE-1
test "a build that names no optimize mode uses the fast one and Debug stays explicit" {
    const plain = try parse(&.{ "main.my", "-o", "out" });
    try std.testing.expectEqualStrings(default_mode, plain.mode);
    try std.testing.expectEqualStrings("ReleaseFast", (try parse(&.{ "main.my", "--run" })).mode);
    try std.testing.expectEqualStrings("Debug", (try parse(&.{ "main.my", "-o", "out", "--mode", "Debug" })).mode);
    try std.testing.expect(std.mem.indexOf(u8, usage, "default ReleaseFast") != null);
}
test "build options reject missing values unsupported targets and incompatible provider controls" {
    const invalid = [_][]const []const u8{
        &.{},                                        &.{ "a.my", "b.my", "-o", "out" },         &.{ "a.my", "-o" },
        &.{ "a.my", "--unknown" },                   &.{ "a.my", "-o=" },                       &.{ "a.my", "-o", "out", "--report=true" },
        &.{ "a.my", "-o", "out", "--target=arm64" }, &.{ "a.my", "-o", "out", "--mode=other" }, &.{ "a.my", "-o", "out", "--library", "--provider=x.c" },
    };
    for (invalid) |args| try std.testing.expectError(error.InvalidBuildArguments, parse(args));
}

test "temporary native runs accept runtime options and reject persistent output" {
    const parsed = try parse(&.{ "main.my", "--run", "--", "--max-steps=12", "--gc-stress" });
    try std.testing.expect(parsed.run);
    try std.testing.expectEqualStrings("--max-steps=12", parsed.arguments[0]);
    try std.testing.expectEqual(@as(usize, 2), parsed.arguments.len);
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "-o", "out" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "--library" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "-o", "out", "--", "--gc-stress" }));
}

// spec-case: MEMORY-CEILING-1
test "a temporary native run accepts a suffixed byte ceiling and rejects malformed text" {
    try std.testing.expectEqual(@as(?u64, 64 << 20), (try parse(&.{ "main.my", "--run", "--max-memory=64M" })).max_memory);
    try std.testing.expectEqual(@as(?u64, 1 << 30), (try parse(&.{ "main.my", "--run", "--max-memory", "1G" })).max_memory);
    // Unresolved by default, so MYLANG_MEMORY_LIMIT and the built-in default still apply.
    try std.testing.expectEqual(@as(?u64, null), (try parse(&.{ "main.my", "--run" })).max_memory);
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "--max-memory=eight" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "--max-memory" }));
}

test "native link controls are repeatable and reject injected compiler switches" {
    _ = try parse(&.{ "main.my", "--run", "--link=a.c", "--link", "b.o", "--library-path", "lib", "--link-library=m" });
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "--link-library=-shared" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "--link=-Wl,bad" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "--library-path" }));
}
