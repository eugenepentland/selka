//! Executable backend algebra witnesses, including effects and IEEE exclusions.
const std = @import("std");
const t = std.testing;
const options = @import("test_options");

fn succeeds(argv: []const []const u8) ![]u8 {
    const result = try std.process.run(t.allocator, t.io, .{ .argv = argv });
    defer t.allocator.free(result.stderr);
    errdefer t.allocator.free(result.stdout);
    if (!std.meta.eql(result.term, std.process.Child.Term{ .exited = 0 })) {
        std.debug.print("{s}\n", .{result.stderr});
        return error.TestUnexpectedResult;
    }
    return result.stdout;
}

const il =
    \\export function l $zero(l %x) {
    \\@start
    \\ %a =l mul %x, 0
    \\ %b =l and %x, 0
    \\ %c =l umulh %x, 0
    \\ %d =l umulh %x, 1
    \\ %ab =l or %a, %b
    \\ %cd =l or %c, %d
    \\ %out =l or %ab, %cd
    \\ ret %out
    \\}
    \\export function w $zero_word(w %x) {
    \\@start
    \\ %a =w mul 0, %x
    \\ %b =w and 4294967296, %x
    \\ %c =w umulh %x, 1
    \\ %ab =w or %a, %b
    \\ %out =w or %ab, %c
    \\ ret %out
    \\}
    \\export function l $effect() {
    \\@start
    \\ %x =l call $touch()
    \\ %out =l mul %x, 0
    \\ ret %out
    \\}
    \\export function d $floating(d %x) {
    \\@start
    \\ %out =d mul %x, d_0
    \\ ret %out
    \\}
    \\export function l $ordinary(l %x) {
    \\@start
    \\ %a =l mul %x, 3
    \\ %out =l and %a, 255
    \\ ret %out
    \\}
;

const witness =
    \\#include <stdint.h>
    \\#include <string.h>
    \\extern uint64_t zero(uint64_t), effect(void), ordinary(uint64_t);
    \\extern uint32_t zero_word(uint32_t);
    \\extern double floating(double);
    \\static unsigned effects;
    \\uint64_t touch(void) { ++effects; return UINT64_MAX; }
    \\int main(void) {
    \\    uint64_t values[] = {0, 1, UINT64_MAX, UINT64_C(0x8000000000000000), UINT64_C(0xffffffff00000001)};
    \\    for (unsigned i = 0; i < sizeof(values) / sizeof(values[0]); ++i) {
    \\        uint64_t x = values[i];
    \\        if (zero(x) || zero_word((uint32_t)x) || ordinary(x) != ((x * 3) & 255)) return 1;
    \\    }
    \\    if (effect() || effects != 1) return 2;
    \\    uint64_t bits = UINT64_C(0x7ff8000000000123);
    \\    double nan; memcpy(&nan, &bits, 8);
    \\    double result = floating(nan);
    \\    if (result == result) return 3;
    \\    result = floating(-1.0); memcpy(&bits, &result, 8);
    \\    if (bits != UINT64_C(0x8000000000000000)) return 4;
    \\    return 0;
    \\}
;

// spec: QBE-INTEGER-ANNIHILATOR-1
test "QBE integer annihilators preserve widths effects NaN and signed zero" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "algebra.ssa", .data = il });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "witness.c", .data = witness });
    const input = try temporary.dir.realPathFileAlloc(t.io, "algebra.ssa", t.allocator);
    defer t.allocator.free(input);
    const folder = std.fs.path.dirname(input).?;
    const assembly = try std.fs.path.join(t.allocator, &.{ folder, "algebra.s" });
    defer t.allocator.free(assembly);
    const c = try std.fs.path.join(t.allocator, &.{ folder, "witness.c" });
    defer t.allocator.free(c);
    const binary = try std.fs.path.join(t.allocator, &.{ folder, "witness" });
    defer t.allocator.free(binary);
    t.allocator.free(try succeeds(&.{ options.qbe_path, "-o", assembly, input }));
    const text = try temporary.dir.readFileAlloc(t.io, "algebra.s", t.allocator, .unlimited);
    defer t.allocator.free(text);
    const zero_start = std.mem.indexOf(u8, text, "zero:") orelse return error.TestUnexpectedResult;
    const zero_end = std.mem.indexOfPos(u8, text, zero_start, ".size") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, text[zero_start..zero_end], "mul") == null);
    try t.expect(std.mem.indexOf(u8, text[zero_start..zero_end], "and") == null);
    t.allocator.free(try succeeds(&.{ options.zig_path, "cc", "-O2", c, assembly, "-o", binary }));
    t.allocator.free(try succeeds(&.{binary}));
}
