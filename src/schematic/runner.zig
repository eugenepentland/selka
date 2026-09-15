//! Execute the guest DSL parser and SVG generator with three explicitly supplied source files.
const std = @import("std");
const print = std.debug.print;
const application = @import("app.zig");
const diagnostics = @import("diagnostics.zig");
/// The native step budget one schematic rendering may spend.
const steps = @import("host_native").step_budget;
/// Publish SVG on stdout only after parsing, semantic validation and rendering succeed.
/// The host bounds its own address space first: it executes guest bytecode in
/// this process, so a runaway guest is a runaway host.
pub fn main(init: std.process.Init) void {
    _ = @import("memory_budget").guardHost(init.environ_map);
    run(init) catch |err| {
        if (err != error.InvalidSchematic and err != error.GuestTrap) print("schematic-svg: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
fn run(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--dev-session")) return @import("dev_session.zig").run(init);
    if (try emit(init, args)) return;
    var start: usize = 1;
    while (start < args.len and std.mem.eql(u8, args[start], "--gc-stress")) start += 1;
    const arguments: []const []const u8 = if (start > 1) &.{ steps, "--gc-stress" } else &.{steps};
    const inputs = args[start..];
    if (inputs.len != 5 or !std.mem.eql(u8, inputs[0], "--project")) {
        print("usage: schematic-svg [--gc-stress] --project DIRECTORY MODULE.sexp PINOUT.sexp INTERFACE.sexp > output.svg\n", .{});
        return error.InvalidSchematic;
    }
    var documents: [3][]const u8 = undefined;
    for (inputs[2..], &documents) |path, *out| out.* = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(1024 * 1024));
    var app: application.App = undefined;
    try app.initDisk(init, inputs[1]);
    defer app.deinit();
    const svg = app.run(&documents, arguments) catch |err| {
        if (app.issue) |issue| diagnostics.report(issue, inputs[2..], &documents);
        return err;
    };
    try std.Io.File.stdout().writeStreamingAll(init.io, svg);
}
/// Serve the native build driver's frontend request from this same executable,
/// so a schematic application needs no separately installed compiler to build itself.
fn emit(init: std.process.Init, args: []const []const u8) !bool {
    if (args.len < 3 or !std.mem.eql(u8, args[1], "emit-project-qbe")) return false;
    const allocator = init.arena.allocator();
    var program: @import("mylang").embedded_project.Program = undefined;
    try program.initDisk(allocator, init.io, std.fs.path.dirname(args[2]) orelse ".");
    defer program.deinit();
    try std.Io.File.stdout().writeStreamingAll(init.io, try program.compilation.emitQbe(allocator));
    return true;
}
