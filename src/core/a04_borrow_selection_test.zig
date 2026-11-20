//! Generated borrowed selections require exact live logical type contracts.
const std = @import("std");
const language = @import("selka");
const typed = language.typed;
const choice = @import("build_borrow_selection.zig");
const owner = @import("single_owner.zig");
const build = @import("build.zig");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const flags = @import("flags.zig");
const passes = @import("passes.zig");

fn selection(program: typed.Program, kind: @FieldType(typed.BorrowSelection, "kind")) *typed.Node {
    for (@constCast(program.nodes)) |*node| if (node.data == .borrow_selection and node.data.borrow_selection.kind == kind) return node;
    unreachable;
}

// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "A04 borrowed logical choices refuse invalid node and canonical type identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var unit = try language.Compilation.init(arena.allocator(), "choice-types.selka",
        \\func main() -> int:
        \\    return strings.char_count(min("z", "a"))
    );
    try unit.check();
    const program = unit.program.?;
    const node = selection(program, .min_text);
    const original = node.data.borrow_selection;
    try std.testing.expect(choice.valid(program, original, node.ty));
    var invalid = original;
    invalid.first = @fromBackingInt(program.nodes.len);
    try std.testing.expect(!choice.valid(program, invalid, node.ty));
    invalid = original;
    invalid.second = @fromBackingInt(program.nodes.len);
    try std.testing.expect(!choice.valid(program, invalid, node.ty));
    try std.testing.expect(!choice.valid(program, original, .i64));
    try std.testing.expect(!choice.valid(program, original, @fromBackingInt(typed.Type.record_base + program.records.len)));
    const first = &@constCast(program.nodes)[@backingInt(original.first)];
    const saved_type = first.ty;
    first.ty = @fromBackingInt(typed.Type.record_base + program.records.len);
    try std.testing.expect(!choice.valid(program, original, node.ty));
    first.ty = saved_type;
    const record = &@constCast(program.records)[node.ty.recordIndex()];
    const collection = record.collection.kind;
    record.collection.kind = .bytes;
    try std.testing.expect(!choice.valid(program, original, node.ty));
    record.collection.kind = collection;
    node.data.borrow_selection.kind = .optional_default;
    try std.testing.expect(!choice.valid(program, node.data.borrow_selection, node.ty));
    var failure: owner.Failure = .{};
    try std.testing.expectError(error.Rejected, owner.check(arena.allocator(), program, &failure));
    try std.testing.expectEqualStrings("E_INTERNAL_BORROW_SELECTION", failure.code);
    try std.testing.expectEqual(@as(?language.ownership_rules.Rule, null), failure.rule);
    var refusal: build.Refusal = .{};
    try std.testing.expectError(error.Unsupported, build.buildModule(arena.allocator(), program, &refusal));
    try std.testing.expectEqualStrings("borrowed selection logical contract", refusal.reason);
}

// spec-case: OPTION-METHODS-1
// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "A04 borrowed logical optional choices reject fallible and affine carriers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var unit = try language.Compilation.init(arena.allocator(), "choice-option.selka",
        \\func count(value: str?, fallback: str) -> int:
        \\    return strings.char_count(value.unwrap_or(fallback))
        \\func main() -> int:
        \\    return count(Some("a"), "b")
    );
    try unit.check();
    const program = unit.program.?;
    const node = selection(program, .optional_default);
    const original = node.data.borrow_selection;
    try std.testing.expect(choice.valid(program, original, node.ty));
    const option = program.nodes[@backingInt(original.first)].ty;
    const record = &@constCast(program.records)[option.recordIndex()];
    const contract = record.contract;
    record.contract.move_only = true;
    try std.testing.expect(!choice.valid(program, original, node.ty));
    record.contract = contract;
    record.contract.requires_handling = true;
    try std.testing.expect(!choice.valid(program, original, node.ty));
    record.contract = contract;
    record.shape.variants.?.fallible = true;
    try std.testing.expect(!choice.valid(program, original, node.ty));
    record.shape.variants.?.fallible = false;
    const variants = record.shape.variants.?;
    const cases = try arena.allocator().dupe(typed.Variant, variants.cases);
    record.shape.variants.?.cases = cases;
    cases[0].name = "unrelated";
    try std.testing.expect(!choice.valid(program, original, node.ty));
    record.shape.variants = variants;
    var invalid = original;
    invalid.kind = .max_text;
    try std.testing.expect(!choice.valid(program, invalid, node.ty));
}

