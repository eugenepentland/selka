//! `mylang run` and `run-project`: build the checked program with the native
//! backend and execute it.
//!
//! The executable is published under the build cache by the identity of the QBE
//! units it was made from, so running an unchanged program spawns it instead of
//! rebuilding it, and `run` and `build` share one object cache. Guest standard
//! output and error pass straight through; the child's exit status is the
//! command's.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const builder = @import("qbe_build.zig");
const options = @import("qbe_build_options.zig");
const bundled = @import("qbe_build_assets");

/// Native build, tool and child-process failures raised while running a program.
pub const Error = builder.Error;

/// One native run: the emitted units, and the build settings that also carry the
/// program's own arguments and its byte ceiling.
pub const Request = struct {
    io: std.Io,
    environ: *const std.process.Environ.Map,
    /// The `qbe-units-v1` manifest the frontend emitted for this program.
    manifest: []const u8,
    settings: options.Options = .{ .source = "", .run = true },
    /// `json` re-renders the runtime's trap text as `diagnostic-v1` records.
    diagnostics: Format = .text,
};

/// Terminal text, or one versioned JSON object per line on standard error.
pub const Format = enum { text, json };

/// Build the program when its units changed, then run it and return its exit status.
pub fn execute(allocator: std.mem.Allocator, request: Request) Error!u8 {
    var context = try fs.Context.init(allocator, request.io, request.environ);
    defer context.deinit();
    const path = try publish(context, request.settings, request.manifest);
    if (request.diagnostics == .text) return builder.spawn(context, path, request.settings);
    return observe(context, path, request.settings);
}

/// Run the program with its diagnostics captured, so a trap the native runtime
/// located can be re-rendered as JSON. Standard output still streams through.
fn observe(context: fs.Context, path: []const u8, settings: options.Options) Error!u8 {
    const argv = try builder.command(context, path, settings.arguments);
    var child = try std.process.spawn(context.io, .{
        .argv = argv,
        .environ_map = try builder.ceiling(context, settings),
        .stderr = .pipe,
    });
    var buffer: [4096]u8 = undefined;
    var reader = child.stderr.?.readerStreaming(context.io, &buffer);
    const captured = reader.interface.allocRemaining(context.allocator, .limited(4 * 1024 * 1024)) catch "";
    const outcome = builder.status(try child.wait(context.io));
    try translate(context, captured);
    return outcome;
}

/// One `path:line:column` locator the native runtime printed.
const Place = struct { path: []const u8, line: u64, column: u64 };

/// Re-emit captured runtime diagnostics as `diagnostic-v1` JSON lines.
fn translate(context: fs.Context, text: []const u8) Error!void {
    var frames: std.ArrayList(struct { function: []const u8, location: Located }) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    const first = lines.first();
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "  in ")) continue;
        const split = std.mem.lastIndexOf(u8, line, " at ") orelse continue;
        const at = position(line[split + 4 ..]) orelse continue;
        try frames.append(context.allocator, .{ .function = line[5..split], .location = located(at) });
    }
    const marker = std.mem.indexOf(u8, first, ": error[") orelse return passthrough(context, text);
    const rest = first[marker + 8 ..];
    const close = std.mem.indexOfScalar(u8, rest, ']') orelse return passthrough(context, text);
    const at = position(first[0..marker]) orelse return passthrough(context, text);
    const body = if (std.mem.indexOf(u8, rest[close..], "]: ")) |offset| rest[close + offset + 3 ..] else "native execution failed";
    const record = try std.json.Stringify.valueAlloc(context.allocator, .{
        .version = "diagnostic-v1",
        .kind = "diagnostic",
        .diagnostic = .{
            .code = rest[0..close],
            .severity = "error",
            .message = body,
            .location = located(at),
            .notes = &[_]u32{},
            .stack = .{ .frames = frames.items, .omitted = 0 },
        },
    }, .{});
    try passthrough(context, try std.fmt.allocPrint(context.allocator, "{s}\n", .{record}));
}

