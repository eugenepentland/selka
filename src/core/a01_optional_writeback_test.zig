//! Same-owner optional reconstruction transfers recursive payloads exactly once.
const std = @import("std");
const language = @import("mylang");
const options = @import("core_test_options");
const contract = @import("single_owner.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;

const source =
    \\record Inner:
    \\    number: int
    \\    words: str[]
    \\
    \\record Node:
    \\    value: int
    \\    inner: Inner
    \\    text: str
    \\    words: str[]
    \\    left: Node?
    \\    right: Node?
    \\
    \\func leaf(value: int) -> Node:
    \\    return Node(value=value, inner=Inner(number=value, words=["inner-" + str(value)]), text="text-" + str(value), words=["word-" + str(value)], left=None, right=None)
    \\
    \\func original() -> Node?:
    \\    return Some(Node(value=1, inner=Inner(number=1, words=["inner-" + str(1)]), text="parent-" + str(1), words=["top-" + str(1)], left=Some(leaf(2)), right=Some(leaf(3))))
    \\
    \\func early(value: int) -> str:
    \\    mut child = original()
    \\    if child is not None:
    \\        child.value = value
    \\        child.text = "early-" + str(child.value)
    \\        return child.text.copy()
    \\    return "absent"
    \\
    \\func failure() -> Result[str, str]:
    \\    mut child = original()
    \\    if child is not None:
    \\        child.value = 70
    \\        child.text = "error-" + str(child.value)
    \\        return Err(child.text.copy())
    \\    return Ok("absent")
    \\
    \\func fail_int() -> Result[int, str]:
    \\    return Err("staged-" + str(7))
    \\
    \\func failed_rhs() -> Result[str, str]:
    \\    mut child = original()
    \\    if child is not None:
    \\        const staged = try fail_int()
    \\        child.value = staged
    \\        return Ok(child.text.copy())
    \\    return Ok("absent")
    \\
    \\func mutate(mut child: Node?) -> int:
    \\    if child is not None:
    \\        child.value = 41
    \\        child.text = "mut-" + str(42)
    \\        return child.value
    \\    return 0
    \\
    \\func main(out: Stream) -> int:
    \\    const source = original()
    \\    mut child = source.copy()
    \\    if child is not None:
    \\        child.value = 20
    \\        child.value += 1
    \\        child.value -= 1
    \\        child.inner.number = 30
    \\        child.inner.words = ["inner-new-" + str(31)]
    \\        assert child.inner.number == 30 and child.inner.words == ["inner-new-31"]
    \\        child.text = "new-" + str(21)
    \\        child.words = ["new-word-" + str(22)]
    \\        assert child.value == 20 and child.text == "new-21" and child.words == ["new-word-22"]
    \\        match child.left:
    \\            case Some(left):
    \\                assert left.value == 2 and left.text == "text-2" and left.words == ["word-2"]
    \\            case None:
    \\                assert False
    \\        match child.right:
    \\            case Some(right):
    \\                assert right.value == 3 and right.text == "text-3"
    \\            case None:
    \\                assert False
    \\        for i in range(32):
    \\            child.value = i
    \\            child.text = "repeat-" + str(i)
    \\            child.words = ["repeat-word-" + str(i)]
    \\            if i == 19:
    \\                break
    \\        assert child.value == 19 and child.text == "repeat-19"
    \\        child = Some(leaf(90))
    \\        if child is not None:
    \\            child.value = 91
    \\            assert child.value == 91 and child.text == "text-90"
    \\    match source:
    \\        case Some(before):
    \\            assert before.value == 1 and before.text == "parent-1" and before.words == ["top-1"]
    \\        case None:
    \\            assert False
    \\    mut parameter_child = original()
    \\    assert mutate(mut parameter_child) == 41
    \\    if parameter_child is not None:
    \\        assert parameter_child.text == "mut-42"
    \\    child = None
    \\    if child is not None:
    \\        child.value = 99
    \\    assert early(8) == "early-8"
    \\    match failure():
    \\        case Ok(value):
    \\            assert False
    \\        case Err(error):
    \\            assert error == "error-70"
    \\    match failed_rhs():
    \\        case Ok(value):
    \\            assert False
    \\        case Err(error):
    \\            assert error == "staged-7"
    \\    out.print("optional-writeback", 42)
    \\    return 0
;

fn checked(a: std.mem.Allocator, text: []const u8) !language.typed.Program {
    var unit = try language.Compilation.init(a, "optional-writeback.my", text);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |item| report("{s}: {s}\n", .{ item.code, item.message });
        return err;
    };
    return unit.program.?;
}

