//! Core IR builder tests: SSA shapes from checked source, the refusals of
//! unsupported constructs, and the copies `own.zig` puts in front of shared pushes.
const std = @import("std");
const transition = @import("ownership_transition_test_support.zig");
const support = @import("test_support.zig");
const build = @import("build.zig");
const typed = @import("selka").typed;

fn malformedRefusal(allocator: std.mem.Allocator, program: typed.Program, expected: []const u8, span: u32) !void {
    return malformedInputRefusal(allocator, .{ .program = program }, expected, span);
}

fn malformedInputRefusal(allocator: std.mem.Allocator, input: build.Input, expected: []const u8, span: u32) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{ .rule = .Z3 };
    try std.testing.expectError(error.Unsupported, build.buildExecutable(arena.allocator(), input, &refusal));
    try std.testing.expectEqualStrings(expected, refusal.reason);
    try std.testing.expectEqual(span, refusal.span);
    try std.testing.expect(refusal.rule == null);
}

fn malformedViewType(allocator: std.mem.Allocator, container: typed.Record, returns_view: bool, expected: []const u8) !void {
    const span: @import("selka").source.Span = .{ .start = 13, .end = 14 };
    const view: typed.Type = @fromBackingInt(typed.Type.record_base);
    const records = [_]typed.Record{
        .{ .id = view, .name = "DictValues", .declaration = span, .fields = &.{}, .shape = .{ .builtin = .live_view } },
        container,
    };
    const locals = [_]typed.Local{.{ .name = "value", .declaration = span, .ty = container.id, .mutable = false }};
    const functions = [_]typed.Function{.{
        .id = @fromBackingInt(0),
        .name = "main",
        .declaration = span,
        .signature = .{ .return_type = if (returns_view) view else .i64, .parameter_count = if (returns_view) 0 else 1 },
        .scope = .{ .body = @fromBackingInt(0), .locals = &locals },
    }};
    try malformedRefusal(allocator, .{ .nodes = &.{}, .statements = &.{}, .functions = &functions, .main = @fromBackingInt(0), .records = &records }, expected, span.start);
}

test "builder consistency guards keep malformed dictionary view storage unlabeled" {
    const view: typed.Type = @fromBackingInt(typed.Type.record_base);
    var container: typed.Record = .{
        .id = @fromBackingInt(typed.Type.record_base + 1),
        .name = "Container",
        .declaration = .{ .start = 13, .end = 14 },
        .fields = &.{},
        .managed = true,
        .shape = .{ .buffer = view },
    };
    try malformedViewType(std.testing.allocator, container, false, "a live dictionary view as a checked list element");
    container.collection = .{ .kind = .dictionary, .key = .i64 };
    try malformedViewType(std.testing.allocator, container, false, "a live dictionary view as a checked dictionary value");
    container.managed = false;
    container.shape = .{ .array = .{ .element = view, .length = 1 } };
    try malformedViewType(std.testing.allocator, container, false, "a live dictionary view as a checked fixed array element");
    container.shape = .{};
    container.fields = &.{.{ .name = "view", .declaration = .{ .start = 13, .end = 14 }, .ty = view }};
    try malformedViewType(std.testing.allocator, container, false, "a live dictionary view as a checked aggregate field");
    try malformedViewType(std.testing.allocator, container, true, "a live dictionary view as a checked return type");
}

fn malformedTaskValue(allocator: std.mem.Allocator, node: typed.Node, expected: []const u8) !void {
    const locals = [_]typed.Local{.{ .name = "handle", .declaration = node.span, .ty = .task_handle, .mutable = false }};
    const functions = [_]typed.Function{.{
        .id = @fromBackingInt(0),
        .name = "main",
        .declaration = node.span,
        .scope = .{ .body = @fromBackingInt(0), .locals = &locals },
    }};
    const statements = [_]typed.Statement{.{ .span = node.span, .terminates = true, .data = .{ .ret = @fromBackingInt(0) } }};
    try malformedRefusal(allocator, .{ .nodes = &.{node}, .statements = &statements, .functions = &functions, .main = @fromBackingInt(0) }, expected, @intCast(node.span.start));
}

