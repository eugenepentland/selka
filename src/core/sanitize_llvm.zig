//! TSAN-BUILD-1: add instrumentation attributes to all emitted definitions,
//! including fixed inline helpers, generated adapters and the native entry.
const std = @import("std");

/// LLVM input with every definition marked for ThreadSanitizer. The native
/// driver uses this only when SELKA_CORE_SANITIZE=thread was validated.
pub fn instrument(a: std.mem.Allocator, input: []const u8) std.mem.Allocator.Error![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, input, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try output.append(a, '\n');
        first = false;
        if (!std.mem.startsWith(u8, line, "define ") or std.mem.indexOf(u8, line, " sanitize_thread") != null) {
            try output.appendSlice(a, line);
            continue;
        }
        // All emitter definitions have their opening brace on the signature
        // line. A struct return/parameter may have earlier braces.
        const brace = std.mem.lastIndexOfScalar(u8, line, '{') orelse {
            try output.appendSlice(a, line);
            continue;
        };
        const metadata = std.mem.indexOf(u8, line[0..brace], " !");
        const end = metadata orelse std.mem.trimEnd(u8, line[0..brace], " ").len;
        try output.appendSlice(a, line[0..end]);
        try output.appendSlice(a, " sanitize_thread");
        try output.appendSlice(a, line[end..]);
    }
    return output.toOwnedSlice(a);
}

// spec: TSAN-BUILD-1
test "thread instrumentation covers every emitted definition before debug metadata and is idempotent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input =
        \\declare ptr @external(ptr)
        \\define internal fastcc { i64, ptr } @task(ptr %env) nounwind !dbg !12 {
        \\  ret { i64, ptr } zeroinitializer
        \\}
        \\define weak_odr hidden ptr @bridge(ptr %fn, ptr %env) {
        \\  %value = call fastcc ptr %fn(ptr %env)
        \\  ret ptr %value
        \\}
        \\define i32 @main() sanitize_thread {
        \\  ret i32 0
        \\}
    ;
    const text = try instrument(arena.allocator(), input);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, text, " sanitize_thread"));
    try std.testing.expect(std.mem.indexOf(u8, text, "nounwind sanitize_thread !dbg !12 {") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@bridge(ptr %fn, ptr %env) sanitize_thread {") != null);
    try std.testing.expect(std.mem.startsWith(u8, text, "declare ptr @external(ptr)\n"));
    try std.testing.expectEqualStrings(text, try instrument(arena.allocator(), text));
}
