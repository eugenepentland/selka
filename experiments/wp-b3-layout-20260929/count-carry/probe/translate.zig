const std = @import("std");
const llvm = @import("llvm");
test "translate actual extracted count fragments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signatures: llvm.Signatures = .empty;
    const table = try llvm.RuntimeTable.read(a, &.{.{ .name = "probe.h", .bytes = "int myl_qbe_rc_status(void *ctx, unsigned status);\n" }});
    inline for (.{ "count", "zero" }) |kind| {
        const path = ".tmp/carry-probe/" ++ kind ++ "-probe.ssa";
        const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1 << 20));
        var units = std.mem.splitSequence(u8, text, "\n\n");
        inline for (.{ "owner", "hold" }) |name| {
            const unit = units.next() orelse return error.MissingUnit;
            var diagnostic: llvm.Diagnostic = .{ .unit = name };
            const translated = try llvm.translate(a, unit, .{ .signatures = &signatures, .runtime = &table }, &diagnostic);
            const out = try std.fmt.allocPrint(a, ".tmp/carry-probe/{s}-{s}.ll", .{ kind, name });
            try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = out, .data = translated });
        }
    }
}
