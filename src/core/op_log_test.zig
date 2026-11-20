//! The op log of lowering (`op_log.zig`): recorded by hand, then by lowering real programs.
const std = @import("std");
const ir = @import("ir.zig");
const build = @import("build.zig");
const op_log = @import("op_log.zig");
const stable_names = @import("stable_names.zig");
const support = @import("test_support.zig");

/// Reserve a nominal record by hand the way `ModuleBuilder.reserve` does, and fill it.
fn nominal(a: std.mem.Allocator, module: *ir.Module, recorder: *op_log.Recorder, name: []const u8, fields: []const ir.Type) !ir.Type {
    const reserved: ir.Type = @fromBackingInt(@intCast(ir.Type.first_compound + module.compounds.items.len));
    try module.compounds.append(a, .{ .record = &.{} });
    try recorder.reserved(reserved, .{ .module = "src/a.selka", .name = name });
    module.compounds.items[@backingInt(reserved) - ir.Type.first_compound] = .{ .record = try a.dupe(ir.Type, fields) };
    try recorder.filled(module, reserved);
    return reserved;
}

test "op log: a recorded segment replays into the tables it recorded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    var recorder = op_log.Recorder.init(a, std.testing.allocator, true);
    defer recorder.deinit();
    recorder.attach(&module, null);
    try recorder.begin(&module, .lower, "app::f");
    const pair = try nominal(a, &module, &recorder, "Pair", &.{ .i64, .str });
    const list = try module.intern(a, .{ .list = pair });
    const boxed = try module.intern(a, .{ .box = pair });
    try module.strings.append(a, "hello");
    try module.functions.append(a, .{ .name = "helper", .signature = .{ .params = &.{ list, boxed }, .ret = pair }, .span = 7 });
    try recorder.end(&module);
    recorder.detach(&module);
    try std.testing.expectEqual(@as(usize, 1), recorder.segments.items.len);
    try std.testing.expectEqual(@as(?op_log.Mismatch, null), try recorder.verify(a, &module));
    try std.testing.expectEqual(@as(usize, 1), recorder.segments.items[0].functions.len);
    try std.testing.expectEqualStrings("hello", recorder.segments.items[0].strings[0]);
    // A table that differs from the log is found, and named.
    try module.strings.append(a, "extra");
    const found = (try recorder.verify(a, &module)).?;
    try std.testing.expectEqualStrings("strings", found.table);
    try std.testing.expectEqual(@as(usize, 1), found.index);
}

test "op log: a segment that only finds a nominal type names it, and the segment that reserved it holds its content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    var recorder = op_log.Recorder.init(a, std.testing.allocator, true);
    defer recorder.deinit();
    recorder.attach(&module, null);
    try recorder.begin(&module, .lower, "app::first");
    const pair = try nominal(a, &module, &recorder, "Pair", &.{ .i64, .bool });
    try recorder.end(&module);
    try recorder.begin(&module, .lower, "app::second");
    const found = try module.intern(a, .{ .list = pair });
    try module.functions.append(a, .{ .name = "second", .signature = .{ .params = &.{found}, .ret = .void } });
    try recorder.end(&module);
    recorder.detach(&module);
    try std.testing.expectEqual(@as(?op_log.Mismatch, null), try recorder.verify(a, &module));
    // The second segment names the record and holds no content for it.
    const second = recorder.segments.items[1].types;
    try std.testing.expectEqual(@as(usize, 2), second.len);
    try std.testing.expectEqualStrings("Pair", second[0].nominal.name);
    try std.testing.expect(second[1] == .structural);
    // Replayed after the first segment, the record is found, not created twice.
    var both: ir.Module = .{};
    try op_log.replay(a, recorder.segments.items, &both);
    try std.testing.expectEqual(@as(usize, 2), both.compounds.items.len);
    try std.testing.expectEqualSlices(ir.Type, &.{ .i64, .bool }, both.compounds.items[0].record);
}

test "op log: a function made by a family is keyed by its creator and a runtime helper by its symbol and signature" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    var recorder = op_log.Recorder.init(a, std.testing.allocator, true);
    defer recorder.deinit();
    recorder.attach(&module, null);
    try recorder.begin(&module, .lower, "app::spawn");
    try module.functions.append(a, .{ .name = "app::spawn", .signature = .{ .params = &.{}, .ret = .void } });
    try recorder.declared(0, "app::spawn");
    try module.functions.append(a, .{ .name = "<task.thunk.5>", .signature = .{ .params = &.{}, .ret = .void } });
    try module.functions.append(a, .{ .name = "<task.thunk.9>", .signature = .{ .params = &.{}, .ret = .void } });
    try module.functions.append(a, .{ .name = "myl_core_x", .signature = .{ .params = &.{.str}, .ret = .i64, .linkage = .runtime_c } });
    try module.functions.append(a, .{ .name = "myl_core_x", .signature = .{ .params = &.{.bytes}, .ret = .i64, .linkage = .runtime_c } });
    try recorder.end(&module);
    recorder.detach(&module);
    const functions = recorder.segments.items[0].functions;
    try std.testing.expect(functions[0].key.eql(.{ .source = "app::spawn" }));
    try std.testing.expect(functions[1].key.eql(.{ .generated = .{ .creator = "app::spawn", .role = .task_thunk, .ordinal = 0 } }));
    try std.testing.expect(functions[2].key.eql(.{ .generated = .{ .creator = "app::spawn", .role = .task_thunk, .ordinal = 1 } }));
    try std.testing.expect(!functions[3].key.eql(functions[4].key));
    try std.testing.expectEqualStrings("myl_core_x", functions[3].key.runtime.symbol);
}

