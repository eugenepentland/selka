//! Declared domain codecs: wire types, encode/decode member contracts, execution
//! during typed conversion, and the diagnostics that reject an invalid declaration.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const typed = @import("typed.zig");
const source =
    \\class Wire:
    \\    n: i64
    \\
    \\
    \\result Decoded:
    \\    ok: Positive,
    \\    err: i64
    \\
    \\
    \\domain Positive: i64:
    \\    codec Wire:
    \\        decode: from_wire,
    \\        encode: to_wire
    \\
    \\    private def raw(x: i64) -> Positive:
    \\        return wrap<Positive>(x)
    \\
    \\    def from_wire(x: Wire) -> Decoded:
    \\        if x.n <= 0:
    \\            return Err(-1)
    \\        return Ok(Positive.raw(x.n))
    \\
    \\    def to_wire(x: Positive) -> Wire:
    \\        return Wire(n=unwrap(x))
;
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "codec.my", source ++
        \\def main() -> i64:
        \\    return 0
    );
    defer c.deinit();
    try c.emit();
    const code = c.code.?;
    var domain: typed.Type = undefined;
    for (code.records) |record| if (record.contract.codec != null) {
        domain = record.id;
        break;
    };
    const codec = code.records[domain.recordIndex()].contract.codec.?;
    try t.expectEqualStrings("Wire", typed.typeName(codec.wire, code.records));
    for ([_]i64{ 7, 0, -1 }) |number| {
        const wire = try typed.Value.create(allocator, codec.wire, &.{.{ .i64 = number }});
        defer wire.release(allocator);
        const result = try language.vm.invoke(allocator, code, codec.decode, &.{wire}, .{});
        defer result.value.release(allocator);
        const shape = typed.resultShape(result.value.typeOf(), code.records).?;
        try t.expectEqual(if (number > 0) shape.ok_tag else shape.error_tag, try result.value.variantTag());
        if (number > 0) {
            const encoded = try language.vm.invoke(allocator, code, codec.encode, result.value.aggregate.fields, .{});
            defer encoded.value.release(allocator);
            try t.expectEqual(number, encoded.value.aggregate.fields[0].i64);
        }
    }
    // Declaring a contract does not silently enable representation-only decoding.
    @import("typed_json.zig").checkType(allocator, code.records, domain) catch |err| {
        if (err == error.OutOfMemory) return err;
        try t.expectEqual(error.NoImplicitCodec, err);
        return;
    };
    return error.TestExpectedOpaqueDomain;
}
test "domain codec contracts resolve checked factories and wire types under every allocation failure" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn reject(bytes: []const u8, expected: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "bad-codec.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(expected, c.diagnostics.items[0].code);
}
const prefix = "result R{ok:D,err:i64} domain D:i64{";
const suffix = "fn dec(x:i64)->R{return new R.ok(wrap<D>(x));} fn enc(x:D)->i64{return unwrap(x);}}fn main()->i64{return 0;}";
// spec: WIRE-4
test "domain codec declarations reject duplicate missing unknown and private entries" {
    try reject(prefix ++ "codec i64{decode:dec,decode:dec,encode:enc}" ++ suffix, "E_DUPLICATE_CODEC_KEY");
    try reject(prefix ++ "codec i64{decode:dec}" ++ suffix, "E_INCOMPLETE_CODEC");
    try reject(prefix ++ "codec i64{encode:enc}" ++ suffix, "E_INCOMPLETE_CODEC");
    try reject(prefix ++ "codec i64{}" ++ suffix, "E_INCOMPLETE_CODEC");
    try reject(prefix ++ "codec i64{other:enc}" ++ suffix, "E_CODEC_KEY");
    try reject(prefix ++ "codec i64{decode:dec,encode:enc}codec i64{decode:dec,encode:enc}" ++ suffix, "E_DUPLICATE_CODEC");
    try reject(prefix ++ "codec i64{decode:missing,encode:enc}" ++ suffix, "E_CODEC_FUNCTION");
    try reject(prefix ++ "codec i64{decode:dec,encode:missing}" ++ suffix, "E_CODEC_FUNCTION");
    try reject(prefix ++ "codec i64{decode:dec,encode:enc}private " ++ suffix, "E_CODEC_PRIVATE");
}
const Provider = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\module main
            \\import data as d
            \\
            \\
            \\def main() -> i64:
            \\    match codec_decode<d.Positive>(d.Wire(n=7)):
            \\        case d.Decoded.ok(x):
            \\            return codec_encode<d.Positive>(x).n
            \\        case d.Decoded.err(e):
            \\            return e
        );
        if (std.mem.eql(u8, path, "data.my")) return allocator.dupe(u8, "module data;export Wire;export Decoded;export Positive;" ++ source);
        return error.NotFound;
    }
};
fn projectScenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Provider.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var c = try language.project_compile.Compilation.init(&index);
    try c.emit();
    try t.expectEqual(@as(i64, 7), (try language.vm.runWithOptions(allocator, c.code.?, .{})).value);
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
    const wire_ty = try c.publicValueType("data::Wire");
    const wire = try typed.Value.create(allocator, wire_ty, &.{.{ .i64 = 9 }});
    defer wire.release(allocator);
    const result = try c.invokePublic(allocator, "data::Positive.from_wire", &.{wire}, .{});
    defer result.value.release(allocator);
    try t.expectEqual(@as(i64, 9), result.value.aggregate.fields[0].aggregate.fields[0].i64);
}
test "domain codec module relocation and public schemas preserve contracts and opaque backing under allocation failures" {
    try projectScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), projectScenario, .{});
}
test "domain codec formatting preserves comments entries and checked contracts" {
    var c = try language.Compilation.init(t.allocator, "format.my", prefix ++ "codec i64{// wire contract\nencode:enc,decode:dec,}" ++ suffix);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    var again = try language.Compilation.init(t.allocator, "formatted.my", formatted);
    defer again.deinit();
    try again.check();
    const stable = try again.format(t.allocator);
    defer t.allocator.free(stable);
    try t.expectEqualStrings(formatted, stable);
    try t.expect(std.mem.indexOf(u8, formatted, "// wire contract") != null);
}