test "builder consistency guards reject task values without their scope unlabeled" {
    try malformedTaskValue(std.testing.allocator, .{ .span = .{ .start = 23, .end = 24 }, .ty = .task_group, .data = .task_group_open }, "invalid checked task group outside its `with` scope");
    try malformedTaskValue(std.testing.allocator, .{ .span = .{ .start = 27, .end = 28 }, .ty = .i64, .data = .{ .task_result = @fromBackingInt(0) } }, "invalid checked task result without its group");
}

test "builder consistency guard rejects a mutable task callee unlabeled" {
    const span: @import("selka").source.Span = .{ .start = 31, .end = 32 };
    const nodes = [_]typed.Node{
        .{ .span = span, .ty = .i64, .data = .{ .call = .{ .function = @fromBackingInt(1), .arguments = &.{} } } },
        .{ .span = span, .ty = .task_handle, .data = .{ .task_submit = .{ .group = @fromBackingInt(0), .call = @fromBackingInt(0) } } },
    };
    const statements = [_]typed.Statement{.{ .span = span, .terminates = true, .data = .{ .ret = @fromBackingInt(1) } }};
    const functions = [_]typed.Function{
        .{ .id = @fromBackingInt(0), .name = "main", .declaration = span, .scope = .{ .body = @fromBackingInt(0) } },
        .{ .id = @fromBackingInt(1), .name = "mutated", .declaration = span, .scope = .{ .body = @fromBackingInt(0) }, .signature = .{ .declared_mutates = &.{0} } },
    };
    try malformedRefusal(std.testing.allocator, .{ .nodes = &nodes, .statements = &statements, .functions = &functions, .main = @fromBackingInt(0) }, "invalid checked task callee with a mut parameter", span.start);
}

test "builder consistency guard rejects an owning parallel callback unlabeled" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const src = try @import("selka").source.Source.init(arena.allocator(), "@stdlib/parallel.selka", "map");
    const span: @import("selka").source.Span = .{ .start = 0, .end = 3 };
    const list: typed.Type = @fromBackingInt(typed.Type.record_base);
    const callback: typed.Type = @fromBackingInt(typed.Type.record_base + 1);
    const records = [_]typed.Record{
        .{ .id = list, .name = "int[]", .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = .i64 } },
        .{ .id = callback, .name = "callback", .declaration = span, .fields = &.{}, .contract = .{ .callback = .{ .parameters = &.{.i64}, .return_type = .i64, .own = &.{true} } } },
    };
    const locals = [_]typed.Local{
        .{ .name = "values", .declaration = span, .ty = list, .mutable = false },
        .{ .name = "callback", .declaration = span, .ty = callback, .mutable = false },
    };
    const functions = [_]typed.Function{.{
        .id = @fromBackingInt(0),
        .name = "parallel::map",
        .declaration = span,
        .signature = .{ .return_type = list, .parameter_count = 2 },
        .scope = .{ .body = @fromBackingInt(0), .locals = &locals },
    }};
    const program: typed.Program = .{ .nodes = &.{}, .statements = &.{}, .functions = &functions, .main = @fromBackingInt(0), .records = &records };
    try malformedInputRefusal(std.testing.allocator, .{ .program = program, .source = src }, "invalid checked parallel.map callback with an owning or mutable parameter", span.start);
}

fn frontendTaskRefusal(allocator: std.mem.Allocator, text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const checked = try support.checkSource(arena.allocator(), text);
    try std.testing.expect(!checked.passed);
    try std.testing.expect(checked.program == null);
    try std.testing.expect(checked.diagnostics.len != 0);
    try std.testing.expect(!std.mem.eql(u8, "E_CORE_UNSUPPORTED", checked.diagnostics[0].code));
    try std.testing.expect(checked.diagnostics[0].provenance.rule != .Z3);
}

test "builder consistency task and callback counterparts are refused before lowering" {
    try frontendTaskRefusal(std.testing.allocator,
        \\import parallel
        \\func bump(mut values: int[]) -> int:
        \\    values[0] = 2
        \\    return values[0]
        \\func main() -> int:
        \\    mut values = [1]
        \\    with parallel.group() as g:
        \\        const task = g.submit(bump, values)
        \\        return task.result()
    );
    try frontendTaskRefusal(std.testing.allocator,
        \\import parallel
        \\func take(own values: int[]) -> int:
        \\    return len(values)
        \\func main() -> int:
        \\    return parallel.map([[1]], take)[0]
    );
}

