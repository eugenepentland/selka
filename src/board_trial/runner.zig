//! Execute sanitized trial inputs through the native guest and the standalone Zig baseline.
const std = @import("std");
const print = std.debug.print;
const host = @import("host.zig");
const input = @import("input.zig");
const baseline = @import("baseline.zig");
const Kernel = @import("kernel.zig").Kernel;
const m = @import("model.zig");
const Row = struct { name: []const u8, guest: m.Observation, baseline: m.Observation };
/// Read one bounded request file and emit observations; no expected answers enter this process.
/// Guest code runs in a child process under its own ceiling, so this process only
/// parses a bounded request file, drives the native build and reads bytes back.
pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (try emit(init, args)) return;
    if (args.len != 4 or !std.mem.eql(u8, args[1], "--project")) {
        print("usage: board-trial --project DIRECTORY REQUESTS.json\n", .{});
        return error.Usage;
    }
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[3], allocator, .limited(4 * 1024 * 1024));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{ .allocate = .alloc_always, .parse_numbers = false });
    if (parsed.value != .array) return error.InvalidSnapshot;
    const rows = try allocator.alloc(Row, parsed.value.array.items.len);
    try compare(init, args[2], parsed.value.array.items, rows);
    const output = try std.json.Stringify.valueAlloc(allocator, rows, .{});
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
/// Serve the native build driver's frontend request from this same executable,
/// so a board application needs no separately installed compiler to build itself.
fn emit(init: std.process.Init, args: []const []const u8) !bool {
    if (args.len != 3 or !std.mem.eql(u8, args[1], "emit-project-qbe")) return false;
    const allocator = init.arena.allocator();
    var program: @import("mylang").embedded_project.Program = undefined;
    try program.initDisk(allocator, init.io, std.fs.path.dirname(args[2]) orelse ".");
    defer program.deinit();
    try std.Io.File.stdout().writeStreamingAll(init.io, try program.compilation.emitQbe(allocator));
    return true;
}
/// Sanitize every transport first, so a malformed request never reaches a build,
/// then answer each one with the native guest and the standalone Zig baseline.
fn compare(init: std.process.Init, root: []const u8, requests: []const std.json.Value, rows: []Row) !void {
    const allocator = init.arena.allocator();
    const sanitized = try allocator.alloc(input.Request, requests.len);
    for (requests, sanitized) |raw, *out| out.* = try input.request(allocator, raw);
    var session = try host.Session.init(init, root);
    defer session.deinit();
    for (sanitized, rows) |request, *row| {
        var kernel: Kernel = .{ .unavailable = request.unavailable };
        const answer = baseline.validate(request.board, &kernel);
        row.* = .{
            .name = request.name,
            .guest = session.run(request.board, request.unavailable) catch |err| {
                print("case {s}: {s}\n", .{ request.name, @errorName(err) });
                return err;
            },
            .baseline = .{ .outcome = answer, .calls = kernel.calls },
        };
    }
}
