//! Direct links (BUILD-LINK-1): the final link runs `zig ld.lld` itself
//! instead of going through the `zig cc` driver every time.
//!
//! `zig cc` turns a link request into one `ld.lld` command, and to do so it
//! probes the host C library first — it starts `cc -E -Wp,-v` and
//! `cc -print-file-name=crt1.o` — and resolves the compiler-rt and sanitizer
//! archives it bundles. On a 50,000-line project that driver work was about
//! 40 ms of a 120 ms link, and it gives the same answer for every link of the
//! same flags on the same host. So the first link of a given shape asks
//! `zig cc` to show its command (`-###`, which still links), and remembers that
//! command with the object list and the output replaced by markers. Later links
//! of that shape run `zig ld.lld` with the remembered arguments and this link's
//! objects and output, which is the command `zig cc` would have run.
//!
//! A template is keyed by everything that reaches `zig cc`'s answer: the tool
//! stamps and build environment, the environment variables that steer its
//! host probe, and every argument other than the objects and the output. It
//! is used only when every path it names still exists, and a direct link that
//! fails falls back to `zig cc`, which reports the program's own link error
//! and records a fresh template.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const spawn = @import("qbe_build_spawn.zig");

/// The version every template key starts with.
const version = "mylang-link-template-v1";
/// The token that stands for this link's object list, and the one for its output.
const objects_marker = "\x01objects";
const output_marker = "\x01output";
/// What a build's scratch directory reads as in a template key.
const scratch_marker = "\x01scratch";
/// The environment `zig cc` reads while it probes the host and resolves its
/// bundled archives; a template made under other values is another template.
const probe_variables = [_][]const u8{ "PATH", "ZIG_GLOBAL_CACHE_DIR", "ZIG_LIBC", "LIBRARY_PATH", "NIX_LDFLAGS", "NIX_CFLAGS_COMPILE", "NIX_DYNAMIC_LINKER" };
/// The line of `zig cc -###`'s standard error that is the linker command.
const linker_prefix = "ld.lld ";

/// One final link: the `zig cc` command (`argv[0]` is Zig, `argv[1]` is `cc`),
/// the objects it names as one contiguous run, the output it writes, and this
/// build's private scratch directory, which the compile-only path-mapping
/// flags name and which differs on every build.
pub const Link = struct { argv: []const []const u8, objects: []const []const u8, output: []const u8, scratch: []const u8 = "" };

/// Where templates are kept and the build environment (tool stamps, mode,
/// target) that is part of every template's key.
pub const Place = struct { directory: []const u8, environment: []const u8 };

/// How one link ran: directly from a template, through `zig cc` while
/// recording a template, or through `zig cc` alone.
pub const Route = enum { direct, recorded, driver };

/// Link, directly when a template for this shape exists and still applies,
/// otherwise through `zig cc`, recording a template when its command can be
/// read back unambiguously.
pub fn run(context: fs.Context, place: Place, link: Link) fs.Error!Route {
    const a = context.allocator;
    const run_start = objectRun(link) orelse {
        try context.command(link.argv, null);
        return .driver;
    };
    const file = try templatePath(context, place, link, run_start);
    if (try load(context, file)) |template| {
        if (try direct(context, link, template)) return .direct;
    }
    var shown: std.ArrayList([]const u8) = .empty;
    try shown.appendSlice(a, link.argv[0..2]);
    try shown.append(a, "-###");
    try shown.appendSlice(a, link.argv[2..]);
    const result = try spawn.run(a, .{ .argv = shown.items });
    const line = linkerLine(result.stderr);
    // Everything else `zig cc` wrote (a warning) is the link's own output.
    try writeExcept(context, result.stderr, line);
    if (fs.exitCode(result.term) != 0) return error.NativeToolFailed;
    const template = (try record(a, link, line orelse return .driver)) orelse return .driver;
    if (!try applies(context, template)) return .driver;
    context.atomic(file, try std.mem.join(a, "\x00", template)) catch return .driver;
    return .recorded;
}

/// The index in `argv` where the object run starts, or null when the objects
/// are not one contiguous run of it, or any argument holds a space (the
/// command `zig cc` prints separates arguments by spaces without quoting).
fn objectRun(link: Link) ?usize {
    if (link.argv.len < 2 or link.objects.len == 0) return null;
    for (link.argv) |argument| if (std.mem.indexOfScalar(u8, argument, ' ') != null) return null;
    const first = position(link.argv, link.objects[0]) orelse return null;
    if (first + link.objects.len > link.argv.len) return null;
    for (link.objects, link.argv[first .. first + link.objects.len]) |object, argument| {
        if (!std.mem.eql(u8, object, argument)) return null;
    }
    return first;
}

/// The index of the first of `items` equal to `text`.
fn position(items: []const []const u8, text: []const u8) ?usize {
    for (items, 0..) |item, index| if (std.mem.eql(u8, item, text)) return index;
    return null;
}

