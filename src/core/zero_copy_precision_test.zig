//! Zero-copy part 1, checker precision (lane O3, item 3): the refused neighbours of the shapes the checker now accepts. Each
//! accepted shape is a test of `tests/lang/zero_copy_precision.selka`, which a Debug compiler builds (validating every ownership
//! certificate) and runs with the leak check. Each program here is one step past it, where the same rule still refuses.
const std = @import("std");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");

/// Check `source` and require the single-owner checker to refuse it with `code` and a message containing `words`.
fn refuses(backing: std.mem.Allocator, source: []const u8, code: []const u8, words: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const program = try support.checkedProgram(a, source);
    try std.testing.expectError(error.Rejected, unique.check(a, program, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, words) != null);
}

/// Check `source` and require the single-owner checker to accept it.
fn accepts(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const program = try support.checkedProgram(a, source);
    try unique.check(a, program, &failure);
    try std.testing.expectEqualStrings("", failure.code);
}

test "zero-copy 3a: a narrowed option is read as a borrow of its payload, and a write to the option while it is live is refused" {
    try accepts(std.testing.allocator,
        \\func lookup(n: int) -> bytes?:
        \\    if n > 0:
        \\        return Some(b"x")
        \\    return None
        \\
        \\func f(n: int) -> int:
        \\    const found = lookup(n)
        \\    if found is None:
        \\        return 0
        \\    const id = found.unwrap_or(b"")
        \\    return len(id)
        \\
        \\func main() -> int:
        \\    return f(1)
        \\
    );
    try refuses(std.testing.allocator,
        \\func lookup(n: int) -> bytes?:
        \\    if n > 0:
        \\        return Some(b"x")
        \\    return None
        \\
        \\func f(n: int) -> int:
        \\    mut found = lookup(n)
        \\    if found is None:
        \\        return 0
        \\    const id = found.unwrap_or(b"")
        \\    found = None
        \\    return len(id)
        \\
        \\func main() -> int:
        \\    return f(1)
        \\
    , "E_SINGLE_OWNER_OVERLAP", "'found' cannot be changed or moved while 'id' borrows it");
}

test "zero-copy 3b: a loop variable names an element of the iterated field, so only a mut argument naming that field overlaps it" {
    const shape =
        \\record Pin:
        \\    net: bytes
        \\
        \\record Ledger:
        \\    names: bytes[] = []
        \\    pins: Pin[] = []
        \\
        \\func remember(mut names: bytes[], net: bytes):
        \\    append(mut names, copy(net))
        \\
        \\func touch(mut pins: Pin[], net: bytes):
        \\    append(mut pins, Pin(net=copy(net)))
        \\
        \\func collect(mut ledger: Ledger) -> int:
        \\    for pn in ledger.pins:
        \\        CALL
        \\    return len(ledger.names)
        \\
        \\func main() -> int:
        \\    mut ledger = Ledger(pins=[Pin(net=b"GND")])
        \\    return collect(mut ledger)
        \\
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try accepts(std.testing.allocator, try std.mem.replaceOwned(u8, a, shape, "CALL", "remember(mut ledger.names, pn.net)"));
    try refuses(std.testing.allocator, try std.mem.replaceOwned(u8, a, shape, "CALL", "touch(mut ledger.pins, pn.net)"), "E_SINGLE_OWNER_OVERLAP", "a value cannot be moved or mutated while another argument or iteration borrows it");
}

test "zero-copy 3b: a match arm whose payload owns storage still holds the matched element while it reads the payload" {
    try accepts(std.testing.allocator,
        \\func clear(mut attach: int?[], i: int):
        \\    match attach[i]:
        \\        case None:
        \\            return
        \\        case Some(sec):
        \\            if sec > 0:
        \\                attach[i] = None
        \\
        \\func main() -> int:
        \\    mut a: int?[] = [Some(1)]
        \\    clear(mut a, 0)
        \\    return 0
        \\
    );
    try refuses(std.testing.allocator,
        \\func clear(mut names: bytes?[], i: int) -> int:
        \\    match names[i]:
        \\        case None:
        \\            return 0
        \\        case Some(name):
        \\            names[i] = None
        \\            return len(name)
        \\
        \\func main() -> int:
        \\    mut a: bytes?[] = [Some(b"x")]
        \\    return clear(mut a, 0)
        \\
    , "E_SINGLE_OWNER_OVERLAP", "match");
}

test "zero-copy 3c: a slice of a view binding is a view, and storing it in a record is still a view escape" {
    try accepts(std.testing.allocator,
        \\func degree_len(unit: bytes) -> int:
        \\    const tail = unit[3:]
        \\    const degree = tail[1:]
        \\    return len(degree)
        \\
        \\func main() -> int:
        \\    return degree_len(b"ppm/C")
        \\
    );
    try refuses(std.testing.allocator,
        \\record Holder:
        \\    text: bytes
        \\
        \\func hold(unit: bytes) -> Holder:
        \\    const tail = unit[3:]
        \\    const degree = tail[1:]
        \\    return Holder(text=degree)
        \\
        \\func main() -> int:
        \\    return len(hold(b"ppm/C").text)
        \\
    , "E_SLICE_ESCAPES", "copy");
}

test "zero-copy 3d: a mut local that borrows may take a literal or a from call, but not a fresh value" {
    try accepts(std.testing.allocator,
        \\record Sig:
        \\    direction: bytes
        \\
        \\func flip(direction: bytes) -> bytes from direction:
        \\    if direction == b"in":
        \\        return b"out"
        \\    return direction
        \\
        \\func pick(sig: Sig, controller: bool) -> int:
        \\    mut dir = b"none"
        \\    if controller:
        \\        dir = flip(sig.direction)
        \\    else:
        \\        dir = sig.direction
        \\    return len(dir)
        \\
        \\func main() -> int:
        \\    return pick(Sig(direction=b"in"), True)
        \\
    );
    try refuses(std.testing.allocator,
        \\func compute(m: int) -> int[]:
        \\    mut r: int[] = []
        \\    for i in range(m):
        \\        append(mut r, i)
        \\    return r
        \\
        \\func layered(m: int, fixed: int[]?) -> int:
        \\    mut rank: int[] = []
        \\    match fixed:
        \\        case Some(f):
        \\            rank = f
        \\        case None:
        \\            rank = compute(m)
        \\    return len(rank)
        \\
        \\func main() -> int:
        \\    return layered(3, None)
        \\
    , "E_SINGLE_OWNER_OVERLAP", "'f' borrows from 'fixed'");
}
