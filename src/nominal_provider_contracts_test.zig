//! Invalid provider layouts must reject in ordinary and unused generic functions alike.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const fixture = @import("nominal_provider_fixture.zig");
fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.initTrusted(t.allocator, "bad-nominal-provider.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
fn rejectBody(body: []const u8, code: []const u8) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{
        fixture.declarations, body, "\n\n\n",
        \\func main() -> i64:
        \\    return 0
    });
    defer t.allocator.free(text);
    try reject(text, code);
}
const env_call =
    \\
    \\
    \\result Lookup[T]:
    \\    ok: Entry[T],
    \\    err: i64
    \\
    \\
    \\func f[T](env: Environment) -> Lookup[T]:
    \\    mut name: FixedArray[u8, 0] = FixedArray[u8, 0]([])
    \\    return environment_get[Lookup[T]](env, name)
    \\
    \\
    \\func main() -> i64:
    \\    return 0
;
/// The same source is checked as written and with every type parameter erased,
/// so the generic template and its concrete instantiation share one contract.
fn bothForms(text: []const u8, code: []const u8) !void {
    try reject(text, code);
    const concrete = try std.mem.replaceOwned(u8, t.allocator, text, "[T]", "");
    defer t.allocator.free(concrete);
    try reject(concrete, code);
}
test "nominal provider environment contracts reject wrong missing extra and renamed fields in both checkers" {
    const schemas = [_][]const u8{
        \\record Entry[T]:
        \\    present: bool
        \\    length: u64
        \\    bytes: FixedArray[i64, 4]
        ,
        \\record Entry[T]:
        \\    present: bool
        \\    length: i64
        \\    bytes: FixedArray[u8, 4]
        ,
        \\record Entry[T]:
        \\    present: i64
        \\    length: u64
        \\    bytes: FixedArray[u8, 4]
        ,
        \\record Entry[T]:
        \\    present: bool
        \\    length: u64
        ,
        \\record Entry[T]:
        \\    present: bool
        \\    length: u64
        \\    bytes: FixedArray[u8, 4]
        \\    extra: bool
        ,
        \\record Entry[T]:
        \\    exists: bool
        \\    length: u64
        \\    bytes: FixedArray[u8, 4]
        ,
        \\enum Entry[T]:
        \\    present(value: bool)
        \\    length(value: u64)
        \\    bytes(value: FixedArray[u8, 4])
        ,
    };
    for (schemas) |schema| {
        const text = try std.mem.concat(t.allocator, u8, &.{ schema, env_call });
        defer t.allocator.free(text);
        try bothForms(text, "E_ENVIRONMENT_RESULT");
    }
    try reject(
        \\record Entry[T: integer]:
        \\    present: bool
        \\    length: u64
        \\    bytes: FixedArray[T, 4]
        \\
        \\
        \\result Lookup[T: integer]:
        \\    ok: Entry[T],
        \\    err: i64
        \\
        \\
        \\func f[T: integer](env: Environment) -> Lookup[T]:
        \\    return environment_get[Lookup[T]](env, [])
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_ENVIRONMENT_RESULT");
    try reject(
        \\record Entry[T]:
        \\    present: bool
        \\    length: u64
        \\    bytes: FixedArray[u8, 4]
        \\
        \\
        \\result Lookup[T]:
        \\    ok: Entry[T],
        \\    err: i64
        \\
        \\
        \\func f[T: integer](env: Environment, name: FixedArray[T, 1]) -> Lookup[T]:
        \\    return environment_get[Lookup[T]](env, name)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_ENVIRONMENT_NAME");
}
test "nominal provider completion and read contracts reject wrong named shapes in both checkers" {
    const Case = struct { declaration: []const u8, body: []const u8, code: []const u8 };
    const cases = [_]Case{
        .{ .declaration =
        \\record Failure[T]:
        \\    code: u64
        \\    resource: File
        \\
        \\
        \\result R[T]:
        \\    ok: bool,
        \\    err: Failure[T]
        , .body =
        \\    return complete_resource[R[T]](input)
        , .code = "E_COMPLETION_RESULT" },
        .{ .declaration =
        \\record Failure[T]:
        \\    code: i64
        \\    resource: i64
        \\
        \\
        \\result R[T]:
        \\    ok: bool,
        \\    err: Failure[T]
        , .body =
        \\    return complete_resource[R[T]](input)
        , .code = "E_COMPLETION_RESULT" },
        .{ .declaration =
        \\record Chunk[T]:
        \\    bytes: FixedArray[u8, 4]
        \\    length: u64
        \\    present: bool
        \\
        \\
        \\result R[T]:
        \\    ok: Chunk[T],
        \\    err: i64
        , .body =
        \\    mut file = input
        \\    return read_resource[R[T]](file)
        , .code = "E_RESOURCE_IO_RESULT" },
        .{ .declaration =
        \\record Chunk[T]:
        \\    bytes: FixedArray[u8, 4]
        \\    length: u64
        \\    eof: bool
        \\
        \\
        \\result R[T]:
        \\    ok: Chunk[T],
        \\    err: bool
        , .body =
        \\    mut file = input
        \\    return read_resource[R[T]](file)
        , .code = "E_RESOURCE_IO_RESULT" },
        .{ .declaration =
        \\result R[T]:
        \\    ok: i64,
        \\    err: i64
        , .body =
        \\    mut file = input
        \\    mut empty: FixedArray[u8, 0] = FixedArray[u8, 0]([])
        \\    return write_resource[R[T]](file, empty)
        , .code = "E_RESOURCE_IO_RESULT" },
    };
    for (cases) |case| {
        const text = try std.fmt.allocPrint(
            t.allocator,
            "resource File: filesystem\n\n\n{s}\n\n\nfunc f[T](input: File) -> R[T]:\n{s}\n\n\nfunc main() -> i64:\n    return 0",
            .{ case.declaration, case.body },
        );
        defer t.allocator.free(text);
        try bothForms(text, case.code);
    }
    try rejectBody(
        \\resource Other: filesystem
        \\
        \\
        \\func f[T](input: Other) -> Finish[T]:
        \\    return complete_resource[Finish[T]](input)
    , "E_GENERIC_TYPE");
}
