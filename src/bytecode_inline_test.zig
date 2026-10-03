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
/// reaches `main` through `use`, so both removed calls retain logical frames.
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

/// A caller whose helper constructs a list, which admits allocation.
const allocating_program =
    \\def make(x: i64) -> list[int]:
    \\    return [x]
    \\
    \\
    \\def use(x: i64) -> i64:
    \\    return make(x)[0]
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
    try testing.expectEqual(@as(usize, 0), try loweredCallSites(pure_program));
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

/// A float helper: `float(i)` and `int(x)` call the pure
/// `myl_qbe_float_unary`, so the helper is spliced, and a conversion that
/// traps inside the splice still reports the helper's frame.
const float_program =
    \\def scaled(x: i64, factor: float) -> i64:
    \\    return int(float(x) * factor)
    \\
    \\
    \\def use(x: i64, factor: float) -> i64:
    \\    return scaled(x, factor)
    \\
    \\
    \\def main() -> i64:
    \\    return use(3, 2.5) + use(1, 1e300)
;

// spec-case: BYTECODE-INLINE-2
test "a callee that converts between integers and floats is inlined and keeps its trap frames" {
    try testing.expect(!try keepsCall(float_program, "scaled"));
    var compilation = try language.Compilation.init(testing.allocator, test_path, float_program);
    defer compilation.deinit();
    const outcome = try native.run(&compilation);
    try testing.expect(outcome.trapped());
    try testing.expectEqual(@as(usize, 3), outcome.trap.frames.len);
    try testing.expectEqualStrings("scaled", outcome.trap.frames[0].function);
    try testing.expectEqualStrings("use", outcome.trap.frames[1].function);
    try testing.expectEqualStrings("main", outcome.trap.frames[2].function);
}

// spec: BYTECODE-INLINE-3
test "a callee over the flat budget inlines only inside a loop" {
    try testing.expectEqual(@as(usize, 1), try callsTo(bulky_program, "cold", "big"));
    try testing.expectEqual(@as(usize, 0), try callsTo(bulky_program, "hot", "big"));
    try testing.expectEqual(@as(i64, 70), try loweredValue(bulky_program));
}

/// Zero-argument calls need a separate call-site marker: otherwise a refused
/// entry would already be inside the callee's inline trace range.
const zero_argument_program =
    \\def leaf() -> i64:
    \\    return 7
    \\
    \\
    \\def middle() -> i64:
    \\    return leaf()
    \\
    \\
    \\def main() -> i64:
    \\    first = middle()
    \\    return first + middle()
;

// spec: BYTECODE-INLINE-4
test "inlined zero argument calls enforce logical depth and report only entered frames" {
    try testing.expectEqual(@as(usize, 0), try loweredCallSites(zero_argument_program));
    var compilation = try language.Compilation.init(testing.allocator, test_path, zero_argument_program);
    defer compilation.deinit();
    const one = try native.runWithOptions(&compilation, .{ .max_frames = 1 });
    try testing.expectEqualStrings("R_FRAME_LIMIT", one.trap.code);
    try testing.expectEqual(@as(usize, 1), one.trap.frames.len);
    try testing.expectEqualStrings("main", one.trap.frames[0].function);
    try testing.expectEqual(@as(u64, 10), one.trap.frames[0].line);
    const two = try native.runWithOptions(&compilation, .{ .max_frames = 2 });
    try testing.expectEqualStrings("R_FRAME_LIMIT", two.trap.code);
    try testing.expectEqual(@as(usize, 2), two.trap.frames.len);
    try testing.expectEqualStrings("middle", two.trap.frames[0].function);
    try testing.expectEqual(@as(u64, 6), two.trap.frames[0].line);
    try testing.expectEqualStrings("main", two.trap.frames[1].function);
    try testing.expectEqual(@as(i64, 14), (try native.runWithOptions(&compilation, .{ .max_frames = 3 })).value);
}

// spec-case: BYTECODE-INLINE-4
test "inlined argument calls preserve frame admission through a conditional body" {
    var compilation = try language.Compilation.init(testing.allocator, test_path, pure_program);
    defer compilation.deinit();
    const limited = try native.runWithOptions(&compilation, .{ .max_frames = 2 });
    try testing.expectEqualStrings("R_FRAME_LIMIT", limited.trap.code);
    try testing.expectEqual(@as(usize, 2), limited.trap.frames.len);
    try testing.expectEqualStrings("use", limited.trap.frames[0].function);
    try testing.expectEqualStrings("main", limited.trap.frames[1].function);
    try testing.expectEqual(@as(i64, 7), (try native.runWithOptions(&compilation, .{ .max_frames = 3 })).value);
}

// spec-case: BYTECODE-INLINE-4
test "inlined call evaluates a trapping argument before refusing frame admission" {
    var compilation = try language.Compilation.init(testing.allocator, test_path,
        \\def leaf(x: i64) -> i64:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    value = 9223372036854775807
        \\    return leaf(value + 1)
    );
    defer compilation.deinit();
    const outcome = try native.runWithOptions(&compilation, .{ .max_frames = 1 });
    try testing.expectEqualStrings("R_OVERFLOW", outcome.trap.code);
    try testing.expectEqual(@as(usize, 1), outcome.trap.frames.len);
    try testing.expectEqualStrings("main", outcome.trap.frames[0].function);
    try testing.expectEqual(@as(u64, 7), outcome.trap.frames[0].line);
}

