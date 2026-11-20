//! Lowering of parallel task groups (E1b), checked on the emitted text: the join comes before the drops of the values a
//! task lends, no thunk drops anything, and only an `own` argument is taken out of the environment. Runtime behaviour
//! (values, leaks, threads) is in `tests/lang/parallel_groups.selka`, and the mask is checked by `task_mask_fixture.c`.
const std = @import("std");
const build = @import("build.zig");
const support = @import("test_support.zig");
const own = @import("own.zig");
const emit_llvm = @import("emit_llvm.zig");
const language = @import("selka");
const ownership = @import("single_owner.zig");
const flags = @import("flags.zig");

const lent_aliases =
    \\import parallel
    \\import strings
    \\
    \\record Bag:
    \\    values: int[]
    \\func size(values: int[]) -> int:
    \\    return len(values)
    \\func record_size(value: Bag) -> int:
    \\    return len(value.values)
    \\func dictionary_size(value: dict[int, int[]]) -> int:
    \\    return len(value[1])
    \\func text_size(value: str) -> int:
    \\    return len(value)
    \\func bytes_size(value: bytes) -> int:
    \\    return len(value)
    \\func go() -> int:
    \\    const rows = [[1, 2, 3]]
    \\    const bag = Bag(values=[4, 5])
    \\    const table = {1: [6, 7, 8, 9]}
    \\    const text = "owned-" + str(1)
    \\    const octets = strings.encode(text)
    \\    const record_alias = bag
    \\    const dictionary_alias = table
    \\    mut answer = 0
    \\    with parallel.group() as g:
    \\        const row = rows[0]
    \\        const field = record_alias.values
    \\        const entry = dictionary_alias[1]
    \\        const text_alias = text
    \\        const bytes_alias = octets
    \\        const a = g.submit(size, row)
    \\        const b = g.submit(record_size, record_alias)
    \\        const c = g.submit(dictionary_size, dictionary_alias)
    \\        const d = g.submit(size, field)
    \\        const e = g.submit(size, entry)
    \\        const f = g.submit(text_size, text_alias)
    \\        const h = g.submit(bytes_size, bytes_alias)
    \\        answer = a.result() + b.result() + c.result() + d.result() + e.result() + f.result() + h.result()
    \\    return answer
    \\func main() -> int:
    \\    return go()
;

/// A group whose list is lent to a task that reads it: the program every join-order test starts from.
const lent_list =
    \\import parallel
    \\
    \\func weigh(values: int[], work: int) -> int:
    \\    mut total = work
    \\    for v in values:
    \\        total += v
    \\    return total
    \\
    \\func go() -> int:
    \\    mut out = 0
    \\    with parallel.group() as g:
    \\        const xs = [1, 2, 3]
    \\        const t = g.submit(weigh, xs, 10)
    \\        out = t.result()
    \\    return out
    \\
    \\func main() -> int:
    \\    return go()
    \\
;

/// Early exits from the group: a `return` and a `break` join on their own exit edges, with a lent list declared in the block.
const exit_edges =
    \\import parallel
    \\
    \\func weigh(values: int[], work: int) -> int:
    \\    mut total = work
    \\    for v in values:
    \\        total += v
    \\    return total
    \\
    \\func go(flag: int) -> int:
    \\    mut out = 0
    \\    for i in range(3):
    \\        with parallel.group() as g:
    \\            const xs = [1, 2, i]
    \\            const t = g.submit(weigh, xs, 10)
    \\            if i == 1:
    \\                break
    \\            const value = t.result()
    \\            if flag > 0:
    \\                return value
    \\            out += value
    \\    return out
    \\
    \\func main() -> int:
    \\    return go(0)
    \\
;

/// Three kinds of argument: a lent list, an `own` list, and a temporary list. Only the `own` one is taken by the thunk.
const three_arguments =
    \\import parallel
    \\
    \\func weigh(values: int[], work: int) -> int:
    \\    mut total = work
    \\    for v in values:
    \\        total += v
    \\    return total
    \\
    \\func consume(own values: int[]) -> int:
    \\    mut total = 0
    \\    for v in values:
    \\        total += v
    \\    return total
    \\
    \\func go() -> int:
    \\    mut out = 0
    \\    with parallel.group() as g:
    \\        const xs = [1, 2, 3]
    \\        const ys = [4, 5]
    \\        const t = g.submit(weigh, xs, 10)
    \\        const u = g.submit(consume, own ys)
    \\        const v = g.submit(weigh, [6], 1)
    \\        out = t.result() + u.result() + v.result()
    \\    return out
    \\
    \\func main() -> int:
    \\    return go()
    \\
