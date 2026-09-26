//! Live view metadata owns H while projected dictionary loans remain H-only.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;

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
    try t.expect(std.mem.indexOf(u8, text, "call $myl_rc_hold_acquire") != null);
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
}