fn refuses(allocator: std.mem.Allocator, text: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var unit = try language.Compilation.init(arena.allocator(), "optional-writeback-negative.my", text);
    unit.check() catch |err| {
        try std.testing.expectEqual(error.SourceError, err);
        try std.testing.expectEqualStrings(code, unit.diagnostics.items[0].code);
        return;
    };
    var failure: contract.Failure = .{};
    contract.checkMode(arena.allocator(), unit.program.?, &failure, true) catch |err| {
        try std.testing.expectEqual(error.Rejected, err);
        if (!std.mem.eql(u8, code, failure.code)) report("optional writeback refusal: {s}: {s}\n", .{ failure.code, failure.message });
        try std.testing.expectEqualStrings(code, failure.code);
        return;
    };
    report("optional writeback unexpectedly admitted:\n{s}\n", .{text});
    return error.TestExpectedError;
}

fn field(value: std.json.Value, path: []const []const u8) i64 {
    var at = value;
    for (path) |name| at = at.object.get(name) orelse return -1;
    return at.integer;
}

fn inspect(a: std.mem.Allocator, binary: []const u8, llvm_path: []const u8, expected: []const u8) !void {
    const path = try std.fmt.allocPrint(a, "{s}.json", .{binary});
    var environment = std.process.Environ.Map.init(a);
    try environment.put("MYLANG_COUNTERS", path);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{binary}, .environ_map = &environment });
    if (ran.term != .exited or ran.term.exited != 0) report("optional writeback run: {s}{s}\n", .{ ran.stdout, ran.stderr });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings(expected, ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
    const counts = try std.json.parseFromSliceLeaky(std.json.Value, a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(16 << 20)), .{});
    for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks", "live_bytes_at_exit" }) |name|
        try std.testing.expectEqual(@as(i64, 0), field(counts, &.{ "totals", name }));
    for ([_][]const u8{ "retain", "release", "unique_test" }) |name|
        try std.testing.expectEqual(@as(i64, 0), field(counts, &.{ "kinds", name, "count" }));
    try std.testing.expect(field(counts, &.{ "totals", "allocs" }) > 0);
    try std.testing.expect(field(counts, &.{ "kinds", "release_unique", "count" }) > 0);
    const llvm = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, llvm_path, a, .limited(16 << 20));
    try std.testing.expect(zero.emittedClean(llvm));
    const symbols = try std.process.run(a, std.testing.io, .{ .argv = &.{ "nm", binary } });
    try std.testing.expect(symbols.term == .exited and symbols.term.exited == 0);
    for ([_][]const u8{ "myl_core_retain", "myl_core_release", "myl_core_share", "count_retain", "count_release", "count_is_unique" }) |legacy|
        try std.testing.expect(std.mem.indexOf(u8, symbols.stdout, legacy) == null);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "A01 optional writeback admits only the same narrowed owner" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try checked(arena.allocator(), source);
    var failure: contract.Failure = .{};
    contract.checkMode(arena.allocator(), program, &failure, true) catch |err| {
        report("optional writeback: {s}: {s}\n", .{ failure.code, failure.message });
        return err;
    };
    try refuses(std.testing.allocator,
        \\record Node:
        \\    value: int
        \\    left: Node?
        \\func bad(child: Node?) -> Node?:
        \\    if child is not None:
        \\        return Some(child)
        \\    return None
        \\func main() -> int:
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\record Node:
        \\    value: int
        \\    left: Node?
        \\func main() -> int:
        \\    mut child: Node? = Some(Node(value=1, left=None))
        \\    const other: Node? = Some(Node(value=2, left=None))
        \\    if other is not None:
        \\        child = Some(other)
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
    // Narrowing a mut argument back into an optional remains a separate refusal.
    try refuses(std.testing.allocator,
        \\record Node:
        \\    value: int
        \\    left: Node?
        \\func replace(mut child: Node?) -> int:
        \\    child = None
        \\    return 0
        \\func main() -> int:
        \\    mut child: Node? = Some(Node(value=1, left=None))
        \\    if child is not None:
        \\        _ = replace(mut child)
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "A01 optional writeback transfers recursive storage in five native modes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "optional.my", .data = source });
    const input = try std.fs.path.join(a, &.{ root, "optional.my" });
    const modes = [_][]const []const u8{ &.{"--release"}, &.{"--unoptimized"}, &.{ "--release", "--verify-facts" }, &.{"--optimize-debug"}, &.{ "--release", "--no-facts" } };
    for (modes, 0..) |flags, index| {
        const binary = try std.fmt.allocPrint(a, "{s}/optional-{d}", .{ root, index });
        const llvm_path = try std.fmt.allocPrint(a, "{s}.ll", .{binary});
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", input, "-o", binary, "--cache-dir", root, "--counters", "--experimental-zero-rc", "--emit-llvm", llvm_path });
        try argv.appendSlice(a, flags);
        const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("optional writeback build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        try inspect(a, binary, llvm_path, "optional-writeback 42\n");
    }
}

fn findStore(program: language.typed.Program, function: language.typed.Function) !language.typed.Store {
    for (program.statements) |stmt| {
        if (stmt.data == .assign and @import("optional_writeback.zig").shape(program, function, stmt.data.assign) != null) return stmt.data.assign;
    }
    return error.TestExpectedOptionalWriteback;
}

fn findDefinition(program: language.typed.Program, receiver: language.typed.LocalId) !language.typed.NodeId {
    for (program.statements) |stmt| {
        if (stmt.data == .initialize and stmt.data.initialize.slot == receiver) return stmt.data.initialize.value;
    }
    return error.TestExpectedReceiverDefinition;
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "A01 optional writeback rejects mismatched reconstruction metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rules = @import("optional_writeback.zig");
    var program = try checked(a,
        \\record Node:
        \\    value: int
        \\    left: Node?
        \\func main() -> int:
        \\    mut child: Node? = Some(Node(value=1, left=None))
        \\    if child is not None:
        \\        child.value = 20
        \\        return child.value
        \\    return 0
    );
    const function = program.functions[0];
    var missing = program;
    missing.statements = &.{};
    try std.testing.expectError(error.TestExpectedOptionalWriteback, findStore(missing, function));
    try std.testing.expectError(error.TestExpectedReceiverDefinition, findDefinition(missing, @fromBackingInt(0)));
    const store = try findStore(program, function);
    const found = rules.shape(program, function, store).?;
    const definition = try findDefinition(program, found.receiver);
    try std.testing.expect(rules.projection(program, function, store, found, definition));
    const nodes = try a.dupe(language.typed.Node, program.nodes);
    program.nodes = nodes;
    const variant = @backingInt(store.value);
    const original_variant = nodes[variant];
    nodes[variant].data.variant.tag = 1 - found.tag;
    try std.testing.expect(rules.shape(program, function, store) == null);
    nodes[variant] = original_variant;
    var wrong_store = store;
    wrong_store.slot = found.receiver;
    try std.testing.expect(rules.shape(program, function, wrong_store) == null);
    const payload = @backingInt(found.payload);
    const original_update = nodes[payload];
    const base = @backingInt(nodes[payload].data.update.base);
    const original_base = nodes[base];
    nodes[base].data.local = store.slot;
    try std.testing.expect(rules.shape(program, function, store) == null);
    nodes[base] = original_base;
    const fields = try a.dupe(language.typed.FieldInit, nodes[payload].data.update.fields);
    nodes[payload].data.update.fields = fields;
    fields[0].value = nodes[payload].data.update.base;
    try std.testing.expect(rules.shape(program, function, store) == null);
    nodes[payload] = original_update;
    const block = nodes[@backingInt(definition)].data.block_value;
    const dispatch = program.statements[@backingInt(program.statements[@backingInt(block.body)].data.block[0])].data.match;
    const root = @backingInt(dispatch.value);
    const original_root = nodes[root];
    nodes[root].data.local = found.receiver;
    try std.testing.expect(!rules.projection(program, function, store, found, definition));
    nodes[root] = original_root;
    nodes[root].ty = nodes[base].ty;
    try std.testing.expect(!rules.projection(program, function, store, found, definition));
    nodes[root] = original_root;
    const statements = try a.dupe(language.typed.Statement, program.statements);
    program.statements = statements;
    for (dispatch.arms) |arm| {
        if (arm.slot != null) continue;
        statements[@backingInt(arm.body)].data = .{ .block = &.{} };
    }
    try std.testing.expect(!rules.projection(program, function, store, found, definition));
}

const invalidated =
    \\record Node:
    \\    value: int
    \\    text: str
    \\    next: Node?
    \\func clear(mut child: Node?) -> int:
    \\    child = None
    \\    return 20
    \\func main() -> int:
    \\    mut child: Node? = Some(Node(value=1, text="owned-" + str(1), next=None))
    \\    if child is not None:
    \\        child.value = clear(mut child)
    \\        return 1
    \\    return 0
;

fn buildSucceeded(built: std.process.RunResult) !void {
    if (built.term != .exited or built.term.exited != 0) report("optional control build: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "A01 optional writeback keeps invalidation refusal and ordinary compatibility" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "ordinary.my", .data = source });
    try refuses(std.testing.allocator, invalidated, "E_MUTATION_OVERLAP");
    const input = try std.fs.path.join(a, &.{ root, "ordinary.my" });
    const binary = try std.fs.path.join(a, &.{ root, "ordinary" });
    const built = try std.process.run(a, std.testing.io, .{ .argv = &.{ options.corePath(), "build", input, "-o", binary, "--cache-dir", root, "--release" } });
    try buildSucceeded(built);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{binary} });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("optional-writeback 42\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}
