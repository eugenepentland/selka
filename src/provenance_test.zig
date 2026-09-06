//! Ownership diagnostics identify causal sites; repaired fixtures must execute correctly.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");
fn checkRepair(bad: []const u8, fixed: []const u8, code: []const u8, locations: [3]usize, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "repair.my", bad);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const problem = c.diagnostics.items[0];
    try t.expectEqualStrings(code, problem.code);
    try t.expectEqual(locations[0], problem.span.start);
    try t.expectEqual(locations[1], problem.related.?.span.start);
    try t.expectEqual(locations[2], problem.provenance.origin.?.span.start);
    const rendered = try problem.render(t.allocator, c.src);
    defer t.allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, "value declared here") != null);
    var repaired = try language.Compilation.init(t.allocator, "repaired.my", fixed);
    defer repaired.deinit();
    try t.expectEqual(expected, (try repaired.execute(t.allocator)).value);
}
fn at(text: []const u8, needle: []const u8, skip: usize) usize {
    return std.mem.indexOf(u8, text, needle).? + skip;
}
// spec: DIAGNOSTIC-PROVENANCE-1
test "ownership transfer diagnostics identify the use move and declaration before a valid repair" {
    for ([_]bool{ false, true }) |generic| {
        const prefix = if (generic) "fn work<T:copy>()->i64{" else "fn work()->i64{";
        const main = if (generic) "fn main()->i64{return work::<bool>();}" else "fn main()->i64{return work();}";
        const body = "let original=new R.ok(7);let moved=original;acknowledge original;acknowledge moved;return 7;}";
        const bad = try std.mem.concat(t.allocator, u8, &.{ "result R{ok:i64,err:i64}", prefix, body, main });
        defer t.allocator.free(bad);
        const fixed = try std.mem.replaceOwned(u8, t.allocator, bad, "acknowledge original;", "");
        defer t.allocator.free(fixed);
        try checkRepair(
            bad,
            fixed,
            "E_RESULT_CONSUMED",
            .{ at(bad, "acknowledge original", 12), at(bad, "moved=original", 6), at(bad, "let original", 4) },
            7,
        );
    }
}
test "borrow conflict diagnostics identify the loan and owner before shortening the loan scope" {
    for ([_]bool{ false, true }) |generic| {
        const prefix = if (generic) "fn work<T:copy>()->i64{" else "fn work()->i64{";
        const main = if (generic) "fn main()->i64{return work::<bool>();}" else "fn main()->i64{return work();}";
        const bad = try std.mem.concat(t.allocator, u8, &.{ prefix, "let mut owner=7;borrow owner as loan{owner=9;discard read_ref(loan);}return owner;}", main });
        defer t.allocator.free(bad);
        const fixed = try std.mem.replaceOwned(u8, t.allocator, bad, "owner=9;discard read_ref(loan);}", "discard read_ref(loan);}owner=9;");
        defer t.allocator.free(fixed);
        try checkRepair(
            bad,
            fixed,
            "E_BORROW_CONFLICT",
            .{ at(bad, "owner=9", 0), at(bad, "as loan", 3), at(bad, "mut owner", 4) },
            9,
        );
    }
}
test "suspended parent diagnostics retain the child loan and original value location" {
    for ([_]bool{ false, true }) |generic| {
        const prefix = if (generic) "fn work<T:copy>()->i64{" else "fn work()->i64{";
        const main = if (generic) "fn main()->i64{return work::<bool>();}" else "fn main()->i64{return work();}";
        const bad = try std.mem.concat(t.allocator, u8, &.{ prefix, "let mut owner=7;borrow mut owner as parent{borrow parent as child{return read_ref(parent);}}}", main });
        defer t.allocator.free(bad);
        const fixed = try std.mem.replaceOwned(u8, t.allocator, bad, "read_ref(parent)", "read_ref(child)");
        defer t.allocator.free(fixed);
        try checkRepair(
            bad,
            fixed,
            "E_BORROW_SUSPENDED",
            .{ at(bad, "read_ref(parent)", 9), at(bad, "as child", 3), at(bad, "mut owner", 4) },
            7,
        );
    }
}
test "transfer witnesses follow continuing branches and reset after replacement" {
    const schema = "result R{ok:i64,err:i64}";
    for ([_]bool{ false, true }) |generic| {
        const prefix = if (generic) "fn work<T:copy>(flag:bool)->i64{" else "fn work(flag:bool)->i64{";
        const body = "let mut value=new R.ok(1);if flag{acknowledge value;return 1;}else{acknowledge value;}value=new R.ok(2);let current=value;acknowledge value;acknowledge current;return 2;}fn main()->i64{return 0;}";
        const bad = try std.mem.concat(t.allocator, u8, &.{ schema, prefix, body });
        defer t.allocator.free(bad);
        var c = try language.Compilation.init(t.allocator, "branch-move.my", bad);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
        const problem = c.diagnostics.items[0];
        try t.expectEqualStrings("E_RESULT_CONSUMED", problem.code);
        try t.expectEqual(at(bad, "current=value", 8), problem.related.?.span.start);
        try t.expectEqual(at(bad, "mut value", 4), problem.provenance.origin.?.span.start);
    }
}
fn renderScenario(allocator: std.mem.Allocator) !void {
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    defer sink.deinit();
    const failure = sink.failTransfer("E_OWNED_CONSUMED", .{ .start = 4, .end = 5 }, .{ .start = 0, .end = 1 }, .{ .start = 2, .end = 3 });
    if (failure != error.SourceError) return failure;
    const text = try sink.items.items[0].render(allocator, .{ .path = "locations.my", .bytes = "x\nx\nx", .line_starts = &.{ 0, 2, 4 } });
    defer allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "locations.my:3:1: error[E_OWNED_CONSUMED]") != null);
    try t.expect(std.mem.indexOf(u8, text, "note: locations.my:2:1: earlier transfer") != null);
    try t.expect(std.mem.indexOf(u8, text, "note: locations.my:1:1: value declared here") != null);
}
test "provenance collection and rendering preserve allocation failures" {
    try renderScenario(t.allocator);
    try t.checkAllAllocationFailures(t.allocator, renderScenario, .{});
}

