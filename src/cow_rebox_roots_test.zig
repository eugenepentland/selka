//! Replacing recursive owners keeps earlier snapshots rooted at each allocation.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

const source =
    \\record Node:
    \\    mapping: dict[int, int]
    \\    child: Option[Node]
    \\
    \\def through(value: Option[Node]) -> Option[Node]:
    \\    return value
    \\
    \\def warm() -> bool:
    \\    original: Option[Node] = Some(Node({1: 7}, None))
    \\    saved = through(original)
    \\    if original is None or saved is None:
    \\        return False
    \\    original.mapping[1] = 13
    \\    return original.mapping[1] == 13 and saved.mapping[1] == 7
    \\
    \\def repeated() -> bool:
    \\    original: Option[Node] = Some(Node({1: 7}, None))
    \\    saved = through(original)
    \\    if original is None or saved is None:
    \\        return False
    \\    original.mapping[1] = 13
    \\    original.mapping[1] = 17
    \\    return original.mapping[1] == 17 and saved.mapping[1] == 7
    \\
    \\def main() -> int:
    \\    if not warm():
    \\        return 1
    \\    if not repeated():
    \\        return 2
    \\    return 0
;

// spec: COW-BOX-REBOX-ROOTS-1
test "GC reboxing roots preserve snapshots across standalone repeated writes" {
    var compilation = try language.Compilation.init(t.allocator, "rebox-roots.my", source);
    defer compilation.deinit();
    const result = try native.runWithPolicy(&compilation, .{ .step_checks = false, .frame_checks = false, .cow = .checks }, .{});
    try t.expect(!result.trapped());
    try t.expectEqual(@as(i64, 0), result.value);
}
