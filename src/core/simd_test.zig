//! `Simd[T, N]` in the new core: one LLVM vector per value, elementwise instructions on it, lane
//! reads as `extractelement`, and no call boundary that spills it to memory.
const std = @import("std");
const support = @import("test_support.zig");

const vector_source =
    \\func blend(a: Simd[float, 8], b: Simd[float, 8]) -> Simd[float, 8]:
    \\    return a + b * b
    \\func lane(v: Simd[float, 4], k: int) -> float:
    \\    return v[k]
    \\func main() -> int:
    \\    const v = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])
    \\    const eight = blend(Simd[float, 8]([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]), Simd[float, 8]([0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]))
    \\    const mask: Simd[bool, 4] = v < v
    \\    if mask[0] or eight[7] < 0.0:
    \\        return 1
    \\    return int(lane(-v, 2))
;

test "Simd values lower to LLVM vectors that stay in SSA and cross calls in registers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), vector_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "<8 x double>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "fadd <8 x double>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "fmul <8 x double>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "fneg <4 x double>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "extractelement <4 x double>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "fcmp olt <4 x double>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "insertelement <4 x double>") != null);
}

test "Simd lanes of a mask are spilled one by one, never as a bit-packed vector store" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), vector_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "store <4 x i1>") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "<4 x i1>") != null);
}

test "Simd operators outside their lanes and vector-scalar mixes are refused with a named rule" {
    const language = @import("selka");
    const refused = [_][]const u8{
        "func main() -> int:\n    const m = Simd[bool, 4]([True, False, True, False])\n    const w = m + m\n    return 0\n",
        "func main() -> int:\n    const v = Simd[float, 3]([1.0, 2.0, 3.0])\n    return 0\n",
        "func main() -> int:\n    const v = Simd[float, 2]([1.0, 2.0])\n    const w = v + 1.0\n    return 0\n",
        "func main() -> int:\n    const v = Simd[int, 4]([1, 2, 3, 4])\n    const w = v / v\n    return 0\n",
        "func main() -> int:\n    const v = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])\n    const w = wrapping_add(v, v)\n    return 0\n",
    };
    const codes = [_][]const u8{ "E_SIMD_LANE", "E_SIMD_LENGTH", "E_TYPE", "E_SIMD_OPERATOR", "E_SIMD_LANE" };
    for (refused, codes) |source, code| {
        var compilation = try language.Compilation.init(std.testing.allocator, "refused.selka", source);
        defer compilation.deinit();
        try std.testing.expectError(error.SourceError, compilation.check());
        try std.testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
    }
}

const integer_source =
    \\func lanes(a: Simd[int, 4], b: Simd[int, 4]) -> Simd[int, 4]:
    \\    return a + b * b
    \\func compare_bytes(a: Simd[u8, 4], b: Simd[u8, 4]) -> Simd[bool, 4]:
    \\    return a + b < a
    \\func main() -> int:
    \\    const v = Simd[int, 4]([1, 2, 3, 4])
    \\    const wrapped = wrapping_add(v, v)
    \\    const negated = -v
    \\    const masked = bit_and(v, wrapped)
    \\    const small: Simd[bool, 4] = compare_bytes(Simd[u8, 4]([1, 2, 3, 4]), Simd[u8, 4]([1, 2, 3, 4]))
    \\    if small[0]:
    \\        return 1
    \\    return int(lanes(masked, negated)[3])
;

test "Simd integer lanes lower to checked vector arithmetic, wrapping and bit operators, and unsigned mask compares" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), integer_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "@llvm.sadd.with.overflow.v4i64(<4 x i64>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "@llvm.smul.with.overflow.v4i64(<4 x i64>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "@llvm.ssub.with.overflow.v4i64(<4 x i64> zeroinitializer, <4 x i64>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "@llvm.uadd.with.overflow.v4i8(<4 x i8>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= add <4 x i64>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= and <4 x i64>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= icmp ult <4 x i8>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "@llvm.vector.reduce.or.v4i1(<4 x i1>") != null);
}

test "simd lane operations lower to one vector select, a lane fma and ordered lane folds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\import simd
        \\
        \\func main() -> int:
        \\    const a = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])
        \\    const b = Simd[float, 4]([0.5, 0.5, 0.5, 0.5])
        \\    const picked = simd.select(a < b, a, b)
        \\    const fused = simd.fma(a, b, picked)
        \\    return int(simd.sum(fused) + simd.max(a))
    ;
    const llvm = try support.llvmText(arena.allocator(), source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "select <4 x i1>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call <4 x double> @llvm.fma.v4f64(") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "extractelement <4 x double>") != null);
}

