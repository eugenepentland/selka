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

/// A callee larger than the flat budget, called once from a loop and once from a
/// straight-line function, so only the hot site may be spliced.
const bulky_program =
    \\def big(x: i64) -> i64:
    \\    v0 = x + 1
    \\    v1 = v0 + 1
    \\    v2 = v1 + 1
    \\    v3 = v2 + 1
    \\    v4 = v3 + 1
    \\    v5 = v4 + 1
    \\    v6 = v5 + 1
    \\    v7 = v6 + 1
    \\    v8 = v7 + 1
    \\    v9 = v8 + 1
    \\    v10 = v9 + 1
    \\    v11 = v10 + 1
    \\    v12 = v11 + 1
    \\    v13 = v12 + 1
    \\    return v13
    \\
    \\
    \\def cold(x: i64) -> i64:
    \\    return big(x)
    \\
    \\
    \\def hot(x: i64) -> i64:
    \\    total = 0
    \\    index = 0
    \\    while index < 4:
    \\        total = total + big(x)
    \\        index = index + 1
    \\    return total
    \\
    \\
    \\def main() -> i64:
    \\    return cold(0) + hot(0)
;

/// Number of direct calls left in the lowered body of `caller` that name `name`.
fn callsTo(source: []const u8, caller: []const u8, name: []const u8) !usize {
    var compilation = try language.Compilation.init(testing.allocator, test_path, source);
    defer compilation.deinit();
    try compilation.emit();
    const program = compilation.code.?;
    var count: usize = 0;
    for (program.functions) |function| {
        if (!std.mem.eql(u8, function.name, caller)) continue;
        for (function.scope.instructions) |instruction| switch (instruction.op) {
            .call => |id| if (std.mem.eql(u8, program.functions[@backingInt(id)].name, name)) {
                count += 1;
            },
            else => {},
        };
    }
    return count;
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

// spec: BYTECODE-INLINE-3
test "a callee over the flat budget inlines only inside a loop" {
    try testing.expectEqual(@as(usize, 1), try callsTo(bulky_program, "cold", "big"));
    try testing.expectEqual(@as(usize, 0), try callsTo(bulky_program, "hot", "big"));
    try testing.expectEqual(@as(i64, 70), try loweredValue(bulky_program));
}
