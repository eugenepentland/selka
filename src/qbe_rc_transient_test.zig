//! RC-TRANSIENT-FIELD-1: nested field reads consumed at once take no loan.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\record Chunk:
    \\    code: list[int]
    \\    names: list[str]
    \\record Function:
    \\    arity: int
    \\    chunk: Chunk
    \\record Frame:
    \\    code: list[int]
    \\    names: list[str]
    \\def frame(function: Function) -> Frame:
    \\    return Frame(code=function.chunk.code, names=function.chunk.names)
    \\def chunk(at: int) -> int:
    \\    function = Function(at, Chunk([at], ["c"]))
    \\    saved = function.chunk
    \\    return len(saved.code) + function.arity
    \\def made() -> Function:
    \\    return Function(1, Chunk([1], ["a"]))
    \\def fresh() -> Frame:
    \\    return Frame(code=made().chunk.code, names=[])
    \\def main() -> int:
    \\    value = Function(2, Chunk([7], ["x"]))
    \\    return len(frame(value).code) + chunk(3) + len(fresh().code)
;

fn loans(name: []const u8) !usize {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_transient.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    for (manifest.value.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return std.mem.count(u8, function.il, "# RC-GLUE-1 loan");
    }
    return error.TestUnexpectedResult;
}

// spec: RC-TRANSIENT-FIELD-1
test "RC nested field reads copied into a constructor take no loans" {
    try t.expectEqual(@as(usize, 0), try loans("frame"));
}

// spec-case: RC-TRANSIENT-FIELD-1
test "RC field reads stored into a local or read from a call result keep their loans" {
    try t.expect(try loans("chunk") > 0);
    try t.expect(try loans("fresh") > 0);
}