test "simd lane operations refuse fused multiply-add on integer lanes, select on a value that is not a mask, and a literal outside the lane type" {
    const refused = [_][]const u8{
        "import simd\n\nfunc main() -> int:\n    const a = Simd[int, 2]([1, 2])\n    const r = simd.fma(a, a, a)\n    return 0\n",
        "import simd\n\nfunc main() -> int:\n    const a = Simd[float, 2]([1.0, 2.0])\n    const r = simd.select(a, a, a)\n    return 0\n",
        "import simd\n\nfunc main() -> int:\n    const v: Simd[u8, 16] = simd.splat(300)\n    return 0\n",
    };
    const codes = [_][]const u8{ "E_SIMD_LANE", "E_SIMD_ARGUMENT", "E_TYPE" };
    for (refused, codes) |source, code| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const checked = try support.checkSource(arena.allocator(), source);
        try std.testing.expect(!checked.passed);
        try std.testing.expectEqualStrings(code, checked.diagnostics[0].code);
    }
}

const list_element_source =
    \\func first(xs: Simd[float, 4][]) -> Simd[float, 4]:
    \\    return xs[0]
    \\func store_first(mut xs: Simd[float, 4][], v: Simd[float, 4]):
    \\    xs[0] = v
    \\func main() -> int:
    \\    mut xs: Simd[float, 4][] = []
    \\    append(mut xs, Simd[float, 4]([1.0, 2.0, 3.0, 4.0]))
    \\    store_first(mut xs, first(xs))
    \\    return 0
;

test "a Simd list element is loaded and stored assuming only 8-byte alignment, since a list buffer is 8-aligned" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.releaseLlvmText(arena.allocator(), list_element_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "load <4 x double>, ptr ") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "store <4 x double> %p1, ptr ") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "align 8, !tbaa") != null);
    try std.testing.expect(!vectorAccessAligned32(llvm));
}

/// Whether a line of `llvm` accesses a vector value assuming 32-byte alignment.
fn vectorAccessAligned32(llvm: []const u8) bool {
    var lines = std.mem.splitScalar(u8, llvm, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "x double>") != null and std.mem.indexOf(u8, line, "align 32") != null) return true;
    }
    return false;
}

const mask_source =
    \\func main() -> int:
    \\    const x = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])
    \\    const lo = Simd[float, 4]([0.0, 0.0, 0.0, 0.0])
    \\    const hi = Simd[float, 4]([2.5, 2.5, 2.5, 2.5])
    \\    const inside: Simd[bool, 4] = (x > lo) and (x < hi)
    \\    const outside: Simd[bool, 4] = not inside
    \\    const either: Simd[bool, 4] = inside or outside
    \\    const flipped = bit_xor(either, inside)
    \\    const flag = not inside[0]
    \\    if flag or flipped[0]:
    \\        return 1
    \\    return 0
;

test "mask logic lowers to lane-by-lane i1 vector operations, and a scalar not stays one i1 xor" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), mask_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= and <4 x i1> ") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= or <4 x i1> ") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= xor <4 x i1> ") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "xor <4 x i1> %") != null and std.mem.indexOf(u8, llvm, "<i1 true, i1 true, i1 true, i1 true>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= xor i1 ") != null);
}

test "mask logic refuses comparisons between masks and not on float lanes, each by its code" {
    const refused = [_][]const u8{
        "func main() -> int:\n    const m = Simd[bool, 2]([True, False])\n    const r = m == m\n    return 0\n",
        "func main() -> int:\n    const v = Simd[float, 2]([1.0, 2.0])\n    const r = not v\n    return 0\n",
    };
    const codes = [_][]const u8{ "E_SIMD_LANE", "E_SIMD_LANE" };
    for (refused, codes) |source, code| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const checked = try support.checkSource(arena.allocator(), source);
        try std.testing.expect(!checked.passed);
        try std.testing.expectEqualStrings(code, checked.diagnostics[0].code);
    }
}

test "a mask refuses a scalar bool with a message that names the splat repair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const checked = try support.checkSource(arena.allocator(), "func main() -> int:\n    const m = Simd[bool, 2]([True, False])\n    const r = m and True\n    return 0\n");
    try std.testing.expect(!checked.passed);
    try std.testing.expectEqualStrings("E_TYPE", checked.diagnostics[0].code);
    try std.testing.expect(std.mem.indexOf(u8, checked.diagnostics[0].message, "splat it with simd.splat") != null);
}

const splat_source =
    \\import simd
    \\func main() -> int:
    \\    const x = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])
    \\    const y: Simd[float, 4] = x - simd.splat(1.0)
    \\    const z: Simd[bool, 4] = simd.splat(2.5) < x
    \\    if z[0]:
    \\        return 1
    \\    return int(y[3])
;

test "a splat operand of a binary operator lowers to the vector operations of its peer's type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), splat_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= fsub <4 x double> ") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= fcmp olt <4 x double> ") != null);
}

test "a bare scalar does not broadcast, and two splats have no type to take" {
    const refused = [_][]const u8{
        "func main() -> int:\n    const v = Simd[float, 2]([1.0, 2.0])\n    const w = v - 1.0\n    return 0\n",
        "import simd\n\nfunc main() -> int:\n    const w = simd.splat(1.0) - simd.splat(2.0)\n    return 0\n",
    };
    const codes = [_][]const u8{ "E_TYPE", "E_SIMD_CONTEXT" };
    for (refused, codes) |source, code| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const checked = try support.checkSource(arena.allocator(), source);
        try std.testing.expect(!checked.passed);
        try std.testing.expectEqualStrings(code, checked.diagnostics[0].code);
    }
}

