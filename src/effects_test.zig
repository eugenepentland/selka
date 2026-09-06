const fixture_path = "effects.my";
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const sets = @import("effect_set.zig");
const declarations = @import("fixture_declarations_test.zig").allocator_results;
fn reject(source: []const u8, code: []const u8, text: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, text) != null);
    if (std.mem.eql(u8, code, "E_EFFECT_BOUND")) try t.expect(c.diagnostics.items[0].related != null);
}
fn result(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectEqual(expected, (try c.execute(t.allocator)).value);
}

// spec: OWN-11
test "direct and transitive allocation violate explicit bounds with witness paths" {
    try reject(declarations ++ "fn main(alloc: allocator) -> i64 noalloc { acknowledge acquire_buffer<R>(alloc, 1); return 0; }", "E_EFFECT_BOUND", "allocation");
    try reject(declarations ++ "fn allocate(alloc: allocator) -> R { return acquire_buffer<R>(alloc, 1); } fn " ++
        "helper(alloc: allocator) -> R { return allocate(alloc); } fn main(alloc: allocator) " ++
        "-> i64 noalloc { acknowledge helper(alloc); return 0; }", "E_EFFECT_BOUND", "main -> helper -> allocate");
    try reject(declarations ++ "fn unused(alloc: allocator) -> R effects() { return acquire_buffer<R>(alloc, 1); } fn main() -> i64 { return 0; }", "E_EFFECT_BOUND", "unused");
    try reject(declarations ++ "fn grow(alloc: allocator, input: B) -> R noalloc { let mut b = input; acknowledge reserve_buffer<Status>(b, alloc, 0); return new R.ok(b); } fn main() -> i64 { return 0; }", "E_EFFECT_BOUND", "grow");
}

test "recursive effect summaries reach fixed points independent of declaration order" {
    const a = "fn a(alloc: allocator, n: i64) -> R { if n == 0 { return acquire_buffer<R>(alloc, 1); } return b(alloc, n - 1); } ";
    const b = "fn b(alloc: allocator, n: i64) -> R { return a(alloc, n); } ";
    try reject(declarations ++ a ++ b ++ "fn main(alloc: allocator) -> i64 noalloc { acknowledge b(alloc, 0); return 0; }", "E_EFFECT_BOUND", "main -> b -> a");
    try reject(declarations ++ b ++ a ++ "fn main(alloc: allocator) -> i64 noalloc { acknowledge b(alloc, 0); return 0; }", "E_EFFECT_BOUND", "main -> b -> a");
    try result("fn a(alloc: allocator, n: i64) -> i64 noalloc { if n == 0 { return 7; } return " ++
        "b(alloc, n - 1); } fn b(alloc: allocator, n: i64) -> i64 effects() { return a(alloc, " ++
        "n); } fn main(alloc: allocator) -> i64 noalloc { return b(alloc, 3); }", 7);
}

const accepted = declarations ++ "fn edit(input: B) -> R noalloc { let mut b = input; discard try " ++
    "append_buffer<Status>(b, 7); discard try resize_buffer<Status>(b, 2, 9); borrow mut " ++
    "b[0..2] as s { write_slice(s, 1, 11); } return new R.ok(b); } fn release(input: B) " ++
    "-> i64 effects() { discard input; return 3; } fn main(alloc: allocator) -> i64 " ++
    "effects(allocation) { match acquire_buffer<R>(alloc, 2) { R.ok(b) => { match edit(b) " ++
    "{ R.ok(updated) => { let n = read_buffer(updated, 1); return n + release(updated); }," ++
    " R.err(e) => { return e; } } }, R.err(e) => { return e; } } }";
test "noalloc permits reserved edits borrowed writes owned transfer and buffer cleanup" {
    try result(accepted, 14);
    var c = try language.Compilation.init(t.allocator, fixture_path, accepted);
    defer c.deinit();
    try c.emit();
    try t.expectEqual(@as(sets.Mask, 0), c.program.?.functions[0].policy.effects);
    try t.expectEqual(sets.bit(.allocation), c.program.?.functions[2].policy.effects);
    const dump = try c.dump(t.allocator);
    defer t.allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "effects {allocation} allowed {allocation}") != null);
}

test "effect scanning includes untaken branches short circuit operands constructors and reference calls" {
    try reject(declarations ++ "fn main(alloc: allocator) -> i64 noalloc { if false { acknowledge acquire_buffer<R>(alloc, 1); } return 0; }", "E_EFFECT_BOUND", "main");
    try reject(declarations ++ "fn allocate(alloc: allocator) -> bool { acknowledge acquire_buffer<R>(alloc, 1); " ++
        "return true; } fn main(alloc: allocator) -> i64 noalloc { discard false && " ++
        "allocate(alloc); return 0; }", "E_EFFECT_BOUND", "main -> allocate");
    try reject(declarations ++ "struct Box { result: R } fn main(alloc: allocator) -> i64 noalloc { acknowledge new Box { result: acquire_buffer<R>(alloc, 1) }; return 0; }", "E_EFFECT_BOUND", "main");
    try reject(declarations ++ "fn helper(alloc: allocator, s: &[]i64) -> u64 { acknowledge acquire_buffer<R>(alloc, " ++
        "1); return len_slice(s); } fn main(alloc: allocator) -> i64 noalloc { let a = new " ++
        "[1]i64[7]; borrow a[0..1] as s { return cast<i64>(helper(alloc, s)); } }", "E_EFFECT_BOUND", "main -> helper");
    try reject(declarations ++ "fn helper(alloc: allocator, s: &[]i64) -> &[]i64 from s { acknowledge " ++
        "acquire_buffer<R>(alloc, 1); return s; } fn main(alloc: allocator) -> i64 noalloc { " ++
        "let a = new [1]i64[7]; borrow a[0..1] as s { borrow helper(alloc, s) as output { " ++
        "return read_slice(output, 0); } } }", "E_EFFECT_BOUND", "main -> helper");
}

