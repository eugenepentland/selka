//! The receiver split repair preserves the one call and prior evaluation order.
const std = @import("std");
const t = std.testing;
const language = @import("selka");
const repair = @import("receiver_repair.zig");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");

const helpers = "func selected(mut items: int[]) -> int:\n    append(mut items, 3)\n    return 0\n\n";
const prefix = helpers ++ "func main() -> int:\n    mut items = [1, 2]\n";
const call = "selected(mut items)";
const fixture = prefix ++ "    items[" ++ call ++ "] = 9\n    return items[0] + len(items)\n";

fn span(bytes: []const u8, text: []const u8) language.source.Span {
    const start = std.mem.indexOf(u8, bytes, text).?;
    return .{ .start = start, .end = start + text.len };
}

fn site(bytes: []const u8) repair.Site {
    const selected = if (std.mem.indexOf(u8, bytes, call)) |start|
        language.source.Span{ .start = start, .end = start + call.len }
    else multiline: {
        const start = std.mem.lastIndexOf(u8, bytes, "selected(").?;
        break :multiline language.source.Span{ .start = start, .end = std.mem.indexOfScalarPos(u8, bytes, start, ')').? + 1 };
    };
    return .{ .receiver = span(bytes, "items["), .call = selected };
}

fn prove(a: std.mem.Allocator, bytes: []const u8) !?language.diagnostic.Fix {
    return repair.prove(a, try language.source.Source.init(a, "receiver.selka", bytes), site(bytes));
}

fn apply(a: std.mem.Allocator, bytes: []const u8, fix: language.diagnostic.Fix) ![]const u8 {
    try t.expectEqual(@as(usize, 2), fix.count());
    const insertion = fix.edit;
    const replacement = fix.more[0];
    try t.expect(insertion.span.start == insertion.span.end and insertion.span.end <= replacement.span.start);
    return std.mem.concat(a, u8, &.{
        bytes[0..insertion.span.start], insertion.text, bytes[insertion.span.end..replacement.span.start], replacement.text, bytes[replacement.span.end..],
    });
}

fn noFix(gpa: std.mem.Allocator, statement: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.mem.concat(a, u8, &.{ prefix, "    ", statement, "\n    return 0\n" });
    try t.expectEqual(@as(?language.diagnostic.Fix, null), try prove(a, bytes));
}

test "receiver repair moves a scalar call once and the repaired program passes Core" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fix = (try prove(a, fixture)).?;
    const name = try std.fmt.allocPrint(a, "mutation_result_{d}", .{site(fixture).call.start});
    try t.expectEqualStrings(try std.fmt.allocPrint(a, "    const {s} = {s}\n", .{ name, call }), fix.edit.text);
    try t.expectEqualStrings(call, fixture[fix.more[0].span.start..fix.more[0].span.end]);
    const after = try apply(a, fixture, fix);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, after, call));
    var failure: unique.Failure = .{};
    try unique.checkWithSource(a, try support.checkedProgram(a, after), try language.source.Source.init(a, "receiver.selka", after), &failure);
    try t.expectEqualStrings("", failure.message);
}

test "receiver repair withholds prior reads effects augmented writes and conditional evaluation" {
    try noFix(t.allocator, "items[selected(mut items)] = items[0]");
    try noFix(t.allocator, "items[selected(mut items)] = previous");
    try noFix(t.allocator, "items[selected(mut items)] = holder.value");
    try noFix(t.allocator, "items[selected(mut items)] = 8 + 1");
    try noFix(t.allocator, "items[selected(mut items)] = other()");
    try noFix(t.allocator, "items[selected(mut items)] += 9");
    try noFix(t.allocator, "items[selected(mut items) + 1] = 9");
    try noFix(t.allocator, "items[selected(mut items) if True else 0] = 9");
    try noFix(t.allocator, "items[selected(\n        mut items\n    )] = 9");
}

test "receiver repair withholds earlier indices even literals that may trap" {
    try noFix(t.allocator, "items[999][selected(mut items)] = 9");
    try noFix(t.allocator, "items[index][selected(mut items)] = 9");
    try noFix(t.allocator, "items[items[0]][selected(mut items)] = 9");
    try noFix(t.allocator, "items[other()][selected(mut items)] = 9");
    try noFix(t.allocator, "items[selected(mut items)][index] = 9");
}

test "receiver repair preserves CRLF indentation and avoids names in comments" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const stem = try std.fmt.allocPrint(a, "mutation_result_{d}", .{site(fixture).call.start});
    const collision = try std.fmt.allocPrint(a, "{s}# {s} is reserved\n", .{ fixture, stem });
    const renamed = (try prove(a, collision)).?;
    try t.expectEqualStrings(try std.fmt.allocPrint(a, "{s}_1", .{stem}), renamed.more[0].text);
    const crlf = try std.mem.replaceOwned(u8, a, fixture, "\n", "\r\n");
    const fix = (try prove(a, crlf)).?;
    try t.expect(std.mem.startsWith(u8, fix.edit.text, "    const mutation_result_"));
    try t.expect(std.mem.endsWith(u8, fix.edit.text, "\r\n"));
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, fix.edit.text, "\n"));
}

test "receiver repair requires an exact call span and a standalone source statement" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try language.source.Source.init(a, "receiver.selka", fixture);
    const partial: repair.Site = .{ .receiver = site(fixture).receiver, .call = span(fixture, "selected(mut") };
    try t.expectEqual(@as(?language.diagnostic.Fix, null), try repair.prove(a, src, partial));
    try noFix(t.allocator, "mut before = 0; items[selected(mut items)] = 9");
}

test "receiver repair maps both edits to one original module with stable generated names" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const left = try language.source.Source.init(a, "left.selka", "func other() -> int:\n    return 0\n");
    const right = try language.source.Source.init(a, "receiver.selka", fixture);
    const mapped = try language.source.Source.initMapped(a, &.{ left, right });
    const local_site = site(fixture);
    const global: repair.Site = .{ .receiver = try mapped.mappedSpan(1, local_site.receiver), .call = try mapped.mappedSpan(1, local_site.call) };
    const fix = (try repair.prove(a, mapped, global)).?;
    const standalone = (try prove(a, fixture)).?;
    try t.expectEqualStrings(standalone.more[0].text, fix.more[0].text);
    try t.expectEqualStrings(call, mapped.text(fix.more[0].span));
    try t.expectEqual(@as(usize, 1), (try mapped.originalSpan(fix.edit.span)).input);
    try t.expectEqual(@as(usize, 1), (try mapped.originalSpan(fix.more[0].span)).input);
    const crossed: repair.Site = .{ .receiver = try mapped.mappedSpan(0, .{ .start = 0, .end = 4 }), .call = global.call };
    try t.expectEqual(@as(?language.diagnostic.Fix, null), try repair.prove(a, mapped, crossed));
}
