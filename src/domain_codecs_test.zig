//! Declared domain codecs: wire types, encode/decode member contracts, execution
//! during typed conversion, and the diagnostics that reject an invalid declaration.
const source_names = @import("source_names.zig");
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const typed = @import("typed.zig");
const source =
    \\public record Wire:
    \\    n: i64
    \\
    \\
    \\public result Decoded:
    \\    ok: Positive,
    \\    err: i64
    \\
    \\
    \\public domain Positive: i64:
    \\    codec Wire:
    \\        decode: from_wire,
    \\        encode: to_wire
    \\
    \\    private func raw(x: i64) -> Positive:
    \\        return wrap[Positive](x)
    \\
    \\    func from_wire(x: Wire) -> Decoded effects():
    \\        if x.n <= 0:
    \\            return Err(-1)
    \\        return Ok(Positive.raw(x.n))
    \\
    \\    func to_wire(x: Positive) -> Wire effects():
    \\        return Wire(n=unwrap(x))
    \\
    \\
    \\
;
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "codec.selka", source ++
        \\func main() -> i64:
        \\    return 0
    );
    defer c.deinit();
    try c.check();
    const code = c.program.?;
    var domain: typed.Type = undefined;
    for (code.records) |record| if (record.contract.codec != null) {
        domain = record.id;
        break;
    };
    const codec = code.records[domain.recordIndex()].contract.codec.?;
    try t.expectEqualStrings("Wire", typed.typeName(codec.wire, code.records));
    try t.expectEqualStrings("Positive.from_wire", code.functions[@backingInt(codec.decode)].name);
    try t.expectEqualStrings("Positive.to_wire", code.functions[@backingInt(codec.encode)].name);
}
test "domain codec contracts resolve checked factories and wire types under every allocation failure" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn reject(bytes: []const u8, expected: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "bad-codec.selka", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(expected, c.diagnostics.items[0].code);
}
const prefix =
    \\result R:
    \\    ok: D,
    \\    err: i64
    \\
    \\
    \\domain D: i64:
    \\
;
const suffix =
    \\    func dec(x: i64) -> R:
    \\        return Ok(wrap[D](x))
    \\
    \\    func enc(x: D) -> i64:
    \\        return unwrap(x)
    \\
    \\
    \\func main() -> i64:
    \\    return 0
;
const private_decode =
    \\    private func dec(x: i64) -> R:
    \\        return Ok(wrap[D](x))
    \\
    \\    func enc(x: D) -> i64:
    \\        return unwrap(x)
    \\
    \\
    \\func main() -> i64:
    \\    return 0
