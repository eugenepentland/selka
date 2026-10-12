//! Bounded map captures and result transfer through the generated range worker.
const std = @import("std");
const language = @import("mylang");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const contract = @import("single_owner.zig");
const passes = @import("passes.zig");

const source =
    \\import parallel
    \\func transform(value: str) -> str:
    \\    return value + "!"
    \\func main(out: Stream) -> int:
    \\    const result = parallel.map(["input-" + str(7)], transform)
    \\    out.print(result[0])
    \\    return 0
;

const Entry = struct {
    /// Load the entry and leave standard imports to the embedded loader.
    pub fn read(_: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        return a.dupe(u8, source);
    }
};

fn module(a: std.mem.Allocator) !ir.Module {
    var context: u8 = 0;
    var project: language.embedded_project.Program = undefined;
    try project.init(a, .{ .context = &context, .read = Entry.read });
    const checked = project.compilation.program.?;
    var failure: contract.Failure = .{};
    try contract.checkMode(a, checked, &failure, true);
    var refusal: @import("build.zig").Refusal = .{};
    return @import("build.zig").buildExecutable(a, .{ .program = checked, .source = project.compilation.src, .single_owner = true, .zero_rc = true }, &refusal);
}

// spec-case: NEW-CORE-ZERO-RC-TASKS-2
test "zero RC map worker borrows one source list and returns one owned chunk without element boxes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m = try module(a);
    try support.verified(a, &m, &.{});
    var found: usize = 0;
    for (m.functions.items) |function| {
        if (!std.mem.startsWith(u8, function.name, "<parallel.map.worker.")) continue;
        found += 1;
        try std.testing.expectEqual(.list, m.kind(function.signature.ret));
        const capture = m.compound(m.compound(function.signature.params[0]).box).record;
        try std.testing.expectEqual(@as(usize, 4), capture.len);
        try std.testing.expectEqual(.list, m.kind(capture[0]));
        try std.testing.expectEqual(@as(usize, 1), function.loops.items.len);
        var marked = false;
        for (function.insts.items) |inst| {
            try std.testing.expect(inst.op != .box_make);
            if (inst.op == .call and std.mem.eql(u8, m.functions.items[inst.a.index()].name, "myl_core_task_item")) marked = true;
        }
        try std.testing.expect(marked);
    }
    try std.testing.expectEqual(@as(usize, 1), found);
    const result = try passes.run(a, &m, .verify);
    try support.verified(a, &m, result.plans);
    var failure: contract.Failure = .{};
    try contract.verifyLowered(&m, &failure);
}
