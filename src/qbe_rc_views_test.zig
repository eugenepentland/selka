//! Live view metadata owns H while projected dictionary loans remain H-only.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;

fn iterationHeld(source: []const u8) !void {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "iteration_identity.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "# RC-GLUE-1 hold") != null);
    try t.expect(std.mem.indexOf(u8, text, "storew 8") != null);
    try t.expect(std.mem.indexOf(u8, text, "call $myl_qbe_fail_iteration") != null);
}

const iteration_dictionary =
    \\def main() -> int:
    \\    values = {1: 10}
    \\    for key in values:
    \\        values[2] = key
    \\    return 0
;
const iteration_list =
    \\def grow(values: mut list[int]) -> int:
    \\    for value in values:
    \\        _ = value
    \\        _ = values.pop()
    \\        continue
    \\    return 0
    \\def main() -> int:
    \\    values = [1]
    \\    return grow(mut values)
;

// spec: COW-ITERATION-IDENTITY-1
test "iteration identity retains dictionary headers with RC hold tokens" {
    try iterationHeld(iteration_dictionary);
}

// spec-case: COW-ITERATION-IDENTITY-1
test "iteration identity retains pinned list headers and checks continue steps" {
    try iterationHeld(iteration_list);
}

// spec-case: DICT-VIEWS-1
test "RC live dictionary views use hold shapes and guarded receiver holds" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_views.my",
        \\def main() -> int:
        \\    mapping = {1: 3}
        \\    live = mapping.values()
        \\    mapping[1] = 7
        \\    return list(live)[0]
    );
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "MYL_RC_SHAPE_HOLD_POINTER") != null);
    try t.expect(std.mem.indexOf(u8, text, "# RC-GLUE-1 hold") != null);
    try t.expect(std.mem.indexOf(u8, text, "storew 8") != null);
}

// spec-case: DICT-VIEWS-1
test "RC live dictionary views leave user shadow records with ordinary owner shapes" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_shadow_view.my",
        \\record DictValues[K, V]:
        \\    mapping: dict[K, V]
        \\def main() -> int:
        \\    original = {1: 7}
        \\    value = DictValues[int, int](mapping=original)
        \\    original[1] = 9
        \\    return value.mapping[1]
    );
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "MYL_RC_SHAPE_HOLD_POINTER") == null);
    try t.expect(std.mem.indexOf(u8, text, "call $myl_rc_hold_acquire") == null);
    try t.expect(std.mem.indexOf(u8, text, "# RC-GLUE-1 hold") == null);
}