const program =
    \\record Pair:
    \\    left: int
    \\    right: str
    \\
    \\
    \\record Tree:
    \\    value: int
    \\    children: Tree[]
    \\
    \\
    \\enum Shape:
    \\    empty
    \\    radius(value: int)
    \\    pair(value: Pair)
    \\
    \\
    \\enum Slot[T]:
    \\    empty
    \\    filled(value: T)
    \\
    \\
    \\func total(tree: Tree) -> int:
    \\    mut sum = tree.value
    \\    for child in tree.children:
    \\        sum += total(child)
    \\    return sum
    \\
    \\
    \\func area(shape: Shape) -> int:
    \\    match shape:
    \\        case empty:
    \\            return 0
    \\        case radius(value=r):
    \\            return r * r
    \\        case pair(value=p):
    \\            return p.left
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const tree = Tree(value=1, children=[Tree(value=2, children=[])])
    \\    mut counts: dict[str, int] = {}
    \\    counts["a"] = total(tree)
    \\    const slot: Slot[int] = Slot.filled(value=9)
    \\    mut sum = area(Shape.pair(value=Pair(left=2, right="x"))) + len(counts)
    \\    match slot:
    \\        case empty:
    \\            sum += 0
    \\        case filled(value=value):
    \\            sum += value
    \\    print(out, sum)
    \\    return 0
    \\
;

test "op log: lowering a program records an op log that replays into its tables" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try support.checkedProgram(a, program);
    var summary: op_log.Summary = .{};
    var refusal: build.Refusal = .{};
    const module = try build.buildExecutable(a, .{ .program = checked, .names = &summary }, &refusal);
    try std.testing.expect(summary.checked);
    // The roots, then a lowering and a normalization segment for each of main, total and area.
    try std.testing.expect(summary.segments >= 1 + 2 * 3);
    try std.testing.expect(summary.types >= module.compounds.items.len);
    try std.testing.expectEqual(module.functions.items.len, summary.functions);
    try std.testing.expectEqual(module.strings.items.len, summary.strings);
}

test "op log: a segment replays into a module whose types differ, finding what exists and creating the rest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The segment, as the program that first lowered the function saw it: a record, a list of strings, a box of the record.
    var source: ir.Module = .{};
    var recorder = op_log.Recorder.init(a, std.testing.allocator, true);
    defer recorder.deinit();
    recorder.attach(&source, null);
    try recorder.begin(&source, .lower, "app::f");
    const strings = try source.intern(a, .{ .list = .str });
    const pair = try nominal(a, &source, &recorder, "Pair", &.{ .i64, strings });
    const boxed = try source.intern(a, .{ .box = pair });
    try recorder.end(&source);
    recorder.detach(&source);
    const ops = recorder.segments.items[0].types;
    // Another program: other types first, and the list of strings already made, but no record.
    var live: ir.Module = .{};
    var other = op_log.Recorder.init(a, std.testing.allocator, true);
    defer other.deinit();
    other.attach(&live, null);
    try other.begin(&live, .lower, "app::g");
    _ = try live.intern(a, .{ .list = .i64 });
    const existing = try live.intern(a, .{ .list = .str });
    try std.testing.expect(try other.replayable(&live, a, ops));
    const replayed = try other.replayInto(&live, a, ops);
    try other.end(&live);
    other.detach(&live);
    // The list was found, the record and the box were created after the two types that were already there.
    try std.testing.expectEqual(@as(usize, 4), live.compounds.items.len);
    try std.testing.expectEqual(existing, replayed.map[0]);
    try std.testing.expectEqual(@as(usize, 1), replayed.created.len);
    try std.testing.expectEqualStrings("Pair", replayed.created[0].name.name);
    try std.testing.expectEqualSlices(ir.Type, &.{ .i64, existing }, live.compounds.items[2].record);
    try std.testing.expectEqual(replayed.created[0].ty, live.compounds.items[3].box);
    try std.testing.expectEqual(boxed, @as(ir.Type, @fromBackingInt(ir.Type.first_compound + 2)));
    // A record the module lacks and the operations do not fill cannot be replayed.
    try std.testing.expect(!try other.replayable(&live, a, &.{.{ .nominal = .{ .module = "", .name = "Missing" } }}));
    try std.testing.expect(!try other.replayable(&live, a, &.{.{ .structural = .{ .list = @fromBackingInt(ir.Type.first_compound + 5) } }}));
}