test "effect bounds reject unknown and duplicate names and noio permits allocation" {
    try reject("fn main(alloc: allocator) -> i64 effects(magic) { return 0; }", "E_UNKNOWN_EFFECT", "unknown effect");
    try reject("fn main(alloc: allocator) -> i64 effects(clock, clock) { return 0; }", "E_DUPLICATE_EFFECT", "more than once");
    try result(declarations ++ "fn main(alloc: allocator) -> i64 noio { acknowledge acquire_buffer<R>(alloc, 1); return 9; }", 9);
    try result("fn main(alloc: allocator) -> i64 effects(filesystem, network, clock, random, environment) { let mut x = 1; x += 2; return x; }", 3);
    try result("fn noalloc() -> i64 { let effects = 2; let noio = 3; return effects + noio; } fn main(alloc: allocator) -> i64 { return noalloc(); }", 5);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, fixture_path, accepted);
    defer c.deinit();
    try t.expectEqual(@as(i64, 14), (try c.execute(allocator)).value);
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    var found = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer found.deinit();
}
fn rejectionScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, fixture_path, declarations ++ "fn helper(alloc: allocator) -> R { return acquire_buffer<R>(alloc, 1); } fn " ++
        "main(alloc: allocator) -> i64 noalloc { acknowledge helper(alloc); return 0; }");
    defer c.deinit();
    c.check() catch |err| switch (err) {
        error.SourceError => {
            const rendered = try c.diagnostics.items[0].render(allocator, c.src);
            defer allocator.free(rendered);
            return;
        },
        else => return err,
    };
    return error.TestUnexpectedResult;
}
test "effect graph inference witnesses emission and rendering release every failed allocation" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
    try t.checkAllAllocationFailures(no_resize.allocator(), rejectionScenario, .{});
}

test "bytecode independently rejects forged summaries and violated bounds" {
    var c = try language.Compilation.init(t.allocator, fixture_path, declarations ++ "fn helper(alloc: allocator) -> R { return acquire_buffer<R>(alloc, 1); } fn main(alloc: allocator) -> i64 { acknowledge helper(alloc); return 0; }");
    defer c.deinit();
    try c.emit();
    const functions = @constCast(c.code.?.functions);
    const original = functions[1];
    functions[1].policy.effects = 0;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    functions[1] = original;
    functions[1].policy.effect_bound = .{ .allowed = 0, .span = .{ .start = 0, .end = 0 } };
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    functions[1] = original;
    try language.bytecode.validate(t.allocator, c.code.?);
}

test "duplicate discovery retains normalized declared effect contracts" {
    var c = try language.Compilation.init(t.allocator, fixture_path, "fn a(n: i64) -> i64 effects(clock, random) { return n + 1; } fn b(x: i64) -> i64 " ++
        "effects(random, clock) { return x + 1; } fn different(n: i64) -> i64 noalloc { " ++
        "return n + 1; } fn main() -> i64 { return 0; }");
    defer c.deinit();
    try c.check();
    var found = try language.duplicates.discover(t.allocator, c.program.?, .{ .min_nodes = 1 });
    defer found.deinit();
    try t.expectEqual(@as(usize, 1), found.groups.len);
    try t.expectEqual(@as(usize, 2), found.groups[0].members.len);
}

test "long recursive call graphs infer allocation without recursive host traversal" {
    var source: std.Io.Writer.Allocating = .init(t.allocator);
    defer source.deinit();
    try source.writer.writeAll(declarations);
    for (0..512) |index| {
        try source.writer.print("fn f{d}(alloc: allocator) -> R {{ ", .{index});
        if (index == 511) try source.writer.writeAll("acknowledge acquire_buffer<R>(alloc, 1); ");
        try source.writer.print("return f{d}(alloc); }} ", .{(index + 1) % 512});
    }
    try source.writer.writeAll("fn main(alloc: allocator) -> i64 noalloc { acknowledge f0(alloc); return 0; }");
    try reject(source.written(), "E_EFFECT_BOUND", "f510 -> f511");
}

test "effect rendering propagates a full writer failure" {
    var storage: [0]u8 = .{};
    var writer: std.Io.Writer = .fixed(&storage);
    try t.expectError(error.WriteFailed, sets.write(&writer, sets.bit(.allocation)));
}
