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
    var timings = language.timings.Profile.init(init.io, options.timings_json, .byte_io);
    var status: u8 = 1;
    defer timings.report(status) catch |err| print("mylang-io: timing report: {s}\n", .{@errorName(err)});
    try execute(init, options, &timings);
    status = 0;
}
fn execute(init: std.process.Init, options: @import("limits.zig").Options, timings: *language.timings.Profile) !void {
    const allocator = init.arena.allocator();
    timings.begin("compilation_inclusive", true);
    var program: language.embedded_project.Program = undefined;
    try program.initDisk(allocator, init.io, options.project);
    defer program.deinit();
    timings.counts.modules = program.loaded.modules.items.len;
    timings.counts.source_bytes = program.loaded.counts.bytes;
    timings.counts.ast_nodes = program.compilation.syntax.nodes.items.len + program.compilation.syntax.statements.items.len;
    timings.counts.typed_nodes = program.compilation.program.?.nodes.len + program.compilation.program.?.statements.len;
    timings.begin("stdin_read", false);
    var buffer: [8192]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    const input = try reader.interface.allocRemaining(allocator, .limited(options.input + 1));
    timings.counts.input_bytes = input.len;
    try validateInputLength(input.len, options.input);
    timings.end();
    // VM and host-call temporaries must be reclaimable within a long invocation.
    // Source/input storage may use the process arena because it has one lifetime.
    var total: language.allocation_budget.Memory = .{ .parent = init.gpa, .limit = options.memory.total };
    var vm_budget = total.child(options.memory.vm);
    var host_budget = total.child(options.memory.host);
    var observations: @import("memory_budget.zig").Observations = .{
        .backing = vm_budget.child(options.memory.vm),
        .bookkeeping = vm_budget.child(options.memory.vm),
    };
    defer @import("memory_budget.zig").report(init.io, options.memory, total, vm_budget, host_budget, observations);
    const runtime_allocator = observations.bookkeeping.allocator();
    var context: bridge.Context = .{ .allocator = host_budget.allocator(), .input = input, .output_limit = options.output };
    defer context.deinit();
    var registry = try language.vm_host.Registry.init(runtime_allocator, program.compilation.code.?);
    defer registry.deinit();
    try context.install(&registry);
    var grants: @import("grants.zig").State = undefined;
    try grants.init(host_budget.allocator(), init.io, options.grants);
    defer grants.deinit();
    var vm_options = grants.options();
    vm_options.max_steps = options.execution.steps;
    vm_options.memory.backing_allocator = observations.backing.allocator();
    vm_options.memory.statistics = &observations.buffers;
    vm_options.pools.statistics = &observations.pools;
    timings.begin("vm_execution", false);
    const result = try language.vm.runWithHost(runtime_allocator, program.compilation.code.?, vm_options, &registry, .{ .max_calls = options.execution.calls, .max_work = options.execution.work });
    timings.end();
    switch (result) {
        .trap => |trap| {
            const message = try trap.render(allocator, program.compilation.src);
            print("{s}", .{message});
            return error.GuestTrap;
        },
        .value => |value| try validateExit(value),
    }
    timings.begin("stdout_write", false);
    try std.Io.File.stdout().writeStreamingAll(init.io, context.output.items);
    timings.counts.output_bytes = context.output.items.len;
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
    try t.expectError(error.InvalidArguments, @import("limits.zig").parse(&.{"mylang-io"}));
    try t.expectError(error.InvalidArguments, @import("limits.zig").parse(&.{ "mylang-io", "--unknown", "." }));
    try t.expectEqualStrings("project", (try @import("limits.zig").parse(&.{ "mylang-io", "--project", "project" })).project);
    try validateInputLength(2 * 1024 * 1024, 2 * 1024 * 1024);
    try t.expectError(error.InputLimit, validateInputLength(2 * 1024 * 1024 + 1, 2 * 1024 * 1024));
    try validateExit(0);
    try t.expectError(error.GuestExit, validateExit(1));
    try t.expectError(error.GuestExit, validateExit(-1));
}
// spec: SCOPED-PROVIDERS-4
test "runner grants require explicit directories and numeric endpoints" {
    const t = std.testing;
    const parse = @import("limits.zig").parse;
    try t.expectError(error.InvalidArguments, parse(&.{ "mylang-io", "--project", ".", "--allow-write" }));
    try t.expectError(error.InvalidArguments, parse(&.{ "mylang-io", "--project", ".", "--allow-dir=a", "--allow-dir=b" }));
    try t.expectError(error.InvalidArguments, parse(&.{ "mylang-io", "--project", ".", "--allow-endpoint=example.org:80" }));
    const options = try parse(&.{ "mylang-io", "--project", ".", "--allow-dir=data", "--allow-write", "--allow-endpoint=127.0.0.1:8000" });
    try t.expectEqualStrings("data", options.grants.directory.?);
    try t.expect(options.grants.writable);
    try t.expectEqual(@as(usize, 1), options.grants.count);
}
