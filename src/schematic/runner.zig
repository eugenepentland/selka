//! Execute the guest DSL parser and SVG generator with three explicitly supplied source files.
const std = @import("std");
const print = std.debug.print;
const application = @import("app.zig");
const diagnostics = @import("diagnostics.zig");
const native = @import("host_native");
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
    // The ceilings one render runs under come from the build policy itself, so
    // only collection stress travels from the command line.
    const arguments: []const []const u8 = if (start > 1) &.{"--gc-stress"} else &.{};
    // RC-DEFAULT-1: stress needs the collector, so a stressed render builds its
    // guest under the tracing GC instead of the reference-counting default.
    if (start > 1) try init.environ_map.put("MYLANG_RUNTIME", "gc-v1");
    const selected = try buildOptions(args, &start);
    if (start < args.len and std.mem.eql(u8, args[start], "--dev-session")) {
        if (start + 1 != args.len) return error.InvalidSchematic;
        return @import("dev_session.zig").run(init, selected);
    }
    const inputs = args[start..];
    if (inputs.len != 5 or !std.mem.eql(u8, inputs[0], "--project")) {
        print("usage: schematic-svg [--gc-stress] [--bounded] [--backend qbe|llvm [--llvm-opt 0|1|2|3|s|z] [--lto]] --project DIRECTORY MODULE.sexp PINOUT.sexp INTERFACE.sexp > output.svg\n", .{});
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
/// The build policy this invocation asks for: the shipped release policy unless
/// a flag names another code generator or restores instruction accounting.
fn buildOptions(args: []const []const u8, start: *usize) !native.BuildOptions {
    var result: native.BuildOptions = application.release;
    while (start.* < args.len) {
        const argument = args[start.*];
        if (std.mem.eql(u8, argument, "--lto")) {
            result.llvm.lto = true;
            start.* += 1;
            continue;
        }
        if (std.mem.eql(u8, argument, "--bounded")) {
            result.accounting = .steps;
            start.* += 1;
            continue;
        }
        const field: enum { backend, llvm_opt } = if (std.mem.eql(u8, argument, "--backend"))
            .backend
        else if (std.mem.eql(u8, argument, "--llvm-opt"))
            .llvm_opt
        else
            break;
        if (start.* + 1 >= args.len) return error.InvalidSchematic;
        const value = args[start.* + 1];
        switch (field) {
            .backend => {
                result.backend = std.meta.stringToEnum(native.Backend, value) orelse return error.InvalidSchematic;
                // QBE refuses the release policy's LLVM controls, so naming it
                // drops them rather than failing the build behind the flag.
                if (result.backend == .qbe) result.llvm = .{};
            },
            .llvm_opt => result.llvm.optimization = value,
        }
        start.* += 2;
    }
    return result;
}

// spec: SCHEMATIC-RUNNER-POLICY-1
test "the runner ships the release policy and keeps the bounded and QBE arms" {
    var start: usize = 1;
    const shipped = try buildOptions(&.{"schematic-svg"}, &start);
    try std.testing.expectEqual(native.Backend.llvm, shipped.backend);
    try std.testing.expectEqualStrings("3", shipped.llvm.optimization.?);
    try std.testing.expectEqual(false, shipped.llvm.lto);
    try std.testing.expectEqual(native.Accounting.frames, shipped.accounting);
    start = 1;
    const qbe = try buildOptions(&.{ "schematic-svg", "--backend", "qbe", "--bounded" }, &start);
    try std.testing.expectEqual(native.Backend.qbe, qbe.backend);
    try std.testing.expectEqual(@as(?[]const u8, null), qbe.llvm.optimization);
    try std.testing.expectEqual(native.Accounting.steps, qbe.accounting);
    try std.testing.expectEqual(@as(usize, 4), start);
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
