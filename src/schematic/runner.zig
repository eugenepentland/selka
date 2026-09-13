//! Execute the guest DSL parser and SVG generator with three explicitly supplied source files.
const std = @import("std");
const print = std.debug.print;
const application = @import("app.zig");
const diagnostics = @import("diagnostics.zig");
const language = @import("mylang");
/// Publish SVG on stdout only after parsing, semantic validation and rendering succeed.
pub fn main(init: std.process.Init) void {
    run(init) catch |err| {
        if (err != error.InvalidSchematic and err != error.GuestTrap) print("schematic-svg: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
fn run(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--dev-session")) return @import("dev_session.zig").run(init);
    var gc_stress = false;
    var gc_report = false;
    var start: usize = 1;
    while (start < args.len) : (start += 1) {
        if (std.mem.eql(u8, args[start], "--gc-stress")) {
            gc_stress = true;
        } else if (std.mem.eql(u8, args[start], "--gc-report")) {
            gc_report = true;
        } else break;
    }
    const inputs = args[start..];
    if (inputs.len != 5 or !std.mem.eql(u8, inputs[0], "--project")) {
        print("usage: schematic-svg [--gc-stress] [--gc-report] --project DIRECTORY MODULE.sexp PINOUT.sexp INTERFACE.sexp > output.svg\n", .{});
        return error.InvalidSchematic;
    }
    var documents: [3][]const u8 = undefined;
    for (inputs[2..], &documents) |path, *out| out.* = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(1024 * 1024));
    var app: application.App = undefined;
    try app.initDisk(allocator, init.io, inputs[1]);
    defer app.deinit();
    var statistics: language.vm.GcStatistics = .{};
    const svg = app.run(allocator, &documents, .{
        .max_steps = 100_000_000,
        .memory = .{ .gc = .{ .stress = gc_stress, .statistics = &statistics } },
    }) catch |err| {
        if (app.issue) |issue| diagnostics.report(issue, inputs[2..], &documents);
        if (app.trap) |trap| {
            const at = app.program.compilation.src.locate(trap.span.start);
            print("{s}:{d}:{d}: {s}: {s}\n", .{ at.path, at.line, at.column, trap.code, trap.message });
        }
        return err;
    };
    defer allocator.free(svg);
    if (gc_report) print("GC: created={d} reclaimed={d} collections={d} peak_objects={d} live_objects={d}\n", .{
        statistics.created, statistics.reclaimed, statistics.collections, statistics.peak_objects, statistics.live_objects,
    });
    try std.Io.File.stdout().writeStreamingAll(init.io, svg);
}
