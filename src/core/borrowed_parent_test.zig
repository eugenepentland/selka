//! O4: a borrowed record may hold `Some(p)` of a read-only record parameter, and `None` beside its borrows. A recursive
//! field's box is a frame box (`box_frame`): a slot of the call that made it, written once at entry. A value that holds a
//! frame box its own call made is never returned, even under `from`; a box an ancestor made is returned `from` the
//! parameter that holds it. Every other escape keeps 1A's refusal. Guest behaviour is `tests/lang/borrowed_parents.selka`.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");
const ir = @import("ir.zig");
const report = std.debug.print;

const prelude =
    \\record Block:
    \\    name: bytes
    \\    ports: bytes[]
    \\
    \\record Scope:
    \\    block: Block
    \\    name: bytes = b""
    \\    parent: Scope? = None
    \\
    \\record Holder:
    \\    scope: Scope
    \\    tags: bytes[]
    \\
    \\func depth(scope: Scope) -> int:
    \\    match scope.parent:
    \\        case None:
    \\            return 0
    \\        case Some(p):
    \\            return 1 + depth(p)
    \\
    \\func up(s: Scope) -> Scope? from s:
    \\    return s.parent
    \\
    \\
;

const frame_fragment = "whose box lives in this call's frame";

/// `source` after the prelude; a source that starts with an import keeps it first.
fn program(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    const import = "import parallel\n";
    if (!std.mem.startsWith(u8, source, import)) return std.mem.concat(a, u8, &.{ prelude, source });
    return std.mem.concat(a, u8, &.{ import, prelude, source[import.len..] });
}

fn refuses(backing: std.mem.Allocator, source: []const u8, code: []const u8, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const unit = try support.checkSource(a, try program(a, source));
    try std.testing.expect(unit.passed);
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    if (!std.mem.eql(u8, code, failure.code)) report("code {s}: {s}\n", .{ failure.code, failure.message });
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(language.ownership_rules.valid(.{ .code = failure.code, .rule = failure.rule.? }));
    if (std.mem.indexOf(u8, failure.message, fragment) == null) report("missing '{s}' in: {s}\n", .{ fragment, failure.message });
    try std.testing.expect(std.mem.indexOf(u8, failure.message, fragment) != null);
}

fn accepts(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const checked = try support.checkedProgram(a, try program(a, source));
    unique.check(a, checked, &failure) catch |err| {
        report("refused: {s} {s}\n", .{ failure.code, failure.message });
        return err;
    };
    try std.testing.expectEqualStrings("", failure.code);
}

test "O4 Some of a read-only record parameter and None beside borrows: a walk, a const, a 4f local, an ancestor's box returned from" {
    try accepts(std.testing.allocator,
        \\record Sub:
        \\    name: bytes
        \\    block: Block
        \\
        \\record Tree:
        \\    block: Block
        \\    subs: Sub[]
        \\
        \\func walk(scope: Scope, subs: Sub[]) -> int:
        \\    mut total = depth(scope)
        \\    for sb in subs:
        \\        total += walk(Scope(block=sb.block, name=sb.name, parent=Some(scope)), [])
        \\        const child = Scope(block=sb.block, parent=Some(scope))
        \\        total += depth(child)
        \\    return total
        \\
        \\func last(scope: Scope, subs: Sub[]) -> int:
        \\    mut current = Scope(block=scope.block, parent=Some(scope))
        \\    for sb in subs:
        \\        current = Scope(block=sb.block, name=sb.name, parent=Some(scope))
        \\    return depth(current)
        \\
        \\func grand(s: Scope) -> Scope? from s:
        \\    match s.parent:
        \\        case None:
        \\            return None
        \\        case Some(p):
        \\            return up(p)
        \\
        \\func root(block: Block) -> int:
        \\    return depth(Scope(block=block))
        \\
        \\func main() -> int:
        \\    const t = Tree(block=Block(name=b"t", ports=[]), subs=[])
        \\    return walk(Scope(block=t.block), t.subs) + last(Scope(block=t.block), t.subs) + root(t.block)
        \\
    );
}

