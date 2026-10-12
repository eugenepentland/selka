//! Generated borrowed selections require exact live logical type contracts.
const std = @import("std");
const language = @import("mylang");
const typed = language.typed;
const choice = @import("build_borrow_selection.zig");
const owner = @import("single_owner.zig");
const build = @import("build.zig");

fn selection(program: typed.Program, kind: @FieldType(typed.BorrowSelection, "kind")) *typed.Node {
    for (@constCast(program.nodes)) |*node| if (node.data == .borrow_selection and node.data.borrow_selection.kind == kind) return node;
    unreachable;
}

// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "A04 borrowed logical choices refuse invalid node and canonical type identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var unit = try language.Compilation.init(arena.allocator(), "choice-types.my",
        \\func main() -> int:
        \\    return len(min("z", "a"))
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
    try std.testing.expectError(error.Rejected, owner.checkMode(arena.allocator(), program, &failure, true));
    try std.testing.expectEqualStrings("E_ZERO_RC_UNSUPPORTED", failure.code);
    var refusal: build.Refusal = .{};
    try std.testing.expectError(error.Unsupported, build.buildModule(arena.allocator(), program, &refusal));
    try std.testing.expectEqualStrings("borrowed selection logical contract", refusal.reason);
}

// spec-case: OPTION-METHODS-1
// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "A04 borrowed logical optional choices reject fallible and affine carriers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var unit = try language.Compilation.init(arena.allocator(), "choice-option.my",
        \\func count(value: str?, fallback: str) -> int:
        \\    return len(value.unwrap_or(fallback))
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