;

/// Lower `source` and emit it as LLVM text, after the ownership pass the driver runs.
fn emitText(arena: std.mem.Allocator, source: []const u8) ![]const u8 {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(arena, source, &refusal);
    _ = try own.run(arena, &module, .{});
    try support.verified(arena, &module, &.{});
    const context: u8 = 0;
    return emit_llvm.emitModule(arena, &module, .{ .locator = .{ .context = &context, .locate = noLocation }, .source_path = "task.selka", .main = .{} });
}

fn noLocation(_: *const anyopaque, _: u32) emit_llvm.Location {
    return .{ .line = 1, .column = 1 };
}

/// The text of the function defined as `::name"(`, from its `define` line to its closing brace. A call of it elsewhere is not
/// a definition, so only `define` lines are matched.
fn functionText(text: []const u8, name: []const u8) ?[]const u8 {
    var needle_buffer: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&needle_buffer, "::{s}\"(", .{name}) catch return null;
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, text, from, "\ndefine ")) |line| {
        const line_end = std.mem.indexOfScalarPos(u8, text, line + 1, '\n') orelse text.len;
        if (std.mem.indexOf(u8, text[line..line_end], needle) != null) {
            const end = std.mem.indexOfPos(u8, text, line_end, "\n}") orelse return null;
            return text[line + 1 .. end + 2];
        }
        from = line_end;
    }
    return null;
}

/// The bodies of every task thunk in `text`: each function whose name names `<task.thunk.`.
fn thunkCount(text: []const u8) usize {
    var count: usize = 0;
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, text, from, "\ndefine ")) |line| {
        const end = std.mem.indexOfScalarPos(u8, text, line + 1, '\n') orelse text.len;
        if (std.mem.indexOf(u8, text[line..end], "<task.thunk.") != null) count += 1;
        from = end;
    }
    return count;
}

/// Each thunk's body, concatenated: the text of every `define` whose name names `<task.thunk.`.
fn thunkBodies(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, text, from, "\ndefine ")) |line| {
        const end = std.mem.indexOfScalarPos(u8, text, line + 1, '\n') orelse text.len;
        if (std.mem.indexOf(u8, text[line..end], "<task.thunk.") != null) {
            const close = std.mem.indexOfPos(u8, text, end, "\n}") orelse text.len;
            try out.appendSlice(arena, text[line + 1 .. @min(close + 2, text.len)]);
        }
        from = end;
    }
    return out.items;
}

/// Whether no drop sits between `submit` and `join` in the text of `body`.
fn noDropBetween(body: []const u8, submit: usize, join: usize) bool {
    const drop = std.mem.indexOfPos(u8, body[0..join], submit, "@myl_core_drop_");
    return drop == null;
}

/// The offset of the label that starts the basic block holding `at`: the nearest line at column 0 that ends in `:`.
fn blockStart(body: []const u8, at: usize) usize {
    var line_start = at;
    while (true) {
        const newline = std.mem.lastIndexOfScalar(u8, body[0..line_start], '\n') orelse return 0;
        const line_end = std.mem.indexOfScalarPos(u8, body, newline + 1, '\n') orelse body.len;
        const line = body[newline + 1 .. line_end];
        if (line.len > 1 and line[line.len - 1] == ':' and line[0] != ' ') return newline + 1;
        line_start = newline;
    }
}

/// Checks every join after `submit` against its own block, and returns how many joins there are.
fn joinsKeepDropsBehind(body: []const u8, submit: usize) !usize {
    var joins: usize = 0;
    var from: usize = submit;
    while (std.mem.indexOfPos(u8, body, from, "@myl_core_owned_group_end")) |join| {
        if (!noDropInBlockBefore(body, join)) return error.TestUnexpectedResult;
        joins += 1;
        from = join + 1;
    }
    return joins;
}

/// Whether no drop sits in the basic block of `join` before the join: the join runs first on every path through it.
fn noDropInBlockBefore(body: []const u8, join: usize) bool {
    return std.mem.indexOfPos(u8, body[0..join], blockStart(body, join), "@myl_core_drop_") == null;
}

test "task groups: the join precedes the drop of a lent list on the fall-through edge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try emitText(arena.allocator(), lent_list);
    const body = functionText(text, "go") orelse return error.TestUnexpectedResult;
    const submit = std.mem.indexOf(u8, body, "@myl_core_owned_task_submit_indexed") orelse return error.TestUnexpectedResult;
    const join = std.mem.indexOfPos(u8, body, submit, "@myl_core_owned_group_end") orelse return error.TestUnexpectedResult;
    try std.testing.expect(noDropBetween(body, submit, join));
    try std.testing.expect(noDropInBlockBefore(body, join));
    // The lent list is dropped after the join: a drop exists, and it comes after the join.
    const drop = std.mem.indexOfPos(u8, body, join, "@myl_core_drop_") orelse return error.TestUnexpectedResult;
    try std.testing.expect(drop > join);
}