test "O4 a value holding its own call's frame box is not returned, even under from: directly, through a const, through a from call" {
    try refuses(std.testing.allocator,
        \\func g(s: Scope) -> Scope from s:
        \\    return Scope(block=s.block, parent=Some(s))
        \\
        \\func main() -> int:
        \\    return depth(g(Scope(block=Block(name=b"x", ports=[]))))
        \\
    , "E_SINGLE_OWNER_BORROW", frame_fragment);
    try refuses(std.testing.allocator,
        \\func g(s: Scope) -> Scope from s:
        \\    const child = Scope(block=s.block, parent=Some(s))
        \\    return child
        \\
        \\func main() -> int:
        \\    return depth(g(Scope(block=Block(name=b"x", ports=[]))))
        \\
    , "E_SINGLE_OWNER_BORROW", frame_fragment);
    try refuses(std.testing.allocator,
        \\func g(s: Scope) -> Scope? from s:
        \\    return up(Scope(block=s.block, parent=Some(s)))
        \\
        \\func main() -> int:
        \\    return 0
        \\
    , "E_SINGLE_OWNER_BORROW", frame_fragment);
}

test "O4 a record holding a lent Some is not stored, moved, written, returned without from, or kept past a write to its owner" {
    const cases = [_][]const u8{
        \\func f(s: Scope) -> int:
        \\    mut out: Scope[] = []
        \\    append(mut out, Scope(block=s.block, parent=Some(s)))
        \\    return len(out)
        ,
        \\func f(s: Scope) -> int:
        \\    mut out: dict[bytes, Scope] = {}
        \\    out[b"k"] = Scope(block=s.block, parent=Some(s))
        \\    return len(out)
        ,
        \\func f(s: Scope) -> int:
        \\    const h = Holder(scope=Scope(block=s.block, parent=Some(s)), tags=[b"t"])
        \\    return depth(h.scope)
        ,
        \\func take(own x: Scope) -> int:
        \\    return depth(x)
        \\
        \\func f(s: Scope) -> int:
        \\    const child = Scope(block=s.block, parent=Some(s))
        \\    return take(own child)
        ,
        \\func g(s: Scope) -> Scope:
        \\    return Scope(block=s.block, parent=Some(s))
        \\
        \\func f(s: Scope) -> int:
        \\    return depth(g(s))
        ,
        \\func f(s: Scope) -> int:
        \\    mut child = Scope(block=s.block, parent=Some(s))
        \\    child = Scope(block=s.block, name=s.name, parent=Some(s))
        \\    child.name = b"x"
        \\    return depth(child)
        ,
        \\func f(s: Scope) -> int:
        \\    mut b = Block(name=b"x", ports=[])
        \\    const child = Scope(block=b, parent=Some(s))
        \\    b.name = b"y"
        \\    return depth(child)
        ,
        \\func g(mut s: Scope) -> int:
        \\    return depth(Scope(block=s.block, parent=Some(s)))
        \\
        \\func f(s: Scope) -> int:
        \\    mut c = copy(s)
        \\    return g(mut c)
        ,
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const source = try std.mem.concat(a, u8, &.{ prelude, case, "\n\nfunc main() -> int:\n    return f(Scope(block=Block(name=b\"x\", ports=[])))\n" });
        const unit = try support.checkSource(a, source);
        var failure: unique.Failure = .{};
        const rejected = !unit.passed or std.meta.isError(unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
        if (!rejected) report("accepted:\n{s}\n", .{case});
        try std.testing.expect(rejected);
    }
}

test "O4 a task reads a record holding a lent Some within its join, and a write to its owner while the group is open is refused" {
    try accepts(std.testing.allocator,
        \\import parallel
        \\
        \\func f(s: Scope) -> int:
        \\    const child = Scope(block=s.block, parent=Some(s))
        \\    mut total = 0
        \\    with parallel.group() as g:
        \\        const t = g.submit(depth, child)
        \\        total = t.result()
        \\    return total
        \\
        \\func main() -> int:
        \\    return f(Scope(block=Block(name=b"x", ports=[])))
        \\
    );
    try refuses(std.testing.allocator,
        \\import parallel
        \\
        \\func f(s: Scope) -> int:
        \\    mut b = Block(name=b"x", ports=[])
        \\    const child = Scope(block=b, parent=Some(s))
        \\    mut total = 0
        \\    with parallel.group() as g:
        \\        const t = g.submit(depth, child)
        \\        b.name = b"y"
        \\        total = t.result()
        \\    return total
        \\
        \\func main() -> int:
        \\    return f(Scope(block=Block(name=b"x", ports=[])))
        \\
    , "E_TASK_LOAN", "lent to a task");
}

test "O4 Some(p) of a recursive field lowers to one entry-block frame box per parameter, lent and never dropped" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = prelude ++
        \\func two(scope: Scope) -> int:
        \\    return depth(Scope(block=scope.block, parent=Some(scope))) + depth(Scope(block=scope.block, name=scope.name, parent=Some(scope)))
        \\
        \\func main() -> int:
        \\    return two(Scope(block=Block(name=b"x", ports=[])))
        \\
    ;
    const ir_text = try support.irText(a, source);
    const at = std.mem.indexOf(u8, ir_text, "fn two(") orelse return error.TestUnexpectedResult;
    const end = std.mem.indexOfPos(u8, ir_text, at + 1, "\nfn ") orelse ir_text.len;
    const two = ir_text[at..end];
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, two, "box_frame"));
    try std.testing.expect(std.mem.indexOf(u8, two, "b0:\n  %") != null);
    try std.testing.expect(std.mem.indexOf(u8, two, "box_make") == null);
    try std.testing.expect(std.mem.indexOf(u8, two, "myl_core_owned_copy") == null);
    const owned = try support.ownedText(a, source);
    const owned_at = std.mem.indexOf(u8, owned, "fn two(") orelse return error.TestUnexpectedResult;
    const owned_end = std.mem.indexOfPos(u8, owned, owned_at + 1, "\nfn ") orelse owned.len;
    try std.testing.expect(std.mem.indexOf(u8, owned[owned_at..owned_end], "drop") == null);
    const llvm = try support.llvmText(a, source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "store i32 8388610") != null);
}

