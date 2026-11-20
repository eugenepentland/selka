//! `selka check` and `selka build` agree on the G3 redo's five check-versus-build shapes (lane O3, item 2). `check`
//! accepted each and `build` refused it with E_CORE_UNSUPPORTED (rule Z3). Three, and the non-fallible half of the fourth,
//! were valid: Core now lowers them, so the redo's repros build and run. The rest are refused by `check` with the
//! diagnostic `build` gives too: F-RA-202 stores borrowed text in a record (a view is no borrowed field, rule B7), and a
//! fallible function returning a borrow of its `mut` parameter is a build-time limit the certificate cannot state yet (Z3).
const std = @import("std");
const testing = std.testing;

/// What one command printed on standard error, and how it ended.
const Outcome = struct { code: u8, stderr: []u8 };

/// `selka ARGS...` run in a fresh directory holding `main.selka`, with a private cache.
fn ran(source: []const u8, args: []const []const u8) !Outcome {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.append(testing.allocator, compiler);
    try argv.appendSlice(testing.allocator, args);
    try argv.appendSlice(testing.allocator, &.{ "--cache-dir", "cache" });
    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = argv.items,
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    testing.allocator.free(result.stdout);
    return .{ .code = switch (result.term) {
        .exited => |code| code,
        else => 255,
    }, .stderr = result.stderr };
}

/// `check` passes `source`, and `run` of it, which builds it, exits with `status`.
fn agreesAndRuns(source: []const u8, status: u8) !void {
    const checked = try ran(source, &.{ "check", "main.selka" });
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqual(@as(u8, 0), checked.code);
    const built = try ran(source, &.{ "run", "main.selka", "--zig=" ++ @import("test_options").zig_path });
    defer testing.allocator.free(built.stderr);
    try testing.expect(std.mem.indexOf(u8, built.stderr, "E_CORE_UNSUPPORTED") == null);
    try testing.expectEqual(status, built.code);
}

/// `check` and `build` both refuse `source` with the same first diagnostic line, which contains `expected`.
fn bothRefuse(source: []const u8, expected: []const u8) !void {
    const checked = try ran(source, &.{ "check", "main.selka" });
    defer testing.allocator.free(checked.stderr);
    const built = try ran(source, &.{ "build", "main.selka", "-o", "main", "--zig=" ++ @import("test_options").zig_path });
    defer testing.allocator.free(built.stderr);
    try testing.expectEqual(@as(u8, 1), checked.code);
    try testing.expectEqual(@as(u8, 1), built.code);
    try testing.expect(std.mem.indexOf(u8, checked.stderr, expected) != null);
    try testing.expect(std.mem.indexOf(u8, built.stderr, expected) != null);
}

test "check/build agree: F-RA-14, a call passing a record and a copy of its nested field, then a write to a sibling" {
    try agreesAndRuns(
        \\record Table:
        \\    declared: int[] = []
        \\    published: int[] = []
        \\
        \\record Block:
        \\    name: bytes
        \\    table: Table = Table()
        \\    items: int[] = []
        \\
        \\record Facts:
        \\    seeds: int[]
        \\
        \\record Derived:
        \\    values: int[]
        \\    notes: bytes[]
        \\
        \\func collect(mut counter: int, block: Block) -> Facts:
        \\    counter += 1
        \\    return Facts(seeds=copy(block.items))
        \\
        \\func derive(block: Block, seeds: int[], declared: int[]) -> Derived:
        \\    return Derived(values=copy(seeds) + copy(declared), notes=[block.name + b"!"])
        \\
        \\func bad(mut counter: int, mut block: Block) -> int:
        \\    block.table.declared = [1, 2]
        \\    const facts = collect(mut counter, block)
        \\    const derived = derive(block, copy(facts.seeds), copy(block.table.declared))
        \\    block.table.published = copy(derived.values)
        \\    return len(derived.notes) * 10 + len(block.table.published)
        \\
        \\func main() -> int:
        \\    mut counter = 0
        \\    mut block = Block(name=b"x", items=[3])
        \\    return bad(mut counter, mut block)
        \\
    , 13);
}