fn malformedViewCall(allocator: std.mem.Allocator, mutable: bool) !void {
    const span: @import("selka").source.Span = .{ .start = 37, .end = 38 };
    const view: typed.Type = @fromBackingInt(typed.Type.record_base);
    const dictionary: typed.Type = @fromBackingInt(typed.Type.record_base + 1);
    const records = [_]typed.Record{
        .{ .id = view, .name = "DictValues", .declaration = span, .fields = &.{}, .shape = .{ .builtin = .live_view } },
        .{ .id = dictionary, .name = "dict", .declaration = span, .fields = &.{}, .managed = true, .collection = .{ .kind = .dictionary, .key = .i64 }, .shape = .{ .buffer = .i64 } },
    };
    const locals = [_]typed.Local{.{ .name = "view", .declaration = span, .ty = view, .mutable = mutable }};
    const result: typed.Type = if (mutable) .i64 else dictionary;
    const nodes = [_]typed.Node{
        .{ .span = span, .ty = view, .data = .{ .local = @fromBackingInt(0) } },
        .{ .span = span, .ty = result, .data = .{ .call = .{ .function = @fromBackingInt(1), .arguments = &.{@fromBackingInt(0)} } } },
    };
    const statements = [_]typed.Statement{.{ .span = span, .terminates = true, .data = .{ .ret = @fromBackingInt(1) } }};
    const functions = [_]typed.Function{
        .{ .id = @fromBackingInt(0), .name = "main", .declaration = span, .signature = .{ .return_type = result, .parameter_count = 1 }, .scope = .{ .body = @fromBackingInt(0), .locals = &locals } },
        .{
            .id = @fromBackingInt(1),
            .name = "use",
            .declaration = span,
            .signature = .{ .return_type = result, .parameter_count = 1, .declared_mutates = if (mutable) &.{0} else &.{} },
            .scope = .{ .body = @fromBackingInt(0), .locals = &locals },
        },
    };
    const expected = if (mutable) "a live dictionary view as a checked mutable argument" else "a live dictionary view as a checked dictionary call argument";
    try malformedRefusal(allocator, .{ .nodes = &nodes, .statements = &statements, .functions = &functions, .main = @fromBackingInt(0), .records = &records }, expected, span.start);
}

test "builder consistency guards reject live dictionary views passed to ordinary calls unlabeled" {
    try malformedViewCall(std.testing.allocator, true);
    try malformedViewCall(std.testing.allocator, false);
}

const counted_loop =
    \\func total(n: int) -> int:
    \\    mut acc = 0
    \\    for i in range(n):
    \\        acc += i * 2
    \\    return acc
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, total(4))
    \\    return 0
    \\
;

// spec: NEW-CORE-IR-1
test "a counted loop becomes header, body, latch and exit blocks with phis for its carried locals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), counted_loop);
    try std.testing.expectEqualStrings(
        \\fn main(cap) -> i64
        \\b0:
        \\  %2 = call i64 total(4:i64)
        \\  print param0, %2
        \\  ret 0:i64
        \\fn total(i64) -> i64
        \\b0:
        \\  jump b1
        \\b1: ; preds b0 b3
        \\  %4 = phi i64 0:i64, %14
        \\  %8 = phi i64 0:i64, %11
        \\  %6 = cmp.lt bool %4, param0
        \\  branch %6, b2, b4
        \\b2: ; preds b1
        \\  %10 = mul.exact i64 %4, 2:i64
        \\  %11 = add.exact i64 %8, %10
        \\  jump b3
        \\b3: ; preds b2
        \\  %14 = add.exact i64 %4, 1:i64
        \\  jump b1
        \\b4: ; preds b1
        \\  ret %8
        \\
    , text);
}

const short_circuit =
    \\func pick(a: int, b: int) -> bool:
    \\    return a > 0 and b > 0 or a == b
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, pick(1, 2))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-IR-1
test "and/or evaluate their right operand in its own block and join with a phi" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), short_circuit);
    try std.testing.expect(std.mem.indexOf(u8, text, "phi bool") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, text, "phi bool"));
    try std.testing.expect(std.mem.indexOf(u8, text, "cmp.eq bool param0, param1") != null);
}