test "O4 borrow_result never accepts a returned borrow that reaches a frame box, and accepts an ancestor's box through a parameter" {
    const builder = @import("test_builder.zig");
    const valid = @import("borrow_result.zig").valid;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const record = try module.intern(a, .{ .record = &.{ .str, .i64 } });
    const boxed = try module.intern(a, .{ .box = record });
    const option = try module.intern(a, .{ .@"union" = &.{ .void, boxed } });
    const holder = try module.intern(a, .{ .record = &.{option} });
    const overlay = try module.borrowedType(a, record);
    const returned = try module.intern(a, .{ .@"union" = &.{ .void, overlay } });
    const contract: ir.BorrowContract = .{ .path = &.{.{ .payload = 1 }}, .sources = &.{.{ .argument = 0 }} };

    var own_frame: builder.Builder = .{ .arena = a, .function = .{ .name = "own_frame", .signature = .{ .params = &.{record}, .ret = returned, .borrow = contract } } };
    const entry = try own_frame.block();
    const param = try own_frame.detached(.{ .op = .param, .ty = record, .data = 0 });
    const frame = try own_frame.put(entry, .{ .op = .box_frame, .ty = boxed, .a = param });
    const inner = try own_frame.put(entry, .{ .op = .box_get, .ty = record, .a = frame });
    const lent = try own_frame.put(entry, .{ .op = .borrow, .ty = overlay, .a = inner });
    const some = try own_frame.put(entry, .{ .op = .union_make, .ty = returned, .a = lent, .data = 1 });
    _ = try own_frame.put(entry, .{ .op = .ret, .ty = .void, .a = some });
    try std.testing.expect(!try valid(a, &module, &own_frame.function, some));

    var ancestor: builder.Builder = .{ .arena = a, .function = .{ .name = "ancestor", .signature = .{ .params = &.{holder}, .ret = returned, .borrow = contract } } };
    const start = try ancestor.block();
    const self = try ancestor.detached(.{ .op = .param, .ty = holder, .data = 0 });
    const field = try ancestor.put(start, .{ .op = .record_get, .ty = option, .a = self, .data = 0 });
    const payload = try ancestor.put(start, .{ .op = .union_payload, .ty = boxed, .a = field, .data = 1 });
    const value = try ancestor.put(start, .{ .op = .box_get, .ty = record, .a = payload });
    const borrowed = try ancestor.put(start, .{ .op = .borrow, .ty = overlay, .a = value });
    const wrapped = try ancestor.put(start, .{ .op = .union_make, .ty = returned, .a = borrowed, .data = 1 });
    _ = try ancestor.put(start, .{ .op = .ret, .ty = .void, .a = wrapped });
    try std.testing.expect(try valid(a, &module, &ancestor.function, wrapped));
}