/// `<directory>/link-<key>.args`, the key covering everything but the objects and output.
fn templatePath(context: fs.Context, place: Place, link: Link, run_start: usize) fs.Error![]const u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    frame(&hash, version);
    frame(&hash, place.environment);
    for (probe_variables) |name| {
        frame(&hash, name);
        frame(&hash, context.environ.get(name) orelse "\x00unset");
    }
    for (link.argv, 0..) |argument, index| {
        if (index > run_start and index < run_start + link.objects.len) continue;
        if (index == run_start) {
            frame(&hash, objects_marker);
        } else if (std.mem.eql(u8, argument, link.output)) {
            frame(&hash, output_marker);
        } else if (link.scratch.len != 0 and std.mem.indexOf(u8, argument, link.scratch) != null) {
            // A flag that maps the scratch directory only renames paths in
            // compiled debug information; the linker line never names it.
            frame(&hash, try std.mem.replaceOwned(u8, context.allocator, argument, link.scratch, scratch_marker));
        } else frame(&hash, argument);
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    const name = try std.fmt.allocPrint(context.allocator, "link-{s}.args", .{std.fmt.bytesToHex(digest, .lower)});
    return std.fs.path.join(context.allocator, &.{ place.directory, name });
}

fn frame(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

/// A stored template's arguments, or null when there is none or it is not one.
fn load(context: fs.Context, file: []const u8) fs.Error!?[]const []const u8 {
    const bytes = context.read(file) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    var tokens: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.splitScalar(u8, bytes, 0);
    while (parts.next()) |part| try tokens.append(context.allocator, part);
    return if (wellFormed(tokens.items)) tokens.items else null;
}

/// Exactly one object marker and one output marker, after the program name.
fn wellFormed(template: []const []const u8) bool {
    if (template.len < 2 or !std.mem.eql(u8, template[0], "ld.lld")) return false;
    var objects: usize = 0;
    var outputs: usize = 0;
    for (template) |token| {
        objects += @intFromBool(std.mem.eql(u8, token, objects_marker));
        outputs += @intFromBool(std.mem.eql(u8, token, output_marker));
    }
    return objects == 1 and outputs == 1;
}

/// Run `zig ld.lld` with `template` filled in for this link, reporting false
/// (and linking nothing) when a path the template names is gone, or when the
/// direct link fails, so `zig cc` can take over and say why.
fn direct(context: fs.Context, link: Link, template: []const []const u8) fs.Error!bool {
    if (!try applies(context, template)) return false;
    const a = context.allocator;
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ link.argv[0], "ld.lld" });
    for (template[1..]) |token| {
        if (std.mem.eql(u8, token, objects_marker)) {
            try argv.appendSlice(a, link.objects);
        } else if (std.mem.eql(u8, token, output_marker)) {
            try argv.append(a, link.output);
        } else try argv.append(a, token);
    }
    const result = try spawn.run(a, .{ .argv = argv.items });
    if (fs.exitCode(result.term) != 0) return false;
    try std.Io.File.stderr().writeStreamingAll(context.io, result.stderr);
    return true;
}

/// Whether every argument of `template` that names a path still names one.
fn applies(context: fs.Context, template: []const []const u8) fs.Error!bool {
    for (template[1..]) |token| {
        if (std.mem.indexOfScalar(u8, token, '/') == null) continue;
        if (!context.exists(token)) return false;
    }
    return true;
}

/// The linker command line of `zig cc -###`'s standard error, if it printed one.
fn linkerLine(stderr: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, stderr, '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, line, linker_prefix)) return line;
    return null;
}

/// Write `stderr` without the linker line `zig cc -###` added to it.
fn writeExcept(context: fs.Context, stderr: []const u8, line: ?[]const u8) fs.Error!void {
    const shown = line orelse return std.Io.File.stderr().writeStreamingAll(context.io, stderr);
    const at = @intFromPtr(shown.ptr) - @intFromPtr(stderr.ptr);
    try std.Io.File.stderr().writeStreamingAll(context.io, stderr[0..at]);
    const rest = @min(stderr.len, at + shown.len + 1);
    try std.Io.File.stderr().writeStreamingAll(context.io, stderr[rest..]);
}

