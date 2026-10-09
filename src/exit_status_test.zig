//! The entry point's `int` result is the process exit status, truncated to the
//! low 8 bits, and `--print-result` remains an orthogonal way to print it.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

/// Build one guest program and run it once through the native backend.
fn run(source: []const u8) !native.Run {
    var compilation = try language.Compilation.init(t.allocator, "exit.selka", source);
    defer compilation.deinit();
    return native.run(&compilation);
}

// spec: EXIT-STATUS-1
test "a program returning 7 exits with status 7" {
    const outcome = try run(
        \\func main() -> int:
        \\    return 7
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(i64, 7), outcome.value);
    try t.expectEqual(@as(u8, 7), outcome.status);
}

// spec-case: EXIT-STATUS-1
test "a returned value wider than a byte truncates so 256 exits 0" {
    const outcome = try run(
        \\func main() -> int:
        \\    return 256
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(i64, 256), outcome.value);
    try t.expectEqual(@as(u8, 0), outcome.status);
}

// spec-case: EXIT-STATUS-1
test "a returned value keeps only its low byte so 259 exits 3" {
    const outcome = try run(
        \\func main() -> int:
        \\    return 259
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(u8, 3), outcome.status);
}

// spec-case: EXIT-STATUS-1
test "a runtime trap outranks the return and exits 1" {
    const outcome = try run(
        \\func main() -> int:
        \\    _ = divtrunc(1, 0)
        \\    return 7
    );
    try t.expect(outcome.trapped());
    try t.expectEqualStrings("R_DIVISION_BY_ZERO", outcome.trap.code);
    try t.expectEqual(@as(u8, 1), outcome.status);
}

// spec-case: EXIT-STATUS-1
test "print-result still prints the value while the status reflects it" {
    // The native runner always passes --print-result, so the value line follows
    // the program's own output; the exit status carries the same value.
    const outcome = try run(
        \\func main(out: Stream) -> int:
        \\    out.print("hi")
        \\    return 5
    );
    try t.expect(!outcome.trapped());
    try t.expectEqualStrings("hi\n", outcome.stdout);
    try t.expectEqual(@as(i64, 5), outcome.value);
    try t.expectEqual(@as(u8, 5), outcome.status);
}

// spec-case: EXIT-STATUS-1
test "a unit entry exits 0 and a Result entry carries its adapted code" {
    const ok = try run(
        \\func main():
        \\    pass
    );
    try t.expect(!ok.trapped());
    try t.expectEqual(@as(u8, 0), ok.status);
    const err = try run(
        \\func main() -> Result[Unit, int]:
        \\    return Err(9)
    );
    try t.expect(!err.trapped());
    try t.expectEqual(@as(i64, 9), err.value);
    try t.expectEqual(@as(u8, 9), err.status);
}
