//! Original emission, backend selection and cache boundaries of native V2.
const std = @import("std");
const policy = @import("runtime_contract").native_variants.Policy;
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const proof = @import("qbe_rc_native_variant.zig");
const t = std.testing;
const source =
    \\union Choice:
    \\    empty,
    \\    number: int,
    \\    values: list[int]
    \\def change(value: Choice) -> Choice:
    \\    result = value
    \\    result = Choice.number(3)
    \\    return result
    \\def main() -> int:
    \\    value = Choice.values([1, 2])
    \\    value = change(value)
    \\    return 0
;

// spec: RC-NATIVE-VARIANT-BACKEND-1
test "RC-NATIVE-VARIANT-BACKEND-1 selects only resolved QBE current producers" {
    const cases = [_]struct { llvm: bool, foreign: bool, expected: policy }{
        .{ .llvm = false, .foreign = false, .expected = .qbe_v2 },
        .{ .llvm = true, .foreign = false, .expected = .original },
        .{ .llvm = false, .foreign = true, .expected = .original },
        .{ .llvm = true, .foreign = true, .expected = .original },
    };
    for (cases) |case| try t.expectEqual(case.expected, policy.forBackend(case.llvm, case.foreign));
    try t.expect(@import("qbe_build_backend.zig").legacyLlvm("/arbitrary/qbe_llvm.py"));
    try t.expect(!@import("qbe_build_backend.zig").legacyLlvm("/arbitrary/qbe"));
}

// spec-case: RC-NATIVE-VARIANT-BACKEND-1
test "RC-NATIVE-VARIANT-BACKEND-1 original policy keeps foreign argv unchanged" {
    const build = @import("qbe_build.zig");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const old = try build.frontendSwitches(arena.allocator(), .{ .drop_debug = false, .step_checks = true, .frame_checks = true });
    try t.expectEqual(@as(usize, 0), old.len);
    const selected = try build.frontendSwitches(arena.allocator(), .{ .drop_debug = false, .step_checks = true, .frame_checks = true, .native_variants = .qbe_v2 });
    try t.expectEqual(@as(usize, 1), selected.len);
    try t.expectEqualStrings("--native-variants=qbe-v2", selected[0]);
    try t.expect(policy.original.flag() == null);
    try t.expectEqualStrings("", policy.original.identity());
    try t.expectEqual(policy.original, policy.parse("original").?);
    try t.expectEqual(policy.qbe_v2, policy.parse("qbe-v2").?);
    try t.expect(policy.parse("unchecked") == null);
}

fn emit(selected: policy) ![]u8 {
    var compilation = try compiler.Compilation.init(t.allocator, "native_policy.my", source);
    defer compilation.deinit();
    return compilation.emitQbeWithOptions(t.allocator, .{ .native_variants = selected });
}

// spec-case: RC-NATIVE-VARIANT-BACKEND-1
test "RC-NATIVE-VARIANT-BACKEND-1 original and default APIs preserve exact IL and metadata" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "native_policy.my", source);
    defer compilation.deinit();
    const default = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(default);
    const original = try emit(.original);
    defer t.allocator.free(original);
    try t.expectEqualStrings(default, original);
    try t.expect(std.mem.indexOf(u8, original, "# RC-NATIVE-VARIANT-1") == null);
    const selected = try emit(.qbe_v2);
    defer t.allocator.free(selected);
    try t.expect(std.mem.indexOf(u8, selected, "# RC-NATIVE-VARIANT-1") != null);
}

// spec-case: RC-NATIVE-VARIANT-BACKEND-1
test "RC-NATIVE-VARIANT-BACKEND-1 GC and counting keep exact original helper streams" {
    const saved = runtime.get();
    defer runtime.set(saved);
    for ([_]runtime.Selection{ .gc, .rc_counting }) |mode| {
        runtime.set(mode);
        const original = try emit(.original);
        defer t.allocator.free(original);
        const selected = try emit(.qbe_v2);
        defer t.allocator.free(selected);
        try t.expectEqualStrings(original, selected);
        try t.expect(std.mem.indexOf(u8, selected, "# RC-NATIVE-VARIANT-1") == null);
    }
}

