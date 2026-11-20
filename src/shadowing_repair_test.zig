//! The repair note of an `E_SHADOWING` refusal (lane FR18): which refusals carry it, and what it names.
const std = @import("std");
const repair = @import("shadowing_repair.zig");
const module_names = @import("module_names.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");

// spec: SHADOWING-NOTE-1
test "SHADOWING-NOTE-1: the checker's refusal names what the binding hides, and only a module-level name or an import is repaired by rename" {
    const allocator = std.testing.allocator;
    const message = try module_names.shadowingMessage(allocator, "parameter", "strings", "the imported module");
    defer allocator.free(message);
    const hidden = repair.hiddenBy(message).?;
    try std.testing.expectEqualStrings("strings", hidden.name);
    try std.testing.expect(hidden.module_level);
    const local = try module_names.shadowingMessage(allocator, "binding", "n", "the local");
    defer allocator.free(local);
    try std.testing.expect(!repair.hiddenBy(local).?.module_level);
    try std.testing.expect(repair.hiddenBy("iteration names must differ") == null);
}

// spec: SHADOWING-NOTE-2
test "SHADOWING-NOTE-2: one refusal gets the position form, several of one name the hiding: form with their count" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = "func live() -> int:\n    return 1\nfunc f() -> int:\n    const live = 2\n    return live\nfunc g(reason: int) -> int:\n    return reason\n";
    const src = try source.Source.init(a, "server.selka", text);
    const first = std.mem.indexOf(u8, text, "live = 2").?;
    const hide_live = try module_names.shadowingMessage(a, "binding", "live", "the function");
    const hide_reason = try module_names.shadowingMessage(a, "parameter", "reason", "the function");
    const reason = std.mem.indexOf(u8, text, "reason:").?;
    const items = [_]diagnostic.Diagnostic{
        .{ .code = diagnostic.shadowing, .span = .{ .start = first, .end = first + 4 }, .message = hide_live },
        .{ .code = diagnostic.shadowing, .span = .{ .start = first, .end = first + 4 }, .message = hide_live },
        .{ .code = diagnostic.shadowing, .span = .{ .start = reason, .end = reason + 6 }, .message = hide_reason },
        .{ .code = "E_OTHER", .span = .{ .start = 0, .end = 1 }, .message = "other" },
    };
    const noted = try repair.annotate(a, &items, src, .{ .root = "/p/src", .cwd = "/p", .entry = "main.selka" });
    try std.testing.expectEqualStrings("2 bindings of this program hide `live`; rename them all with `selka rename src/main.selka hiding:live <new-name>`", noted[0].provenance.requirement.?.message);
    try std.testing.expectEqualStrings("rename the binding with `selka rename src/main.selka src/server.selka:6:8 <new-name>`", noted[2].provenance.requirement.?.message);
    try std.testing.expect(noted[3].provenance.requirement == null);
    // The note points at the binding itself, and nothing else of the refusal changes.
    try std.testing.expectEqual(items[2].span.start, noted[2].provenance.requirement.?.span.start);
    try std.testing.expectEqualStrings(items[2].message, noted[2].message);
}
