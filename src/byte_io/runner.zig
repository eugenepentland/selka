//! Disk-loaded native applications with only bounded raw stdin/stdout authority.
const std = @import("std");
const print = std.debug.print;
const language = @import("mylang");
const host = @import("host.zig");
const limits = @import("limits.zig");
const bulk = @import("bulk.zig");
/// Publish output only after a successful guest exit; send tool failures to stderr.
pub fn main(init: std.process.Init) void {
    run(init) catch |err| {
        print("mylang-io: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
fn run(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (try emit(init, args)) return;
    var options = try limits.parse(args);
    limits.inherit(&options, init.environ_map);
    var timings = language.timings.Profile.init(init.io, options.timings_json, .byte_io);
    var status: u8 = 1;
    defer timings.report(status) catch |err| print("mylang-io: timing report: {s}\n", .{@errorName(err)});
    try execute(init, options, &timings);
    status = 0;
}
/// Serve the native build driver's frontend request from this same executable,
/// so a byte application needs no separately installed compiler to build itself.
fn emit(init: std.process.Init, args: []const []const u8) !bool {
    if (args.len != 3 or !std.mem.eql(u8, args[1], "emit-project-qbe")) return false;
    const allocator = init.arena.allocator();
    var program: language.embedded_project.Program = undefined;
    try program.initDisk(allocator, init.io, std.fs.path.dirname(args[2]) orelse ".");
    defer program.deinit();
    try std.Io.File.stdout().writeStreamingAll(init.io, try program.compilation.emitQbe(allocator));
    return true;
}
fn execute(init: std.process.Init, options: limits.Options, timings: *language.timings.Profile) !void {
    const allocator = init.arena.allocator();
    timings.begin("compilation_inclusive", true);
    var program: language.embedded_project.Program = undefined;
    try program.initDisk(allocator, init.io, options.project);
    defer program.deinit();
    timings.counts.modules = program.loaded.modules.items.len;
    timings.counts.source_bytes = program.loaded.counts.bytes;
    timings.counts.ast_nodes = program.compilation.syntax.nodes.items.len + program.compilation.syntax.statements.items.len;
    timings.counts.typed_nodes = program.compilation.program.?.nodes.len + program.compilation.program.?.statements.len;
    // The copied-block ABI is structural, so it is settled against the emitted
    // native metadata before any trusted callback is linked into the guest.
    const shape = try bulk.validate(allocator, try program.compilation.emitQbe(allocator));
    var session = try host.Session.init(init, options, shape);
    defer session.deinit();
    timings.begin("stdin_read", false);
    var buffer: [8192]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    const input = try reader.interface.allocRemaining(allocator, .limited(options.input + 1));
    timings.counts.input_bytes = input.len;
    try validateInputLength(input.len, options.input);
    timings.end();
    timings.begin("vm_execution", false);
    const value = try session.invoke(input, options.execution.steps);
    timings.end();
    try validateExit(value);
    const published = try session.output();
    timings.begin("stdout_write", false);
    try std.Io.File.stdout().writeStreamingAll(init.io, published);
    timings.counts.output_bytes = published.len;
    timings.end();
}

fn validateInputLength(length: usize, limit: usize) error{InputLimit}!void {
    if (length > limit) return error.InputLimit;
}
fn validateExit(value: i64) error{GuestExit}!void {
    if (value != 0) return error.GuestExit;
}
test "runner rejects InvalidArguments InputLimit and GuestExit at the publication boundary" {
    const t = std.testing;
    try t.expectError(error.InvalidArguments, limits.parse(&.{"mylang-io"}));
    try t.expectError(error.InvalidArguments, limits.parse(&.{ "mylang-io", "--unknown", "." }));
    try t.expectEqualStrings("project", (try limits.parse(&.{ "mylang-io", "--project", "project" })).project);
    try validateInputLength(2 * 1024 * 1024, 2 * 1024 * 1024);
    try t.expectError(error.InputLimit, validateInputLength(2 * 1024 * 1024 + 1, 2 * 1024 * 1024));
    try validateExit(0);
    try t.expectError(error.GuestExit, validateExit(1));
    try t.expectError(error.GuestExit, validateExit(-1));
}
// spec-case: SCOPED-PROVIDERS-4
test "runner grants require explicit directories and numeric endpoints" {
    const t = std.testing;
    try t.expectError(error.InvalidArguments, limits.parse(&.{ "mylang-io", "--project", ".", "--allow-write" }));
    try t.expectError(error.InvalidArguments, limits.parse(&.{ "mylang-io", "--project", ".", "--allow-dir=a", "--allow-dir=b" }));
    try t.expectError(error.InvalidArguments, limits.parse(&.{ "mylang-io", "--project", ".", "--allow-endpoint=example.org:80" }));
    const options = try limits.parse(&.{ "mylang-io", "--project", ".", "--allow-dir=data", "--allow-write", "--allow-endpoint=127.0.0.1:8000" });
    try t.expectEqualStrings("data", options.grants.directory.?);
    try t.expect(options.grants.writable);
    try t.expectEqual(@as(usize, 1), options.grants.count);
}
