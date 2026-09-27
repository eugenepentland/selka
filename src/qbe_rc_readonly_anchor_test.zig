//! RC-READONLY-ANCHOR-1: values read out of read-only parameters take no token.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\record Chunk:
    \\    code: list[int]
    \\record Function:
    \\    arity: int
    \\    chunk: Chunk
    \\union Obj:
    \\    free,
    \\    function: Function
    \\record Runtime:
    \\    objects: list[Obj]
    \\    count: int
    \\def arity(rt: Runtime, at: int) -> int:
    \\    match rt.objects[at]:
    \\        case Obj.function(payload):
    \\            return payload.arity + len(payload.chunk.code)
    \\        case _:
    \\            return -1
    \\def code(rt: Runtime, at: int) -> list[int]:
    \\    match rt.objects[at]:
    \\        case Obj.function(payload):
    \\            return payload.chunk.code
    \\        case _:
    \\            return []
    \\def mutated(rt: mut Runtime, at: int) -> int:
    \\    rt.count = at
    \\    match rt.objects[at]:
    \\        case Obj.function(payload):
    \\            return payload.arity
    \\        case _:
    \\            return -1
    \\def main() -> int:
    \\    rt = Runtime([Obj.function(Function(2, Chunk([7])))], 1)
    \\    return arity(rt, 0) + len(code(rt, 0)) + mutated(mut rt, 0)
;

fn operations(name: []const u8) !usize {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_readonly_anchor.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    for (manifest.value.functions) |function| {
        if (!std.mem.eql(u8, function.name, name)) continue;
        const il = function.il;
        return std.mem.count(u8, il, "# RC-GLUE-1 loan") + std.mem.count(u8, il, "# RC-GLUE-1 retain");
    }
    return error.TestUnexpectedResult;
}

// spec: RC-READONLY-ANCHOR-1
test "RC reads out of a read-only parameter take no loan or payload retain" {
    try t.expectEqual(@as(usize, 0), try operations("arity"));
}

// spec-case: RC-READONLY-ANCHOR-1
test "RC anchored reads still copy into returned owners and mut roots keep tokens" {
    try t.expect(try operations("code") > 0);
    try t.expect(try operations("mutated") > 0);
}