fn named(module: *const ir.Module, name: []const u8) !*const ir.Function {
    for (module.functions.items) |*function| if (std.mem.eql(u8, function.name, name)) return function;
    return error.MissingFunction;
}

test "named borrowing selection lookup refuses a missing exact source function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module: ir.Module = .{};
    try module.functions.appendSlice(arena.allocator(), &.{
        .{ .name = "optional_count_suffix", .signature = .{ .params = &.{}, .ret = .void } },
        .{ .name = "other::optional_count", .signature = .{ .params = &.{}, .ret = .void } },
    });
    try std.testing.expectError(error.MissingFunction, named(&module, "optional_count"));
    try std.testing.expectEqualStrings("optional_count_suffix", (try named(&module, "optional_count_suffix")).name);
}

fn operations(function: *const ir.Function, op: ir.Op) usize {
    var count: usize = 0;
    for (function.insts.items) |inst| if (inst.op == op) {
        count += 1;
    };
    return count;
}

fn typedOperations(function: *const ir.Function, op: ir.Op, ty: ir.Type) usize {
    var count: usize = 0;
    for (function.insts.items) |inst| if (inst.op == op and inst.ty == ty) {
        count += 1;
    };
    return count;
}

fn expectCanonicalDictionaryCopy(module: *const ir.Module, name: []const u8) !void {
    const function = try named(module, name);
    const value = module.compound(function.signature.params[0]).dict.value;
    try std.testing.expectEqual(value, function.signature.ret);
}

// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "O3 borrowing selections read optional payload and extrema views without implicit copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a,
        \\func optional_count(value: str?, fallback: str) -> int:
        \\    const selected = value.unwrap_or(fallback)
        \\    return len(selected)
        \\func extrema_count(left: str, right: str) -> int:
        \\    return len(min(left, right)) + len(max(left, right))
        \\func main() -> int:
        \\    return optional_count(Some("z"), "a") + extrema_count("z", "a")
    , &refusal);
    const optional = try named(&module, "optional_count");
    const extrema = try named(&module, "extrema_count");
    try std.testing.expectEqual(@as(usize, 0), operations(optional, .str_from_view));
    try std.testing.expectEqual(@as(usize, 1), typedOperations(optional, .union_payload, .str_view));
    try std.testing.expectEqual(@as(usize, 1), typedOperations(optional, .phi, .str_view));
    try std.testing.expectEqual(@as(usize, 0), operations(extrema, .str_from_view));
    try std.testing.expectEqual(@as(usize, 2), typedOperations(extrema, .phi, .str_view));
}

// spec-case: OPTION-METHODS-1
test "O3 borrowing selections adapt an owned fallback to an optional view without a copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a,
        \\func count(value: str?) -> int:
        \\    return len(value.unwrap_or("fallback"))
        \\func main() -> int:
        \\    return count(None) + count(Some("present"))
    , &refusal);
    const function = try named(&module, "count");
    try std.testing.expectEqual(@as(usize, 0), operations(function, .str_from_view));
    try std.testing.expectEqual(@as(usize, 1), typedOperations(function, .str_view_of, .str_view));
    try std.testing.expectEqual(@as(usize, 1), typedOperations(function, .phi, .str_view));
}

// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "O3 borrowing selections retain an explicit copy as owned text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a,
        \\func saved_optional(value: str?, fallback: str) -> str:
        \\    return copy(value.unwrap_or(fallback))
        \\func saved_extremum(left: str, right: str) -> str:
        \\    return copy(min(left, right))
        \\func main() -> int:
        \\    return len(saved_optional(Some("z"), "a")) + len(saved_extremum("z", "a"))
    , &refusal);
    const optional = try named(&module, "saved_optional");
    const extremum = try named(&module, "saved_extremum");
    try std.testing.expectEqual(ir.Type.str, optional.signature.ret);
    try std.testing.expectEqual(ir.Type.str, extremum.signature.ret);
    try std.testing.expectEqual(@as(usize, 1), typedOperations(optional, .str_from_view, .str));
    try std.testing.expectEqual(@as(usize, 1), typedOperations(extremum, .str_from_view, .str));
}

