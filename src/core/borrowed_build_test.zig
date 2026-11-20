//! Physical borrowed result construction before normalization and ownership.
const std = @import("std");
const support = @import("test_support.zig");
const ir = @import("ir.zig");
const build = @import("build.zig");
const ownership = @import("single_owner.zig");

fn operations(module: *const ir.Module, name: []const u8, op: ir.Op) usize {
    var count: usize = 0;
    for (module.functions.items) |function| {
        const local = if (std.mem.lastIndexOf(u8, function.name, "::")) |at| function.name[at + 2 ..] else function.name;
        if (!std.mem.eql(u8, local, name)) continue;
        for (function.insts.items) |inst| if (inst.op == op) {
            count += 1;
        };
    }
    return count;
}

test "O3 returned list slices borrow the final mut owner before a copy loop is built" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a,
        \\func first(mut rows: str[][]) -> str[][] from rows:
        \\    return rows[0:1]
        \\func main() -> int:
        \\    mut rows = [["first"], ["second"]]
        \\    const borrowed = first(mut rows)
        \\    return len(borrowed)
    , &refusal);
    try std.testing.expectEqual(@as(usize, 1), operations(&module, "first", .list_slice_view));
    try std.testing.expectEqual(@as(usize, 0), operations(&module, "first", .list_new));
    try std.testing.expectEqual(@as(usize, 0), operations(&module, "first", .list_copy));
    _ = try @import("own.zig").run(a, &module, .{});
    try support.verified(a, &module, &.{});
}

test "O3 whole borrowed dictionaries expose their physical shape to indexed reads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a,
        \\import dicts
        \\func same(mapping: dict[str, str[]]) -> dict[str, str[]] from mapping:
        \\    return mapping
        \\func main() -> int:
        \\    const mapping = {"first": ["one", "two"]}
        \\    const borrowed = same(mapping)
        \\    const selected = dicts.get(borrowed, "first", ["fallback"])
        \\    return len(borrowed["first"]) + len(selected)
    , &refusal);
    try std.testing.expect(operations(&module, "main", .dict_entry_value) >= 2);
    try std.testing.expectEqual(@as(usize, 0), operations(&module, "main", .list_copy));
    _ = try @import("own.zig").run(a, &module, .{});
    try support.verified(a, &module, &.{});
}

test "O3 borrowed result const aliases keep temporary and final mut owners without copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\func choose(left: str[], right: str[]) -> str[] from left, right:
        \\    return right
        \\func final(mut values: str[]) -> str[] from values:
        \\    return values
        \\func main() -> int:
        \\    const selected = choose(["left"], ["right"])
        \\    const alias = selected
        \\    const again = alias
        \\    mut values = ["mutable"]
        \\    const borrowed = final(mut values)
        \\    const mut_alias = borrowed
        \\    return len(selected) + len(alias) + len(again) + len(borrowed) + len(mut_alias)
    ;
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure);
    var refusal: build.Refusal = .{};
    var module = try build.buildModule(a, unit.program.?, &refusal);
    try std.testing.expectEqual(@as(usize, 0), operations(&module, "main", .list_copy));
    _ = try @import("own.zig").run(a, &module, .{});
    try support.verified(a, &module, &.{});
}

test "O3 borrowed result const aliases hold every root until the alias last use" {
    const template =
        \\func choose(left: str[], right: str[]) -> str[] from left, right:
        \\    return right
        \\func main() -> int:
        \\    mut left = ["left"]
        \\    mut right = ["right"]
        \\    const selected = choose(left, right)
        \\    const alias = selected
        \\    const size = len(selected)
        \\    append(mut {s}, "changed")
        \\    return size + len(alias)
    ;
    for ([_][]const u8{ "left", "right" }) |root| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const text = try std.fmt.allocPrint(a, template, .{root});
        const unit = try support.checkSource(a, text);
        try std.testing.expect(unit.passed);
        var failure: ownership.Failure = .{};
        try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
        try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
        try std.testing.expect(failure.rule == .R2);
        const write = std.mem.indexOf(u8, text, "append(mut").?;
        try std.testing.expect(failure.span.start >= write);
    }
}

test "O3 borrowed result const aliases release all roots after the alias last use" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a,
        \\func choose(left: str[], right: str[]) -> str[] from left, right:
        \\    return right
        \\func main() -> int:
        \\    mut left = ["left"]
        \\    mut right = ["right"]
        \\    const selected = choose(left, right)
        \\    const alias = selected
        \\    const size = len(selected) + len(alias)
        \\    append(mut left, "changed")
        \\    append(mut right, "changed")
        \\    return size
    );
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure);
}

test "O3 borrowed result const aliases cannot hide a temporary return source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\func choose(left: str[], right: str[]) -> str[] from left, right:
        \\    return right
        \\func escape(left: str[]) -> str[] from left:
        \\    const selected = choose(left, ["temporary"])
        \\    const alias = selected
        \\    return alias
        \\func main() -> int:
        \\    return 0
    ;
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_BORROW", failure.code);
    try std.testing.expect(failure.rule == .R3);
    const returned = std.mem.indexOf(u8, text, "return alias").?;
    try std.testing.expect(failure.span.start >= returned);
}

test "O3 borrowed result const aliases leave ordinary owned local moves unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a,
        \\func main() -> int:
        \\    mut owner = [["one"]]
        \\    const alias = own owner
        \\    return len(owner) + len(alias)
    );
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_MOVED", failure.code);
    try std.testing.expect(failure.rule == .B3);
}

