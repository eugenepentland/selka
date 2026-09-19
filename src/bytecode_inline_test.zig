//! Bytecode inlining removes calls that cannot allocate, including trapping
//! scalar helpers, and records the frames a removed call would have pushed.
const std = @import("std");
const language = @import("compiler.zig");
const inliner = @import("bytecode_inline.zig");
const native = @import("native_execute.zig");
const testing = std.testing;
/// Source path used by every inline test program.
const test_path = "inline.my";

/// A caller whose helper is a leaf of comparison and local operations. The call
/// sits in `use`, not the entry function, which keeps every entry frame.
const pure_program =
    \\def helper(x: i64) -> bool:
    \\    return x > 0
    \\
    \\
    \\def use(x: i64) -> bool:
    \\    return helper(x)
    \\
    \\
    \\def main() -> i64:
    \\    if use(41):
    \\        return 7
    \\    return 0
;

/// A caller whose helper performs a checked add: it can trap, but its lowering
/// never allocates, so the call is inlined.
const fallible_program =
    \\record Cell:
    \\    value: i64
    \\
    \\
    \\def risky(x: i64) -> i64:
    \\    return x + 1
    \\
    \\
    \\def make(x: i64) -> Cell:
    \\    return Cell(value=x)
    \\
    \\
    \\def use(x: i64) -> i64:
    \\    cell = make(x)
    \\    return risky(cell.value)
    \\
    \\
    \\def main() -> i64:
    \\    return use(41)
;

/// A caller whose helper constructs a record, which admits allocation.
const allocating_program =
    \\record Cell:
    \\    value: i64
    \\
    \\
    \\def make(x: i64) -> Cell:
    \\    return Cell(value=x)
    \\
    \\
    \\def use(x: i64) -> i64:
    \\    return make(x).value
    \\
    \\
    \\def main() -> i64:
    \\    return use(5)
;

/// A trapping bounds read reached through two transparent inlinable helpers, so
/// the runtime must replay both frames from the inline table.
const trace_program =
    \\record Buffer:
    \\    data: bytes
    \\
    \\
    \\def peek(buf: Buffer, i: i64) -> i64:
    \\    return buf.data[i]
    \\
    \\
    \\def use(buf: Buffer, i: i64) -> i64:
    \\    return peek(buf, i)
    \\
    \\
    \\def main() -> i64:
    \\    buf = Buffer(data=b"abc")
    \\    return use(buf, 9)
;

/// A caller rewritten in two fixpoint sweeps because it precedes its callees:
/// the second splice shifts the first one's pc, so its recorded call position
/// must move with it.
const resweep_program =
    \\def use(x: i64) -> i64:
    \\    first = b(0)
    \\    return first + a(x)
    \\
    \\
    \\def b(x: i64) -> i64:
    \\    return a(x)
    \\
    \\
    \\def a(x: i64) -> i64:
    \\    return x + 1
    \\
    \\
    \\def main() -> i64:
    \\    return use(9223372036854775807)
;

/// Number of direct calls left after lowering and inlining `source`.
fn loweredCallSites(source: []const u8) !usize {
    var compilation = try language.Compilation.init(testing.allocator, test_path, source);
    defer compilation.deinit();
    try compilation.emit();
    return inliner.callSites(compilation.code.?);
}

/// Whether the lowered program still contains a direct call to `name`.
fn keepsCall(source: []const u8, name: []const u8) !bool {
    var compilation = try language.Compilation.init(testing.allocator, test_path, source);
    defer compilation.deinit();
    try compilation.emit();
    const program = compilation.code.?;
    for (program.functions) |function| for (function.scope.instructions) |instruction| switch (instruction.op) {
        .call => |id| if (std.mem.eql(u8, program.functions[@backingInt(id)].name, name)) return true,
        else => {},
    };
    return false;
}

/// The entry value of `source`, built and run through the native backend.
fn loweredValue(source: []const u8) !i64 {
    var compilation = try language.Compilation.init(testing.allocator, test_path, source);
    defer compilation.deinit();
    return (try native.run(&compilation)).value;
}

// spec: BYTECODE-INLINE-1
test "inlining removes an eligible helper call and preserves its result" {
    try testing.expectEqual(@as(usize, 1), try loweredCallSites(pure_program));
    try testing.expectEqual(@as(i64, 7), try loweredValue(pure_program));
}

// spec: BYTECODE-INLINE-2
test "inlining removes a call to a trapping but non-allocating leaf" {
    try testing.expect(!try keepsCall(fallible_program, "risky"));
    try testing.expectEqual(@as(i64, 42), try loweredValue(fallible_program));
}

// spec-case: BYTECODE-INLINE-2
test "inlining keeps a call to an allocating callee" {
    try testing.expect(try keepsCall(allocating_program, "make"));
    try testing.expectEqual(@as(i64, 5), try loweredValue(allocating_program));
}

// spec-case: BYTECODE-INLINE-2
test "a trap inside an inlined callee reports the frames it replaced" {
    var compilation = try language.Compilation.init(testing.allocator, test_path, trace_program);
    defer compilation.deinit();
    const outcome = try native.run(&compilation);
    try testing.expect(outcome.trapped());
    try testing.expectEqual(@as(usize, 3), outcome.trap.frames.len);
    try testing.expectEqualStrings("peek", outcome.trap.frames[0].function);
    try testing.expectEqualStrings("use", outcome.trap.frames[1].function);
    try testing.expectEqualStrings("main", outcome.trap.frames[2].function);
}

// spec-case: BYTECODE-INLINE-2
test "a later splice remaps an earlier splice's call site" {
    var compilation = try language.Compilation.init(testing.allocator, test_path, resweep_program);
    defer compilation.deinit();
    const outcome = try native.run(&compilation);
    try testing.expect(outcome.trapped());
    try testing.expectEqual(@as(usize, 3), outcome.trap.frames.len);
    try testing.expectEqualStrings("a", outcome.trap.frames[0].function);
    try testing.expectEqualStrings("use", outcome.trap.frames[1].function);
    try testing.expectEqual(@as(u64, 3), outcome.trap.frames[1].line);
}