test "O3 borrowing selections normalization preserves byte list and writeback return representations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a,
        \\func borrowed_bytes(raw: bytes) -> bytes from raw:
        \\    return raw
        \\func borrowed_items(items: int[]) -> int[] from items:
        \\    return items
        \\func borrowed_writeback(mut text: str) -> str from text:
        \\    return text
        \\func main() -> int:
        \\    mut text = "hello"
        \\    const selected = borrowed_writeback(mut text)
        \\    return len(selected) + len(borrowed_bytes(b"abc")) + len(borrowed_items([1, 2]))
    , &refusal);
    const bytes = try named(&module, "borrowed_bytes");
    const items = try named(&module, "borrowed_items");
    const writeback = try named(&module, "borrowed_writeback");
    try std.testing.expectEqual(ir.Type.bytes_view, bytes.signature.ret);
    try std.testing.expect(module.kind(items.signature.ret) == .list_view);
    try std.testing.expect(module.containsBorrow(writeback.signature.ret));
    try std.testing.expectEqual(@as(usize, 0), operations(bytes, .call));
    try std.testing.expectEqual(@as(usize, 0), operations(items, .list_copy));
    try std.testing.expectEqual(@as(usize, 0), operations(writeback, .str_from_view));
    try std.testing.expectEqual(@as(usize, 1), operations(writeback, .record_make));
}

// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "O3 dictionary wrapper defaults keep reads borrowed and explicit copies canonical" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a,
        \\import dicts
        \\record Node:
        \\    value: int
        \\    next: Node?
        \\func read_node(mapping: dict[str, Node?], key: str, fallback: Node?) -> int:
        \\    match dicts.get(mapping, key, fallback):
        \\        case Some(node):
        \\            return node.value
        \\        case None:
        \\            return 0
        \\func clone_node(mapping: dict[str, Node?], key: str, fallback: Node?) -> Node?:
        \\    return copy(dicts.get(mapping, key, fallback))
        \\func read_text(mapping: dict[str, str??], key: str, fallback: str??) -> int:
        \\    match dicts.get(mapping, key, fallback):
        \\        case Some(inner):
        \\            match inner:
        \\                case Some(text):
        \\                    return len(text)
        \\                case None:
        \\                    return 7
        \\        case None:
        \\            return 11
        \\func clone_text(mapping: dict[str, str??], key: str, fallback: str??) -> str??:
        \\    return copy(dicts.get(mapping, key, fallback))
        \\func main() -> int:
        \\    mut nodes: dict[str, Node?] = {"hit": Some(Node(value=7, next=None))}
        \\    mut fallback: Node? = Some(Node(value=11, next=None))
        \\    mut words: dict[str, str??] = {"hit": Some(Some("stored"))}
        \\    mut text: str?? = Some(Some("fallback"))
        \\    return read_node(nodes, "missing", clone_node(nodes, "hit", fallback)) + read_text(words, "missing", clone_text(words, "hit", text))
    , &refusal);
    for ([_][]const u8{ "main::read_node", "main::read_text" }) |name| {
        const function = try named(&module, name);
        try std.testing.expect(module.containsBorrow(function.signature.params[2]));
        try std.testing.expectEqual(@as(usize, 0), operations(function, .str_from_view));
        try std.testing.expectEqual(@as(usize, 0), operations(function, .box_make));
        try std.testing.expectEqual(@as(usize, 0), operations(function, .list_copy));
        for (function.insts.items) |inst| try std.testing.expect(inst.data & flags.written_copy == 0);
    }
    try expectCanonicalDictionaryCopy(&module, "main::clone_node");
    try expectCanonicalDictionaryCopy(&module, "main::clone_text");
    const result = try passes.run(a, &module, .verify);
    try support.verified(a, &module, result.plans);
}