test "owned buffer queries report the transfer site and repair to the surviving owner" {
    const schema = @import("fixture_declarations_test.zig").generic_buffer_results;
    for ([_]bool{ false, true }) |generic| {
        const prefix = if (generic) "fn work<T:copy>(heap:allocator)->R{" else "fn work(heap:allocator)->R{";
        const main = if (generic)
            "fn main(heap:allocator)->i64{match work::<bool>(heap){R.ok(n)=>{return n;},R.err(e)=>{return e;}}}"
        else
            "fn main(heap:allocator)->i64{match work(heap){R.ok(n)=>{return n;},R.err(e)=>{return e;}}}";
        const bad = try std.mem.concat(t.allocator, u8, &.{ schema, prefix, "let original=try acquire_buffer<A>(heap,2);let moved=original;return new R.ok(cast<i64>(capacity_buffer(original)));}", main });
        defer t.allocator.free(bad);
        const fixed = try std.mem.replaceOwned(u8, t.allocator, bad, "capacity_buffer(original)", "capacity_buffer(moved)");
        defer t.allocator.free(fixed);
        try checkRepair(
            bad,
            fixed,
            "E_OWNED_CONSUMED",
            .{ at(bad, "capacity_buffer(original)", 16), at(bad, "moved=original", 6), at(bad, "let original", 4) },
            2,
        );
    }
}

