//! RC-EXIT-SKIP-1: only the function that returns last asks the runtime whether
//! to keep its owners, and only an RC program has anything to ask about.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const ask = "call $myl_qbe_exit_skip";
const plain =
    \\def build(n: int) -> list[str]:
    \\    items: list[str] = []
    \\    for i in range(n):
    \\        items.append("x" + str(i))
    \\    return items
    \\def main(out: Stream) -> int:
    \\    xs = build(5)
    \\    out.print(len(xs))
    \\    return 0
;
const wrapped =
    \\def build(n: int) -> list[str]:
    \\    items: list[str] = []
    \\    for i in range(n):
    \\        items.append("x" + str(i))
    \\    return items
    \\def main(out: Stream):
    \\    xs = build(5)
    \\    out.print(len(xs))
;
const recursive =
    \\def main(out: Stream) -> int:
    \\    xs = ["a", "b"]
    \\    if len(xs) > 5:
    \\        return main(out)
    \\    out.print(len(xs))
    \\    return 0
;
const called =
    \\def again(out: Stream) -> int:
    \\    return main(out)
    \\def main(out: Stream) -> int:
    \\    xs = ["a", "b"]
    \\    out.print(len(xs))
    \\    return 0
;
fn emit(selection: runtime.Selection, source: []const u8) !std.json.Parsed(Manifest) {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(selection);
    var compilation = try compiler.Compilation.init(t.allocator, "exit_skip.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
fn asked(manifest: Manifest, name: []const u8) !bool {
    return std.mem.indexOf(u8, try named(manifest, name), ask) != null;
}
fn at(text: []const u8, needle: []const u8) !usize {
    return std.mem.indexOf(u8, text, needle) orelse error.TestUnexpectedResult;
}

// spec-case: RC-EXIT-SKIP-1
test "RC-EXIT-SKIP-1 the entry asks after its scopes close and before its drops, and no callee asks" {
    var manifest = try emit(.rc, plain);
    defer manifest.deinit();
    const il = try named(manifest.value, "main");
    const exit = try at(il, "# rc-exit");
    const question = try at(il, ask);
    // The labels are defined at the start of a line; the branch only names them.
    const drops = try at(il, "\n@rcexitdrop");
    const done = try at(il, "\n@rcexitdone");
    try t.expect(exit < question);
    try t.expect(question < drops);
    try t.expect(drops < done);
    try t.expect(std.mem.indexOf(u8, il[done..], " ret ") != null);
    try t.expect(!try asked(manifest.value, "build"));
}

// spec-case: RC-EXIT-SKIP-1
test "RC-EXIT-SKIP-1 the function behind the synthesized entry wrapper is the one that asks" {
    var manifest = try emit(.rc, wrapped);
    defer manifest.deinit();
    try t.expect(try asked(manifest.value, "main"));
    try t.expect(!try asked(manifest.value, "build"));
}

// spec-case: RC-EXIT-SKIP-1
test "RC-EXIT-SKIP-1 a main that is called or calls itself keeps every drop" {
    var recurring = try emit(.rc, recursive);
    defer recurring.deinit();
    try t.expect(!try asked(recurring.value, "main"));
    var reached = try emit(.rc, called);
    defer reached.deinit();
    try t.expect(!try asked(reached.value, "main"));
}

// spec-case: RC-EXIT-SKIP-1
test "RC-EXIT-SKIP-1 the tracing collector's lowering never asks" {
    var manifest = try emit(.gc, plain);
    defer manifest.deinit();
    try t.expect(!try asked(manifest.value, "main"));
    try t.expect(!try asked(manifest.value, "build"));
}