test "task groups: every join of an early exit precedes the drops after it, on each exit edge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try emitText(arena.allocator(), exit_edges);
    const body = functionText(text, "go") orelse return error.TestUnexpectedResult;
    const submit = std.mem.indexOf(u8, body, "@myl_core_owned_task_submit_indexed") orelse return error.TestUnexpectedResult;
    // A `break`, a `return` and the block's end each join. The first join in the text follows the submit with no drop
    // between them (a drop placed right after the submit would show here), and every join runs before any drop in its block.
    const first = std.mem.indexOfPos(u8, body, submit, "@myl_core_owned_group_end") orelse return error.TestUnexpectedResult;
    try std.testing.expect(noDropBetween(body, submit, first));
    // Nothing in this program drops before its first join, so a drop anywhere ahead of that join is a lent value freed early.
    try std.testing.expect(std.mem.indexOf(u8, body[0..first], "@myl_core_drop_") == null);
    try std.testing.expect(try joinsKeepDropsBehind(body, submit) >= 3);
}

test "task groups: a thunk never drops a value, and only an own argument is taken from the environment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try emitText(arena.allocator(), three_arguments);
    try std.testing.expectEqual(@as(usize, 3), thunkCount(text));
    const bodies = try thunkBodies(arena.allocator(), text);
    // No thunk drops: the lent values belong to their lenders, and the environment releases the rest.
    try std.testing.expect(std.mem.indexOf(u8, bodies, "@myl_core_drop_") == null);
    // Exactly one argument is `own`, so exactly one slot is taken out of the environment.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, bodies, "@myl_core_task_take("));
}

fn aliasLenders(module: *const @import("ir.zig").Module) !usize {
    var lenders: usize = 0;
    for (module.functions.items) |function| {
        for (function.insts.items) |instruction| {
            try std.testing.expect(instruction.op != .list_copy);
            try std.testing.expect(instruction.op != .dict_copy);
            try std.testing.expect(instruction.op != .buffer_copy);
            if (instruction.op != .box_make or instruction.data & flags.lent_box == 0) continue;
            const source = function.inst(function.resolve(instruction.a));
            try std.testing.expect(module.managed(source.ty));
            try std.testing.expect(!module.containsBorrow(source.ty));
            try std.testing.expect(source.op != .text_sentinel);
            try std.testing.expect(instruction.b != .none);
            lenders += 1;
        }
    }
    return lenders;
}

test "F1 task aliases lend canonical storage without copies and drop owners after the join" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(arena.allocator(), lent_aliases, &refusal);
    try std.testing.expectEqual(@as(usize, 7), try aliasLenders(&module));
    _ = try own.run(arena.allocator(), &module, .{});
    try support.verified(arena.allocator(), &module, &.{});
    const text = try emitText(arena.allocator(), lent_aliases);
    const body = functionText(text, "go") orelse return error.TestUnexpectedResult;
    const submit = std.mem.indexOf(u8, body, "@myl_core_owned_task_submit_indexed") orelse return error.TestUnexpectedResult;
    const join = std.mem.indexOfPos(u8, body, submit, "@myl_core_owned_group_end") orelse return error.TestUnexpectedResult;
    try std.testing.expect(noDropBetween(body, submit, join));
    try std.testing.expect(std.mem.indexOfPos(u8, body, join, "@myl_core_drop_") != null);
}

fn applyTaskRepair(a: std.mem.Allocator, text: []const u8, source: language.source.Source, failure: ownership.Failure) ![]const u8 {
    try std.testing.expect(failure.repair == .explicit_fix);
    const edits = try a.dupe(language.diagnostic.Edit, failure.repair.explicit_fix);
    for (edits) |*edit| {
        const original = try source.originalSpan(edit.span);
        try std.testing.expectEqualStrings(text, source.origins[original.input].original.bytes);
        edit.span = original.span;
    }
    std.mem.sort(language.diagnostic.Edit, edits, {}, struct {
        fn before(_: void, left: language.diagnostic.Edit, right: language.diagnostic.Edit) bool {
            return left.span.start < right.span.start;
        }
    }.before);
    var fixed: std.ArrayList(u8) = .empty;
    var offset: usize = 0;
    for (edits) |edit| {
        try std.testing.expect(edit.span.start >= offset);
        try fixed.appendSlice(a, text[offset..edit.span.start]);
        try fixed.appendSlice(a, edit.text);
        offset = edit.span.end;
    }
    try fixed.appendSlice(a, text[offset..]);
    return fixed.items;
}