const plain_record_program =
    \\record Pair:
    \\    left: int
    \\    right: int
    \\
    \\def make(value: int) -> Pair:
    \\    return Pair(left=value, right=value + 1)
    \\
    \\def score(pair: Pair) -> int:
    \\    return pair.left + pair.right
    \\
    \\def changed(pair: Pair) -> int:
    \\    pair.left += 1
    \\    return score(pair)
    \\
    \\def main() -> int:
    \\    pair = make(7)
    \\    alias = pair
    \\    return changed(pair) + score(alias)
;

// spec: BYTECODE-INLINE-5
test "inlining plain constructors preserves returned record snapshots" {
    try testing.expect(!try keepsCall(plain_record_program, "make"));
    try testing.expect(!try keepsCall(plain_record_program, "score"));
    try testing.expectEqual(@as(i64, 31), try loweredValue(plain_record_program));
}

const result_program =
    \\def checked(value: int) -> Result[int, int]:
    \\    if value < 0:
    \\        return Err(3)
    \\    return Ok(value)
    \\
    \\def forwarded(value: int) -> Result[int, int]:
    \\    result = checked(value)?
    \\    return Ok(result + 1)
    \\
    \\def main() -> int:
    \\    match forwarded(-1):
    \\        case Ok(value):
    \\            return value
    \\        case Err(code):
    \\            return code
;

// spec-case: BYTECODE-INLINE-5
test "inlining plain results preserves propagation into a caller with another return type" {
    try testing.expect(!try keepsCall(result_program, "checked"));
    try testing.expect(!try keepsCall(result_program, "forwarded"));
    try testing.expectEqual(@as(i64, 3), try loweredValue(result_program));
}

// spec-case: BYTECODE-INLINE-5
test "inlining declines propagation when unfinished caller operands need preservation" {
    const source =
        \\def through(value: Result[int, int]) -> Result[int, int]:
        \\    return Ok(value?)
        \\
        \\def main() -> int:
        \\    first, result = 7, through(Err(3))
        \\    match result:
        \\        case Ok(value):
        \\            return first + value
        \\        case Err(code):
        \\            return first + code
    ;
    try testing.expect(try keepsCall(source, "through"));
    try testing.expectEqual(@as(i64, 10), try loweredValue(source));
}

// spec-case: BYTECODE-INLINE-5
test "inlining retains construction calls with managed payload ownership" {
    const source =
        \\record Owner:
        \\    values: list[int]
        \\
        \\def make(values: list[int]) -> Owner:
        \\    return Owner(values=values)
        \\
        \\def main() -> int:
        \\    values = [7]
        \\    owner = make(values)
        \\    values[0] = 9
        \\    return owner.values[0]
    ;
    try testing.expect(try keepsCall(source, "make"));
    try testing.expectEqual(@as(i64, 7), try loweredValue(source));
}

// spec-case: BYTECODE-INLINE-5
test "inlining plain options keeps both some and none branches" {
    const source =
        \\def optional(value: int) -> Option[int]:
        \\    if value < 0:
        \\        return None
        \\    return Some(value)
        \\
        \\def main() -> int:
        \\    match optional(-1):
        \\        case Some(value):
        \\            return value
        \\        case None:
        \\            match optional(7):
        \\                case Some(value):
        \\                    return value
        \\                case None:
        \\                    return 0
    ;
    try testing.expect(!try keepsCall(source, "optional"));
    try testing.expectEqual(@as(i64, 7), try loweredValue(source));
}

// spec-case: BYTECODE-INLINE-5
test "inlined plain result traces retain exact origin conversion and return locations" {
    const source =
        \\union Fault:
        \\    Code: int
        \\
        \\def checked(x: int) -> Result[int, int]:
        \\    if x < 0:
        \\        return Err(3)
        \\    return Ok(x)
        \\
        \\def forwarded(x: int) -> Result[int, Fault]:
        \\    value = checked(x)?
        \\    return Ok(value + 1)
        \\
        \\def main() -> Result[int, Fault]:
        \\    return forwarded(-1)
    ;
    try testing.expect(!try keepsCall(source, "checked"));
    try testing.expect(!try keepsCall(source, "forwarded"));
    var compilation = try language.Compilation.init(testing.allocator, test_path, source);
    defer compilation.deinit();
    const outcome = try native.run(&compilation);
    try testing.expect(!outcome.trapped());
    var actual = std.mem.tokenizeAny(u8, outcome.stderr, " \t\n");
    var expected = std.mem.tokenizeAny(u8, "error: Fault.Code(3) inline.my:6:16 checked Err(...) created " ++
        "inline.my:10:13 forwarded ? converted to Fault.Code inline.my:14:5 main returned", " ");
    while (expected.next()) |word| try testing.expectEqualStrings(word, actual.next() orelse "");
    try testing.expect(actual.next() == null);
}

// spec-case: BYTECODE-INLINE-5
test "stackHeights rejects an invalid failure edge without leaking its analysis storage" {
    const bytecode = @import("bytecode.zig");
    const function: bytecode.Function = .{
        .id = @fromBackingInt(0),
        .name = "invalid",
        .scope = .{ .instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .jump = 1 } }} },
    };
    try testing.expectError(error.InternalError, bytecode.stackHeights(testing.allocator, .{ .functions = &.{function} }, function));
}
