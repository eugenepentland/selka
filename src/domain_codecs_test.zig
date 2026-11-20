//! Declared domain codecs: wire types, encode/decode member contracts, execution
//! during typed conversion, and the diagnostics that reject an invalid declaration.
const std = @import("std");
const removed_code = @import("domain_migration.zig").removed_code;
const t = std.testing;
const language = @import("compiler.zig");
const typed = @import("typed.zig");
const source =
    // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
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
    var c = try withoutEffectsCompilation(allocator, "codec.selka", source ++
        \\func main() -> i64:
        \\    return 0
    );
    defer c.deinit();
    try expectSourceError(c.check());
    try t.expect(hasCode(c.diagnostics.items, removed_code));
}
test "domain codec contracts resolve checked factories and wire types under every allocation failure" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn reject(bytes: []const u8, expected: []const u8) !void {
    if (std.mem.indexOf(u8, bytes, " effects()") != null)
        try effectsWitness(t.allocator, "bad-codec.selka", bytes);
    const current = try eraseEffects(t.allocator, bytes);
    defer t.allocator.free(current);
    var c = try language.Compilation.init(t.allocator, "bad-codec.selka", current);
    defer c.deinit();
    try expectSourceError(c.check());
    try t.expect(hasCode(c.diagnostics.items, expected));
}
const prefix =
    // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
    \\result R:
    \\    ok: D,
    \\    err: i64
    \\
    \\
    \\domain D: i64:
    \\
;
const suffix =
    // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
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
    // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
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
        if (std.mem.eql(u8, path, "main.selka")) return allocator.dupe(u8,
            \\import data as d
            \\
            \\
            \\func main() -> i64:
            \\    match d.Positive.from_wire(d.Wire(n=7)):
            \\        case ok(x):
            \\            return d.Positive.to_wire(x).n
            \\        case err(e):
            \\            return e
        );
        if (std.mem.eql(u8, path, "data.selka")) return allocator.dupe(u8, "" ++ source);
        return error.NotFound;
    }
    fn readWithoutEffects(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "data.selka")) return eraseEffects(allocator, source);
        return read(context, allocator, path, limit);
    }
};
fn projectScenario(allocator: std.mem.Allocator) !void {
    var original = language.project.Project.init(allocator);
    defer original.deinit();
    try original.load(.{ .context = null, .read = Provider.read }, "main", .{});
    if (language.interfaces.build(&original)) |_| return error.TestExpectedError else |err| {
        if (err != error.SourceError) return err;
    }
    try t.expectEqualStrings("E_EFFECTS_REMOVED", original.problem.?.code);

    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Provider.readWithoutEffects }, "main", .{});
    var index = try language.interfaces.build(&project);
    var c = try language.project_compile.Compilation.init(&index);
    try expectSourceError(c.check());
    try t.expect(hasCode(c.diagnostics.items.items, removed_code));
}
test "domain codec module relocation and public schemas preserve contracts and opaque backing under allocation failures" {
    try projectScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), projectScenario, .{});
    try recordSchemaScenario(t.allocator);
    var record_stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(record_stable.allocator(), recordSchemaScenario, .{});
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
    try expectSourceError(again.check());
    try t.expect(hasCode(again.diagnostics.items, removed_code));
    const stable = try again.format(t.allocator);
    defer t.allocator.free(stable);
    try t.expectEqualStrings(formatted, stable);
    try t.expect(std.mem.indexOf(u8, formatted, "# wire contract") != null);
}

const source_call =
    \\func main() -> i64:
    \\    match Positive.from_wire(Wire(n=7)):
    \\        case ok(x):
    \\            return Positive.to_wire(x).n
    \\        case err(e):
    \\            return e
