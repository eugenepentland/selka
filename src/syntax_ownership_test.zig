//! Checking never grows or frees the parser's syntax lists. The checker holds the
//! parsed program by value, as its callers do, so a list it reallocated would leave
//! every other holder reading a freed buffer. Lowerings that need synthetic syntax
//! (nested variant patterns) append only to a private copy of the tables.
const std = @import("std");
const t = std.testing;
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema = @import("sema.zig");
const source = @import("source.zig");

/// Nested variant arms (fielded, positional under an option, and in a generic
/// body) and literal arms: every match lowering the checker has.
const matches =
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
    \\enum Deep:
    \\    held(box: Wrap)
    \\    empty
    \\
    \\
    \\enum Maybe[T]:
    \\    some(value: T)
    \\    nothing
    \\
    \\
    \\func option_shape(found: Shape?) -> int:
    \\    match found:
    \\        case Some(circle(radius=r)):
    \\            return r
    \\        case Some(square(side=s)):
    \\            return s * 2
    \\        case None:
    \\            return 0
    \\
    \\
    \\func deep(value: Deep) -> int:
    \\    match value:
    \\        case held(box=Wrap.one(inner=Shape.circle(radius=r))):
    \\            return r
    \\        case held(box=Wrap.one(inner=Shape.square(side=s))):
    \\            return s + 100
    \\        case held(box=Wrap.none):
    \\            return -1
    \\        case empty:
    \\            return -2
    \\
    \\
    \\func pick[T](value: Maybe[Maybe[T]], fallback: T) -> T:
    \\    match value:
    \\        case some(value=Maybe.some(value=inner)):
    \\            return inner
    \\        case some(value=Maybe.nothing):
    \\            return fallback
    \\        case nothing:
    \\            return fallback
    \\
    \\
    \\func nest[T](x: T) -> Maybe[Maybe[T]]:
    \\    const inner: Maybe[T] = Maybe.some(value=x)
    \\    return Maybe.some(value=inner)
    \\
    \\
    \\func digit(n: int) -> int:
    \\    match n:
    \\        case 0 | 1:
    \\            return 1
    \\        case _:
    \\            return 2
    \\
    \\
    \\func main() -> int:
    \\    const a = option_shape(Shape.circle(radius=3))
    \\    const b = deep(Deep.held(box=Wrap.one(inner=Shape.square(side=4))))
    \\    return a + b + pick[int](nest[int](5), 0) + digit(a)
    \\
;

/// An allocator over `inner` that overwrites every block it frees, in every build
/// mode, so a stale reader of a freed list sees 0xAA instead of its old contents.
const Poisoning = struct {
    inner: std.mem.Allocator,

    fn allocator(self: *Poisoning) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self: *Poisoning = @ptrCast(@alignCast(context));
        return self.inner.rawAlloc(len, alignment, ret);
    }
    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) bool {
        const self: *Poisoning = @ptrCast(@alignCast(context));
        return self.inner.rawResize(memory, alignment, len, ret);
    }
    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) ?[*]u8 {
        const self: *Poisoning = @ptrCast(@alignCast(context));
        return self.inner.rawRemap(memory, alignment, len, ret);
    }
    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self: *Poisoning = @ptrCast(@alignCast(context));
        @memset(memory, 0xAA);
        self.inner.rawFree(memory, alignment, ret);
    }
};

const Parsed = struct { src: source.Source, program: ast.Program };

/// Parse `text` into `storage` as a project module is parsed: the node and
/// statement lists grow in a separate allocator and settle at their exact length,
/// so any append to them reallocates.
fn parseSettled(storage: std.mem.Allocator, text: []const u8) !Parsed {
    const src = try source.Source.init(storage, "matches.selka", text);
    var sink: diagnostic.Sink = .{ .allocator = storage };
    const tokens = try lexer.lex(storage, text, &sink);
    var p: parser.Parser = .{ .src = src, .storage = storage, .tokens = tokens, .sink = &sink, .syntax = .{ .growth = t.allocator } };
    defer p.release();
    return .{ .src = src, .program = try p.parse() };
}

test "checking nested and literal matches leaves the parser's exact-length syntax lists intact" {
    var storage: std.heap.ArenaAllocator = .init(t.allocator);
    defer storage.deinit();
    var checking: std.heap.ArenaAllocator = .init(t.allocator);
    defer checking.deinit();
    var poisoning: Poisoning = .{ .inner = checking.allocator() };
    const parsed = try parseSettled(storage.allocator(), matches);
    try t.expectEqual(parsed.program.nodes.items.len, parsed.program.nodes.capacity);
    try t.expectEqual(parsed.program.statements.items.len, parsed.program.statements.capacity);
    const nodes = try t.allocator.dupe(ast.Node, parsed.program.nodes.items);
    defer t.allocator.free(nodes);
    const statements = try t.allocator.dupe(ast.Statement, parsed.program.statements.items);
    defer t.allocator.free(statements);
    var sink: diagnostic.Sink = .{ .allocator = poisoning.allocator() };
    _ = try sema.check(poisoning.allocator(), parsed.src, parsed.program, &sink);
    // The caller's copy of the program still reads the lists the parser built.
    try t.expectEqualSlices(u8, std.mem.sliceAsBytes(nodes), std.mem.sliceAsBytes(parsed.program.nodes.items));
    try t.expectEqualSlices(u8, std.mem.sliceAsBytes(statements), std.mem.sliceAsBytes(parsed.program.statements.items));
}
