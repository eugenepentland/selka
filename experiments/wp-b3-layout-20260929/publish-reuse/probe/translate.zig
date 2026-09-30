const std = @import("std");
const llvm = @import("llvm");
test "translate actual publication and release fragments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signatures: llvm.Signatures = .empty;
    const table = try llvm.RuntimeTable.read(a, &.{.{ .name = "probe.h", .bytes = "void myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop(void *heap, void *slot);\nvoid myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan(void *heap, void *slot);\nint myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_publish(void *heap, void *dst, void *src, unsigned region, unsigned mode);\nint myl_rc_take_failure(void *heap);\nint myl_qbe_rc_status(void *ctx, unsigned status);\n" }});
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, ".tmp/pub-proof/fragments.ssa", a, .limited(1 << 20));
    var units = std.mem.splitSequence(u8, text, "\n\n");
    inline for (.{ "owner", "hold", "publish" }) |name| {
        const unit = units.next() orelse return error.MissingUnit;
        var diagnostic: llvm.Diagnostic = .{ .unit = name };
        const translated = try llvm.translate(a, unit, .{ .signatures = &signatures, .runtime = &table }, &diagnostic);
        const path = ".tmp/pub-proof/" ++ name ++ ".ll";
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = translated });
    }
}