const pair_schema = "result R{ok:i64,err:i64}struct Pair{first:R,second:R,code:i64}";
const pair_binding = "let pair=new Pair{first:new R.ok(1),second:new R.ok(2),code:7};";
// spec: DIAGNOSTIC-PARTIAL-MOVE-1
test "missing field and partial record diagnostics point to extraction and execute valid repairs" {
    for ([_]bool{ false, true }) |generic| {
        const prefix = if (generic) "fn work<T:copy>()->i64{" else "fn work()->i64{";
        const main = if (generic) "fn main()->i64{return work::<bool>();}" else "fn main()->i64{return work();}";
        const before = try std.mem.concat(t.allocator, u8, &.{ pair_schema, prefix, pair_binding, "acknowledge take_field(pair,first);" });
        defer t.allocator.free(before);
        const after = "acknowledge take_field(pair,second);return read_field(pair,code);}";
        const fixed = try std.mem.concat(t.allocator, u8, &.{ before, after, main });
        defer t.allocator.free(fixed);
        for ([_]bool{ false, true }) |whole| {
            const bad = try std.mem.concat(t.allocator, u8, &.{ before, if (whole) "acknowledge pair;" else "acknowledge take_field(pair,first);", after, main });
            defer t.allocator.free(bad);
            try checkRepair(
                bad,
                fixed,
                if (whole) "E_PARTIAL_MOVE" else "E_FIELD_MOVED",
                .{ before.len + (if (whole) @as(usize, 12) else 28), at(bad, "take_field(pair,first)", 16), at(bad, "let pair", 4) },
                7,
            );
        }
    }
}
test "partial field witnesses restore the continuing branch instead of the returned branch" {
    for ([_]bool{ false, true }) |generic| {
        const prefix = if (generic) "fn work<T:copy>(flag:bool)->i64{" else "fn work(flag:bool)->i64{";
        const main = if (generic) "fn main()->i64{return work::<bool>(false);}" else "fn main()->i64{return work(false);}";
        const branches = "if flag{acknowledge take_field(pair,first);acknowledge take_field(pair,second);return 5;}else{acknowledge take_field(pair,second);}";
        const before = try std.mem.concat(t.allocator, u8, &.{ pair_schema, prefix, pair_binding, branches });
        defer t.allocator.free(before);
        const bad = try std.mem.concat(t.allocator, u8, &.{ before, "acknowledge take_field(pair,second);return read_field(pair,code);}", main });
        defer t.allocator.free(bad);
        const fixed = try std.mem.concat(t.allocator, u8, &.{ before, "acknowledge take_field(pair,first);return read_field(pair,code);}", main });
        defer t.allocator.free(fixed);
        try checkRepair(
            bad,
            fixed,
            "E_FIELD_MOVED",
            .{ before.len + 28, std.mem.lastIndexOf(u8, before, "take_field(pair,second)").? + 16, at(bad, "let pair", 4) },
            7,
        );
    }
}
fn fieldFailureScenario(allocator: std.mem.Allocator) !void {
    const text = pair_schema ++ "fn work<T:copy>()->i64{" ++ pair_binding ++
        "acknowledge take_field(pair,first);acknowledge take_field(pair,first);return 0;}fn main()->i64{return 0;}";
    var c = try language.Compilation.init(allocator, "field-failure.my", text);
    defer c.deinit();
    c.check() catch |err| {
        if (err != error.SourceError) return err;
        const problem = c.diagnostics.items[0];
        try t.expectEqualStrings("E_FIELD_MOVED", problem.code);
        try t.expectEqual(at(text, "take_field(pair,first)", 16), problem.related.?.span.start);
        return;
    };
    try t.expect(false);
}
test "partial move checking preserves allocation failures through rejection and provenance" {
    try fieldFailureScenario(t.allocator);
    // In-place arena growth otherwise makes the number of counted allocations address-dependent.
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), fieldFailureScenario, .{});
}

test "replacement clears partial move witnesses before taking the replenished record" {
    for ([_]bool{ false, true }) |generic| {
        const prefix = if (generic) "fn work<T:copy>()->i64{" else "fn work()->i64{";
        const main = if (generic) "fn main()->i64{return work::<bool>();}" else "fn main()->i64{return work();}";
        const setup = "let mut pair=new Pair{first:new R.ok(1),second:new R.ok(2),code:3};" ++
            "acknowledge take_field(pair,first);acknowledge take_field(pair,second);" ++
            "pair=new Pair{first:new R.ok(4),second:new R.ok(5),code:7};acknowledge take_field(pair,first);";
        const before = try std.mem.concat(t.allocator, u8, &.{ pair_schema, prefix, setup });
        defer t.allocator.free(before);
        const after = "acknowledge take_field(pair,second);return read_field(pair,code);}";
        const bad = try std.mem.concat(t.allocator, u8, &.{ before, "acknowledge pair;", after, main });
        defer t.allocator.free(bad);
        const fixed = try std.mem.concat(t.allocator, u8, &.{ before, after, main });
        defer t.allocator.free(fixed);
        try checkRepair(
            bad,
            fixed,
            "E_PARTIAL_MOVE",
            .{ before.len + 12, std.mem.lastIndexOf(u8, before, "take_field(pair,first)").? + 16, at(bad, "mut pair", 4) },
            7,
        );
    }
}
