const fixture_path = "effects.my";
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const sets = @import("effect_set.zig");
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
    try t.expectEqual(expected, (try native.run(&c)).value);
}

const allocate_body = "def allocate() -> int:\n    items: list[int] = []\n    return len(items)\n\n";
// spec: OWN-11
test "direct and transitive allocation violate explicit bounds with witness paths" {
    try reject("def main() -> int noalloc:\n    items: list[int] = []\n    return len(items)\n", "E_EFFECT_BOUND", "main");
    try reject(allocate_body ++ "def helper() -> int:\n    return allocate()\n\n" ++
        "def main() -> int noalloc:\n    return helper()\n", "E_EFFECT_BOUND", "main -> helper -> allocate");
    try reject("def unused() -> int effects():\n    items: list[int] = []\n    return len(items)\n\n" ++
        "def main() -> int:\n    return 0\n", "E_EFFECT_BOUND", "unused");
}

const recursive_a = "def a(n: int) -> int:\n    if n == 0:\n        items: list[int] = []\n        return len(items)\n    return b(n - 1)\n\n";
const recursive_b = "def b(n: int) -> int:\n    return a(n)\n\n";
const recursive_main = "def main() -> int noalloc:\n    return b(0)\n";
test "recursive effect summaries reach fixed points independent of declaration order" {
    try reject(recursive_a ++ recursive_b ++ recursive_main, "E_EFFECT_BOUND", "main -> b -> a");
    try reject(recursive_b ++ recursive_a ++ recursive_main, "E_EFFECT_BOUND", "main -> b -> a");
    try result("def a(n: int) -> int noalloc:\n    if n == 0:\n        return 7\n    return b(n - 1)\n\n" ++
        "def b(n: int) -> int effects():\n    return a(n)\n\n" ++
        "def main() -> int noalloc:\n    return b(3)\n", 7);
}

test "effect scanning includes untaken branches and short circuit operands" {
    try reject("def main() -> int noalloc:\n    if False:\n        items: list[int] = []\n        return len(items)\n    return 0\n", "E_EFFECT_BOUND", "main");
    try reject("def allocate() -> bool:\n    items: list[int] = []\n    return len(items) == 0\n\n" ++
        "def main() -> int noalloc:\n    _ = False and allocate()\n    return 0\n", "E_EFFECT_BOUND", "main -> allocate");
}

test "effect bounds reject unknown and duplicate names and noio permits allocation" {
    try reject("def main() -> i64 effects(magic):\n    return 0\n", "E_UNKNOWN_EFFECT", "unknown effect");
    try reject("def main() -> i64 effects(clock, clock):\n    return 0\n", "E_DUPLICATE_EFFECT", "more than once");
    try result("def main() -> int noio:\n    items: list[int] = []\n    items.append(9)\n    return items[0]\n", 9);
    try result(
        \\def main() -> i64 effects(filesystem, network, clock, random, environment):
        \\    x = 1
        \\    x += 2
        \\    return x
    , 3);
    try result(
        \\def noalloc() -> i64:
        \\    effects = 2
        \\    noio = 3
        \\    return effects + noio
        \\
        \\
        \\def main() -> i64:
        \\    return noalloc()
    , 5);
}

const accepted = "def edit(n: int) -> int noalloc:\n    return n + 11\n\n" ++
    "def release(n: int) -> int effects():\n    _ = n\n    return 3\n\n" ++
    "def main() -> int effects(managed_allocation):\n    items: list[int] = []\n" ++
    "    items.append(edit(0))\n    return items[0] + release(items[0])\n";
test "noalloc permits scalar edits while the managed caller declares its allocation" {
    try result(accepted, 14);
    var c = try language.Compilation.init(t.allocator, fixture_path, accepted);
    defer c.deinit();
    try c.emit();
    try t.expectEqual(@as(sets.Mask, 0), c.program.?.functions[0].policy.effects);
    try t.expectEqual(sets.bit(.managed_allocation), c.program.?.functions[2].policy.effects);
    const dump = try c.dump(t.allocator);
    defer t.allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "effects {managed_allocation} allowed {managed_allocation}") != null);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, fixture_path, accepted);
    defer c.deinit();
    try c.emit();
    try t.expectEqual(sets.bit(.managed_allocation), c.program.?.functions[2].policy.effects);
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    var found = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer found.deinit();
}
fn rejectionScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, fixture_path, allocate_body ++
        "def main() -> int noalloc:\n    return allocate()\n");
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

test "duplicate discovery retains normalized declared effect contracts" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def a(n: i64) -> i64 effects(clock, random):
        \\    return n + 1
        \\
        \\
        \\def b(x: i64) -> i64 effects(random, clock):
        \\    return x + 1
        \\
        \\
        \\def different(n: i64) -> i64 noalloc:
        \\    return n + 1
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer c.deinit();
    try c.check();
    var found = try language.duplicates.discover(t.allocator, c.program.?, .{ .min_nodes = 1 });
    defer found.deinit();
    try t.expectEqual(@as(usize, 1), found.groups.len);
    try t.expectEqual(@as(usize, 2), found.groups[0].members.len);
}

test "effect rendering propagates a full writer failure" {
    var storage: [0]u8 = .{};
    var writer: std.Io.Writer = .fixed(&storage);
    try t.expectError(error.WriteFailed, sets.write(&writer, sets.bit(.managed_allocation)));
}

// spec-case: EFFECT-CEILING-1
test "declared ceilings reject hidden effects through generic and callback calls" {
    // A generic body that hides an allocating call behind an empty ceiling rejects
    // once it is instantiated, exactly like an ordinary direct call.
    try reject(
        \\def allocate() -> i64:
        \\    items: list[i64] = []
        \\    return len(items)
        \\
        \\
        \\def wrapper[T](x: T) -> i64 effects():
        \\    _ = x
        \\    return allocate()
        \\
        \\
        \\def main() -> i64 noalloc:
        \\    return wrapper[i64](1)
    , "E_EFFECT_BOUND", "exceeds declared bound");

    // Invoking a callback uses the destination contract's ceiling, so a caller
    // that promises less than the callback's declared effects rejects.
    try reject(
        \\def tick(x: i64) -> i64 effects(clock):
        \\    _ = x
        \\    return 0
        \\
        \\
        \\def call(f: def(i64) -> i64 effects(clock)) -> i64 effects():
        \\    return f(1)
        \\
        \\
        \\def main() -> i64:
        \\    return call(tick)
    , "E_EFFECT_BOUND", "exceeds declared bound");
}