const source_call =
    \\def main() -> i64:
    \\    match codec_decode<Positive>(Wire(n=7)):
    \\        case Decoded.ok(x):
    \\            return codec_encode<Positive>(x).n
    \\        case Decoded.err(e):
    \\            return e
;
fn sourceScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "source-codec.my", source ++ source_call);
    defer c.deinit();
    const result = try c.execute(allocator);
    try t.expectEqual(@as(i64, 7), result.value);
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "codec_decode<Positive>") != null);
    var again = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 7), (try again.execute(allocator)).value);
}
// spec: SOURCE-CODEC-1
test "source codec operations resolve declared methods and preserve formatting under allocation failures" {
    try sourceScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), sourceScenario, .{});
}
test "source codec operations reject missing contracts invalid arity and backing bypass" {
    try reject(
        \\domain D: i64:
        \\    pass
        \\
        \\
        \\def main() -> i64:
        \\    return codec_encode<D>(0)
    , "E_CODEC_REQUIRED");
    try reject(
        \\def main() -> i64:
        \\    return codec_decode<i64>(0)
    , "E_TYPE");
    try reject(source ++
        \\def main() -> i64:
        \\    return codec_encode<Positive>(7)
    , "E_TYPE");
    try reject(source ++
        \\def main() -> i64:
        \\    return codec_decode<Positive>()
    , "E_CODEC_ARITY");
    try reject(source ++ "fn main()->i64{return codec_decode(7);}", "E_CODEC_ARITY");
    try reject(
        \\def helper[T](x: T) -> T:
        \\    return codec_encode<T>(x)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_BODY_UNSUPPORTED");
}

test "source codec operations follow selected method names rather than naming conventions" {
    var c = try language.Compilation.init(t.allocator, "named.my", prefix ++
        "codec i64{decode:dec,encode:enc}fn dec(x:i64)->R{return new R.ok(wrap<D>(x*2));}" ++
        "fn enc(x:D)->i64{return unwrap(x)+1;}}fn main()->i64{match codec_decode<D>(7){R.ok(x)=>{return codec_encode<D>(x);},R.err(e)=>{return e;}}}");
    defer c.deinit();
    try t.expectEqual(@as(i64, 15), (try c.execute(t.allocator)).value);
}
