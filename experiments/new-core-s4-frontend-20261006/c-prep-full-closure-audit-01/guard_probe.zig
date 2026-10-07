//! Audit the unchanged production helper with an owned external resource.
const std = @import("std");
const tool = @import("tool");

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 4) return error.InvalidArguments;
    var environment = try init.minimal.environ.createMap(a);
    defer environment.deinit();
    const request: tool.Request = .{ .arena = a, .io = init.io, .environment = &environment, .executable = args[1], .cache = args[3] };
    const before = try tool.capture(request);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[2], .data = "# owned external resource added after capture\n" });
    const stable = try tool.unchanged(request, before);
    const after = try tool.capture(request);
    std.debug.print("cacheable_before={}\ncacheable_after={}\ninputs={}\nunchanged={}\n", .{ before.cacheable, after.cacheable, before.inputs, stable });
    std.debug.print("before_digest={s}\nafter_digest={s}\n", .{ std.fmt.bytesToHex(before.digest, .lower), std.fmt.bytesToHex(after.digest, .lower) });
    std.debug.print("before_generation={s}\nafter_generation={s}\n", .{ std.fmt.bytesToHex(before.generation, .lower), std.fmt.bytesToHex(after.generation, .lower) });
    if (!before.cacheable or !after.cacheable) return error.UnprovedFixture;
}
