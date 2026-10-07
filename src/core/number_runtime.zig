//! Separately cached Zig number-text runtime; integer-only programs pay no formatter build.
const std = @import("std");

/// Complete helper sources. Imports are copied beside the independent runtime unit.
pub const SourceUnit = struct { name: []const u8, bytes: []const u8 };

/// Source units copied into the content-addressed runtime build directory.
pub const sources = [_]SourceUnit{
    .{ .name = "core_number_text.zig", .bytes = @embedFile("runtime/core_number_text.zig") },
    .{ .name = "core_number_parse.zig", .bytes = @embedFile("runtime/core_number_parse.zig") },
    .{ .name = "core_number_format.zig", .bytes = @embedFile("runtime/core_number_format.zig") },
};

/// Explicit target and options: all are hashed into the formatter object's key.
pub const options: []const []const u8 = &.{ "-target", @import("target.zig").native_link_target, "-mcpu", "baseline", "-O", "ReleaseFast", "-fPIC", "-fno-stack-check", "-fno-stack-protector", "-lc" };

/// Allocation, filesystem and tool failures share the native driver's errors.
pub const Error = error{ ToolFailed, OutOfMemory, WriteFailed };

/// Whether emitted code actually calls a Zig number helper.
pub fn needed(llvm: []const u8) bool {
    const names = [_][]const u8{ "myl_core_str_from_f64", @import("flags.zig").buffer_float_symbol, "myl_core_format_number", "myl_core_format_float", "myl_core_format_text", "myl_core_parse_float_range", "myl_core_round_float" };
    for (names) |name| if (std.mem.indexOf(u8, llvm, name) != null) return true;
    return false;
}

/// Cache key contains named helper contents, the toolchain's identity and every compile option.
pub fn key(version: []const u8) [32]u8 {
    return fingerprint(version, &sources, options);
}

/// Complete runtime fingerprint, exposed for independent cache-invalidation checks.
pub fn fingerprint(version: []const u8, units: []const SourceUnit, settings: []const []const u8) [32]u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("myl-core-number-runtime-v1\x00");
    hash.update(version);
    hash.update("\x00");
    for (settings) |option| {
        hash.update(option);
        hash.update("\x00");
    }
    for (units) |source| {
        hash.update(source.name);
        hash.update("\x00");
        var digest: [32]u8 = undefined;
        std.crypto.hash.Blake3.hash(source.bytes, &digest, .{});
        hash.update(&digest);
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return digest;
}

/// Compile the independent helper only on a cache miss; rename a unique partial atomically.
/// `native` is the driver's build context; `tool` is the toolchain's content identity,
/// which keys the object in place of a `zig version` process.
pub fn object(native: anytype, directory: []const u8, tool: [32]u8) Error![]const u8 {
    const allocator = native.arena;
    const io = native.io;
    const log = native.log;
    const stem = try std.fmt.allocPrint(allocator, "core_number_text-{x}", .{key(&tool)});
    const path = try std.fs.path.join(allocator, &.{ directory, try std.fmt.allocPrint(allocator, "{s}.o", .{stem}) });
    const cwd = std.Io.Dir.cwd();
    const report = native.environment.get("MYL_CORE_RUNTIME_REPORT") != null;
    if (cwd.access(io, path, .{})) |_| {
        if (report) try log.print(allocator, "number-text cache hit: {s}\n", .{path});
        return path;
    } else |_| {}
    // Keep both source staging and output private to each program during concurrent misses.
    var output_digest: [16]u8 = undefined;
    std.Io.random(io, &output_digest);
    const staging = try std.fs.path.join(allocator, &.{ directory, try std.fmt.allocPrint(allocator, "{s}-{x}", .{ stem, output_digest }) });
    cwd.createDirPath(io, staging) catch return error.WriteFailed;
    defer retireDirectory(io, staging);
    for (sources) |source| {
        const file = try std.fs.path.join(allocator, &.{ staging, source.name });
        cwd.writeFile(io, .{ .sub_path = file, .data = source.bytes }) catch return error.WriteFailed;
    }
    const partial = try std.fmt.allocPrint(allocator, "{s}.{x}.partial", .{ path, output_digest });
    defer retireFile(io, partial);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ native.zig, "build-obj", try std.fs.path.join(allocator, &.{ staging, sources[0].name }) });
    try argv.appendSlice(allocator, options);
    try argv.append(allocator, try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{partial}));
    if (report) try log.print(allocator, "number-text cache miss: {s}\n", .{path});
    native.counts.processes += 1;
    _ = try execute(allocator, io, native.environment, argv.items, log);
    try native.guard.check(log);
    cwd.rename(partial, cwd, path, io) catch return error.WriteFailed;
    return path;
}

fn retireDirectory(io: std.Io, path: []const u8) void {
    // This invocation owns staging; removing it after success or failure is best effort.
    std.Io.Dir.cwd().deleteTree(io, path) catch return;
}

fn retireFile(io: std.Io, path: []const u8) void {
    // A published partial already moved away; otherwise discard this invocation's file.
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}

fn execute(allocator: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map, argv: []const []const u8, log: *std.ArrayList(u8)) Error![]const u8 {
    const result = std.process.run(allocator, io, .{ .argv = argv, .environ_map = environment }) catch return error.ToolFailed;
    try log.appendSlice(allocator, result.stderr);
    if (result.term != .exited or result.term.exited != 0) return error.ToolFailed;
    return result.stdout;
}
