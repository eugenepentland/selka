//! RC-SELF-STORE-1 and RC-RETURN-MOVE-1: match bindings and returned locals
//! keep the owner they already hold instead of retaining and releasing it.
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
    \\record Name:
    \\    chars: bytes
    \\    hash: u32
    \\union Obj:
    \\    free,
    \\    function: Function,
    \\    name: Name
    \\def arity(objects: list[Obj], at: int) -> int:
    \\    match objects[at]:
    \\        case Obj.function(payload):
    \\            return payload.arity
    \\        case _:
    \\            return -1
    \\def function(objects: list[Obj], at: int) -> Function:
    \\    match objects[at]:
    \\        case Obj.function(payload):
    \\            return payload
    \\        case _:
    \\            return Function(0, Chunk([]))
    \\def kept(objects: list[Obj], at: int) -> list[Function]:
    \\    match objects[at]:
    \\        case Obj.function(payload):
    \\            copy = payload
    \\            copy.chunk.code.append(1)
    \\            return [payload, copy]
    \\        case _:
    \\            return []
    \\def replaced(objects: mut list[Obj], at: int) -> int:
    \\    match objects[at]:
    \\        case Obj.function(payload):
    \\            objects[at] = Obj.free
    \\            return payload.arity
    \\        case _:
    \\            return -1
    \\def name(objects: list[Obj], at: int) -> Name:
    \\    match objects[at]:
    \\        case Obj.name(payload):
    \\            return payload
    \\        case _:
    \\            return Name(b"", 0u32)
    \\def forward(value: Function) -> Function:
    \\    return value
    \\def main() -> int:
    \\    objects = [Obj.function(Function(2, Chunk([7])))]
    \\    return arity(objects, 0) + function(objects, 0).arity + len(kept(objects, 0)) + forward(function(objects, 0)).arity + replaced(mut objects, 0) + int(name(objects, 0).hash)
;

fn count(name: []const u8, marker: []const u8) !usize {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_binding_moves.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    for (manifest.value.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return std.mem.count(u8, function.il, marker);
    }
    return error.TestUnexpectedResult;
}

// spec: RC-SELF-STORE-1
test "RC elided payload copies keep the binding's owner without a second retain" {
    try t.expect(try count("arity", "# RC-SELF-STORE-1") > 0);
}

// spec-case: RC-SELF-STORE-1
test "RC payload bindings that outlive a scrutinee write keep their real copy" {
    try t.expectEqual(@as(usize, 0), try count("replaced", "# RC-SELF-STORE-1"));
}

// spec: RC-RETURN-MOVE-1
test "RC returning a named binding moves its owner into the result" {
    try t.expect(try count("name", "# RC-RETURN-MOVE-1") > 0);
}

// spec-case: RC-RETURN-MOVE-1
test "RC returning a parameter keeps the ordinary copy" {
    try t.expectEqual(@as(usize, 0), try count("forward", "# RC-RETURN-MOVE-1"));
}