;
// spec: WIRE-4
test "domain codec declarations reject duplicate missing unknown and private entries" {
    try reject(prefix ++
        \\    codec i64:
        \\        decode: dec,
        \\        decode: dec,
        \\        encode: enc
        \\
    ++ suffix, "E_DUPLICATE_CODEC_KEY");
    try reject(prefix ++
        \\    codec i64:
        \\        decode: dec
        \\
    ++ suffix, "E_INCOMPLETE_CODEC");
    try reject(prefix ++
        \\    codec i64:
        \\        encode: enc
        \\
    ++ suffix, "E_INCOMPLETE_CODEC");
    try reject(prefix ++
        \\    codec i64:
        \\        other: enc
        \\
    ++ suffix, "E_CODEC_KEY");
    try reject(prefix ++
        \\    codec i64:
        \\        decode: dec,
        \\        encode: enc
        \\
        \\    codec i64:
        \\        decode: dec,
        \\        encode: enc
        \\
    ++ suffix, "E_DUPLICATE_CODEC");
    try reject(prefix ++
        \\    codec i64:
        \\        decode: missing,
        \\        encode: enc
        \\
    ++ suffix, "E_CODEC_FUNCTION");
    try reject(prefix ++
        \\    codec i64:
        \\        decode: dec,
        \\        encode: missing
        \\
    ++ suffix, "E_CODEC_FUNCTION");
    try reject(prefix ++
        \\    codec i64:
        \\        decode: dec,
        \\        encode: enc
        \\
    ++ private_decode, "E_CODEC_PRIVATE");
}
const Provider = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, source_names.entry)) return allocator.dupe(u8,
            \\import data as d
            \\
            \\
            \\func main() -> i64:
            \\    match d.Positive.from_wire(d.Wire(n=7)):
            \\        case d.Decoded.ok(x):
            \\            return d.Positive.to_wire(x).n
            \\        case d.Decoded.err(e):
            \\            return e
        );
        if (std.mem.eql(u8, path, "data.selka")) return allocator.dupe(u8, "" ++ source);
        return error.NotFound;
    }
};
fn projectScenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Provider.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var c = try language.project_compile.Compilation.init(&index);
    try c.check();
    try t.expectEqual(@as(i64, 7), (try native.run(&c)).value);
    const json = try @import("schema.zig").render(allocator, &c);
    defer allocator.free(json);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    var found = false;
    for (parsed.value.object.get("types").?.array.items) |item| {
        if (!std.mem.eql(u8, item.object.get("name").?.string, "data::Positive")) continue;
        found = true;
        try t.expect(item.object.get("opaque").?.bool);
        try t.expect(item.object.get("fields") == null);
        const codec = item.object.get("codec").?.object;
        try t.expectEqualStrings("data::Wire", codec.get("wire").?.string);
        try t.expectEqualStrings("data::Positive.from_wire", codec.get("decode").?.string);
        try t.expectEqualStrings("data::Positive.to_wire", codec.get("encode").?.string);
        try t.expectEqualStrings("i64", codec.get("error_type").?.string);
    }
    try t.expect(found);
    try t.expect(std.mem.indexOf(u8, json, "Positive.raw") == null);
    // The declared wire type stays resolvable even though nothing calls the
    // codec from outside the guest any more.
    try t.expect((try c.publicValueType("data::Wire")).isAggregate());
}
test "domain codec module relocation and public schemas preserve contracts and opaque backing under allocation failures" {
    try projectScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), projectScenario, .{});
}
test "domain codec formatting preserves comments entries and checked contracts" {
    var c = try language.Compilation.init(t.allocator, "format.selka", prefix ++
        \\    codec i64:
        \\        # wire contract
        \\        encode: enc,
        \\        decode: dec,
        \\
    ++ suffix);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    var again = try language.Compilation.init(t.allocator, "formatted.selka", formatted);
    defer again.deinit();
    try again.check();
    const stable = try again.format(t.allocator);
    defer t.allocator.free(stable);
    try t.expectEqualStrings(formatted, stable);
    try t.expect(std.mem.indexOf(u8, formatted, "# wire contract") != null);
}

const source_call =
    \\func main() -> i64:
    \\    match Positive.from_wire(Wire(n=7)):
    \\        case Decoded.ok(x):
    \\            return Positive.to_wire(x).n
    \\        case Decoded.err(e):
    \\            return e
;
fn sourceScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "source-codec.selka", source ++ source_call);
    defer c.deinit();
    const result = try native.run(&c);
    try t.expectEqual(@as(i64, 7), result.value);
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "Positive.from_wire") != null);
    var again = try language.Compilation.init(allocator, "formatted.selka", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 7), (try native.run(&again)).value);
}
// spec: SOURCE-CODEC-1
test "source codec operations resolve declared methods and preserve formatting under allocation failures" {
    try sourceScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), sourceScenario, .{});
}
test "domain codec methods reject missing methods invalid arity and backing bypass" {
    try reject(
        \\domain D: i64:
        \\    pass
        \\
        \\
        \\func main() -> i64:
        \\    return D.to_wire(0)
    , "E_UNKNOWN_FUNCTION");
    try reject(
        \\func main() -> i64:
        \\    return i64.from_wire(0)
    , "E_SYNTAX");
    try reject(source ++
        \\func main() -> i64:
        \\    return Positive.to_wire(7)
    , "E_TYPE");
    try reject(source ++
        \\func main() -> i64:
        \\    return Positive.from_wire()
    , "E_ARITY");
    try reject(source ++
        \\func main() -> i64:
        \\    return Positive.from_wire(7)
    , "E_TYPE");
    try reject(
        \\func helper[T](x: T) -> T:
        \\    return T.to_wire(x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}

test "source codec operations follow selected method names rather than naming conventions" {
    var c = try language.Compilation.init(t.allocator, "named.selka", prefix ++
        \\    codec i64:
        \\        decode: dec,
        \\        encode: enc
        \\
        \\    func dec(x: i64) -> R:
        \\        return Ok(wrap[D](x * 2))
        \\
        \\    func enc(x: D) -> i64:
        \\        return unwrap(x) + 1
        \\
        \\
        \\func main() -> i64:
        \\    match D.dec(7):
        \\        case R.ok(x):
        \\            return D.enc(x)
        \\        case R.err(e):
        \\            return e
    );
    defer c.deinit();
    try t.expectEqual(@as(i64, 15), (try native.run(&c)).value);
}