const option_match =
    \\func parse(text: str) -> int:
    \\    match parse_int(text):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, parse("12"))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-IR-1
test "a match on an option tests the tag and binds the payload in its arm" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), option_match);
    try std.testing.expect(std.mem.indexOf(u8, text, "call option[i64] myl_core_span_parse_int_range(param0, 0:i64, ") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "union_tag u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "union_take i64 tag1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call i64 parse(%") != null);
}

// migrate-embedded: skip intentional interior stored dictionary view negative
const stored_view =
    \\func main(out: Stream) -> int:
    \\    mut table = {"a": 1}
    \\    mut holder = [table]
    \\    mut view = holder[0].values()
    \\    print(out, len(view))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-DICT-1
test "D2 rejects an interior stored dictionary view before core lowering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    const outcome = support.buildSource(arena.allocator(), stored_view, &refusal);
    try std.testing.expectError(error.SourceError, outcome);
    try std.testing.expectEqualStrings("", refusal.reason);
    try std.testing.expectEqual(@as(u32, 0), refusal.span);
}

const bytes_task =
    \\import parallel
    \\
    \\func measure(value: bytes) -> int:
    \\    return len(value)
    \\
    \\func go(value: bytes) -> int:
    \\    with parallel.group() as g:
    \\        const t = g.submit(measure, value[0:2])
    \\        return t.result()
    \\
    \\func main() -> int:
    \\    return go(b"abc")
    \\
;

test "ownership builder refusals carry Z3 and binding an owned task argument lowers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    try std.testing.expectError(error.Unsupported, support.buildSource(a, bytes_task, &refusal));
    try std.testing.expectEqualStrings("a slice of bytes given to a task", refusal.reason);
    try std.testing.expectEqualStrings("a slice has no owner to lend, so copy it into a local first", refusal.hint);
    try std.testing.expectEqual(.Z3, refusal.rule.?);
    try std.testing.expectEqual(@as(u32, @intCast(std.mem.indexOf(u8, bytes_task, "g.submit").?)), refusal.span);
    const bound = try std.mem.replaceOwned(u8, a, bytes_task, "const t = g.submit(measure, value[0:2])", "const owned = copy(value[0:2])\n        const t = g.submit(measure, owned)");
    var accepted_refusal: build.Refusal = .{};
    _ = try support.buildSource(a, bound, &accepted_refusal);
    try std.testing.expect(accepted_refusal.rule == null);
}

// The builder refused this under Z3 until D8 (10 November 2026); the check now refuses the slice first, under W4, and
// names the copy, as it does for a list slice.
test "ownership check refuses an inline text slice given to a task's own parameter under W4 (D8)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\import parallel
        \\
        \\func measure(own value: str) -> int:
        \\    return len(value)
        \\
        \\func main() -> int:
        \\    mut text = "abc"
        \\    with parallel.group() as group:
        \\        const task = group.submit(measure, text[0:1])
        \\        return task.result()
    ;
    const checked = try support.checkSource(a, text);
    try std.testing.expect(checked.passed);
    const ownership = @import("single_owner.zig");
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, checked.program.?, checked.src.?, &failure));
    try std.testing.expectEqualStrings("E_SLICE_ESCAPES", failure.code);
    try std.testing.expectEqual(.W4, failure.rule.?);
    const slice_at = std.mem.indexOf(u8, text, "text[0:1]").?;
    try std.testing.expectEqual(slice_at, failure.copy.span.?.start);
    try std.testing.expectEqual(slice_at + "text[0:1]".len, failure.copy.span.?.end);
    const copied = try std.mem.replaceOwned(u8, a, text, "group.submit(measure, text[0:1])", "group.submit(measure, copy(text[0:1]))");
    var accepted_refusal: build.Refusal = .{};
    _ = try support.buildSource(a, copied, &accepted_refusal);
    try std.testing.expect(accepted_refusal.rule == null);
}