/// The template of a printed linker command: this link's objects, which must
/// appear once as one run in order, become one marker, and its output, which
/// must appear once, another. Null when the command cannot be read back that
/// way or already holds a token that looks like a marker.
fn record(allocator: std.mem.Allocator, link: Link, line: []const u8) error{OutOfMemory}!?[]const []const u8 {
    var tokens: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.tokenizeScalar(u8, line, ' ');
    while (parts.next()) |part| try tokens.append(allocator, part);
    const first = position(tokens.items, link.objects[0]) orelse return null;
    if (first + link.objects.len > tokens.items.len) return null;
    for (link.objects, tokens.items[first .. first + link.objects.len]) |object, token| {
        if (!std.mem.eql(u8, object, token)) return null;
    }
    var template: std.ArrayList([]const u8) = .empty;
    var outputs: usize = 0;
    for (tokens.items, 0..) |token, index| {
        if (index == first) try template.append(allocator, objects_marker);
        if (index >= first and index < first + link.objects.len) continue;
        if (std.mem.startsWith(u8, token, "\x01")) return null;
        for (link.objects) |object| if (std.mem.eql(u8, object, token)) return null;
        const is_output = std.mem.eql(u8, token, link.output);
        outputs += @intFromBool(is_output);
        try template.append(allocator, if (is_output) output_marker else token);
    }
    if (outputs != 1) return null;
    return @as(?[]const []const u8, template.items);
}

// spec: BUILD-LINK-1
test "a printed linker command becomes a template that links other objects to another output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first: Link = .{ .argv = &.{ "/zig", "cc", "-O0", "/c/a.o", "/c/b.o", "/rt.a", "-lm", "-o", "/out/1" }, .objects = &.{ "/c/a.o", "/c/b.o" }, .output = "/out/1" };
    const line = "ld.lld --entry _start -o /out/1 /usr/lib/crt1.o /c/a.o /c/b.o /rt.a -lm /usr/lib/crtn.o";
    const template = (try record(a, first, line)).?;
    try std.testing.expect(wellFormed(template));
    try std.testing.expectEqualStrings("ld.lld --entry _start -o \x01output /usr/lib/crt1.o \x01objects /rt.a -lm /usr/lib/crtn.o", try std.mem.join(a, " ", template));
    // The same shape with other objects and another output shares the key.
    var environment: std.process.Environ.Map = .init(a);
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const second: Link = .{ .argv = &.{ "/zig", "cc", "-O0", "/c/x.o", "/rt.a", "-lm", "-o", "/out/2" }, .objects = &.{"/c/x.o"}, .output = "/out/2" };
    const place: Place = .{ .directory = "/cache", .environment = "env" };
    try std.testing.expectEqualStrings(try templatePath(context, place, first, objectRun(first).?), try templatePath(context, place, second, objectRun(second).?));
    // Another flag, or another build environment, is another template.
    const release: Link = .{ .argv = &.{ "/zig", "cc", "-O2", "/c/x.o", "/rt.a", "-lm", "-o", "/out/2" }, .objects = &.{"/c/x.o"}, .output = "/out/2" };
    try std.testing.expect(!std.mem.eql(u8, try templatePath(context, place, second, 3), try templatePath(context, place, release, 3)));
    try std.testing.expect(!std.mem.eql(u8, try templatePath(context, place, second, 3), try templatePath(context, .{ .directory = "/cache", .environment = "other" }, second, 3)));
    // Each build's own scratch directory, which only compile flags name, does not.
    const one: Link = .{ .argv = &.{ "/zig", "cc", "-ffile-prefix-map=/s/1=q", "/c/x.o", "-o", "/out/2" }, .objects = &.{"/c/x.o"}, .output = "/out/2", .scratch = "/s/1" };
    const two: Link = .{ .argv = &.{ "/zig", "cc", "-ffile-prefix-map=/s/2=q", "/c/x.o", "-o", "/out/2" }, .objects = &.{"/c/x.o"}, .output = "/out/2", .scratch = "/s/2" };
    try std.testing.expectEqualStrings(try templatePath(context, place, one, 3), try templatePath(context, place, two, 3));
}

// spec-case: BUILD-LINK-1
test "a command that cannot be read back unambiguously records no template" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const link: Link = .{ .argv = &.{ "/zig", "cc", "/c/a.o", "/c/b.o", "-o", "/out" }, .objects = &.{ "/c/a.o", "/c/b.o" }, .output = "/out" };
    // Objects out of order, an object named twice, or no output: no template.
    try std.testing.expectEqual(@as(?[]const []const u8, null), try record(a, link, "ld.lld /c/b.o /c/a.o -o /out"));
    try std.testing.expectEqual(@as(?[]const []const u8, null), try record(a, link, "ld.lld /c/a.o /c/b.o /c/a.o -o /out"));
    try std.testing.expectEqual(@as(?[]const []const u8, null), try record(a, link, "ld.lld /c/a.o /c/b.o"));
    // An argument with a space cannot survive the printed command at all.
    try std.testing.expectEqual(@as(?usize, null), objectRun(.{ .argv = &.{ "/zig", "cc", "/my dir/a.o", "-o", "/out" }, .objects = &.{"/my dir/a.o"}, .output = "/out" }));
    try std.testing.expect(!wellFormed(&.{ "ld.lld", objects_marker }));
    try std.testing.expect(!wellFormed(&.{ "cc", objects_marker, output_marker }));
}
