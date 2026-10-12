//! Unit bindings have no SSA owner; named provider restrictions still form scopes.
const std = @import("std");
const language = @import("mylang");
const ownership = @import("single_owner.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const report = std.debug.print;

fn lowers(parent: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "provider-store.my", source);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |diagnostic| report("{s}: {s}\n", .{ diagnostic.code, diagnostic.message });
        return err;
    };
    var failure: ownership.Failure = .{};
    ownership.checkMode(a, unit.program.?, &failure, true) catch |err| {
        report("{s}: {s}\n", .{ failure.code, failure.message });
        return err;
    };
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
    const result = try passes.debug(a, &module);
    try ownership.verifyLowered(&module, &failure);
    try support.verified(a, &module, result.plans);
}

// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC provider stores skip Unit bindings and discarded set insertion" {
    try lowers(std.testing.allocator,
        \\func main() -> int:
        \\    const unit = ()
        \\    mut values = {1, 2}
        \\    values.add(3)
        \\    _ = unit
        \\    return len(values)
    );
}

// spec-case: NEW-CORE-ZERO-RC-ABI-1
test "zero RC provider restrictions borrow a named parent inside their scope" {
    try lowers(std.testing.allocator,
        \\func main(fs: Filesystem) -> int:
        \\    with fs.read_only() as frozen:
        \\        if frozen.exists("absent"):
        \\            return 1
        \\        return 0
    );
}
