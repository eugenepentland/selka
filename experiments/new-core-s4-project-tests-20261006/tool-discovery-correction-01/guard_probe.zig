//! Real approved-tool guard replay; only task-owned side inputs are changed.
const std = @import("std");
const tool = @import("tool");
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 4 and args.len != 5) return error.InvalidArguments;
    var environment = try init.minimal.environ.createMap(a);
    defer environment.deinit();
    const request: tool.Request = .{ .arena = a, .io = init.io, .environment = &environment, .executable = args[1], .cache = args[3] };
    const initial = try tool.capture(request);
    std.debug.print("cacheable_before={}\nbefore_inputs={}\nbefore_digest={s}\nbefore_generation={s}\nready=true\n", .{ initial.cacheable, initial.inputs, std.fmt.bytesToHex(initial.digest, .lower), std.fmt.bytesToHex(initial.generation, .lower) });
    var buffer: [8]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    _ = try reader.interface.takeByte();
    const provisional = try tool.lookupReplayCandidate(request);
    if (args.len == 5 and std.mem.eql(u8, args[4], "file-parent")) {
        const info = try std.Io.Dir.cwd().statFile(init.io, args[2], .{});
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[2], .data = "other" });
        try std.Io.Dir.cwd().setTimestamps(init.io, args[2], .{ .modify_timestamp = .init(info.mtime) });
    } else {
        try std.Io.Dir.cwd().createDirPath(init.io, std.fs.path.dirname(args[2]).?);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[2], .data = "# owned external resource added after capture\n" });
    }
    const stable = try tool.unchanged(request, initial);
    const replay_stable = if (provisional) |candidate| try tool.unchanged(request, candidate) else false;
    const final = try tool.capture(request);
    std.debug.print("cacheable_after={}\nafter_inputs={}\nunchanged={}\nprovisional_present={}\nprovisional_unchanged={}\nafter_digest={s}\nafter_generation={s}\n", .{ final.cacheable, final.inputs, stable, provisional != null, replay_stable, std.fmt.bytesToHex(final.digest, .lower), std.fmt.bytesToHex(final.generation, .lower) });
}
