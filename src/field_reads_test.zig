const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "fields.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
const snapshots = "struct Meta { code: i64 } buffer B: i64; result Open { ok: B, err: i64 } struct " ++
    "Owner { buffer: B, meta: Meta } fn run(heap: allocator) -> Open { let b = try " ++
    "acquire_buffer<Open>(heap, 1); let mut owner = new Owner { buffer: b, meta: new Meta " ++
    "{ code: 7 } }; let before = read_field(owner, meta); owner = update(owner) { meta: " ++
    "new Meta { code: 9 } }; let after = read_field(owner, meta); if before.code + " ++
    "after.code == 16 { return new Open.ok(owner.buffer); } else { return new " ++
    "Open.err(99); } } fn main(heap: allocator) -> i64 { match run(heap) { Open.ok(b) => " ++
    "{ return cast<i64>(capacity_buffer(b)); }, Open.err(e) => { return e; } } }";
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "fields.my", snapshots);
    defer c.deinit();
    var stats: @import("memory.zig").Statistics = .{};
    try t.expectEqual(@as(i64, 1), (try c.executeWithOptions(allocator, .{
        .memory = .{ .statistics = &stats },
    })).value);
    try t.expectEqual(@as(u64, 1), stats.created);
    try t.expectEqual(stats.created, stats.released);
}
test "nonconsuming aggregate field reads preserve snapshots and allow later owner transfer" {
    try scenario(t.allocator);
}
test "field reads cannot duplicate resource ownership or result obligations" {
    try reject("resource File: filesystem; struct Wrap { file: File } fn f(w: Wrap) -> i64 { discard read_field(w, file); return 0; } fn main() -> i64 { return 0; }", "E_FIELD_COPY");
    try reject("result R { ok: i64, err: i64 } struct Wrap { pending: R, code: i64 } fn f(w: Wrap) -> i64 { acknowledge read_field(w, pending); return 0; } fn main() -> i64 { return 0; }", "E_FIELD_COPY");
    try reject("resource File: filesystem; struct Wrap { file: File, code: i64 } fn f(w: Wrap) -> i64 { discard w; return read_field(w, code); } fn main() -> i64 { return 0; }", "E_OWNED_CONSUMED");
}
test "inspecting metadata never satisfies a pending result handling obligation" {
    const source = "result R { ok: i64, err: i64 } struct Wrap { pending: R, code: i64 } fn f(w: Wrap) -> i64 { return read_field(w, code); } fn main() -> i64 { return 0; }";
    var c = try language.Compilation.init(t.allocator, "obligation.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expect(std.mem.startsWith(u8, c.diagnostics.items[0].code, "E_RESULT_"));
}
test "field reads respect shared and exclusive access on ordinary records" {
    const source = "struct Meta { code: i64 } fn main() -> i64 { let meta = new Meta { code: 7 }; borrow meta as view { discard read_ref(view); return read_field(meta, code); } }";
    var c = try language.Compilation.init(t.allocator, "borrow.my", source);
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try c.execute(t.allocator)).value);
    try reject("struct Meta { code: i64 } fn main() -> i64 { let mut meta = new Meta { code: 7 }; borrow mut meta as view { discard read_ref(view); return read_field(meta, code); } }", "E_BORROW_CONFLICT");
    try reject("struct Meta { code: i64 } fn f(meta: &Meta) -> i64 { return read_field(meta, code); } fn main() -> i64 { return 0; }", "E_TYPE");
}
test "field read snapshots and ownership survive every allocation failure" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
test "emission rejects forged field output ownership or out of bounds indices" {
    var c = try language.Compilation.init(t.allocator, "fields.my", snapshots);
    defer c.deinit();
    try c.emit();
    const instruction = try @import("instruction_test.zig").find(@constCast(c.code.?.functions[0].scope.instructions), .read_field);
    const original = instruction.*;
    instruction.op.read_field.field = std.math.maxInt(usize);
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    instruction.* = original;
    instruction.op.read_field.output = .i64;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    instruction.* = original;
}
test "duplicate discovery retains selected field and local owner identities" {
    const source = "struct Meta { first: i64, second: i64 } fn a(m: Meta) -> i64 { return read_field(m, " ++
        "first); } fn b(meta: Meta) -> i64 { return read_field(meta, first); } fn c(meta: " ++
        "Meta) -> i64 { return read_field(meta, second); } fn main() -> i64 { return 0; }";
    var c = try language.Compilation.init(t.allocator, "duplicates.my", source);
    defer c.deinit();
    try c.check();
    var analysis = try language.duplicates.discover(t.allocator, c.program.?, .{ .min_nodes = 1 });
    defer analysis.deinit();
    try t.expectEqual(@as(usize, 1), analysis.groups.len);
    try t.expectEqual(@as(usize, 2), analysis.groups[0].members.len);
}

test "direct field reads account for source fields in complete conversions" {
    const source = "struct Source { a: i64, b: i64 } struct Dest { a: i64 } conversion fn convert(src: " ++
        "Source) -> Dest { discard src.b; return new Dest { a: read_field(src, a) }; } fn " ++
        "main() -> i64 { return convert(new Source { a: 7, b: 9 }).a; }";
    var c = try language.Compilation.init(t.allocator, "conversion.my", source);
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try c.execute(t.allocator)).value);
    try reject("struct Source { a: i64, b: i64 } struct Dest { a: i64 } conversion fn convert(src: Source) -> Dest { return new Dest { a: read_field(src, a) }; } fn main() -> i64 { return 0; }", "E_INCOMPLETE_CONVERSION");
}
