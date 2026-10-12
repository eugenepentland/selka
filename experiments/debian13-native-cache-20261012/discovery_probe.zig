const std = @import("std");
const discovery = @import("discovery");
const platform = @import("core_tool_platform");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var profile = platform.profiles[0].discovery;
    profile.installation = "/usr/lib/gcc/x86_64-linux-gnu/14";
    profile.installation_predicates = &.{ "", "include/c++", "include/g++-v14", "include/g++-v14.-1" };
    profile.predicates = &.{
        "/opt/rh",                   "/etc/env.d/gcc",                       "/lib",                                 "/lib64",                    "/lib/x86_64-linux-gnu",
        "/usr/lib/x86_64-linux-gnu", "/usr/x86_64-linux-gnu/lib",            "/usr/x86_64-linux-gnu/lib64",          "/usr/x86_64-linux-gnu/bin", "/usr/lib/gcc/x86_64-linux-gnu/lib64",
        "/usr/include/c++/14",       "/usr/include/x86_64-linux-gnu/c++/14", "/usr/x86_64-linux-gnu/include/c++/14",
    };
    const digest = try discovery.profileState(arena, init.io, args[1], profile);
    std.debug.print("state={s}\n", .{std.fmt.bytesToHex(digest, .lower)});
    for (try discovery.profilePaths(arena, args[1], profile)) |entry|
        std.debug.print("{s} {s}\n", .{ @tagName(entry.role), entry.name });
}
