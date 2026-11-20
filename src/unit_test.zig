//! Unit procedures preserve effectful calls without dummy values or implicit result loss.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const program =
    \\func my_set(x: i64):
    \\    _ = x
    \\
    \\
    \\func skip[T](x: T):
    \\    _ = x
    \\
    \\
    \\func noop():
    \\    return
    \\
    \\
    \\func main() -> i64:
    \\    mut x = 0
    \\    x = 42
    \\    my_set(x)
    \\    skip[i64](x)
    \\    noop()
    \\    return x
;
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "unit.selka", program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
}
// spec: UNIT-1
test "unit calls bare returns and generic fallthrough preserve results" {
    try scenario(t.allocator);
}
// spec: UNIT-3
test "unit data and extern boundaries reject unsupported ABI values explicitly" {
    const typed = @import("typed.zig");
    try t.expectEqual(typed.Type.unit, @as(typed.Value, .unit).typeOf());
    try t.expect(!typed.Type.unit.isAggregate());
    try t.expect(!typed.Type.unit.isInteger());
    try t.expectEqual(@as(?u4, null), typed.Type.unit.capabilityIndex());
    try t.expectEqual(@as(?u4, 7), typed.Type.process_cap.capabilityIndex());
    try t.expectEqual(@as(?u4, 8), typed.Type.input_cap.capabilityIndex());
    try t.expect(typed.Type.input_cap.isHandle() and typed.Type.stream_cap.isHandle() and !typed.Type.process_cap.isHandle());
    try t.expectError(error.NotDataType, @import("data_type.zig").check(t.allocator, &.{}, .unit, true));
    var c = try language.Compilation.init(t.allocator, "host.selka",
        // migrate-embedded: skip preserved original effect retirement witness
        \\extern func f(host: Host, x: unit) -> i64 effects(host)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    );
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_EFFECTS_REMOVED", c.diagnostics.items[0].code);
    var modern = try language.Compilation.init(t.allocator, "host.selka",
        \\extern func f(host: Host, x: unit) -> i64
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    );
    defer modern.deinit();
    try t.expectError(error.SourceError, modern.check());
    try t.expectEqualStrings("E_EXTERN_SIGNATURE", modern.diagnostics.items[0].code);
}
fn publicUnit(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
    return allocator.dupe(u8,
        \\
        \\
        \\public func finish():
        \\    pass
        \\
        \\
        \\func main() -> i64:
        \\    finish()
        \\    return 42
    );
}
// spec: UNIT-6
test "public unit schemas describe a distinct type while unsupported copied ABIs reject invocation" {
    var guest: language.embedded_project.Program = undefined;
    try guest.init(t.allocator, .{ .context = null, .read = publicUnit });
    defer guest.deinit();
    const schema = try language.schema.render(t.allocator, &guest.compilation);
    defer t.allocator.free(schema);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, schema, .{});
    defer parsed.deinit();
    try t.expect(std.mem.indexOf(u8, schema, "\"kind\":\"unit\"") != null);
    try t.expect(std.mem.indexOf(u8, schema, "main::finish") != null);
    try t.expectEqual(@as(i64, 42), (try native.run(&guest.compilation)).value);
}
// spec: UNIT-5
test "unit result payloads still require handling and propagation only drops successful unit" {
    const header =
        \\result Done:
        \\    ok: None,
        \\    err: i64
        \\
        \\
        \\func noop():
        \\    pass
        \\
        \\
        \\func done() -> Done:
        \\    return Ok(noop())
        \\
        \\
        \\
    ;
    var valid = try language.Compilation.init(t.allocator, "result.selka", header ++
        \\func chained() -> Done:
        \\    try done()
        \\    return done()
        \\
        \\
        \\func main() -> i64:
        \\    match chained():
        \\        case ok(_):
        \\            return 42
        \\        case err(code):
        \\            return code
    );
    defer valid.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&valid)).value);
    for ([_][]const u8{ "done()", "pending = done()" }) |statement| {
        const text = try std.fmt.allocPrint(t.allocator, "{s}def main() -> i64:\n    {s}\n    return 0\n", .{ header, statement });
        defer t.allocator.free(text);
        var invalid = try language.Compilation.init(t.allocator, "unhandled.selka", text);
        defer invalid.deinit();
        try t.expectError(error.SourceError, invalid.check());
    }
}

// spec: UNIT-2
test "unit remains distinct and implicit discard cannot lose ordinary or fallible values" {
    const invalid = [_][]const u8{
        \\func main() -> bool:
        \\    return True
        ,
        \\result Done:
        \\    ok: None,
        \\    err: i64
        \\
        \\
        \\func leak(x: Done):
        \\    pass
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        ,
        \\result Done:
        \\    ok: None,
        \\    err: i64
        \\
        \\
        \\func leak[T](x: Done):
        \\    pass
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        ,
        \\func main() -> i64:
        \\    return
        ,
        \\func f():
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        ,
        // migrate-embedded: skip original implicit-discard rejection subject
        \\func f() -> i64:
        \\    return 7
        \\
        \\
        \\func main() -> i64:
        \\    f()
        \\    return 0
        ,
        \\func f[T](x: T):
        \\    x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        ,
        \\func f():
        \\    pass
        \\
        \\
        \\func main() -> i64:
        \\    return f()
        ,
        \\func f():
        \\    pass
        \\
        \\
        \\func main() -> i64:
        \\    if f():
        \\        return 1
        \\    return 0
        ,
        \\func f():
        \\    pass
        \\
        \\
        \\func main() -> i64:
        \\    return f() + 1
        ,
    };
    for (invalid) |text| {
        var c = try language.Compilation.init(t.allocator, "invalid.selka", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
    }
}