test "O3 recursive read-only wrapper arguments borrow boxed payload values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\record Node:
        \\    text: str
        \\    next: Node?
        \\func compare(left: Node?, right: Node?) -> bool:
        \\    return left == right
        \\func main() -> int:
        \\    const left: Node? = Some(Node(text="value", next=None))
        \\    const right: Node? = Some(Node(text="value", next=None))
        \\    if compare(left, right) and compare(left, None):
        \\        return 1
        \\    return 0
    ;
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure);
    var refusal: build.Refusal = .{};
    var module = try build.buildModule(a, unit.program.?, &refusal);
    try std.testing.expect(operations(&module, "main", .box_get) >= 2);
    try support.verified(a, &module, &.{});
    _ = try @import("own.zig").run(a, &module, .{});
    try support.verified(a, &module, &.{});
    const llvm = try support.llvmText(a, text);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "@myl_core_values_equal") != null);
}

fn bindingCopyChecks(a: std.mem.Allocator, text: []const u8, initializer: []const u8) !void {
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    const src = unit.src.?;
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, src, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
    try std.testing.expect(failure.rule == .R2);
    try std.testing.expect(std.mem.indexOf(u8, src.text(failure.span), "source") != null);
    try std.testing.expectEqualStrings("clean", src.text(failure.notes.related.?.span));
    try std.testing.expectEqualStrings("borrowed by this binding", failure.notes.related.?.message);
    try std.testing.expectEqualStrings(initializer, src.text(failure.copy.span.?));
    var rendered: std.ArrayList(u8) = .empty;
    try ownership.render(a, src, failure, .json, &rendered);
    const json = try std.json.parseFromSliceLeaky(std.json.Value, a, rendered.items, .{});
    const diagnostic = json.object.get("diagnostic").?;
    const edits = diagnostic.object.get("fix").?.object.get("edits").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), edits.len);
    try std.testing.expectEqualStrings("copy(", edits[0].object.get("text").?.string);
    try std.testing.expectEqualStrings(")", edits[1].object.get("text").?.string);
    const start: usize = @intCast(edits[0].object.get("bytes").?.object.get("start").?.integer);
    const end: usize = @intCast(edits[1].object.get("bytes").?.object.get("start").?.integer);
    try std.testing.expectEqualStrings(initializer, text[start..end]);
    const repaired = try std.mem.concat(a, u8, &.{ text[0..start], "copy(", text[start..end], ")", text[end..] });
    const after = try support.checkSource(a, repaired);
    try std.testing.expect(after.passed);
    failure = .{};
    try ownership.checkWithSource(a, after.program.?, after.src.?, &failure);
    try std.testing.expectEqualStrings("", failure.message);
}

test "O3 borrowed binding R2 repairs copy strip before its source is replaced" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try bindingCopyChecks(arena.allocator(),
        // migrate-embedded: skip original R2 strip-binding initializer-copy repair witness
        \\import strings
        \\func main() -> int:
        \\    mut source = "  value  "
        \\    const clean = strings.strip(source)
        \\    source = "changed"
        \\    return len(clean)
    , "strings.strip(source)");
}

test "O3 borrowed binding R2 repairs copy declared results before owner mutation or replacement" {
    const template =
        \\func head(values: str[]) -> str[] from values:
        \\    return values[0:1]
        \\func main() -> int:
        \\    mut source = ["value", "kept"]
        \\    const clean = head(source)
        \\    {s}
        \\    return len(clean)
    ;
    for ([_][]const u8{ "append(mut source, \"changed\")", "source = [\"changed\"]" }) |change| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        try bindingCopyChecks(a, try std.fmt.allocPrint(a, template, .{change}), "head(source)");
    }
}

test "O3 borrowed binding R2 repairs withhold copies for temporary result sources" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a,
        \\func choose(left: str[], right: str[]) -> str[] from left, right:
        \\    return right
        \\func main() -> int:
        \\    mut source = ["value"]
        \\    const clean = choose(source, ["temporary"])
        \\    source = ["changed"]
        \\    return len(clean)
    );
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
    try std.testing.expect(failure.rule == .R2);
    try std.testing.expect(failure.copy.span == null);
    var rendered: std.ArrayList(u8) = .empty;
    try ownership.render(a, unit.src.?, failure, .json, &rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"fix\"") == null);
}

test "O3 borrowed binding R2 repairs leave ordinary place binding mutations unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a,
        \\func main() -> int:
        \\    mut source = [["value"]]
        \\    const clean = source[0]
        \\    source = [["changed"]]
        \\    return len(clean)
    );
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
    try std.testing.expect(failure.rule == .R2);
    try std.testing.expect(failure.copy.span == null);
}

test "O3 borrowed binding R2 repairs preserve declared returns through aliases and wrappers" {
    const cases = [_]struct { result: []const u8, body: []const u8 }{
        .{ .result = "str[]", .body = "    return clean" },
        .{ .result = "str[]", .body = "    const alias = clean\n    return alias" },
        .{ .result = "str[]?", .body = "    return Some(clean)" },
    };
    const template =
        \\func head(value: str[]) -> str[] from value:
        \\    return value
        \\func bad(mut source: str[]) -> {s} from source:
        \\    const clean = head(source)
        \\    append(mut source, "changed")
        \\{s}
        \\func main() -> int:
        \\    return 0
    ;
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const unit = try support.checkSource(a, try std.fmt.allocPrint(a, template, .{ case.result, case.body }));
        try std.testing.expect(unit.passed);
        var failure: ownership.Failure = .{};
        try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
        try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
        try std.testing.expect(failure.rule == .R2);
        try std.testing.expectEqualStrings("clean", unit.src.?.text(failure.notes.related.?.span));
        try std.testing.expect(failure.copy.span == null);
        var rendered: std.ArrayList(u8) = .empty;
        try ownership.render(a, unit.src.?, failure, .json, &rendered);
        try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"fix\"") == null);
    }
}
