//! Checker memory is linear in the nested matches and the generic functions a program
//! has. Each test counts the bytes the checker allocates at two sizes: a quadratic
//! copy shows as about four times the bytes for twice the size, a linear one as about
//! two times.
const std = @import("std");
const t = std.testing;
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema = @import("sema.zig");
const source = @import("source.zig");

const enums =
    \\enum Shape:
    \\    circle(radius: int)
    \\    square(side: int)
    \\
    \\
    \\enum Wrap:
    \\    one(inner: Shape)
    \\    none
    \\
    \\
;

const maybe_enum =
    \\enum Maybe[T]:
    \\    some(value: T)
    \\    nothing
    \\
    \\
;

const main_function = "func main() -> int:\n    return 0\n";

/// `count` concrete functions, each with one nested variant match.
fn nestedSource(allocator: std.mem.Allocator, count: usize) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    errdefer text.deinit();
    try text.writer.writeAll(enums);
    for (0..count) |index| try text.writer.print(
        \\func m{d}(value: Wrap) -> int:
        \\    match value:
        \\        case one(inner=Shape.circle(radius=r)):
        \\            return r
        \\        case one(inner=Shape.square(side=s)):
        \\            return s + 100
        \\        case none:
        \\            return -1
        \\
        \\
        \\
    , .{index});
    try text.writer.writeAll(main_function);
    return text.toOwnedSlice();
}

/// `count` tiny generic functions with no match.
fn genericSource(allocator: std.mem.Allocator, count: usize) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    errdefer text.deinit();
    for (0..count) |index| try text.writer.print("func g{d}[T](x: T) -> T:\n    return x\n\n\n", .{index});
    try text.writer.writeAll(main_function);
    return text.toOwnedSlice();
}

/// `count` generic functions, each with one nested variant match.
fn genericNestedSource(allocator: std.mem.Allocator, count: usize) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    errdefer text.deinit();
    try text.writer.writeAll(maybe_enum);
    for (0..count) |index| try text.writer.print(
        \\func p{d}[T](value: Maybe[Maybe[T]], fallback: T) -> T:
        \\    match value:
        \\        case some(value=Maybe.some(value=inner)):
        \\            return inner
        \\        case some(value=Maybe.nothing):
        \\            return fallback
        \\        case nothing:
        \\            return fallback
        \\
        \\
        \\
    , .{index});
    try text.writer.writeAll(main_function);
    return text.toOwnedSlice();
}

/// An allocator over `inner` that counts the bytes it is asked for. Frees are not
/// subtracted, so `total` is what the checker allocated over its whole run.
const Counting = struct {
    inner: std.mem.Allocator,
    total: usize = 0,

    fn allocator(self: *Counting) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self: *Counting = @ptrCast(@alignCast(context));
        const memory = self.inner.rawAlloc(len, alignment, ret) orelse return null;
        self.total += len;
        return memory;
    }
    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) bool {
        const self: *Counting = @ptrCast(@alignCast(context));
        if (!self.inner.rawResize(memory, alignment, len, ret)) return false;
        self.total += len -| memory.len;
        return true;
    }
    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) ?[*]u8 {
        const self: *Counting = @ptrCast(@alignCast(context));
        const moved = self.inner.rawRemap(memory, alignment, len, ret) orelse return null;
        self.total += len -| memory.len;
        return moved;
    }
    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self: *Counting = @ptrCast(@alignCast(context));
        self.inner.rawFree(memory, alignment, ret);
    }
};

const Parsed = struct { src: source.Source, program: ast.Program };

/// Parse `text` into `storage` as a project module is parsed: the node and statement
/// lists grow in a separate allocator and settle at their exact length.
fn parseSettled(storage: std.mem.Allocator, text: []const u8) !Parsed {
    const src = try source.Source.init(storage, "memory.selka", text);
    var sink: diagnostic.Sink = .{ .allocator = storage };
    const tokens = try lexer.lex(storage, text, &sink);
    var p: parser.Parser = .{ .src = src, .storage = storage, .tokens = tokens, .sink = &sink, .syntax = .{ .growth = t.allocator } };
    defer p.release();
    return .{ .src = src, .program = try p.parse() };
}

/// Bytes the checker allocates over one successful check of `text`.
fn checkedBytes(text: []const u8) !usize {
    var storage: std.heap.ArenaAllocator = .init(t.allocator);
    defer storage.deinit();
    const parsed = try parseSettled(storage.allocator(), text);
    var checking: std.heap.ArenaAllocator = .init(t.allocator);
    defer checking.deinit();
    var counting: Counting = .{ .inner = checking.allocator() };
    var sink: diagnostic.Sink = .{ .allocator = counting.allocator() };
    _ = try sema.check(counting.allocator(), parsed.src, parsed.program, &sink);
    return counting.total;
}

/// Bytes the checker allocates for the program `generate` makes with `count` shapes.
fn bytesFor(comptime generate: anytype, count: usize) !usize {
    const text = try generate(t.allocator, count);
    defer t.allocator.free(text);
    return checkedBytes(text);
}

test "checker memory grows linearly with nested matches" {
    const small = try bytesFor(nestedSource, 200);
    const large = try bytesFor(nestedSource, 400);
    // Passes while `large` stays under three times `small`. A failure prints both values.
    try t.expectEqual(large, @min(large, 3 * small - 1));
}

test "checker memory grows linearly with generic functions" {
    const small = try bytesFor(genericSource, 200);
    const large = try bytesFor(genericSource, 400);
    try t.expectEqual(large, @min(large, 3 * small - 1));
}

test "checker memory grows linearly with nested matches in generic functions" {
    const small = try bytesFor(genericNestedSource, 200);
    const large = try bytesFor(genericNestedSource, 400);
    try t.expectEqual(large, @min(large, 3 * small - 1));
}

/// Parse and check three generic functions, each with a nested match, drawing every
/// allocation the checker makes from `allocator`. The program text is made outside it:
/// the writer reports an allocation failure as `WriteFailed`, not `OutOfMemory`.
fn genericNestedCheck(allocator: std.mem.Allocator) !void {
    const text = try genericNestedSource(t.allocator, 3);
    defer t.allocator.free(text);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const parsed = try parseSettled(arena.allocator(), text);
    var sink: diagnostic.Sink = .{ .allocator = arena.allocator() };
    _ = try sema.check(arena.allocator(), parsed.src, parsed.program, &sink);
}

// The generic driver's private table copy must be released on every path: a failed copy
// of the statements must free the nodes copy, and every failed allocation during a body
// must still hand the body's appended syntax back to the copy.
test "generic bodies release their private syntax tables when an allocation fails" {
    const text = try genericNestedSource(t.allocator, 3);
    defer t.allocator.free(text);
    try t.expectEqual(@as(usize, 3), std.mem.count(u8, text, "func p"));
    try genericNestedCheck(t.allocator);
    var failing: t.FailingAllocator = .init(t.allocator, .{});
    try t.checkAllAllocationFailures(failing.allocator(), genericNestedCheck, .{});
}
