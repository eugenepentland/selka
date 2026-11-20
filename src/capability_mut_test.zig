//! `W_CAPABILITY_MUT`: a `mut` capability parameter that the body never assigns and never passes on as `mut` warns, with
//! the certain edit that deletes the `mut`. The parameters that must keep it are the evidence: one the body assigns, one
//! passed on to a callee that writes it, one of a function used as a value, and the non-capability `mut` parameters.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const capability_mut = @import("capability_mut.zig");

/// The edits of the `W_CAPABILITY_MUT` warnings a program reports, as the text each one deletes, in report order.
/// The fixture's arena owns the strings.
fn deleted(arena: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    const report = try fixture.check(arena, text);
    try report.expectAccepted();
    var found: std.ArrayList([]const u8) = .empty;
    for (report.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, capability_mut.code)) continue;
        try t.expect(item.severity == .warning);
        const fix = item.provenance.fix orelse return error.TestUnexpectedResult;
        try t.expect(fix.count() == 1);
        try t.expectEqualStrings("", fix.edit.text);
        try found.append(arena, report.text(fix.edit.span));
    }
    return found.items;
}

/// A program whose only function with a `mut` capability parameter reads it.
const unwritten =
    \\import filesystem
    \\
    \\
    \\func probe(mut fs: Filesystem, path: str) -> bool:
    \\    return fs.exists(path)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut fs = filesystem.memory()
    \\    print(out, probe(mut fs, "a"))
    \\    return 0
;

test "a mut capability parameter the body only reads warns, and the edit deletes mut and its blanks" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try deleted(arena.allocator(), unwritten);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("mut ", found[0]);
}

test "every capability type warns, a Stream included" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try deleted(arena.allocator(),
        \\import filesystem
        \\import random
        \\
        \\
        \\func say(mut out: Stream):
        \\    print(out, "x")
        \\
        \\
        \\func has(mut fs: Filesystem) -> bool:
        \\    return fs.exists("a")
        \\
        \\
        \\func pick(mut entropy: Entropy) -> int:
        \\    match random.from_entropy(entropy):
        \\        case Ok(_):
        \\            return 1
        \\        case Err(_):
        \\            return 0
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut sink = out
        \\    mut fs = filesystem.memory()
        \\    mut entropy = random.seeded_entropy(1)
        \\    say(mut sink)
        \\    print(sink, has(mut fs), pick(mut entropy))
        \\    return 0
    );
    try t.expectEqual(@as(usize, 3), found.len);
}

test "a capability parameter the body assigns keeps mut" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try deleted(arena.allocator(),
        \\import filesystem
        \\
        \\
        \\func swap(mut fs: Filesystem) -> bool:
        \\    fs = filesystem.memory()
        \\    return fs.exists("a")
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut fs = filesystem.memory()
        \\    print(out, swap(mut fs))
        \\    return 0
    );
    try t.expectEqual(@as(usize, 0), found.len);
}

test "a capability parameter passed on as mut to a callee that writes it keeps mut, and the callee is the only one that does" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try deleted(arena.allocator(),
        \\import filesystem
        \\
        \\
        \\func swap(mut fs: Filesystem) -> bool:
        \\    fs = filesystem.memory()
        \\    return fs.exists("a")
        \\
        \\
        \\func relay(mut fs: Filesystem) -> bool:
        \\    return swap(mut fs)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut fs = filesystem.memory()
        \\    print(out, relay(mut fs))
        \\    return 0
    );
    try t.expectEqual(@as(usize, 0), found.len);
}

test "a parameter passed on as mut to a callee that does not write it waits for the callee's own repair" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try deleted(arena.allocator(),
        \\import filesystem
        \\
        \\
        \\func leaf(mut fs: Filesystem) -> bool:
        \\    return fs.exists("a")
        \\
        \\
        \\func relay(mut fs: Filesystem) -> bool:
        \\    return leaf(mut fs)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut fs = filesystem.memory()
        \\    print(out, relay(mut fs))
        \\    return 0
    );
    try t.expectEqual(@as(usize, 1), found.len);
}

test "a function used as a value keeps mut, because its function type spells it" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try deleted(arena.allocator(),
        \\import filesystem
        \\
        \\
        \\record Hook:
        \\    run: func(mut fs: Filesystem) -> bool
        \\
        \\
        \\func probe(mut fs: Filesystem) -> bool:
        \\    return fs.exists("a")
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut fs = filesystem.memory()
        \\    const hook = Hook(run=probe)
        \\    const run = hook.run
        \\    print(out, run(mut fs))
        \\    return 0
    );
    try t.expectEqual(@as(usize, 0), found.len);
}

test "a mut parameter of another type is not this warning's business" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try deleted(arena.allocator(),
        \\func bump(mut count: int) -> int:
        \\    return count + 1
        \\
        \\
        \\func fill(mut xs: int[]):
        \\    append(mut xs, 1)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut count = 1
        \\    mut xs: int[] = []
        \\    fill(mut xs)
        \\    print(out, bump(mut count), len(xs))
        \\    return 0
    );
    try t.expectEqual(@as(usize, 0), found.len);
}
