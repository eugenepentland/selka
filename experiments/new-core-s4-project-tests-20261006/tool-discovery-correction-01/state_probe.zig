const std = @import("std");
const discovery = @import("discovery");
pub fn main(init: std.process.Init) !void {
    const a=init.arena.allocator();
    const args=try init.minimal.args.toSlice(a);
    const digest=try discovery.state(a,init.io,args[1]);
    std.debug.print("state={s}\n",.{std.fmt.bytesToHex(digest,.lower)});
    for(try discovery.paths(a,args[1])) |entry| {
        std.debug.print("{s} {s}\n",.{@tagName(entry.role),entry.name});
    }
}
