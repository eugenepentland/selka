//! C6: the certain borrow repairs for an element read refused as a borrow. Each
//! shape is checked before and after its repair: the refusal names the repair,
//! applying the repair gives the expected text, and the repaired source checks.
//! A shape with no proof keeps the copy repair.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");

/// `source` with the entry point a whole-program check needs.
fn withEntry(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ source, "\n\nfunc main() -> int:\n    return 0\n" });
}

/// Check `text` with the source-aware ownership contract, returning the refusal.
fn refusal(a: std.mem.Allocator, text: []const u8) !unique.Failure {
    var failure: unique.Failure = .{};
    const src = try language.source.Source.init(a, "repair.selka", text);
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, try support.checkedProgram(a, text), src, &failure));
    return failure;
}

/// Check `text` with the ownership contract, which must accept it.
fn expectChecks(a: std.mem.Allocator, text: []const u8) !void {
    var failure: unique.Failure = .{};
    try unique.checkWithSource(a, try support.checkedProgram(a, text), try language.source.Source.init(a, "repair.selka", text), &failure);
}

/// The name span of a refusal whose repair is the const borrow.
fn constSpan(failure: unique.Failure) !language.source.Span {
    return switch (failure.repair) {
        .const_binding => |found| found,
        else => error.TestUnexpectedResult,
    };
}

/// Apply the edits of one repair to `text`, last edit first, and return the result.
fn applyEdits(a: std.mem.Allocator, text: []const u8, edits: []const language.diagnostic.Edit) ![]const u8 {
    const sorted = try a.dupe(language.diagnostic.Edit, edits);
    std.mem.sort(language.diagnostic.Edit, sorted, {}, struct {
        fn less(_: void, left: language.diagnostic.Edit, right: language.diagnostic.Edit) bool {
            return left.span.start > right.span.start;
        }
    }.less);
    var out: []const u8 = try a.dupe(u8, text);
    for (sorted) |edit| {
        out = try std.mem.concat(a, u8, &.{ out[0..edit.span.start], edit.text, out[edit.span.end..] });
    }
    return out;
}

/// The repaired text of a refusal whose repair is a write-back, checked clean.
fn expectWriteBack(backing: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try withEntry(a, source);
    const failure = try refusal(a, text);
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_BORROW", failure.code);
    const edits = switch (failure.repair) {
        .write_back => |found| found,
        else => return error.TestUnexpectedResult,
    };
    const repaired = try applyEdits(a, text, edits);
    try std.testing.expectEqualStrings(try withEntry(a, expected), repaired);
    try expectChecks(a, repaired);
}

const item_record =
    \\record Item:
    \\    value: int
    \\    weight: int
    \\    tags: int[]
    \\
    \\
;

test "C6 (a): a mut element binding that is only read borrows the element, so no repair is needed (D4)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try withEntry(a, item_record ++
        \\func total(items: Item[]) -> int:
        \\    mut sum = 0
        \\    for i in range(len(items)):
        \\        mut item = items[i]
        \\        sum += item.value
        \\    return sum
        \\
        \\
    );
    try expectChecks(a, text);
}

test "C6 (a): a binding the function writes keeps the copy repair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try withEntry(a, item_record ++
        \\func bump(items: Item[]) -> int:
        \\    mut item = items[0]
        \\    item.value = item.value + 1
        \\    return item.value
        \\
        \\
    );
    const failure = try refusal(a, text);
    try std.testing.expect(failure.repair == .none or failure.repair == .write_back);
    try std.testing.expect(failure.copy.span != null);
    // Refused at the write through `item` (D4), with the copy at its binding.
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "write `mut item = copy(items[0])` to keep both") != null);
}

test "C6 (a): a binding whose owner changes while it is live keeps the copy repair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try withEntry(a, item_record ++
        \\func churn(mut items: Item[]) -> int:
        \\    mut item = items[0]
        \\    items[0] = Item(value=9, weight=1, tags=[])
        \\    return item.value
        \\
        \\
    );
    const failure = try refusal(a, text);
    try std.testing.expect(failure.repair != .const_binding);
    try std.testing.expect(failure.copy.span != null);
}

test "C6 (b): a write-back through a scalar field becomes writes to the element place" {
    try expectWriteBack(std.testing.allocator, item_record ++
        \\func bump(mut items: Item[], i: int):
        \\    mut item = items[i]
        \\    item.value = item.value + 1
        \\    items[i] = item
        \\
        \\
    , item_record ++
        \\func bump(mut items: Item[], i: int):
        \\    items[i].value = items[i].value + 1
        \\
        \\
    );
}

test "C6 (b): a binding used whole, or an owner mentioned in between, keeps the copy repair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const whole = try withEntry(a, item_record ++
        \\func weigh(item: Item) -> int:
        \\    return item.weight
        \\
        \\
        \\func bump(mut items: Item[], i: int) -> int:
        \\    mut item = items[i]
        \\    item.value = weigh(item)
        \\    items[i] = item
        \\    return item.value
        \\
        \\
    );
    const whole_failure = try refusal(a, whole);
    try std.testing.expect(whole_failure.repair != .write_back);
    const mentioned = try withEntry(a, item_record ++
        \\func bump(mut items: Item[], i: int):
        \\    mut item = items[i]
        \\    items[i].weight = 4
        \\    item.value = item.value + 1
        \\    items[i] = item
        \\
        \\
    );
    const mentioned_failure = try refusal(a, mentioned);
    try std.testing.expect(mentioned_failure.repair != .write_back);
}

test "C6 (c): a mut binding of an element returned under from borrows it, so no repair is needed (D4)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try withEntry(a, item_record ++
        \\func first(items: Item[]) -> Item from items:
        \\    mut kept = items[0]
        \\    return kept
        \\
        \\
    );
    try expectChecks(a, text);
}

test "C6 (d): a match arm that calls a mut helper names the cost and the alternatives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try withEntry(a, item_record ++
        \\enum Slot:
        \\    empty
        \\    item(value: Item)
        \\
        \\
        \\record Runtime:
        \\    slots: Slot[]
        \\    count: int
        \\
        \\
        \\func bump(mut rt: Runtime):
        \\    rt.count += 1
        \\
        \\
        \\func run(mut rt: Runtime) -> int:
        \\    mut total = 0
        \\    match rt.slots[0]:
        \\        case item(value=payload):
        \\            bump(mut rt)
        \\            total += payload.value
        \\        case _:
        \\            total += 0
        \\    return total
        \\
        \\
    );
    const failure = try refusal(a, text);
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
    // `rt.slots[0]` is a place, not a call's value: the cost of the copy and the local read before the match (FR80).
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "cheap when the payload is numbers") != null);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "read what the arm needs into a local before the match") != null);
}

test "C6: the repair of a write through a borrowing mut binding renders as the certain copy at its binding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try withEntry(a, item_record ++
        \\func total(items: Item[]) -> int:
        \\    mut sum = 0
        \\    for i in range(len(items)):
        \\        mut item = items[i]
        \\        item.value = item.value + 1
        \\        sum += item.value
        \\    return sum
        \\
        \\
    );
    const src = try language.source.Source.init(a, "repair.selka", text);
    const failure = try refusal(a, text);
    var rendered: std.ArrayList(u8) = .empty;
    try unique.render(a, src, failure, .json, &rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"text\":\"copy(\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"text\":\"const \"") == null);
}