fn borrowingTaskRefused(a: std.mem.Allocator, text: []const u8) !void {
    const checked = try support.checkSource(a, text);
    try std.testing.expect(checked.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, checked.program.?, checked.src.?, &failure));
    try std.testing.expectEqualStrings("E_VIEW_FUNCTION_VALUE", failure.code);
    try std.testing.expect(failure.rule == .V4);
    try std.testing.expectEqualStrings("pick", checked.src.?.text(failure.span));
    const fixed = try applyTaskRepair(a, text, checked.src.?, failure);
    try std.testing.expect(std.mem.indexOf(u8, fixed, "g.submit(pick_copy,") != null);
    try std.testing.expect(std.mem.indexOf(u8, fixed, "return copy(pick(") != null);
    const repaired = try support.checkSource(a, fixed);
    try std.testing.expect(repaired.passed);
    failure = .{};
    try ownership.checkWithSource(a, repaired.program.?, repaired.src.?, &failure);
    const llvm = try emitText(a, fixed);
    try std.testing.expect(thunkCount(llvm) != 0);
}

test "F1 task submit refuses borrowed list record and option results with precise V4 repairs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const bodies = [_][]const u8{
        \\func pick(value: int[]) -> int[] from value:
        \\    return value
        \\func main() -> int:
        \\    const value = [1, 2]
        \\    with parallel.group() as g:
        \\        const job = g.submit(pick, value)
        \\        _ = job.result()
        \\    return 0
        ,
        \\record Item:
        \\    values: int[]
        \\func pick(value: Item) -> Item from value:
        \\    return value
        \\func main() -> int:
        \\    const value = Item(values=[1, 2])
        \\    with parallel.group() as g:
        \\        const job = g.submit(pick, value)
        \\        _ = job.result()
        \\    return 0
        ,
        \\func pick(value: int[][]) -> int[]? from value:
        \\    if len(value) == 0:
        \\        return None
        \\    return Some(value[0])
        \\func main() -> int:
        \\    const value = [[1, 2]]
        \\    with parallel.group() as g:
        \\        const job = g.submit(pick, value)
        \\        _ = job.result()
        \\    return 0
        ,
    };
    for (bodies) |body| try borrowingTaskRefused(arena.allocator(), try std.mem.concat(arena.allocator(), u8, &.{ "import parallel\n", body }));
}

/// Plain list, text and bytes parameters given to tasks (FR58), each called with a slice.
const view_parameters =
    \\import parallel
    \\func weigh(values: int[]) -> int:
    \\    return len(values)
    \\func text_size(value: str) -> int:
    \\    return len(value)
    \\func bytes_size(value: bytes) -> int:
    \\    return len(value)
    \\func go(values: int[], text: str, octets: bytes) -> int:
    \\    with parallel.group() as g:
    \\        const a = g.submit(weigh, values)
    \\        const b = g.submit(text_size, text)
    \\        const c = g.submit(bytes_size, octets)
    \\        return a.result() + b.result() + c.result()
    \\func main() -> int:
    \\    const values = [1, 2, 3]
    \\    return go(values[1:3], "abc"[0:2], b"abc"[1:2])
;

test "FR58 a view parameter given to a task is lent as the view itself, with no copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(arena.allocator(), view_parameters, &refusal);
    var stored: usize = 0;
    var passed: usize = 0;
    for (module.functions.items) |function| {
        const thunk = std.mem.startsWith(u8, function.name, "<task.thunk.");
        for (function.insts.items) |instruction| {
            try std.testing.expect(instruction.op != .list_copy and instruction.op != .str_from_view and instruction.op != .block_frame);
            // The environment holds each view parameter itself, not the whole of its cache owner.
            if (instruction.op == .record_make) for (function.operands(instruction.data)) |field| {
                const source = function.inst(function.resolve(field));
                if (module.isView(source.ty) and source.op == .param) stored += 1;
            };
            // The thunk passes the stored view to the callee, as a direct call passes the parameter.
            if (thunk and instruction.op == .call) {
                const first = function.inst(function.resolve(function.operands(instruction.data)[0]));
                if (module.isView(first.ty) and first.op == .record_get) passed += 1;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 3), stored);
    try std.testing.expectEqual(@as(usize, 3), passed);
    _ = try own.run(arena.allocator(), &module, .{});
    try support.verified(arena.allocator(), &module, &.{});
}