/// The JSON location shape shared with source diagnostics; byte spans are the
/// frontend's, and the native runtime reports only lines and columns.
const Located = struct {
    path: []const u8,
    start: struct { line: u64, column: u64 },
    end: ?u8 = null,
    bytes: ?u8 = null,
};

fn located(at: Place) Located {
    return .{ .path = at.path, .start = .{ .line = at.line, .column = at.column } };
}

fn passthrough(context: fs.Context, text: []const u8) Error!void {
    if (text.len != 0) try std.Io.File.stderr().writeStreamingAll(context.io, text);
}

/// Split a trailing `path:line:column` locator, which paths may themselves contain colons.
fn position(text: []const u8) ?Place {
    const last = std.mem.lastIndexOfScalar(u8, text, ':') orelse return null;
    const previous = std.mem.lastIndexOfScalar(u8, text[0..last], ':') orelse return null;
    const line = std.fmt.parseInt(u64, text[previous + 1 .. last], 10) catch return null;
    const column = std.fmt.parseInt(u64, text[last + 1 ..], 10) catch return null;
    return .{ .path = text[0..previous], .line = line, .column = column };
}

/// Name an executable by everything that decides its bytes, without running a tool.
/// A warm run must not pay for a toolchain probe it is about to skip.
fn identity(context: fs.Context, settings: options.Options, manifest: []const u8) Error![]const u8 {
    const environment = try std.json.Stringify.valueAlloc(context.allocator, .{
        .compiler = bundled.compiler_identity,
        .runtime = bundled.content_hash,
        .zig = try context.stamp(try context.executable(settings.zig)),
        .qbe = try context.stamp(try context.executable(settings.qbe)),
        .mode = settings.mode,
        .target = settings.target,
    }, .{});
    return fs.hash(context.allocator, try std.mem.concat(context.allocator, u8, &.{ environment, manifest }));
}

fn publish(context: fs.Context, settings: options.Options, manifest: []const u8) Error![]const u8 {
    const home = try std.fs.path.join(context.allocator, &.{ try context.absolute(settings.cache), "run" });
    const path = try std.fs.path.join(context.allocator, &.{ home, try identity(context, settings, manifest) });
    if (context.exists(path)) return path;
    const prepared = try builder.prepare(context, settings);
    defer context.remove(prepared.cache.temporary);
    try context.mkdir(home);
    const document = try std.json.parseFromSlice(std.json.Value, context.allocator, manifest, .{ .allocate = .alloc_always });
    _ = try builder.assemble(prepared.cache, settings, document.value, path);
    return path;
}

test "a located runtime locator survives paths that carry colons" {
    const at = position("a:b/c.my:12:34").?;
    try std.testing.expectEqualStrings("a:b/c.my", at.path);
    try std.testing.expectEqual(@as(u64, 12), at.line);
    try std.testing.expectEqual(@as(u64, 34), at.column);
    try std.testing.expectEqual(@as(?Place, null), position("no location here"));
}

test "a run identity separates programs, toolchains and build modes" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const home = try directory.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const tool = try std.fs.path.join(context.allocator, &.{ home, "tool" });
    try context.write(tool, "#!/bin/sh\nexit 0\n");
    try std.Io.Dir.cwd().setFilePermissions(std.testing.io, tool, .executable_file, .{});
    const settings: options.Options = .{ .source = "", .run = true, .zig = tool, .qbe = tool };
    const first = try identity(context, settings, "{\"functions\":[]}");
    const second = try identity(context, settings, "{\"functions\":[1]}");
    var release = settings;
    release.mode = "ReleaseFast";
    try std.testing.expectEqual(@as(usize, 64), first.len);
    try std.testing.expect(!std.mem.eql(u8, first, second));
    try std.testing.expect(!std.mem.eql(u8, first, try identity(context, release, "{\"functions\":[]}")));
    try std.testing.expectEqualStrings(first, try identity(context, settings, "{\"functions\":[]}"));
}
