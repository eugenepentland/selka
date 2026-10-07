const std = @import("std");
const frontend = @import("frontend.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    const entry = frontend.entryOf(args[1]);
    var session = frontend.Session.init(a, init.io, entry.root);
    defer session.deinit();
    var report: std.ArrayList(u8) = .empty;
    const checked = try session.checkFile(a, args[1], &report);
    var refusal: build.Refusal = .{};
    var module = try build.buildModuleSource(a, checked.program, checked.src, &refusal);
    _ = try passes.run(a, &module, .trusted);
    var output: std.ArrayList(u8) = .empty;
    for (module.functions.items) |function| {
        var blocks: usize = 0;
        var instructions: usize = 0;
        var loops: usize = 0;
        for (function.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            blocks += 1;
            for (block.insts.items) |ref| if (function.inst(ref).op != .copy) { instructions += 1; };
        }
        for (function.loops.items) |loop| if (loop.body.index() == 0 or function.blocks.items[loop.body.index()].preds.items.len != 0) { loops += 1; };
        try output.print(a, "{s}\t{d}\t{d}\t{d}\t{d}\n", .{function.name,blocks,instructions,function.loops.items.len,loops});
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, output.items);
}