// spec-case: NEW-CORE-DICT-1
test "materialized interior dictionary values survive independent mapping updates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const owned = try std.mem.replaceOwned(u8, a, stored_view, "mut holder = [table]", "mut holder = [copy(table)]");
    const snapshot = try std.mem.replaceOwned(u8, a, owned, "mut view = holder[0].values()", "mut view = list(dicts.values(holder[0]))");
    const modern = try std.mem.replaceOwned(u8, a, snapshot, "print(out, len(view))", "holder[0][\"a\"] = 2\n    table[\"a\"] = 3\n    print(out, len(view), view[0], holder[0][\"a\"], table[\"a\"])");
    for ([_]bool{ false, true }) |optimized| {
        var refusal: build.Refusal = .{};
        var module = try support.buildSource(a, try std.fmt.allocPrint(a, "import dicts\n\n{s}", .{modern}), &refusal);
        const ran = try support.runOwned(a, &module, .{ .release = optimized, .verify = optimized });
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings("1 1 2 3\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
    }
}

const iterate_and_grow =
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2, 3]
    \\    mut total = 0
    \\    for v in xs:
    \\        total += v
    \\        if total < 4:
    \\            append(mut xs, v)
    \\    print(out, total, len(xs))
    \\    return 0
    \\
;

const iterate_only =
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2, 3]
    \\    mut total = 0
    \\    for v in xs:
    \\        total += v
    \\    print(out, total)
    \\    return 0
    \\
;

// spec: NEW-CORE-IR-3
// spec-case: NEW-CORE-ITERATION-1
test "checked list loops preserve element reads and reject growth through an active borrow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try transition.refuses(arena.allocator(), iterate_and_grow, "E_SINGLE_OWNER_OVERLAP");
    const text = try support.irText(arena.allocator(), iterate_only);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get.exact i64") != null);
}

const mutating_helper =
    \\func grow(mut xs: int[]) -> Unit:
    \\    append(mut xs, 4)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2, 3]
    \\    grow(mut xs)
    \\    print(out, len(xs))
    \\    return 0
    \\
;

// spec: NEW-CORE-MUT-1
test "a mut parameter is passed by value and returned: the caller writes the callee's final value back" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), mutating_helper);
    // `grow` returns the list it ends with, and `main` continues with that value.
    try std.testing.expect(std.mem.indexOf(u8, text, "fn grow(list[i64]) -> list[i64]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "%9 = call list[i64] grow(%8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "%10 = list_len u64 %9") != null);
}

const aliased_pushes =
    \\func grow(xs: int[]) -> int:
    \\    mut copy = copy(xs)
    \\    append(mut copy, 1)
    \\    return len(copy)
    \\
    \\
    \\func fill(n: int) -> int:
    \\    mut xs = [0]
    \\    for j in range(n):
    \\        append(mut xs, j)
    \\    return len(xs)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, grow([1, 2]) + fill(3))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-OWN-1
test "a push onto a parameter's list copies it first; a push onto a list the function owns alone does not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.ownedText(arena.allocator(), aliased_pushes);
    // Only `grow`'s push copies (its list is borrowed): `fill`'s list is fresh, and its loop
    // phi is dead after each push, so neither copies nor tests its count.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "list_copy list[i64] param0"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "list_copy"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, text, "is_unique"));
}

/// Overwrite the stack below the caller, as the calls a build makes next do.
noinline fn scribbleStack() u8 {
    var pad: [16384]u8 = undefined;
    @memset(&pad, 0xAA);
    std.mem.doNotOptimizeAway(&pad);
    return pad[pad.len / 2];
}

test "the roots of an executable are still main and the hooks after the stack below the caller is reused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const main: typed.FunctionId = @fromBackingInt(7);
    const alone = try build.rootsOf(arena.allocator(), .{ .program = .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = main } });
    _ = scribbleStack();
    try std.testing.expectEqualSlices(typed.FunctionId, &.{main}, alone);
    const hooks = [_]typed.FunctionId{ @fromBackingInt(3), @fromBackingInt(4) };
    const hooked = try build.rootsOf(arena.allocator(), .{ .program = .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = main }, .hooks = &hooks });
    _ = scribbleStack();
    try std.testing.expectEqualSlices(typed.FunctionId, &.{ main, hooks[0], hooks[1] }, hooked);
}
