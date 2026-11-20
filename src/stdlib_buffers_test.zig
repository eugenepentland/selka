//! The byte-buffer module's words append bytes, integers, floats, UTF-8 and ranges.
const std = @import("std");
const fixture = @import("stdlib_fixture.zig");

// spec: STDLIB-BUFFERS-1
test "standard buffers append every element shape and answer an independent copy" {
    try fixture.run(std.testing.allocator, @embedFile("stdlib/fixtures/buffers_fixture.selka"), 42);
}

test "a byte-buffer method write is refused, and its home is the repair" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try fixture.rejectsWith(arena.allocator(),
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    mut data = byte_buffer(empty)
        \\    _ = data.append_byte(65)
        \\    return 0
        \\
    , "E_METHOD_REMOVED");
}

test "a byte-buffer method that always writes has no value to refuse with, so it is refused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try fixture.rejectsWith(arena.allocator(),
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    mut data = byte_buffer(empty)
        \\    if data.append_int(1):
        \\        return 2
        \\    return 0
        \\
    , "E_METHOD_REMOVED");
}

test "a buffer home that can refuse answers a bool, so a bare statement of it is refused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try fixture.rejectsWith(arena.allocator(),
        \\import buffers
        \\
        \\func main() -> int:
        \\    mut data = buffers.empty()
        \\    buffers.append_byte(mut data, 65)
        \\    return 0
        \\
    , "E_EXPLICIT_DISCARD_REQUIRED");
}

test "a buffer home that always writes answers nothing, so a value use is refused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try fixture.rejectsWith(arena.allocator(),
        \\import buffers
        \\
        \\func main() -> int:
        \\    mut data = buffers.empty()
        \\    if buffers.append_int(mut data, 1):
        \\        return 2
        \\    return 0
        \\
    , "E_TYPE");
}