;
fn sourceScenario(allocator: std.mem.Allocator) !void {
    var c = try withoutEffectsCompilation(allocator, "source-codec.selka", source ++ source_call);
    defer c.deinit();
    try expectSourceError(c.check());
    try t.expect(hasCode(c.diagnostics.items, removed_code));
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "Positive.from_wire") != null);
    var again = try language.Compilation.init(allocator, "formatted.selka", formatted);
    defer again.deinit();
    try expectSourceError(again.check());
    try t.expect(hasCode(again.diagnostics.items, removed_code));
}
// spec: SOURCE-CODEC-1
test "source codec operations resolve declared methods and preserve formatting under allocation failures" {
    try sourceScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), sourceScenario, .{});
}
test "domain codec methods reject missing methods invalid arity and backing bypass" {
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
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
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
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
        \\        case ok(x):
        \\            return D.enc(x)
        \\        case err(e):
        \\            return e
    );
    defer c.deinit();
    try expectSourceError(c.check());
    try t.expect(hasCode(c.diagnostics.items, removed_code));
}

fn hasCode(items: anytype, code: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item.code, code)) return true;
    return false;
}

fn expectSourceError(outcome: anyerror!void) anyerror!void {
    outcome catch |err| {
        if (err == error.SourceError) return;
        return err;
    };
    return error.TestExpectedError;
}

// Keep original effect-bearing bytes executable before checking the remaining
// domain/codec recognizer. Erase only the two known empty source clauses.
fn eraseEffects(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]u8 {
    return std.mem.replaceOwned(u8, allocator, bytes, " effects()", "");
}
fn effectsWitness(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !void {
    var original = try language.Compilation.init(allocator, path, bytes);
    defer original.deinit();
    try expectSourceError(original.check());
    try t.expectEqualStrings("E_EFFECTS_REMOVED", original.diagnostics.items[0].code);
}
fn withoutEffectsCompilation(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !language.Compilation {
    try effectsWitness(allocator, path, bytes);
    const current = try eraseEffects(allocator, bytes);
    defer allocator.free(current);
    return language.Compilation.init(allocator, path, current);
}

// Ordinary former-domain values now expose record fields in the public graph;
// opaque backing and persisted codec metadata intentionally no longer exist.
const RecordProvider = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "data.selka")) return allocator.dupe(u8,
            \\public record Wire:
            \\    n: i64
            \\public record Positive:
            \\    value: i64
            \\public result Decoded:
            \\    ok: Positive,
            \\    err: i64
            \\func raw(value: i64) -> Positive:
            \\    return Positive(value=value)
            \\public func from_wire(value: Wire) -> Decoded:
            \\    if value.n <= 0:
            \\        return Err(-1)
            \\    return Ok(raw(value.n))
            \\public func to_wire(value: Positive) -> Wire:
            \\    return Wire(n=value.value)
        );
        if (std.mem.eql(u8, path, "main.selka")) return allocator.dupe(u8,
            \\import data as d
            \\func main() -> i64:
            \\    match d.from_wire(d.Wire(n=7)):
            \\        case ok(value):
            \\            return d.to_wire(value).n
            \\        case err(error):
            \\            return error
        );
        return error.NotFound;
    }
};
fn recordSchemaScenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = RecordProvider.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var c = try language.project_compile.Compilation.init(&index);
    try c.check();
    try t.expect((try c.publicValueType("data::Wire")).isAggregate());
    try t.expect((try c.publicValueType("data::Positive")).isAggregate());
    const json = try @import("schema.zig").render(allocator, &c);
    defer allocator.free(json);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    var found = false;
    for (parsed.value.object.get("types").?.array.items) |item| {
        if (!std.mem.eql(u8, item.object.get("name").?.string, "data::Positive")) continue;
        found = true;
        try t.expectEqualStrings("record", item.object.get("kind").?.string);
        try t.expect(!item.object.get("opaque").?.bool);
        try t.expect(item.object.get("codec") == null);
        const fields = item.object.get("fields").?.array.items;
        try t.expectEqual(@as(usize, 1), fields.len);
        try t.expectEqualStrings("value", fields[0].object.get("name").?.string);
        try t.expectEqualStrings("i64", fields[0].object.get("type").?.string);
    }
    try t.expect(found);
    try t.expect(std.mem.indexOf(u8, json, "data::raw") == null);
}
