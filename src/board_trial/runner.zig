//! Execute sanitized trial inputs through the VM and the standalone Zig baseline.
const std = @import("std");
const application = @import("app.zig");
const input = @import("input.zig");
const baseline = @import("baseline.zig");
const Kernel = @import("kernel.zig").Kernel;
const m = @import("model.zig");
const Row = struct { name: []const u8, guest: m.Observation, baseline: m.Observation };
/// Read one bounded request file and emit observations; no expected answers enter this process.
pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 4 or !std.mem.eql(u8, args[1], "--project")) {
        std.debug.print("usage: board-trial --project DIRECTORY REQUESTS.json\n", .{});
        return error.Usage;
    }
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[3], allocator, .limited(4 * 1024 * 1024));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{ .allocate = .alloc_always, .parse_numbers = false });
    if (parsed.value != .array) return error.InvalidSnapshot;
    var app: application.App = undefined;
    try app.initDisk(allocator, init.io, args[2]);
    defer app.deinit();
    const rows = try allocator.alloc(Row, parsed.value.array.items.len);
    for (parsed.value.array.items, rows) |raw, *row| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const request = try input.request(arena.allocator(), raw);
        var kernel: Kernel = .{ .unavailable = request.unavailable };
        const native = baseline.validate(request.board, &kernel);
        row.* = .{ .name = request.name, .guest = app.run(arena.allocator(), request.board, request.unavailable, .{}) catch |err| {
            if (app.trap) |problem| std.debug.print("{s}: {s} at {d}:{d}\n", .{ problem.code, problem.message, problem.span.start, problem.span.end });
            std.debug.print("case {s}: {s}\n", .{ request.name, @errorName(err) });
            return err;
        }, .baseline = .{ .outcome = native, .calls = kernel.calls } };
    }
    const output = try std.json.Stringify.valueAlloc(allocator, rows, .{});
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
