//! Which `const` bindings of a record place a later write to the record can make stale (R2, disjoint fields).
const std = @import("std");
const alias_places = @import("alias_places.zig");
const support = @import("test_support.zig");

const prelude =
    \\record Inner:
    \\    n: int
    \\    tags: str[]
    \\
    \\
    \\record Builder:
    \\    items: str[]
    \\    links: str[]
    \\    count: int
    \\    inner: Inner
    \\
    \\
    \\func use(s: str) -> int:
    \\    return len(s)
    \\
    \\
;

/// The flags of local `name` in function `f` of `source`.
fn flagsOf(backing: std.mem.Allocator, source: []const u8, name: []const u8) !alias_places.Flags {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try support.checkedProgram(a, try std.mem.concat(a, u8, &.{ source, "\n\nfunc main() -> int:\n    return 0\n" }));
    for (program.functions) |function| {
        if (!std.mem.eql(u8, function.name, "f")) continue;
        const flags = try alias_places.compute(a, program, function);
        for (function.scope.locals, flags) |local, flag| {
            if (std.mem.eql(u8, local.name, name)) return flag;
        }
    }
    return error.NoSuchLocal;
}

test "a binding of a record place is bound when the record is written later" {
    const flags = try flagsOf(std.testing.allocator, prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const item = self.items[0]
        \\    append(mut self.links, copy(item))
        \\    return use(item)
        \\
    , "item");
    try std.testing.expect(flags.bound);
    try std.testing.expect(!flags.carried);
}

test "a binding whose record is never written after it, or never written, is not bound" {
    const unwritten = try flagsOf(std.testing.allocator, prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const item = self.items[0]
        \\    return use(item)
        \\
    , "item");
    try std.testing.expect(!unwritten.bound);
    const before = try flagsOf(std.testing.allocator, prelude ++
        \\func f(mut self: Builder) -> int:
        \\    append(mut self.links, "x")
        \\    const item = self.items[0]
        \\    return use(item)
        \\
    , "item");
    try std.testing.expect(!before.bound);
}

test "a write of an assignment, a mut argument and a nested field all count" {
    const assigned = try flagsOf(std.testing.allocator, prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const item = self.items[0]
        \\    self.count = 1
        \\    return use(item)
        \\
    , "item");
    try std.testing.expect(assigned.bound);
    const argument = try flagsOf(std.testing.allocator, prelude ++
        \\func grow(mut xs: str[]):
        \\    append(mut xs, "x")
        \\
        \\
        \\func f(mut self: Builder) -> int:
        \\    const item = self.items[0]
        \\    grow(mut self.inner.tags)
        \\    return use(item)
        \\
    , "item");
    try std.testing.expect(argument.bound);
    const nested = try flagsOf(std.testing.allocator, prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const tag = self.inner.tags[0]
        \\    self.inner.n = 3
        \\    return use(tag)
        \\
    , "tag");
    try std.testing.expect(nested.bound);
}

test "a write in a loop that reads a binding made before the loop is carried" {
    const loop = try flagsOf(std.testing.allocator, prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const first = self.items[0]
        \\    for i in range(3):
        \\        self.count = self.count + use(first)
        \\        append(mut self.links, copy(first))
        \\    return self.count
        \\
    , "first");
    try std.testing.expect(loop.bound and loop.carried);
    const inside = try flagsOf(std.testing.allocator, prelude ++
        \\func f(mut self: Builder) -> int:
        \\    for i in range(3):
        \\        const item = self.items[0]
        \\        append(mut self.links, copy(item))
        \\        self.count = self.count + use(item)
        \\    return self.count
        \\
    , "item");
    try std.testing.expect(inside.bound and !inside.carried);
}

test "a copy of a scalar field and a binding of a plain local are not places of a record" {
    const scalar = try flagsOf(std.testing.allocator, prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const n = self.count
        \\    self.count = n + 1
        \\    return n
        \\
    , "n");
    try std.testing.expect(!scalar.bound);
    const local = try flagsOf(std.testing.allocator, prelude ++
        \\func f(mut self: Builder) -> int:
        \\    const names = self.links
        \\    const same = names
        \\    append(mut self.links, "x")
        \\    return len(same)
        \\
    , "same");
    try std.testing.expect(!local.bound);
}

test "a local the body does not declare has no flags to ask for" {
    try std.testing.expectError(error.NoSuchLocal, flagsOf(std.testing.allocator, prelude ++
        \\func f(mut self: Builder) -> int:
        \\    return self.count
        \\
    , "missing"));
}