test "op log: a replay into a recorder that keeps no log registers the types without recording a segment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var source: ir.Module = .{};
    var recorder = op_log.Recorder.init(a, std.testing.allocator, true);
    defer recorder.deinit();
    recorder.attach(&source, null);
    try recorder.begin(&source, .lower, "app::f");
    const pair = try nominal(a, &source, &recorder, "Pair", &.{ .i64, .bool });
    _ = try source.intern(a, .{ .list = pair });
    try recorder.end(&source);
    recorder.detach(&source);
    var live: ir.Module = .{};
    var quiet = op_log.Recorder.init(a, std.testing.allocator, false);
    defer quiet.deinit();
    quiet.attach(&live, null);
    try quiet.begin(&live, .lower, "app::f");
    const replayed = try quiet.replayInto(&live, a, recorder.segments.items[0].types);
    try std.testing.expectEqual(@as(usize, 0), quiet.operations().len);
    try std.testing.expectEqual(@as(usize, 1), replayed.created.len);
    try std.testing.expectEqual(@as(?ir.Type, replayed.created[0].ty), quiet.nominalType(&live, .{ .module = "src/a.selka", .name = "Pair" }));
    // The type the module now holds is found by structure, so a second replay creates nothing.
    const again = try quiet.replayInto(&live, a, recorder.segments.items[0].types);
    try std.testing.expectEqual(@as(usize, 0), again.created.len);
    try std.testing.expectEqual(@as(usize, 2), live.compounds.items.len);
}

const names_program =
    \\import parallel
    \\
    \\record Pair:
    \\    left: int
    \\    right: str
    \\
    \\
    \\func weigh(values: int[], scale: int) -> int:
    \\    mut total = 0
    \\    for value in values:
    \\        total += value * scale
    \\    return total
    \\
    \\
    \\func spread(values: int[]) -> int:
    \\    mut first = 0
    \\    with parallel.group() as g:
    \\        const a = g.submit(weigh, values, 1)
    \\        first = a.result()
    \\    return first
    \\
    \\
    \\func describe(pair: Pair) -> str:
    \\    return f"{pair}"
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const pair = Pair(left=2, right="x")
    \\    const values: int[] = [1, 2, 3]
    \\    print(out, describe(pair), spread(values), len(describe(copy(pair))))
    \\    return 0
    \\
;

/// The names of the compiler-made functions of `module` that the vocabulary knows a family for, in table order.
fn generatedNames(a: std.mem.Allocator, module: *const ir.Module) ![]const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    for (module.functions.items) |function| {
        if (stable_names.generatedRole(function.name) != null) try found.append(a, function.name);
    }
    return found.items;
}

test "op log: compiler-made function names hold no table position" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const plain = try support.projectModule(a, names_program, &refusal);
    // The same program with a function in front of everything that makes types, helpers and functions of its own.
    const shifted_source = try std.mem.concat(a, u8, &.{
        "import parallel\n\nfunc extra(words: str[], table: dict[str, int], flag: bool?) -> int:\n    return len(words) + len(table)\n\n\n",
        names_program["import parallel\n".len..],
    });
    const shifted = try support.projectModule(a, shifted_source, &refusal);
    const before = try generatedNames(a, &plain);
    const after = try generatedNames(a, &shifted);
    try std.testing.expect(before.len >= 3);
    for (before) |name| {
        var present = false;
        for (after) |other| present = present or std.mem.eql(u8, name, other);
        try std.testing.expect(present);
    }
}

test "op log: the role prefixes are the producers' constants" {
    try std.testing.expect(std.mem.eql(u8, stable_names.role_prefixes[5].prefix, @import("aggregate_provider.zig").prefix));
    try std.testing.expect(std.mem.eql(u8, stable_names.role_prefixes[6].prefix, @import("borrowed_provider.zig").prefix));
    try std.testing.expect(std.mem.eql(u8, stable_names.role_prefixes[7].prefix, @import("borrowed_provider.zig").optional_prefix));
    try std.testing.expect(std.mem.eql(u8, stable_names.role_prefixes[4].prefix, @import("build_equality.zig").prefix));
    try std.testing.expect(std.mem.eql(u8, stable_names.role_prefixes[8].prefix, @import("borrow_selection.zig").prefix));
    try std.testing.expect(std.mem.eql(u8, stable_names.role_prefixes[9].prefix, @import("borrow_selection.zig").choice_prefix));
    try std.testing.expect(std.mem.eql(u8, stable_names.role_prefixes[10].prefix, @import("emit_owned_copy.zig").prefix));
    try std.testing.expect(std.mem.eql(u8, stable_names.role_prefixes[3].prefix, @import("build_render.zig").declaration_prefix));
}
