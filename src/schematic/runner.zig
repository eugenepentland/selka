//! Execute the guest DSL parser and SVG generator with three explicitly supplied source files.
const std = @import("std");
const print = std.debug.print;
const application = @import("app.zig");
const diagnostics = @import("diagnostics.zig");
const native = @import("host_native");
/// The native step budget one schematic rendering may spend.
const steps = native.step_budget;
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
    if (try emit(init, args)) return;
    var start: usize = 1;
    while (start < args.len and std.mem.eql(u8, args[start], "--gc-stress")) start += 1;
    const arguments: []const []const u8 = if (start > 1) &.{ steps, "--gc-stress" } else &.{steps};
    const selected = try buildOptions(args, &start);
    if (start < args.len and std.mem.eql(u8, args[start], "--dev-session")) {
        if (start + 1 != args.len) return error.InvalidSchematic;
        return @import("dev_session.zig").run(init, selected);
    }
    const inputs = args[start..];
    if (inputs.len != 5 or !std.mem.eql(u8, inputs[0], "--project")) {
        print("usage: schematic-svg [--gc-stress] [--backend llvm [--llvm-opt 0|1|2|3|s|z] [--lto]] --project DIRECTORY MODULE.sexp PINOUT.sexp INTERFACE.sexp > output.svg\n", .{});
        return error.InvalidSchematic;
    }
    var documents: [3][]const u8 = undefined;
    for (inputs[2..], &documents) |path, *out| out.* = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(1024 * 1024));
    var app: application.App = undefined;
    try app.initDiskWithOptions(init, inputs[1], selected);
    defer app.deinit();
    const svg = app.run(&documents, arguments) catch |err| {
        if (app.issue) |issue| diagnostics.report(issue, inputs[2..], &documents);
        return err;
    };
    try std.Io.File.stdout().writeStreamingAll(init.io, svg);
}
fn buildOptions(args: []const []const u8, start: *usize) !native.BuildOptions {
    var result: native.BuildOptions = .{};
    while (start.* < args.len) {
        const argument = args[start.*];
        if (std.mem.eql(u8, argument, "--lto")) {
            result.lto = true;
            start.* += 1;
            continue;
        }
        const field: enum { backend, llvm_opt, llvm_adapter } = if (std.mem.eql(u8, argument, "--backend"))
            .backend
        else if (std.mem.eql(u8, argument, "--llvm-opt"))
            .llvm_opt
        else if (std.mem.eql(u8, argument, "--llvm-adapter"))
            .llvm_adapter
        else
            break;
        if (start.* + 1 >= args.len) return error.InvalidSchematic;
        const value = args[start.* + 1];
        switch (field) {
            .backend => result.backend = std.meta.stringToEnum(native.Backend, value) orelse return error.InvalidSchematic,
            .llvm_opt => result.llvm_opt = value,
            .llvm_adapter => result.llvm_adapter = value,
        }
        start.* += 2;
    }
    return result;
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