const sqrt_source =
    \\import simd
    \\func main() -> int:
    \\    const v = Simd[float, 4]([1.0, 4.0, 9.0, 16.0])
    \\    const w = Simd[f32, 4]([1.0f32, 4.0f32, 9.0f32, 16.0f32])
    \\    const r = simd.sqrt(v)
    \\    const s = simd.sqrt(w)
    \\    if r[1] != 2.0 or s[2] != 3.0f32:
    \\        return 1
    \\    return 0
;

test "simd.sqrt lowers to one llvm.sqrt on the lane vector, for float and f32 lanes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), sqrt_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call <4 x double> @llvm.sqrt.v4f64(<4 x double> ") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call <4 x float> @llvm.sqrt.v4f32(<4 x float> ") != null);
}

test "simd.sqrt refuses integer lanes, and math.sqrt on a Simd is refused with the simd.sqrt repair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const integer = try support.checkSource(arena.allocator(), "import simd\n\nfunc main() -> int:\n    const v = Simd[int, 4]([1, 4, 9, 16])\n    const r = simd.sqrt(v)\n    return 0\n");
    try std.testing.expect(!integer.passed);
    try std.testing.expectEqualStrings("E_SIMD_LANE", integer.diagnostics[0].code);
    const math_source = try support.checkSource(arena.allocator(), "import math\n\nfunc main() -> int:\n    const x = Simd[float, 4]([1.0, 4.0, 9.0, 16.0])\n    const r: Simd[float, 4] = math.sqrt(x)\n    return 0\n");
    try std.testing.expect(!math_source.passed);
    try std.testing.expectEqualStrings("E_TYPE", math_source.diagnostics[0].code);
    const fix = math_source.diagnostics[0].provenance.fix;
    try std.testing.expect(fix != null);
    try std.testing.expectEqualStrings("simd.sqrt(x)", fix.?.edit.text);
}

const select_masks_source =
    \\import simd
    \\func main() -> int:
    \\    const a = Simd[bool, 4]([True, False, True, False])
    \\    const b = Simd[bool, 4]([False, False, False, True])
    \\    const c = Simd[bool, 4]([True, True, True, True])
    \\    const mixed: Simd[bool, 4] = simd.select(a, b, c)
    \\    if mixed[0]:
    \\        return 1
    \\    return 0
;

test "simd.select on bool lanes lowers to one i1 vector select" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), select_masks_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= select <4 x i1> ") != null);
}

const minmax_source =
    \\func main() -> int:
    \\    const a = Simd[float, 4]([1.0, 5.0, 3.0, 7.0])
    \\    const b = Simd[float, 4]([2.0, 4.0, 6.0, 1.0])
    \\    const low = min(a, b)
    \\    const high = max(a, b)
    \\    if low[0] != 1.0 or high[1] != 5.0:
    \\        return 1
    \\    return 0
;

test "lane-wise min and max compare and select, never minnum or maxnum" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), minmax_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= fcmp olt <4 x double> ") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= select <4 x i1> ") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "minnum") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "maxnum") == null);
}

test "min and max of two Simd values refuse bool lanes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const checked = try support.checkSource(arena.allocator(), "func main() -> int:\n    const a = Simd[bool, 2]([True, False])\n    const b = min(a, a)\n    return 0\n");
    try std.testing.expect(!checked.passed);
    try std.testing.expectEqualStrings("E_PRELUDE_TYPE", checked.diagnostics[0].code);
}

const lane_convert_source =
    \\func main() -> int:
    \\    const v = Simd[f32, 4]([1.0f32, 2.0f32, 3.0f32, 4.0f32])
    \\    const w: Simd[float, 4] = float(v)
    \\    const n: Simd[f32, 4] = f32(w)
    \\    if n[3] != 4.0f32:
    \\        return 1
    \\    return 0
;

test "float and f32 lane conversions lower to one fpext and one fptrunc on the vector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), lane_convert_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= fpext <4 x float> ") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "= fptrunc <4 x double> ") != null);
}

test "a Simd converts only between its float and f32 lanes; other conversions are refused" {
    const refused = [_][]const u8{
        "func main() -> int:\n    const v = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])\n    const w = float(v)\n    return 0\n",
        "func main() -> int:\n    const v = Simd[f32, 4]([1.0f32, 2.0f32, 3.0f32, 4.0f32])\n    const w = f32(v)\n    return 0\n",
        "func main() -> int:\n    const v = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])\n    const w = int(v)\n    return 0\n",
    };
    for (refused) |source| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const checked = try support.checkSource(arena.allocator(), source);
        try std.testing.expect(!checked.passed);
        try std.testing.expectEqualStrings("E_TYPE", checked.diagnostics[0].code);
    }
}