const State = struct { catalog: shapes.Catalog };
const Cow = struct { rc: ?*State };
const Refusal = struct {
    native_variants: policy = .original,
    layouts: *native.Catalog = undefined,
    cow: ?*Cow = undefined,
    touched: bool = false,

    /// A deliberately observable temporary allocation for the refusal test.
    pub fn temp(self: *Refusal) usize {
        self.touched = true;
        return 0;
    }

    /// A deliberately observable instruction write for the refusal test.
    pub fn print(self: *Refusal, comptime _: []const u8, _: anytype) proof.Error!void {
        self.touched = true;
    }
};

// spec-case: RC-NATIVE-VARIANT-BACKEND-1
test "RC-NATIVE-VARIANT-BACKEND-1 original refuses before undefined catalogs or emission" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var emitter: Refusal = .{};
    const take = .{ .ty = @as(@import("typed.zig").Type, .i64), .source = @as(usize, 0), .destination = @as(usize, 1), .region = @as(usize, 2), .disjoint = false };
    try t.expect(try proof.take(Refusal, &emitter, take) == null);
    try t.expect(try proof.release(Refusal, &emitter, .{ .ty = @as(@import("typed.zig").Type, .i64), .address = @as(usize, 0) }) == null);
    try t.expect(!emitter.touched);
}

// spec-case: RC-NATIVE-VARIANT-BACKEND-1
test "RC-NATIVE-VARIANT-BACKEND-1 module emission config preserves original and partitions enabled" {
    const iface = @import("module_interface.zig");
    const original = try iface.configName(t.allocator, .{ .drop_debug = false, .step_checks = true, .frame_checks = true, .arenas = false });
    defer t.allocator.free(original);
    const selected = try iface.configName(t.allocator, .{ .drop_debug = false, .step_checks = true, .frame_checks = true, .arenas = false, .native_variants = .qbe_v2 });
    defer t.allocator.free(selected);
    try t.expect(!std.mem.eql(u8, original, selected));
    const combined = try std.mem.concat(t.allocator, u8, &.{ original, " native-variant=qbe-v2" });
    defer t.allocator.free(combined);
    try t.expectEqualStrings(combined, selected);
}

// spec-case: RC-NATIVE-VARIANT-BACKEND-1
test "RC-NATIVE-VARIANT-BACKEND-1 first-pass unit key includes enabled policy" {
    const fragments = @import("qbe_fragments.zig");
    var compilation = try compiler.Compilation.init(t.allocator, "native_policy.my", source);
    defer compilation.deinit();
    try compilation.emit();
    var keys = try fragments.Keys.init(t.allocator, compilation.code.?);
    defer keys.deinit();
    const original = try keys.local(0, .{ .step_checks = true, .frame_checks = true, .arenas = false, .entry = false });
    const selected = try keys.local(0, .{ .step_checks = true, .frame_checks = true, .arenas = false, .entry = false, .ownership = .{ .native_variants = .qbe_v2 } });
    try t.expect(!std.mem.eql(u8, &original, &selected));
}

const ProjectSource = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) @import("project.zig").ReadError![]u8 {
        if (!std.mem.eql(u8, path, "native_policy.my")) return error.NotFound;
        return allocator.dupe(u8, "module native_policy\n" ++ source);
    }
};

// spec-case: RC-NATIVE-VARIANT-BACKEND-1
test "RC-NATIVE-VARIANT-BACKEND-1 default selective API retains original lowering" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var project = @import("project.zig").Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = ProjectSource.read }, "native_policy", .{});
    var index = try @import("interfaces.zig").build(&project);
    const Compilation = @import("project_compile.zig").Compilation;
    var compilation = try Compilation.init(&index);
    var default_stats: Compilation.SelectedStats = .{};
    const default = try compilation.emitQbeSelected(t.allocator, &.{"native_policy::change"}, &default_stats);
    defer t.allocator.free(default);
    var original_stats: Compilation.SelectedStats = .{};
    const original = try compilation.emitQbeSelectedWithOptions(t.allocator, &.{"native_policy::change"}, &original_stats, .{});
    defer t.allocator.free(original);
    try t.expectEqualStrings(default, original);
    try t.expectEqualDeep(default_stats, original_stats);
    try t.expect(std.mem.indexOf(u8, default, "# RC-NATIVE-VARIANT-1") == null);
}
