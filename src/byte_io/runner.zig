//! Disk-loaded bytecode applications with only bounded raw stdin/stdout authority.
const std = @import("std");
const print = std.debug.print;
const language = @import("mylang");
const bridge = @import("host.zig");
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
    const options = try @import("limits.zig").parse(args);
    var program: language.embedded_project.Program = undefined;
    try program.initDisk(allocator, init.io, options.project);
    defer program.deinit();
    var buffer: [8192]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    const input = try reader.interface.allocRemaining(allocator, .limited(options.input + 1));
    try validateInputLength(input.len, options.input);
    // VM and host-call temporaries must be reclaimable within a long invocation.
    // Source/input storage may use the process arena because it has one lifetime.
    const runtime_allocator = init.gpa;
    var context: bridge.Context = .{ .allocator = runtime_allocator, .input = input, .output_limit = options.output };
    defer context.deinit();
    var registry = try language.vm_host.Registry.init(runtime_allocator, program.compilation.code.?);
    defer registry.deinit();
    try context.install(&registry);
    const result = try language.vm.runWithHost(runtime_allocator, program.compilation.code.?, .{ .max_steps = options.steps }, &registry, .{ .max_calls = options.calls, .max_work = options.work });
    switch (result) {
        .trap => |trap| {
            const message = try trap.render(allocator, program.compilation.src);
            print("{s}", .{message});
            return error.GuestTrap;
        },
        .value => |value| try validateExit(value),
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, context.output.items);
}

fn validateInputLength(length: usize, limit: usize) error{InputLimit}!void {
    if (length > limit) return error.InputLimit;
}
fn validateExit(value: i64) error{GuestExit}!void {
    if (value != 0) return error.GuestExit;
}
test "runner rejects InvalidArguments InputLimit and GuestExit at the publication boundary" {
    const t = std.testing;
    try t.expectError(error.InvalidArguments, @import("limits.zig").parse(&.{"mylang-io"}));
    try t.expectError(error.InvalidArguments, @import("limits.zig").parse(&.{ "mylang-io", "--unknown", "." }));
    try t.expectEqualStrings("project", (try @import("limits.zig").parse(&.{ "mylang-io", "--project", "project" })).project);
    try validateInputLength(2 * 1024 * 1024, 2 * 1024 * 1024);
    try t.expectError(error.InputLimit, validateInputLength(2 * 1024 * 1024 + 1, 2 * 1024 * 1024));
    try validateExit(0);
    try t.expectError(error.GuestExit, validateExit(1));
    try t.expectError(error.GuestExit, validateExit(-1));
}