test "check/build agree: F-RA-710, two mut arguments that are disjoint fields of one record at different depths" {
    try agreesAndRuns(
        \\record Inner:
        \\    rules: str[]
        \\
        \\record Ctx:
        \\    notes: str[]
        \\    block: Inner
        \\
        \\func handle(mut a: str[], mut b: str[]):
        \\    append(mut b, "r")
        \\
        \\func child(mut ctx: Ctx):
        \\    handle(mut ctx.notes, mut ctx.block.rules)
        \\
        \\func main() -> int:
        \\    mut ctx = Ctx(notes=[], block=Inner(rules=[]))
        \\    child(mut ctx)
        \\    child(mut ctx)
        \\    return len(ctx.block.rules) * 10 + len(ctx.notes)
        \\
    , 20);
}

test "check/build agree: F-RA-807, sets.discard on a set field of a mut record" {
    try agreesAndRuns(
        \\import sets
        \\
        \\record State:
        \\    seen: set[bytes]
        \\
        \\func resolve(mut st: State, name: bytes):
        \\    sets.discard(mut st.seen, name)
        \\
        \\func main() -> int:
        \\    mut st = State(seen=set())
        \\    sets.include(mut st.seen, b"x")
        \\    sets.include(mut st.seen, b"y")
        \\    resolve(mut st, b"x")
        \\    resolve(mut st, b"z")
        \\    return len(st.seen)
        \\
    , 1);
}

test "check/build agree: F-RA-115 without a failure, a borrowed result of a mut parameter the function writes" {
    try agreesAndRuns(
        \\record Entry:
        \\    name: bytes
        \\
        \\record Cursor:
        \\    entries: Entry[]
        \\    index: int = 0
        \\
        \\func next(mut self: Cursor) -> Entry? from self:
        \\    if self.index >= len(self.entries):
        \\        return None
        \\    self.index += 1
        \\    return Some(self.entries[self.index - 1])
        \\
        \\func main() -> int:
        \\    mut cursor = Cursor(entries=[Entry(name=b"ab")])
        \\    if next(mut cursor) is Some(entry):
        \\        return len(entry.name) * 10 + cursor.index
        \\    return 0
        \\
    , 21);
}

test "check/build agree: F-RA-115 as the redo wrote it, a fallible borrowed result of a mut parameter, is refused by both" {
    try bothRefuse(
        \\record Entry:
        \\    name: bytes
        \\
        \\record Cursor:
        \\    entries: Entry[]
        \\    index: int = 0
        \\
        \\func next(mut self: Cursor) -> Entry? from self fails str:
        \\    if self.index >= len(self.entries):
        \\        return None
        \\    self.index += 1
        \\    return Some(self.entries[self.index - 1])
        \\
        \\func main() -> int:
        \\    mut cursor = Cursor(entries=[Entry(name=b"a")])
        \\    match next(mut cursor):
        \\        case Ok(found):
        \\            if found is Some(entry):
        \\                return len(entry.name)
        \\            return 0
        \\        case Err(_):
        \\            return 2
        \\
    , "main.selka:8:44: error[E_CORE_UNSUPPORTED]: a function that fails with a managed error cannot return a borrow of its `mut` parameter yet");
}

test "check/build agree: F-RA-202, a record of two borrowed text results, is refused by both as a stored borrow" {
    try bothRefuse(
        \\record Entry:
        \\    design: bytes
        \\    path: bytes
        \\
        \\record Form:
        \\    a: bytes?
        \\    b: bytes?
        \\
        \\func text_a(node: Form) -> bytes? from node:
        \\    return node.a
        \\
        \\func text_b(node: Form) -> bytes? from node:
        \\    return node.b
        \\
        \\func entry_of(node: Form) -> Entry? from node:
        \\    if text_a(node) is Some(design):
        \\        if text_b(node) is Some(path):
        \\            return Some(Entry(design=design, path=path))
        \\    return None
        \\
        \\func main() -> int:
        \\    const f = Form(a=Some(b"design"), b=Some(b"path"))
        \\    if entry_of(f) is Some(e):
        \\        return len(e.path)
        \\    return 0
        \\
    , "main.selka:18:38: error[E_SINGLE_OWNER_BORROW]: `design` is lent by the plain parameter `node`, and field `design` of `Entry` would keep it after the call returns");
}
