//! Execute the guest DSL parser and SVG generator with three explicitly supplied source files.
const std = @import("std");
const print = std.debug.print;
const application = @import("app.zig");
const diagnostics = @import("diagnostics.zig");
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
    if (args.len != 4) {
        print("usage: schematic-svg MODULE.sexp PINOUT.sexp INTERFACE.sexp > output.svg\n", .{});
        return error.InvalidSchematic;
    }
    var documents: [3][]const u8 = undefined;
    for (args[1..], &documents) |path, *out| out.* = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(1024 * 1024));
    var app: application.App = undefined;
    try app.init(allocator, .{ .context = null, .read = application.embedded });
    defer app.deinit();
    const svg = app.run(allocator, &documents, .{ .max_steps = 100_000_000 }) catch |err| {
        if (app.issue) |issue| diagnostics.report(issue, args[1..], &documents);
        if (app.trap) |trap| {
            const at = app.program.compilation.src.locate(trap.span.start);
            print("{s}:{d}:{d}: {s}: {s}\n", .{ at.path, at.line, at.column, trap.code, trap.message });
        }
        return err;
    };
    defer allocator.free(svg);
    try std.Io.File.stdout().writeStreamingAll(init.io, svg);
}
