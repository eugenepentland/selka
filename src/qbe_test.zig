//! Independent QBE unit boundaries and stable artifact inputs.
const std = @import("std");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const Unit = struct { name: []const u8, symbol: []const u8, il: []const u8 };
const Manifest = struct { version: []const u8, abi: []const u8, functions: []Unit, entry: []const u8 };
fn emitted(a: std.mem.Allocator, input: []const u8) !std.json.Parsed(Manifest) {
    var c = try language.Compilation.init(a, "qbe.my", input);
    defer c.deinit();
    const manifest = try c.emitQbe(a);
    defer a.free(manifest);
    return std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ?Unit {
    for (manifest.functions) |unit| if (std.mem.eql(u8, unit.name, name)) return unit;
    return null;
}
/// Count instruction labels that no branch names. A label the unit defines but
/// never mentions leaves a block boundary behind, which is exactly the cost the
/// fallthrough merge removes.
fn unreferencedInstructionLabels(il: []const u8) usize {
    var unreferenced: usize = 0;
    var lines = std.mem.splitScalar(u8, il, '\n');
    while (lines.next()) |line| {
        if (line.len < 3 or line[0] != '@' or line[1] != 'i') continue;
        if (!allDigits(line[2..])) continue;
        var mentions: usize = 0;
        var index: usize = 0;
        while (std.mem.indexOfPos(u8, il, index, line)) |at| {
            const after = at + line.len;
            if (after >= il.len or !std.ascii.isDigit(il[after])) mentions += 1;
            index = at + line.len;
        }
        if (mentions < 2) unreferenced += 1;
    }
    return unreferenced;
}
fn allDigits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |byte| if (!std.ascii.isDigit(byte)) return false;
    return true;
}
// spec: QBE-1
test "scalar units remain stable across body edits and declaration reorder" {
    var before = try emitted(std.testing.allocator,
        \\def square(x: i64) -> i64:
        \\    return x * x
        \\
        \\
        \\def main() -> i64:
        \\    return square(10)
    );
    defer before.deinit();
    var after = try emitted(std.testing.allocator,
        \\def main() -> i64:
        \\    return square(10)
        \\
        \\
        \\def square(x: i64) -> i64:
        \\    return x * x + 1
    );
    defer after.deinit();
    const caller_before = named(before.value, "main").?;
    const caller_after = named(after.value, "main").?;
    const callee_before = named(before.value, "square").?;
    const callee_after = named(after.value, "square").?;
    try std.testing.expectEqualStrings(before.value.entry, after.value.entry);
    try std.testing.expectEqualStrings(caller_before.il, caller_after.il);
    try std.testing.expectEqualStrings(callee_before.symbol, callee_after.symbol);
    try std.testing.expect(!std.mem.eql(u8, callee_before.il, callee_after.il));
}

test "QBE lowers stack joins loops casts and calls independently" {
    const a = std.testing.allocator;
    var c = try language.Compilation.init(a, "qbe.my",
        \\def twice(x: i64) -> i64:
        \\    return x * 2
        \\
        \\
        \\def main() -> i64:
        \\    x: i64 = 0
        \\    while x < 4:
        \\        x = x + 1
        \\    if x == 4:
        \\        return twice(x)
        \\    return 0
    );
    defer c.deinit();
    const manifest = try c.emitQbe(a);
    defer a.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "jnz") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, " =l mul ") != null);
    try std.testing.expectEqual(@as(i64, 8), (try native.run(&c)).value);
}

fn allocationScenario(a: std.mem.Allocator) !void {
    var c = try language.Compilation.init(a, "qbe.my",
        \\def main() -> i64:
        \\    return 7
    );
    defer c.deinit();
    const manifest = try c.emitQbe(a);
    defer a.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "qbe-units-v1") != null);
}
test "QBE emission releases partial allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

test "QBE bounds ABI stack usage and heap backs large local frames" {
    const typed = @import("typed.zig");
    const bc = @import("bytecode.zig");
    const a = std.testing.allocator;
    const src = try @import("source.zig").Source.init(a, "qbe.my", "");
    defer a.free(src.bytes);
    defer a.free(src.path);
    defer a.free(src.line_starts);
    var sink = @import("diagnostic.zig").Sink{ .allocator = a };
    defer sink.deinit();
    const local = typed.Local{ .name = "x", .declaration = .{ .start = 0, .end = 0 }, .ty = .i64, .mutable = false };
    const locals: [5000]typed.Local = @splat(local);
    const instructions = [_]bc.Instruction{
        .{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 0 } },
        .{ .span = .{ .start = 0, .end = 0 }, .op = .ret },
    };
    const functions = [_]bc.Function{.{ .id = @fromBackingInt(0), .name = "main", .signature = .{ .parameter_count = locals.len }, .scope = .{ .locals = &locals, .instructions = &instructions } }};
    const manifest = try @import("qbe.zig").generate(a, .{ .functions = &functions }, src, &sink);
    defer a.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "l %packed") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "myl_qbe_frame_allocate") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "myl_qbe_frame_release") != null);
}

test "QBE emits direct scalar comparisons wrapping and checked addition" {
    var parsed = try emitted(std.testing.allocator,
        \\def main() -> i64:
        \\    x: i64 = 3
        \\    if x < 8:
        \\        return x + 2
        \\    return 0
    );
    defer parsed.deinit();
    const il = named(parsed.value, "main").?.il;
    try std.testing.expect(std.mem.indexOf(u8, il, "csltl") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, " =l add ") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "myl_qbe_int_binary") == null);
    try std.testing.expect(std.mem.indexOf(u8, il, "myl_qbe_fail_overflow") != null);
}
// spec: QBE-BLOCKS-1
test "QBE falls through straight-line instructions without naming their blocks" {
    var parsed = try emitted(std.testing.allocator,
        \\def main() -> i64:
        \\    return 7
    );
    defer parsed.deinit();
    const il = named(parsed.value, "main").?.il;
    try std.testing.expect(std.mem.indexOf(u8, il, "@i0\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "@i1\n") == null);
    try std.testing.expectEqual(@as(usize, 0), unreferencedInstructionLabels(il));
}
// spec-case: QBE-BLOCKS-1
test "QBE keeps every branch label a loop or conditional reaches" {
    const a = std.testing.allocator;
    var c = try language.Compilation.init(a, "qbe.my",
        \\def main() -> i64:
        \\    total = 0
        \\    index = 0
        \\    while index < 4:
        \\        total = total + index
        \\        index = index + 1
        \\    return total
    );
    defer c.deinit();
    const manifest = try c.emitQbe(a);
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    const il = named(parsed.value, "main").?.il;
    try std.testing.expectEqual(@as(usize, 0), unreferencedInstructionLabels(il));
    try std.testing.expect(std.mem.indexOf(u8, il, "jmp @i") != null);
    try std.testing.expectEqual(@as(i64, 6), (try native.run(&c)).value);
}
// spec: QBE-STEP-ACCOUNTING-1
test "a build with no requested ceiling emits no step check but keeps the position marker" {
    const a = std.testing.allocator;
    var c = try language.Compilation.init(a, "qbe.my",
        \\def main() -> i64:
        \\    total = 0
        \\    index = 0
        \\    while index < 4:
        \\        total = total + index
        \\        index = index + 1
        \\    return total
    );
    defer c.deinit();
    const manifest = try c.emitQbeWithOptions(a, .{ .step_checks = false });
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    const il = named(parsed.value, "main").?.il;
    try std.testing.expect(std.mem.indexOf(u8, il, "@step_limit") == null);
    try std.testing.expect(std.mem.indexOf(u8, il, "%maxsteps") == null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, il, "myl_qbe_fail_step"));
    // Trap traces and `assert` messages read the frame's position, so it stays.
    try std.testing.expect(std.mem.indexOf(u8, il, "%position") != null);
    // The runtime has to refuse a ceiling this build cannot honor, exactly once.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, il, "myl_qbe_require_step_accounting"));
}
// spec: QBE-FRAME-ACCOUNTING-1
test "a build without a frame ceiling omits depth accounting and refuses one at run time" {
    const a = std.testing.allocator;
    const source =
        \\def helper(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\def main() -> i64:
        \\    return helper(41)
    ;
    var without = try language.Compilation.init(a, "qbe.my", source);
    defer without.deinit();
    const bare = try without.emitQbeWithOptions(a, .{ .frame_checks = false });
    defer a.free(bare);
    var parsed = try std.json.parseFromSlice(Manifest, a, bare, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    const body = named(parsed.value, "helper").?.il;
    // No depth counter, no ceiling test, and no floor test either: this body is a
    // leaf, so its caller's floor test already covers its frame.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "%ctx, 56"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "%ctx, 8"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_qbe_fail_frame"));
    // The record itself stays: a trap trace is built from it.
    try std.testing.expect(std.mem.indexOf(u8, body, "%position") != null);
    const entry = named(parsed.value, "main").?.il;
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, entry, "myl_qbe_require_frame_accounting"));

    var with = try language.Compilation.init(a, "qbe.my", source);
    defer with.deinit();
    const accounted = try with.emitQbeWithOptions(a, .{});
    defer a.free(accounted);
    var full = try std.json.parseFromSlice(Manifest, a, accounted, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer full.deinit();
    const guarded = named(full.value, "helper").?.il;
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, guarded, "%ctx, 56"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, named(full.value, "main").?.il, "myl_qbe_require_frame_accounting"));
}
// spec: QBE-FLOOR-GUARD-1
test "a leaf skips the stack-floor guard while a calling function keeps it" {
    const a = std.testing.allocator;
    const source =
        \\def leaf(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\def rec(n: i64) -> i64:
        \\    if n <= 0:
        \\        return 0
        \\    return rec(n - 1)
        \\
        \\
        \\def main() -> i64:
        \\    return rec(leaf(2))
    ;
    var c = try language.Compilation.init(a, "qbe.my", source);
    defer c.deinit();
    // Accounting is off so the floor test is the only user of the frame-failure
    // helper: a leaf's frame is bounded at compile time and its caller proved the
    // headroom, so the guard is redundant; a function that calls may recurse.
    const manifest = try c.emitQbeWithOptions(a, .{ .frame_checks = false });
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, named(parsed.value, "leaf").?.il, "myl_qbe_fail_frame"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, named(parsed.value, "rec").?.il, "myl_qbe_fail_frame"));

    const unaccounted = try c.emitQbeWithOptions(a, .{ .frame_checks = false });
    defer a.free(unaccounted);
    var unaccounted_parsed = try std.json.parseFromSlice(Manifest, a, unaccounted, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer unaccounted_parsed.deinit();
    const unaccounted_rec = named(unaccounted_parsed.value, "rec").?.il;
    const boundary = std.mem.indexOf(u8, unaccounted_rec, "@frameadmit") orelse return error.TestUnexpectedResult;
    const record = std.mem.indexOfPos(u8, unaccounted_rec, boundary, "=l alloc8 32") orelse return error.TestUnexpectedResult;
    const floor = std.mem.indexOfPos(u8, unaccounted_rec, record, "=l cultl") orelse return error.TestUnexpectedResult;
    try std.testing.expect(boundary < record);
    try std.testing.expect(record < floor);
}
// spec: QBE-PROLOGUE-1
test "generated code tests traps directly and omits root machinery it never uses" {
    const a = std.testing.allocator;
    var c = try language.Compilation.init(a, "qbe.my",
        \\def size(b: bytes) -> i64:
        \\    return len(b) + 0
        \\
        \\
        \\def main() -> i64:
        \\    data = b"hello"
        \\    return size(data) + size(b"!")
    );
    defer c.deinit();
    const manifest = try c.emitQbe(a);
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    // Every failure check reads the context field instead of calling a helper.
    try std.testing.expect(std.mem.indexOf(u8, manifest, "myl_qbe_failed") == null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "loadl %trap") != null);
    // `size` cannot allocate and never calls, so it roots nothing and needs no
    // mark, restore or heap pointer. `main`'s only allocatable opcodes are two
    // frozen byte literals and a checked `+`, whose lowered bodies name no
    // allocating callee, so it drops the same machinery while the call site
    // still records its trap.
    const reader = named(parsed.value, "size").?.il;
    try std.testing.expect(std.mem.indexOf(u8, reader, "myl_qbe_root_mark") == null);
    try std.testing.expect(std.mem.indexOf(u8, reader, "storel %root_mark, ") == null);
    try std.testing.expect(std.mem.indexOf(u8, reader, "=l add %heap, ") == null);
    try std.testing.expect(std.mem.indexOf(u8, reader, "myl_qbe_heap") == null);
    const caller = named(parsed.value, "main").?.il;
    try std.testing.expect(std.mem.indexOf(u8, caller, "myl_qbe_root_mark") == null);
    try std.testing.expect(std.mem.indexOf(u8, caller, "=l add %heap, ") == null);
    try std.testing.expect(std.mem.indexOf(u8, caller, "=l add %root") == null);
    try std.testing.expect(std.mem.indexOf(u8, caller, "storel %root_mark, ") == null);
    try std.testing.expect(std.mem.indexOf(u8, caller, "myl_native_list_new") == null);
}
// spec: QBE-SAFEPOINT-1
test "an opcode that can allocate pushes no roots in a variant that cannot" {
    const a = std.testing.allocator;
    var program = try language.Compilation.init(a, "qbe.my",
        \\def scan(b: bytes) -> i64:
        \\    total = 0
        \\    index = 0
        \\    while index < len(b):
        \\        total = total + i64(b[index])
        \\        index = index + 1
        \\    return total
        \\
        \\
        \\def narrow(x: i64) -> i64:
        \\    return i64(u8(x))
        \\
        \\
        \\def main() -> i64:
        \\    return scan(b"hello") + narrow(1)
    );
    defer program.deinit();
    const manifest = try program.emitQbe(a);
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    // Neither `get_index` on bytes nor a widening `cast_integer` can allocate.
    const body = named(parsed.value, "scan").?.il;
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "=l add %root"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_list_get"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_qbe_int_cast"));
    try std.testing.expect(std.mem.indexOf(u8, body, "loadub") != null);
    // A narrowing cast keeps its range check but still names only the trap helper.
    const converted = named(parsed.value, "narrow").?.il;
    try std.testing.expect(std.mem.indexOf(u8, converted, "myl_qbe_fail_cast") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, converted, "myl_qbe_int_cast"));
}
// spec: QBE-ELEMENT-READ-1
test "element reads retain bounds checks while immediate record fields avoid snapshots" {
    const a = std.testing.allocator;
    var program = try language.Compilation.init(a, "qbe.my",
        \\record Pair:
        \\    left: i64
        \\    right: i64
        \\
        \\
        \\def scalar(w: list[i64], i: i64) -> i64:
        \\    return w[i]
        \\
        \\
        \\def narrow(w: list[i16], i: i64) -> i16:
        \\    return w[i]
        \\
        \\
        \\def flags(w: list[bool], i: i64) -> bool:
        \\    return w[i]
        \\
        \\
        \\def wide(w: list[Pair], i: i64) -> i64:
        \\    return w[i].left
        \\
        \\
        \\def main() -> i64:
        \\    return scalar([1, 2], 0) + i64(narrow([3i16], 0)) + wide([Pair(left=4, right=5)], 0)
    );
    defer program.deinit();
    const manifest = try program.emitQbe(a);
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    // A scalar element is addressed from the header's storage word at its own
    // stride and loaded at its own width, with a cold path that reports the
    // already-normalized index; nothing calls the runtime element copy.
    const scalar = named(parsed.value, "scalar").?.il;
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, scalar, "myl_native_list_get"));
    try std.testing.expect(std.mem.indexOf(u8, scalar, "myl_qbe_fail_normalized_index_bounds") != null);
    try std.testing.expect(std.mem.indexOf(u8, scalar, "=l mul %v") != null);
    try std.testing.expect(std.mem.indexOf(u8, scalar, "=l loadl %v") != null);
    const narrow = named(parsed.value, "narrow").?.il;
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, narrow, "myl_native_list_get"));
    try std.testing.expect(std.mem.indexOf(u8, narrow, "=l loadsh %v") != null);
    const booleans = named(parsed.value, "flags").?.il;
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, booleans, "myl_native_list_get"));
    try std.testing.expect(std.mem.indexOf(u8, booleans, "=l loadub %v") != null);
    // The only consumer is a scalar field read, so the checked element address
    // reaches that read directly without materializing the whole Pair.
    const wide = named(parsed.value, "wide").?.il;
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, wide, "myl_native_list_get"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, wide, "blit "));
    try std.testing.expect(std.mem.indexOf(u8, wide, "myl_qbe_fail_normalized_index_bounds") != null);
}

const aggregate_projection_program =
    \\record Inner:
    \\    value: int
    \\    other: int
    \\record Item:
    \\    inner: Inner
    \\    label: bytes
    \\def projected(items: list[Item], index: int) -> int:
    \\    return items[index].inner.value
    \\def label(items: list[Item], index: int) -> bytes:
    \\    return items[index].label
    \\def snapshot(items: list[Item], index: int) -> Item:
    \\    return items[index]
    \\def main() -> int:
    \\    with arena():
    \\        items = [Item(inner=Inner(value=7, other=8), label=b"old")]
    \\        saved = snapshot(items, 0)
    \\        name = label(items, -1)
    \\        items[0] = Item(inner=Inner(value=9, other=10), label=b"new")
    \\        i = 0
    \\        while i < 40:
    \\            items.append(Item(inner=Inner(value=i, other=0), label=b"grown" + b"!"))
    \\            i += 1
    \\        if saved.inner.value != 7 or saved.label != b"old" or name != b"old":
    \\            return 1
    \\        if projected(items, 0) != 9 or projected(items, -1) != 39:
    \\            return 2
    \\        return 42
;

// spec: QBE-AGGREGATE-READ-1
test "aggregate projections load scalars directly while escaping records retain snapshots" {
    var parsed = try emitted(std.testing.allocator, aggregate_projection_program);
    defer parsed.deinit();
    for ([_][]const u8{ "projected", "label" }) |name| {
        const body = named(parsed.value, name).?.il;
        try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_list_get"));
        try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit "));
        try std.testing.expect(std.mem.indexOf(u8, body, "myl_qbe_fail_normalized_index_bounds") != null);
    }
    const snapshot = named(parsed.value, "snapshot").?.il;
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, snapshot, "myl_native_list_get"));
    // The escaping record leaves by value: the function returns an aggregate
    // type, so the return copies the checked element into storage the caller
    // owns. That copy is the snapshot (`QBE-RETFWD-1`); no second one is made
    // in per-pc scratch first. The spec-case below checks the snapshot keeps
    // its value across an element write, growth and collection.
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "export function :") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, snapshot, "%agg"));
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "myl_qbe_fail_normalized_index_bounds") != null);
}

// spec-case: QBE-AGGREGATE-READ-1
test "aggregate projections preserve snapshots and managed fields across mutation growth and GC" {
    var program = try language.Compilation.init(std.testing.allocator, "projection.my", aggregate_projection_program);
    defer program.deinit();
    for ([_]bool{ false, true }) |stress| {
        const result = try native.runWithOptions(&program, .{ .gc_stress = stress });
        try std.testing.expect(!result.trapped());
        try std.testing.expectEqual(@as(i64, 42), result.value);
    }
}

// spec-case: QBE-AGGREGATE-READ-1
test "aggregate projections reject both negative and positive out of bounds indexes" {
    const a = std.testing.allocator;
    for ([_]i64{ -2, 1 }) |index| {
        const text = try std.fmt.allocPrint(
            a,
            "record Pair:\n    left: int\n    right: int\ndef read(items: list[Pair], index: int) -> int:\n    return items[index].left\ndef main() -> int:\n    return read([Pair(left=3, right=4)], {d})\n",
            .{index},
        );
        defer a.free(text);
        var program = try language.Compilation.init(a, "projection-bounds.my", text);
        defer program.deinit();
        const result = try native.runWithOptions(&program, .{ .gc_stress = true });
        try std.testing.expect(result.trapped());
        try std.testing.expectEqualStrings("R_LIST_BOUNDS", result.trap.code);
        try std.testing.expectEqual(@as(u64, 5), result.trap.line);
    }
}
// spec: QBE-POSITION-1
test "a build without a ceiling stores a position only where a diagnostic reads it" {
    const a = std.testing.allocator;
    var plain = try language.Compilation.init(a, "qbe.my",
        \\def main() -> i64:
        \\    return 7
    );
    defer plain.deinit();
    const elided = try plain.emitQbeWithOptions(a, .{ .step_checks = false });
    defer a.free(elided);
    var parsed = try std.json.parseFromSlice(Manifest, a, elided, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    // Nothing here can fail, so nothing records a position.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, named(parsed.value, "main").?.il, "%position"));
    // A call site and an `assert` are observable, so both keep one.
    var calls = try language.Compilation.init(a, "qbe.my",
        \\def helper(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\def main() -> i64:
        \\    assert helper(2) == 4, "sum"
        \\    return 0
    );
    defer calls.deinit();
    const observable = try calls.emitQbeWithOptions(a, .{ .step_checks = false });
    defer a.free(observable);
    var kept = try std.json.parseFromSlice(Manifest, a, observable, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer kept.deinit();
    try std.testing.expect(std.mem.count(u8, named(kept.value, "main").?.il, "%position") > 0);
    try std.testing.expect(std.mem.count(u8, named(kept.value, "helper").?.il, "%position") > 0);
}
// spec: QBE-DECODE-RANGE-1
test "a slice decoded in place lowers to one range decoder" {
    var fused = try emitted(std.testing.allocator,
        \\def lexeme(src: bytes, start: i64, end: i64) -> str:
        \\    match src[start:end].decode():
        \\        case Ok(text):
        \\            return text
        \\        case Err(_):
        \\            return ""
        \\
        \\
        \\def main() -> i64:
        \\    return len(lexeme(b"abc", 0, 2))
    );
    defer fused.deinit();
    const body = named(fused.value, "lexeme").?.il;
    try std.testing.expect(std.mem.indexOf(u8, body, "myl_qbe_bytes_decode_range") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_bytes_slice"));
    // A temporary read anywhere else keeps the slice: the second reader would
    // otherwise observe a byte string the fused form never builds.
    var kept = try emitted(std.testing.allocator,
        \\def late(src: bytes, start: i64, end: i64) -> str:
        \\    part = src[start:end]
        \\    if len(part) == 0:
        \\        return ""
        \\    match part.decode():
        \\        case Ok(text):
        \\            return text
        \\        case Err(_):
        \\            return ""
        \\
        \\
        \\def main() -> i64:
        \\    return len(late(b"abc", 0, 2))
    );
    defer kept.deinit();
    try std.testing.expect(std.mem.count(u8, named(kept.value, "late").?.il, "myl_native_bytes_slice") != 0);
    try std.testing.expect(std.mem.indexOf(u8, named(kept.value, "late").?.il, "myl_qbe_bytes_decode_range") == null);
}
// spec-case: PY-BYTES-FUSED-RANGE-1
test "immediate byte slice and view parses emit only range parsers" {
    var parsed = try emitted(std.testing.allocator,
        \\def parse(src: bytes, start: i64, end: i64) -> i64 noalloc:
        \\    match src[start:end].parse_int():
        \\        case Some(integer):
        \\            match src.view(start, end).parse_float():
        \\                case Some(floating):
        \\                    if floating > 0.0:
        \\                        return integer
        \\                case None:
        \\                    pass
        \\        case None:
        \\            pass
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return parse(b"42", 0, 2)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "parse").?.il;
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, body, "myl_native_bytes_range"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_bytes_slice"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_bytes_view"));
}

test "dictionary view iteration reads values directly by insertion position" {
    var parsed = try emitted(std.testing.allocator,
        \\def values_total(mapping: dict[str, int]) -> int noalloc:
        \\    total = 0
        \\    for value in mapping.values():
        \\        total += value
        \\    return total
        \\
        \\
        \\def items_total(mapping: dict[str, int]) -> int noalloc:
        \\    total = 0
        \\    for key, value in mapping.items():
        \\        _ = key
        \\        total += value
        \\    return total
        \\
        \\
        \\def main() -> int:
        \\    mapping = {"a": 20, "b": 22}
        \\    return values_total(mapping) + items_total(mapping)
    );
    defer parsed.deinit();
    const values = named(parsed.value, "values_total").?.il;
    const items = named(parsed.value, "items_total").?.il;
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, values, "myl_native_dictionary_value_at"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, values, "myl_native_dictionary_key_at"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, values, "myl_native_dictionary_read"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, items, "myl_native_dictionary_value_at"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, items, "myl_native_dictionary_key_at"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, items, "myl_native_dictionary_read"));
}
// spec: QBE-STICKY-1
test "a body that cannot leave a sticky trap carries no test for one" {
    var parsed = try emitted(std.testing.allocator,
        \\def scan(b: bytes) -> i64:
        \\    total = 0
        \\    index = 0
        \\    while index < len(b):
        \\        total = total + b[index]
        \\        index = index + 1
        \\    return total
        \\
        \\
        \\def caller(x: i64) -> i64:
        \\    return scan(b"abc") + x
        \\
        \\
        \\def main() -> i64:
        \\    return caller(1)
    );
    defer parsed.deinit();
    // A bounds check unwinds through `myl_qbe_fail_*` and a widening cast calls
    // nothing, so the scan loop carries no sticky read; a guest call can return
    // with the trap set, so the entry keeps one.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, named(parsed.value, "scan").?.il, "loadl %trap"));
    try std.testing.expect(std.mem.count(u8, named(parsed.value, "main").?.il, "loadl %trap") != 0);
}
// spec: QBE-UNWIND-1
test "the fast protocol drops the per-call sticky test and keeps the trace position" {
    const a = std.testing.allocator;
    const source =
        \\def pick(b: bytes, i: i64) -> int:
        \\    return b[i]
        \\
        \\
        \\def main() -> i64:
        \\    return pick(b"abc", 1)
    ;
    var fast = try language.Compilation.init(a, "qbe.my", source);
    defer fast.deinit();
    const bare = try fast.emitQbeWithOptions(a, .{ .step_checks = false, .frame_checks = false });
    defer a.free(bare);
    var parsed = try std.json.parseFromSlice(Manifest, a, bare, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    const reader = named(parsed.value, "pick").?.il;
    // The bounds check still unwinds through its fail helper, but nothing reads
    // the sticky flag afterwards: that helper leaves through the runtime.
    try std.testing.expect(std.mem.indexOf(u8, reader, "myl_qbe_fail_index_bounds") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, reader, "loadl %trap"));
    const caller = named(parsed.value, "main").?.il;
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, caller, "loadl %trap"));
    // A call site keeps its position: a callee's trace names this pc, and the
    // missing sticky branch no longer marks the body observable by itself.
    try std.testing.expect(std.mem.indexOf(u8, caller, ", %position") != null);
    try std.testing.expect(std.mem.indexOf(u8, caller, "call $myl_f_") != null);
    // An accounting build keeps the flag test, so its trap delivery is unchanged.
    var accounted = try language.Compilation.init(a, "qbe.my", source);
    defer accounted.deinit();
    const full = try accounted.emitQbeWithOptions(a, .{ .step_checks = false });
    defer a.free(full);
    var full_parsed = try std.json.parseFromSlice(Manifest, a, full, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer full_parsed.deinit();
    try std.testing.expect(std.mem.indexOf(u8, named(full_parsed.value, "main").?.il, "loadl %trap") != null);
}
/// The unit named `name` in a manifest emitted from `source` under `policy`.
fn emittedUnder(a: std.mem.Allocator, source: []const u8, policy: language.native_interface.Policy, name: []const u8) ![]u8 {
    var program = try language.Compilation.init(a, "qbe.my", source);
    defer program.deinit();
    const manifest = try program.emitQbeWithOptions(a, policy);
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    return a.dupe(u8, (named(parsed.value, name) orelse return error.TestUnexpectedResult).il);
}
// spec: QBE-NORETURN-1
test "the fast protocol ends each fail helper's path in hlt and accounting keeps the sticky exit" {
    const a = std.testing.allocator;
    const halting_source =
        \\def grow(x: int, step: int) -> int:
        \\    return x + step
        \\
        \\
        \\def poke(xs: mut list[int], at: int) -> None:
        \\    xs[at] = 7
        \\
        \\
        \\def flip(x: int, s: int) -> int:
        \\    return -shift_left(x, s)
        \\
        \\
        \\def main() -> int:
        \\    xs: list[int] = [1, 2, 3]
        \\    poke(mut xs, 1)
        \\    return grow(1, flip(2, 1))
    ;
    // Neither accounting: the overflow and the list-bounds failure paths end in
    // `hlt` right after their helper, and no fail call is followed by the jump
    // into the shared exit.
    const fast_grow = try emittedUnder(a, halting_source, .{ .step_checks = false, .frame_checks = false }, "grow");
    defer a.free(fast_grow);
    const fast_poke = try emittedUnder(a, halting_source, .{ .step_checks = false, .frame_checks = false }, "poke");
    defer a.free(fast_poke);
    try std.testing.expect(std.mem.indexOf(u8, fast_grow, "call $myl_qbe_fail_overflow_op(") != null);
    try std.testing.expectEqual(std.mem.count(u8, fast_grow, "call $myl_qbe_fail_"), std.mem.count(u8, fast_grow, "\n hlt\n"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, fast_grow, "jmp @failure"));
    try std.testing.expect(std.mem.indexOf(u8, fast_poke, "myl_qbe_fail_") != null);
    try std.testing.expectEqual(std.mem.count(u8, fast_poke, "call $myl_qbe_fail_"), std.mem.count(u8, fast_poke, "\n hlt\n"));
    // The negation's and the shift's cold blocks call a value helper that
    // always traps there, so they end in `hlt` as well.
    const fast_flip = try emittedUnder(a, halting_source, .{ .step_checks = false, .frame_checks = false }, "flip");
    defer a.free(fast_flip);
    try std.testing.expect(std.mem.indexOf(u8, fast_flip, "call $myl_qbe_int_neg(") != null);
    try std.testing.expect(std.mem.indexOf(u8, fast_flip, "call $myl_qbe_int_binary(") != null);
    try std.testing.expectEqual(std.mem.count(u8, fast_flip, "call $myl_qbe_fail_") + 2, std.mem.count(u8, fast_flip, "\n hlt\n"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, fast_flip, "jmp @failure"));
    // Frame accounting alone keeps the sticky protocol, and with it the return
    // through `@failure` after every helper; so does the fully accounted
    // program a library and the guest-test runner build.
    const framed = try emittedUnder(a, halting_source, .{ .step_checks = false }, "grow");
    defer a.free(framed);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, framed, " hlt"));
    try std.testing.expect(std.mem.indexOf(u8, framed, ")\n jmp @failure\n") != null);
    const accounted = try emittedUnder(a, halting_source, .{}, "poke");
    defer a.free(accounted);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, accounted, " hlt"));
    try std.testing.expect(std.mem.indexOf(u8, accounted, ")\n jmp @failure\n") != null);
}
// spec: QBE-POSITION-2
test "a trap position stores on the cold path and a call site keeps its own" {
    const a = std.testing.allocator;
    var program = try language.Compilation.init(a, "qbe.my",
        \\def pick(b: bytes, i: i64) -> int:
        \\    return b[i]
        \\
        \\
        \\def main() -> i64:
        \\    return pick(b"abc", 1)
    );
    defer program.deinit();
    const manifest = try program.emitQbeWithOptions(a, .{ .step_checks = false });
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    const reader = named(parsed.value, "pick").?.il;
    // The bounds check stores its pc in front of the cold trap call, and the
    // byte read on the common path carries no store of its own.
    try std.testing.expect(std.mem.indexOf(u8, reader, "%position\n call $myl_qbe_fail_index_bounds") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, reader, ", %position"));
    // A call site keeps its store ahead of the call: a callee's trace reads this
    // frame's position when it fails.
    const caller = named(parsed.value, "main").?.il;
    const position = std.mem.indexOf(u8, caller, ", %position") orelse return error.TestUnexpectedResult;
    const site = std.mem.indexOf(u8, caller, "call $myl_f_") orelse return error.TestUnexpectedResult;
    try std.testing.expect(position < site);
}
// spec-case: QBE-STEP-ACCOUNTING-1
test "a requested ceiling keeps the exact per-instruction step check" {
    const a = std.testing.allocator;
    var c = try language.Compilation.init(a, "qbe.my",
        \\def main() -> i64:
        \\    return 7
    );
    defer c.deinit();
    const manifest = try c.emitQbeWithOptions(a, .{});
    defer a.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "@step_limit") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "%maxsteps") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "%position") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "require_step_accounting") == null);
}
test "QBE specializes scalar generic calls" {
    var parsed = try emitted(std.testing.allocator,
        \\def identity[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return identity[i64](2)
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.functions.len);
}
// spec: QBE-PURE-READ-1
test "QBE-PURE-READ-1 a read-only collection probe pushes no roots" {
    var parsed = try emitted(std.testing.allocator,
        \\def probe(counts: dict[str, i64], key: str) -> i64:
        \\    return counts.get(key, 0)
        \\
        \\
        \\def bump(counts: mut dict[str, i64], key: str) -> i64:
        \\    counts[key] = 1
        \\    return len(counts)
        \\
        \\
        \\def main() -> i64:
        \\    counts: dict[str, i64] = {}
        \\    return probe(counts, "k") + bump(mut counts, "k")
    );
    defer parsed.deinit();
    const probe = named(parsed.value, "probe").?.il;
    try std.testing.expect(std.mem.indexOf(u8, probe, "myl_native_dictionary_read(") != null);
    try std.testing.expect(std.mem.indexOf(u8, probe, "myl_qbe_root_mark") == null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, probe, "=l add %root"));
    const bump = named(parsed.value, "bump").?.il;
    try std.testing.expect(std.mem.indexOf(u8, bump, "myl_native_dictionary_length(") != null);
    try std.testing.expect(std.mem.count(u8, bump, "=l add %root") != 0);
}

// spec: QBE-PURECALL-1
test "a call to a function that cannot allocate pushes no roots" {
    const a = std.testing.allocator;
    var program = try language.Compilation.init(a, "qbe.my",
        \\def pure(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\def grow(x: list[i64]) -> i64:
        \\    y = [x[0], 7]
        \\    return len(y)
        \\
        \\
        \\def main() -> i64:
        \\    values = [1, 2, 3]
        \\    return pure(values[0]) + grow(values)
    );
    defer program.deinit();
    const manifest = try program.emitQbe(a);
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    // `pure` reaches no allocation, so its call site roots nothing; `grow`
    // allocates, so its call site still roots the live receiver.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, named(parsed.value, "pure").?.il, "=l add %root"));
    try std.testing.expect(std.mem.count(u8, named(parsed.value, "grow").?.il, "=l add %root") != 0);
    try std.testing.expect(std.mem.count(u8, named(parsed.value, "main").?.il, "=l add %root") != 0);
}
// spec: QBE-ROOTINLINE-1
test "roots are linked and restored with inline stores" {
    const a = std.testing.allocator;
    var program = try language.Compilation.init(a, "qbe.my",
        \\def grow(n: i64) -> list[i64]:
        \\    return [n, n + 1]
        \\
        \\
        \\def main() -> i64:
        \\    values = grow(1)
        \\    more = grow(2)
        \\    return values[0] + more[0]
    );
    defer program.deinit();
    const manifest = try program.emitQbe(a);
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    // No generated call site names the runtime root helpers any more.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_root_push"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_qbe_root_restore"));
    // The head is loaded once and each live root's four-word slot is filled in
    // place — previous at +0, traced address at +8, descriptor at +16 — then
    // linked into the heap's chain and restored with one store to the mark.
    try std.testing.expect(std.mem.indexOf(u8, body, "=l add %heap, 16") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=l loadl") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=l add %root0, 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=l add %root0, 16") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "storel extern $") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "storel %root_mark, ") != null);
}
// spec: QBE-ROOTS-2
test "a scalar root is traced through a value copy, not the slot it came from" {
    const a = std.testing.allocator;
    var program = try language.Compilation.init(a, "qbe.my",
        \\def grow(n: i64) -> list[i64]:
        \\    return [n, n + 1]
        \\
        \\
        \\def main() -> i64:
        \\    values = grow(1)
        \\    more = grow(2)
        \\    return values[0] + more[0]
    );
    defer program.deinit();
    const manifest = try program.emitQbe(a);
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    // A root record is four words and a scalar root's traced address is the
    // fourth: the value is loaded out of its slot and copied into the record,
    // and the slot itself is never stored into.
    try std.testing.expect(std.mem.indexOf(u8, body, "=l alloc8 32") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=l add %root0, 24") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "storel %l0, %v"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "storel %s0, %v"));
    // Clearing a traced one-word local is a store, not an address-taking
    // `memset` call.
    try std.testing.expect(std.mem.indexOf(u8, body, "storel 0, %l0") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "memset(l %l"));
}
// spec: QBE-FRAMES-1
test "a guest function links its own frame record instead of calling enter and leave" {
    var parsed = try emitted(std.testing.allocator,
        \\def helper() -> i64:
        \\    return 1
        \\
        \\
        \\def main() -> i64:
        \\    return helper()
    );
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    // The frame is a record in the native stack: no enter/leave runtime calls,
    // but the metadata pointer is stored and the cold frame trap is reachable.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_qbe_enter_at_sized"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_qbe_leave"));
    try std.testing.expect(std.mem.indexOf(u8, body, "_meta, %v") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "myl_qbe_fail_frame") != null);
}
// spec: QBE-PROMOTE-1
test "scalar slots are declared in the entry block so QBE can promote them" {
    var parsed = try emitted(std.testing.allocator,
        \\def add(a: i64, b: i64) -> i64:
        \\    return a + b
        \\
        \\
        \\def main() -> i64:
        \\    return add(2, 3)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "add").?.il;
    const declaration = std.mem.indexOf(u8, body, " %l0 =l alloc8") orelse return error.TestUnexpectedResult;
    const protocol = std.mem.indexOf(u8, body, "@frameadmit") orelse return error.TestUnexpectedResult;
    // QBE's slot promotion only scans the entry block, so the scalar slots are
    // declared before the frame protocol's first label.
    try std.testing.expect(declaration < protocol);
}
// spec-case: QBE-FRAMES-1
test "fixed aggregate scratch is inside the physical stack-floor check" {
    var parsed = try emitted(std.testing.allocator,
        \\record Pair:
        \\    left: i64
        \\    right: i64
        \\
        \\
        \\def adjust(value: Pair) -> Pair:
        \\    return Pair(left=value.left + 1, right=value.right)
        \\
        \\
        \\def main() -> i64:
        \\    value = adjust(Pair(left=1, right=2))
        \\    return value.left + value.right
    );
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    const scratch = std.mem.indexOf(u8, body, " %agg") orelse return error.TestUnexpectedResult;
    const frame_boundary = std.mem.indexOf(u8, body, "@frameadmit") orelse return error.TestUnexpectedResult;
    const record = std.mem.indexOfPos(u8, body, frame_boundary, "=l alloc8 32") orelse return error.TestUnexpectedResult;
    const floor_probe = std.mem.indexOf(u8, body, "=l cultl") orelse return error.TestUnexpectedResult;
    const admitted = std.mem.indexOf(u8, body, "@stackadmit") orelse return error.TestUnexpectedResult;
    // The guard compares the frame record allocated below every fixed slot.
    // Scratch after this branch would evade the physical-stack accounting.
    try std.testing.expect(scratch < frame_boundary);
    try std.testing.expect(frame_boundary < record);
    try std.testing.expect(record < floor_probe);
    try std.testing.expect(floor_probe < admitted);
}

// spec-case: QBE-FRAMES-1
test "loop scratch has one fixed slot while managed allocation stays in the loop" {
    var parsed = try emitted(std.testing.allocator,
        \\record Pair:
        \\    left: i64
        \\    right: i64
        \\
        \\
        \\def step(value: i64) -> i64:
        \\    return value + 1
        \\
        \\
        \\def main() -> i64:
        \\    index: i64 = 0
        \\    value = Pair(left=0, right=1)
        \\    while index < 3:
        \\        value = Pair(left=value.left + value.right, right=value.left)
        \\        items = [index]
        \\        index = step(index + len(items) - 1)
        \\    return value.left
    );
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    const admitted = std.mem.indexOf(u8, body, "@stackadmit") orelse return error.TestUnexpectedResult;
    const loop_allocation = std.mem.indexOf(u8, body, "call $myl_native_list_new") orelse return error.TestUnexpectedResult;
    // Per-pc aggregate buffers are allocated once for the function, even when
    // their instruction is in a loop. The managed list allocation remains at
    // its instruction and therefore still executes on every iteration.
    try std.testing.expect(std.mem.count(u8, body, " %agg") != 0);
    try std.testing.expect(loop_allocation > admitted);
    try std.testing.expect(std.mem.indexOf(u8, body[admitted..loop_allocation], "jnz") != null);
    try std.testing.expect(std.mem.indexOf(u8, body[loop_allocation..], "jmp @i") != null);
}

// spec-case: QBE-FRAMES-1
test "zero-length aggregate scratch retains later allocation semantics" {
    var parsed = try emitted(std.testing.allocator,
        \\record Item:
        \\    value: i64
        \\
        \\
        \\def count(items: [0]Item) -> u64:
        \\    _ = items
        \\    return 0u64
        \\
        \\
        \\def main() -> i64:
        \\    return i64(count([]))
    );
    defer parsed.deinit();
    const body = named(parsed.value, "count").?.il;
    const boundary = std.mem.indexOf(u8, body, "@frameadmit") orelse return error.TestUnexpectedResult;
    const scratch = std.mem.indexOf(u8, body, "%agg0 =l alloc8 8") orelse return error.TestUnexpectedResult;
    try std.testing.expect(scratch > boundary);
    try std.testing.expect(std.mem.indexOf(u8, body, "blit %l0, %agg0, 0") != null);
}

// spec-case: QBE-FLOOR-GUARD-1
test "large fixed scratch recursion reaches a structured frame trap" {
    const a = std.testing.allocator;
    var source: std.Io.Writer.Allocating = .init(a);
    defer source.deinit();
    try source.writer.writeAll(
        \\record Pair:
        \\    left: i64
        \\    right: i64
        \\
        \\
        \\def descend(depth: i64, value: Pair) -> i64:
        \\
    );
    // Keep this just below the native-frame cutoff. Every assignment needs its
    // own per-pc aggregate buffers and the final value keeps the chain live.
    for (0..60) |_| try source.writer.writeAll("    value = Pair(left=value.left + 1, right=value.right)\n");
    try source.writer.writeAll(
        \\    if depth == 0:
        \\        return value.left
        \\    return descend(depth - 1, value)
        \\
        \\
        \\def main() -> i64:
        \\    return descend(20, Pair(left=0, right=1))
    );
    var compilation = try language.Compilation.init(a, "large-frame.my", source.written());
    defer compilation.deinit();
    const manifest = try compilation.emitQbe(a);
    defer a.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "myl_qbe_frame_allocate") == null);
    const outcome = try native.runWithOptions(&compilation, .{ .max_frames = 4, .max_steps = 100000 });
    try std.testing.expect(outcome.trapped());
    try std.testing.expectEqualStrings("R_FRAME_LIMIT", outcome.trap.code);
    try std.testing.expect(outcome.trap.frames.len != 0);
}
// spec: QBE-FLOAT-ENV-1
test "float arithmetic lowers without a per-operation environment check" {
    var parsed = try emitted(std.testing.allocator,
        \\def main() -> int:
        \\    a = 1.5
        \\    b = 2.5
        \\    c = a + b
        \\    d = c * a
        \\    e = d - b
        \\    f = e / a
        \\    g = sqrt(a)
        \\    if f > g:
        \\        return 1
        \\    return 0
    );
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    // The environment is verified once at context start-up, not per operation.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_qbe_float_check"));
    // The arithmetic is still inline, and the unary helper still carries the
    // intrinsics and conversions, so only the guard disappeared.
    try std.testing.expect(std.mem.indexOf(u8, body, "=d add %v") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=d mul %v") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=d sub %v") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=d div %v") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "myl_qbe_float_unary") != null);
}
// spec: FLOAT-NAN-OBSERVED-1
test "a float result is the bare IEEE operation with no NaN canonicalization" {
    var parsed = try emitted(std.testing.allocator,
        \\def main() -> int:
        \\    a = 1.5
        \\    b = 2.5
        \\    c = a * b
        \\    d = c + a
        \\    e = d - b
        \\    f = e / a
        \\    if f > b:
        \\        return 1
        \\    return 0
    );
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    // Each operation is the arithmetic and the cast back to its bit word: no
    // unordered self-compare, no branch and no out-of-line call beside it, so
    // nothing in a float loop can write memory or needs a source position.
    try std.testing.expect(std.mem.indexOf(u8, body, "=d mul %v") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=d add %v") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=d sub %v") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=d div %v") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "cuod") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "float_canonical") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "9221120237041090560") == null);
}
// spec-case: QBE-FLOAT-ENV-1
test "a C FFI call boundary re-verifies the floating environment" {
    var parsed = try emitted(std.testing.allocator,
        \\extern def foreign_scale(host: Host, x: float) -> float effects(host)
        \\
        \\
        \\def main(host: Host) -> int:
        \\    value = foreign_scale(host, 1.5)
        \\    return int(value)
    );
    defer parsed.deinit();
    const wrapper = named(parsed.value, "foreign_scale").?.il;
    const call = std.mem.indexOf(u8, wrapper, "call $foreign_scale(").?;
    const check = std.mem.indexOf(u8, wrapper, "myl_qbe_float_check").?;
    try std.testing.expect(check > call);
}

// spec: QBE-INTOPS-2
test "QBE checks a constant increment against its bound instead of the general sign test" {
    var parsed = try emitted(std.testing.allocator,
        \\def bump(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\def main() -> i64:
        \\    return bump(1)
    );
    defer parsed.deinit();
    const il = named(parsed.value, "bump").?.il;
    try std.testing.expect(std.mem.indexOf(u8, il, "9223372036854775806") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, " =l xor ") == null);
}

// spec-case: PY-BYTES-5
test "PY-BYTES-5 find_any lowers to one native byte-set search and no guest scan" {
    var parsed = try emitted(std.testing.allocator,
        \\def scan(src: bytes, start: i64) -> i64:
        \\    return src.find_any(b",;", start)
        \\
        \\
        \\def main() -> i64:
        \\    return scan(b"a,b;c", 0)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "scan").?.il;
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "myl_native_bytes_find_any("));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_bytes_find("));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "=w call $myl_native_bytes_has_byte("));
}

// spec: QBE-BUFFER-APPEND-1
test "QBE-BUFFER-APPEND-1 a byte-buffer append lowers its fitting path inline and roots only the grow call" {
    var parsed = try emitted(std.testing.allocator,
        \\def build(n: i64) -> i64:
        \\    empty: list[i64] = []
        \\    buffer = byte_buffer(empty)
        \\    piece = b"mylang!\n"
        \\    for i in range(n):
        \\        _ = buffer.append_range(piece, 0, 8)
        \\    _ = buffer.append_byte(33)
        \\    return len(buffer)
        \\
        \\
        \\def main() -> i64:
        \\    return build(3)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "build").?.il;
    try std.testing.expect(std.mem.indexOf(u8, body, "@buf_fast") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "@byte_fast") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "@buf_refused") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "myl_native_bytes_copy_octets(") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "=w call $myl_native_bytes_buffer_append_range("));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "=w call $myl_native_bytes_buffer_append_byte("));
    try std.testing.expect(std.mem.indexOf(u8, body, "%root0") != null);
}

// spec: QBE-ALIAS-CLASS-1
test "QBE-ALIAS-CLASS-1 a managed receiver and its element storage are marked as memory outside the frame" {
    var parsed = try emitted(std.testing.allocator,
        \\def total(values: list[i64]) -> i64:
        \\    sum = 0
        \\    i = 0
        \\    while i < len(values):
        \\        sum = sum + values[i]
        \\        i = i + 1
        \\    return sum
        \\
        \\
        \\def main() -> i64:
        \\    return total([1, 2, 3])
    );
    defer parsed.deinit();
    const body = named(parsed.value, "total").?.il;
    // Each `len` receiver, the element read's receiver and the storage word
    // that read loads are marked, and nothing else is.
    try std.testing.expectEqual(@as(usize, 6), std.mem.count(u8, body, "myl-obj"));
    // Every marker is its own comment line, which QBE's lexer drops whole, so
    // the QBE backend's assembly is byte-identical with and without them.
    try std.testing.expectEqual(@as(usize, 6), std.mem.count(u8, body, "\n # myl-obj %v"));
}

// spec-case: QBE-ALIAS-CLASS-1
test "QBE-ALIAS-CLASS-1 a function that touches no managed container is marked nowhere" {
    var parsed = try emitted(std.testing.allocator,
        \\def twice(value: i64) -> i64:
        \\    return value + value
        \\
        \\
        \\def main() -> i64:
        \\    return twice(21)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "twice").?.il;
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl-obj"));
}

// spec: QBE-APPEND-FAST-1
test "QBE-APPEND-FAST-1 a list append lowers its fitting path inline and roots only the grow call" {
    var parsed = try emitted(std.testing.allocator,
        \\def build(n: i64) -> i64:
        \\    values: list[i64] = []
        \\    for i in range(n):
        \\        values.append(i)
        \\    return len(values)
        \\
        \\
        \\def main() -> i64:
        \\    return build(3)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "build").?.il;
    try std.testing.expect(std.mem.indexOf(u8, body, "@append_fast") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "cultl") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "=w call $myl_native_list_append_scalar("));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "=w call $myl_native_list_append("));
    try std.testing.expect(std.mem.indexOf(u8, body, "%root0") != null);
}

// spec: QBE-AGGREF-1
test "an aggregate parameter a function only reads crosses by address and is not copied" {
    var parsed = try emitted(std.testing.allocator,
        \\record Pair:
        \\    left: i64
        \\    right: i64
        \\
        \\
        \\def total(pair: Pair) -> i64:
        \\    return pair.left + pair.right
        \\
        \\
        \\def main() -> i64:
        \\    return total(Pair(left=1, right=2))
    );
    defer parsed.deinit();
    const body = named(parsed.value, "total").?.il;
    // The parameter is one address, the entry copies nothing, and the field
    // read follows that address instead of a snapshot of the whole record.
    try std.testing.expect(std.mem.indexOf(u8, body, "(l %ctx, l %a0)") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit %a0"));
    try std.testing.expect(std.mem.indexOf(u8, body, "storel %a0, %l0") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=l loadl %l0") != null);
}

// spec-case: QBE-AGGREF-1
test "an aggregate parameter a function writes keeps the caller's value private" {
    var parsed = try emitted(std.testing.allocator,
        \\record Pair:
        \\    left: i64
        \\    right: i64
        \\
        \\
        \\def bumped(pair: Pair) -> i64:
        \\    pair = Pair(left=pair.left + 1, right=pair.right)
        \\    return pair.left
        \\
        \\
        \\def main() -> i64:
        \\    return bumped(Pair(left=1, right=2))
    );
    defer parsed.deinit();
    const body = named(parsed.value, "bumped").?.il;
    // The body stores into the parameter, so the callee owns a copy of it and
    // the write can never reach the caller's record.
    try std.testing.expect(std.mem.indexOf(u8, body, "(l %ctx, l %a0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "blit %a0, %l0, 16") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "storel %l0, %s") != null);
}

// spec-case: QBE-AGGREF-1
test "an aggregate local the next instruction alone consumes is read from its own slot" {
    var parsed = try emitted(std.testing.allocator,
        \\record Pair:
        \\    left: i64
        \\    right: i64
        \\
        \\
        \\def first(pair: Pair) -> i64:
        \\    held = pair
        \\    return held.left
        \\
        \\
        \\def main() -> i64:
        \\    return first(Pair(left=5, right=6))
    );
    defer parsed.deinit();
    const body = named(parsed.value, "first").?.il;
    // The one field read that follows the load names `held`'s own slot, so no
    // copy of the record is made to read one word out of it.
    try std.testing.expect(std.mem.indexOf(u8, body, "storel %l1, %s0") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit %l1"));
}

// spec-case: QBE-AGGREF-1
test "an aggregate parameter that owns a resource keeps its private copy" {
    var parsed = try emitted(std.testing.allocator,
        \\def opened(value: Result[TextFile, str]) -> bool:
        \\    match value:
        \\        case Ok(_):
        \\            return True
        \\        case Err(_):
        \\            return False
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer parsed.deinit();
    const body = named(parsed.value, "opened").?.il;
    // A value that releases something stays the callee's own copy: the entry
    // copy and the release of that copy are both still here.
    try std.testing.expect(std.mem.indexOf(u8, body, "blit %a0, %l0, ") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "myl_native_owned_drop") != null);
}

// spec-case: QBE-AGGREF-1
test "a call passes an aggregate argument as an address" {
    var parsed = try emitted(std.testing.allocator,
        \\record Pair:
        \\    left: i64
        \\    right: i64
        \\
        \\
        \\def total(pair: Pair) -> i64:
        \\    return pair.left + pair.right
        \\
        \\
        \\def main() -> i64:
        \\    return total(Pair(left=1, right=2))
    );
    defer parsed.deinit();
    const callee = named(parsed.value, "total").?.symbol;
    const caller = named(parsed.value, "main").?.il;
    const needle = try std.fmt.allocPrint(std.testing.allocator, "call ${s}(l %ctx, l %", .{callee});
    defer std.testing.allocator.free(needle);
    try std.testing.expect(std.mem.indexOf(u8, caller, needle) != null);
}

// spec-case: STREAM-BYTES-2
test "STREAM-BYTES-2 a buffer write lowers to the raw byte sink with no snapshot copy" {
    var parsed = try emitted(std.testing.allocator,
        \\def emit(out: Stream) -> i64:
        \\    empty: list[int] = []
        \\    buffer = byte_buffer(empty)
        \\    _ = buffer.append_range(b"head", 0, 4)
        \\    _ = buffer.append_float(2.5)
        \\    return out.write(buffer)
        \\
        \\
        \\def main(out: Stream) -> i64:
        \\    return emit(out)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "emit").?.il;
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "myl_qbe_stream_write_bytes("));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_bytes_copy("));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_bytes_slice("));
}
// spec-case: PY-BYTES-SNAPSHOT-1
test "PY-BYTES-SNAPSHOT-1 converting a buffer publishes a snapshot with no copy call" {
    var parsed = try emitted(std.testing.allocator,
        \\def take() -> bytes:
        \\    empty: list[int] = []
        \\    buffer = byte_buffer(empty)
        \\    _ = buffer.append_range(b"head", 0, 4)
        \\    return bytes(buffer)
        \\
        \\
        \\def main() -> i64:
        \\    return len(take())
    );
    defer parsed.deinit();
    const body = named(parsed.value, "take").?.il;
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "myl_qbe_bytes_snapshot("));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_bytes_copy("));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_qbe_bytes_copy("));
}
// spec: QBE-MATCHPROJ-1
test "QBE-MATCHPROJ a read-only binding names a payload that owns nothing in place" {
    var parsed = try emitted(std.testing.allocator,
        \\union Token:
        \\    pair(first: i64, second: i64),
        \\    empty
        \\
        \\
        \\def first_of(token: Token) -> i64:
        \\    match token:
        \\        case Token.pair(first, _):
        \\            return first
        \\        case Token.empty:
        \\            return 0
        \\
        \\
        \\def main() -> i64:
        \\    return first_of(Token.pair(first=1, second=2))
    );
    defer parsed.deinit();
    const body = named(parsed.value, "first_of").?.il;
    // No payload copy at all: the binding holds the payload's address and the
    // field read is one load through it.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit "));
    try std.testing.expect(std.mem.indexOf(u8, body, "loadl %l1") != null);
}

// spec-case: QBE-MATCHPROJ-1
test "QBE-MATCHPROJ an aggregate payload field is still read through its own address" {
    var parsed = try emitted(std.testing.allocator,
        \\record Span:
        \\    line: i64
        \\    col: i64
        \\
        \\
        \\union Token:
        \\    word(span: Span, kind: i64),
        \\    empty
        \\
        \\
        \\def line_of(token: Token) -> i64:
        \\    match token:
        \\        case Token.word(span, _):
        \\            return span.line
        \\        case Token.empty:
        \\            return 0
        \\
        \\
        \\def main() -> i64:
        \\    return line_of(Token.word(span=Span(line=1, col=2), kind=3))
    );
    defer parsed.deinit();
    const body = named(parsed.value, "line_of").?.il;
    // The 24-byte payload copy is gone. The one remaining copy is the
    // intermediate `span` field read, which belongs to the field projection
    // rather than to the match binding.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "blit "));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "blit %v"));
}

// spec-case: QBE-MATCHPROJ-1
test "QBE-MATCHPROJ a scrutinee the arm writes keeps the payload copy" {
    var parsed = try emitted(std.testing.allocator,
        \\record Span:
        \\    line: i64
        \\    col: i64
        \\
        \\
        \\union Token:
        \\    word(span: Span, kind: i64),
        \\    pair(first: i64, second: i64),
        \\    empty
        \\
        \\
        \\def line_of(token: Token) -> i64:
        \\    result = 0
        \\    match token:
        \\        case Token.word(span, _):
        \\            token = Token.pair(first=50, second=60)
        \\            result = span.line
        \\        case Token.pair(first, _):
        \\            result = first
        \\        case Token.empty:
        \\            result = 0
        \\    return result
        \\
        \\
        \\def main() -> i64:
        \\    return line_of(Token.word(span=Span(line=1, col=2), kind=3))
    );
    defer parsed.deinit();
    const body = named(parsed.value, "line_of").?.il;
    // The local is written, so the binding keeps its copy: the arm reads the
    // value the scrutinee had when the arm was entered.
    try std.testing.expect(std.mem.count(u8, body, "blit ") >= 2);
}

// spec: QBE-ELEMENT-ADDRESS-1
test "an iteration local names its element where it lives" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    a: i64
        \\    c: i64
        \\
        \\
        \\def main() -> i64:
        \\    rows: list[Row] = []
        \\    total = 0
        \\    for row in rows:
        \\        total += row.c
        \\    return total
    );
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    // The loop variable holds the checked element address, so no copy of the
    // sixteen-byte element is made and its slot stays one word.
    try std.testing.expect(std.mem.indexOf(u8, body, "blit ") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "alloc8 16") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=l cultl ") != null);
}
// spec-case: QBE-ELEMENT-ADDRESS-1
test "a scalar element list keeps the value path" {
    var parsed = try emitted(std.testing.allocator,
        \\def main() -> i64:
        \\    values: list[i64] = [1, 2, 3]
        \\    total = 0
        \\    for value in values:
        \\        total += value
        \\    return total
    );
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    // A scalar element is loaded by value, so the address-holding form never
    // applies and the loop still reads the element's own width.
    try std.testing.expect(std.mem.indexOf(u8, body, "myl_qbe_fail_iteration") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=l loadl %v") != null);
}
// spec-case: QBE-ELEMENT-ADDRESS-1
test "an iteration local keeps its copy when a call sits before its last read" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    a: i64
        \\    c: i64
        \\
        \\
        \\def doubled(value: i64) -> i64:
        \\    scratch = [value, value]
        \\    return scratch[1] * 2
        \\
        \\
        \\def main() -> i64:
        \\    rows: list[Row] = []
        \\    total = 0
        \\    for row in rows:
        \\        total += doubled(row.a) + row.c
        \\    return total
    );
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    // The call runs between the store and the variable's last read and can
    // allocate, so the element could move under the address: the loop variable
    // keeps its copy. (A callee that cannot allocate and takes only plain data
    // keeps the borrow instead; see `QBE-ELEMREF-4`.)
    try std.testing.expect(std.mem.indexOf(u8, body, "blit ") != null);
}

// spec: QBE-AGGREF-2
test "QBE-AGGREF-2 a local passed beside another argument is named by its own slot" {
    var parsed = try emitted(std.testing.allocator,
        \\record Point:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\def total(point: Point, extra: i64) -> i64:
        \\    return point.x + point.y + extra
        \\
        \\
        \\def main() -> i64:
        \\    start = Point(x=1, y=2)
        \\    return total(start, 39)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    // The call pushes `39` after the record, so the borrow reaches past that
    // push to the call itself: the record crosses as its own slot's address and
    // is never snapshotted out of the local.
    try std.testing.expect(std.mem.indexOf(u8, body, "storel %l0, %s0") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit %l0,"));
}

// spec: QBE-CTORFWD-1
test "QBE-CTORFWD-1 a constructor assigned to a local writes that local in place" {
    var parsed = try emitted(std.testing.allocator,
        \\record Point:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\def main() -> i64:
        \\    start = Point(x=3, y=4)
        \\    return start.x + start.y
    );
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    // The store immediately after the constructor is the record's destination,
    // so the field stores go through a copy of `%l0` itself instead of the
    // per-pc aggregate scratch: no whole-record copy is emitted, and the
    // scratch declaration forwarding made dead is removed.
    try std.testing.expect(std.mem.indexOf(u8, body, "=l copy %l0") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit "));
    try std.testing.expect(std.mem.indexOf(u8, body, "%agg") == null);
}

// spec-case: QBE-CTORFWD-1
test "QBE-CTORFWD-1 an operand read from the destination keeps the constructor copy" {
    var parsed = try emitted(std.testing.allocator,
        \\record Point:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\record Pair:
        \\    a: Point
        \\    b: Point
        \\
        \\
        \\def main() -> i64:
        \\    p = Pair(a=Point(x=1, y=2), b=Point(x=3, y=4))
        \\    p = Pair(a=p.b, b=p.a)
        \\    return p.a.x + p.b.x
    );
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    // The second constructor's operands name `p`'s own storage, so it keeps the
    // scratch and the copy: filling `p` in place would overwrite the operand its
    // own second field reads. The first constructor is unaffected, so the two
    // field copies of the swap plus the second constructor's whole-record copy
    // are the five that remain.
    try std.testing.expectEqual(@as(usize, 5), std.mem.count(u8, body, "blit "));
    try std.testing.expect(std.mem.indexOf(u8, body, "%agg") != null);
}

// spec: QBE-ARRAYWRITE-1
test "QBE-ARRAYWRITE-1 a replace stored back into its own array writes one element in place" {
    var parsed = try emitted(std.testing.allocator,
        \\def main() -> i64:
        \\    values: [4]i64 = [1, 2, 3, 4]
        \\    values = replace(values, 2, 30)
        \\    return values[2]
    );
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    // The store immediately after the replace names the local the replace read,
    // so the element goes through a copy of `%l0` itself — the second of the
    // two, the first being the literal's own forwarded construction. Neither
    // the copy into the per-pc aggregate scratch nor the copy back out of it is
    // emitted, so the whole function carries no whole-array copy at all and the
    // scratch forwarding made dead is removed.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, body, "=l copy %l0"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit "));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "%agg"));
    // The bounds check against the array's own length is untouched.
    try std.testing.expect(std.mem.indexOf(u8, body, "$myl_qbe_fail_array_bounds") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "cugel") != null);
}

// spec-case: QBE-ARRAYWRITE-1
test "QBE-ARRAYWRITE-1 a replace stored into another local keeps the whole-array copy" {
    var parsed = try emitted(std.testing.allocator,
        \\def main() -> i64:
        \\    values: [4]i64 = [1, 2, 3, 4]
        \\    other: [4]i64 = replace(values, 2, 30)
        \\    return other[2] + values[2]
    );
    defer parsed.deinit();
    const body = named(parsed.value, "main").?.il;
    // `values` keeps its value, so the replace builds the new array in the
    // per-pc scratch and the store copies that scratch into `other`: the two
    // whole-array copies the forwarded spelling removes are both still here.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, body, "blit "));
    try std.testing.expect(std.mem.indexOf(u8, body, "%agg") != null);
}
/// `count` array-literal elements of `1`, each followed by its separator.
fn ones(comptime count: usize) []const u8 {
    comptime {
        @setEvalBranchQuota(100_000);
        var text: []const u8 = "";
        for (0..count) |_| text = text ++ "1, ";
        return text;
    }
}
/// The program `docs/performance.md` times: `kernel` reads one element of a
/// `[n]int` parameter that `main` hands it on every call.
fn peekProgram(comptime n: usize) []const u8 {
    @setEvalBranchQuota(100_000);
    return comptime std.fmt.comptimePrint(
        \\def kernel(values: [{d}]int) -> int:
        \\    return values[0]
        \\
        \\
        \\def main() -> int:
        \\    data: [{d}]int = [{s}1]
        \\    total = 0
        \\    call = 0
        \\    while call < 100000:
        \\        total += kernel(data)
        \\        call += 1
        \\    return total
    , .{ n, n, ones(n - 1) });
}
// spec: QBE-FRAMEFIT-1
test "a callee that only reads a large array parameter keeps a native frame" {
    var parsed = try emitted(std.testing.allocator, peekProgram(1024));
    defer parsed.deinit();
    const body = named(parsed.value, "kernel").?.il;
    // The parameter crosses by address and the element read is one load
    // through it, so no scratch survives and the frame stays on the stack.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_qbe_frame_allocate"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_qbe_frame_release"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "%agg"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit"));
    try std.testing.expect(std.mem.indexOf(u8, body, "loadl") != null);
}
// spec-case: QBE-FRAMEFIT-1
test "a [4096]int parameter keeps the native frame while the local that holds the array is heap-backed" {
    var parsed = try emitted(std.testing.allocator, peekProgram(4096));
    defer parsed.deinit();
    const kernel = named(parsed.value, "kernel").?.il;
    const main = named(parsed.value, "main").?.il;
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, kernel, "myl_qbe_frame_allocate"));
    // `main` owns the 32 KiB array itself, so its measured frame is still over
    // the limit and the second, heap-backed lowering is the one it keeps.
    try std.testing.expect(std.mem.indexOf(u8, main, "myl_qbe_frame_allocate") != null);
    try std.testing.expect(std.mem.indexOf(u8, main, "myl_qbe_frame_release") != null);
}
/// `rot` copies a `[4096]int` parameter into scratch to replace one element
/// and returns the copy, so that scratch survives; `keep` does the same over a
/// `[1024]int`, whose scratch fits the native frame.
const rot_program = rotProgram();
fn rotProgram() []const u8 {
    @setEvalBranchQuota(100_000);
    return comptime std.fmt.comptimePrint(
        \\def rot(values: [4096]int) -> [4096]int:
        \\    return replace(values, 0, 1)
        \\
        \\
        \\def keep(values: [1024]int) -> [1024]int:
        \\    return replace(values, 0, 1)
        \\
        \\
        \\def main() -> int:
        \\    wide: [4096]int = [{s}1]
        \\    narrow: [1024]int = [{s}1]
        \\    turned: [4096]int = rot(wide)
        \\    kept: [1024]int = keep(narrow)
        \\    return turned[0] + kept[0]
    , .{ ones(4095), ones(1023) });
}
// spec-case: QBE-FRAMEFIT-1
test "a frame whose surviving scratch alone exceeds the limit is still heap-backed" {
    var parsed = try emitted(std.testing.allocator, rot_program);
    defer parsed.deinit();
    const rot = named(parsed.value, "rot").?.il;
    const keep = named(parsed.value, "keep").?.il;
    // The copy `replace` makes of a parameter it cannot write in place is real
    // scratch, and 32 KiB of it is over the limit on its own.
    try std.testing.expect(std.mem.indexOf(u8, rot, "%agg") != null);
    try std.testing.expect(std.mem.indexOf(u8, rot, "myl_qbe_frame_allocate") != null);
    try std.testing.expect(std.mem.indexOf(u8, rot, "myl_qbe_frame_release") != null);
    try std.testing.expect(std.mem.indexOf(u8, keep, "%agg") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, keep, "myl_qbe_frame_allocate"));
}
// spec: QBE-AGGREF-9
test "a parameter that crosses by address occupies one word of its callee's frame" {
    var parsed = try emitted(std.testing.allocator, peekProgram(1024));
    defer parsed.deinit();
    const body = named(parsed.value, "kernel").?.il;
    // The slot holds the caller's address, so it is declared as one word and
    // the value's 8 KiB is reserved nowhere in the callee.
    try std.testing.expect(std.mem.indexOf(u8, body, " %l0 =l alloc8 8\n") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "alloc8 8192"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "%frame_memory"));
    try std.testing.expect(std.mem.indexOf(u8, body, " storel %a0, %l0\n") != null);
    // The caller hands over one `l` word too: the same crossing rule decides
    // the argument's ABI type and the word the frame estimate charges for it.
    const caller = named(parsed.value, "main").?.il;
    try std.testing.expect(std.mem.indexOf(u8, caller, "(l %ctx, l %v") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, caller, "(l %ctx, :t"));
}
/// `outer` hands the `[4096]int` parameter it was given straight on to
/// `kernel`, which recurses so the inliner leaves both calls in place.
const relay_program = relayProgram();
fn relayProgram() []const u8 {
    @setEvalBranchQuota(100_000);
    return comptime std.fmt.comptimePrint(
        \\def kernel(values: [4096]int, depth: int) -> int:
        \\    if depth == 0:
        \\        return values[0]
        \\    return kernel(values, depth - 1)
        \\
        \\
        \\def outer(values: [4096]int) -> int:
        \\    return kernel(values, 1) + kernel(values, 2)
        \\
        \\
        \\def main() -> int:
        \\    data: [4096]int = [{s}1]
        \\    return outer(data)
    , .{ones(4095)});
}
// spec-case: QBE-AGGREF-9
test "a caller charges one word of outgoing space for an argument that crosses by address" {
    var parsed = try emitted(std.testing.allocator, relay_program);
    defer parsed.deinit();
    const outer = named(parsed.value, "outer").?.il;
    // `outer` neither holds the array nor copies it: the address it was handed
    // is the address it passes on, so its frame is a few words.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, outer, " call $myl_f_"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, outer, "myl_qbe_frame_allocate"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, outer, "blit"));
    try std.testing.expect(std.mem.indexOf(u8, outer, " %l0 =l alloc8 8\n") != null);
}

// spec-case: QBE-AGGREF-1
test "a list element the loop variable copies is read through its own address" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    a: i64
        \\    b: i64
        \\
        \\
        \\def total(rows: list[Row]) -> i64:
        \\    sum = 0
        \\    for row in rows:
        \\        sum += row.b
        \\    return sum
        \\
        \\
        \\def main() -> i64:
        \\    return total([Row(a=1, b=2)])
    );
    defer parsed.deinit();
    const body = named(parsed.value, "total").?.il;
    // The checked element address reaches the store of the loop variable
    // directly and stays there (QBE-ELEMENT-ADDRESS-1), so neither the per-pc
    // aggregate scratch nor the loop variable's own copy is made.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_list_get"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit "));
    try std.testing.expect(std.mem.indexOf(u8, body, "myl_qbe_fail_normalized_index_bounds") != null);
}

// spec: QBE-CTORREAD-1
test "QBE-CTORREAD-1 a constructor field read out of a local names the local" {
    var parsed = try emitted(std.testing.allocator,
        \\record Point:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\record Pair:
        \\    tag: i64
        \\    left: Point
        \\    right: Point
        \\
        \\
        \\def pack(a: Point, b: Point, tag: i64) -> i64:
        \\    made = Pair(tag=tag, left=a, right=b)
        \\    return made.left.x + made.right.y
        \\
        \\
        \\def main() -> i64:
        \\    return pack(Point(x=1, y=2), Point(x=3, y=4), 5)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "pack").?.il;
    // Both field operands name their own slot, so the only copies left are the
    // two the constructor makes into the record it is building.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, body, "blit "));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "%agg"));
}

// spec: QBE-RETFWD-1
test "QBE-RETFWD-1 an element returned straight back crosses the boundary once" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    a: i64
        \\    b: i64
        \\
        \\
        \\def at(rows: list[Row], index: i64) -> Row:
        \\    return rows[index]
        \\
        \\
        \\def main() -> i64:
        \\    return at([Row(a=1, b=2)], 0).b
    );
    defer parsed.deinit();
    const body = named(parsed.value, "at").?.il;
    // The element address reaches the `ret` directly, so the copy into per-pc
    // scratch and the reload out of it are both gone; the caller's own copy is
    // the only one left and it is made by the return itself.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit "));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "%agg"));
    try std.testing.expect(std.mem.indexOf(u8, body, "myl_qbe_fail_normalized_index_bounds") != null);
}

// spec-case: QBE-RETFWD-1
test "QBE-RETFWD-1 a frame that closes an arena scope keeps the element copy" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    a: i64
        \\    b: i64
        \\
        \\
        \\def at(rows: list[Row], index: i64) -> Row:
        \\    with arena():
        \\        _ = len(rows)
        \\    return rows[index]
        \\
        \\
        \\def main() -> i64:
        \\    return at([Row(a=1, b=2)], 0).b
    );
    defer parsed.deinit();
    const body = named(parsed.value, "at").?.il;
    // The epilogue closes the scope before the result is copied out, so the
    // element is snapshotted while the scope is still open.
    try std.testing.expect(std.mem.indexOf(u8, body, "blit ") != null);
}

// spec: QBE-CALLREF-1
test "QBE-CALLREF-1 a record result the caller only reads stays in the call's buffer" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    a: i64
        \\    b: i64
        \\
        \\
        \\def at(rows: list[Row], index: i64) -> Row:
        \\    return rows[index]
        \\
        \\
        \\def total(rows: list[Row]) -> i64:
        \\    row = at(rows, 0)
        \\    return row.a + row.b
        \\
        \\
        \\def main() -> i64:
        \\    return total([Row(a=1, b=2)])
    );
    defer parsed.deinit();
    const body = named(parsed.value, "total").?.il;
    // `row` holds the address of the call's own result buffer, so the caller
    // makes no copy at all and its slot is one word.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit "));
    try std.testing.expect(std.mem.indexOf(u8, body, " %l1 =l alloc8 8\n") != null);
}

// spec-case: QBE-CALLREF-1
test "QBE-CALLREF-1 a result the body reassigns keeps its own copy" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    a: i64
        \\    b: i64
        \\
        \\
        \\def at(rows: list[Row], index: i64) -> Row:
        \\    return rows[index]
        \\
        \\
        \\def total(rows: list[Row]) -> i64:
        \\    row = at(rows, 0)
        \\    row = Row(a=row.b, b=row.a)
        \\    return row.a + row.b
        \\
        \\
        \\def main() -> i64:
        \\    return total([Row(a=1, b=2)])
    );
    defer parsed.deinit();
    const body = named(parsed.value, "total").?.il;
    // The second store is another write of the same local, so the slot holds
    // the value and the call's result is copied into it.
    try std.testing.expect(std.mem.indexOf(u8, body, "blit ") != null);
}

// spec: QBE-ELEMREF-2
test "QBE-ELEMREF-2 an indexed element local is named in place across branches" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    a: i64
        \\    b: i64
        \\
        \\
        \\def find(rows: list[Row], key: i64) -> i64:
        \\    i = 0
        \\    while i < len(rows):
        \\        row = rows[i]
        \\        if row.a == key:
        \\            return row.b
        \\        i += 1
        \\    return - 1
        \\
        \\
        \\def main() -> i64:
        \\    return find([Row(a=1, b=2)], 1)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "find").?.il;
    // Every instruction the borrow is live across — the field reads, the
    // comparison, the branch and the return — is inert, so the element is
    // never copied out of the list.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit "));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_list_get"));
}

// spec-case: QBE-ELEMREF-2
test "QBE-ELEMREF-2 a temporary reused by two element reads is borrowed for both" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    a: i64
        \\    b: i64
        \\
        \\
        \\def span(rows: list[Row], i: i64, j: i64) -> i64:
        \\    left = rows[i]
        \\    total = left.a + left.b
        \\    left = rows[j]
        \\    return total + left.a + left.b
        \\
        \\
        \\def main() -> i64:
        \\    return span([Row(a=1, b=2), Row(a=3, b=4)], 0, 1)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "span").?.il;
    // Both writes store an element address, so the slot holds an address for
    // the whole function and neither read copies.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit "));
    try std.testing.expect(std.mem.indexOf(u8, body, " %l3 =l alloc8 8\n") != null);
}

// spec-case: QBE-ELEMREF-2
test "QBE-ELEMREF-2 a local one write fills from a copy keeps its value" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    a: i64
        \\    b: i64
        \\
        \\
        \\def span(rows: list[Row], i: i64) -> i64:
        \\    left = rows[i]
        \\    total = left.a
        \\    left = Row(a=9, b=9)
        \\    return total + left.b
        \\
        \\
        \\def main() -> i64:
        \\    return span([Row(a=1, b=2)], 0)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "span").?.il;
    // The constructor's write is not an address, so the slot holds the value
    // and the element read copies into it.
    try std.testing.expect(std.mem.indexOf(u8, body, "blit ") != null);
}

// spec-case: QBE-ELEMREF-2
test "QBE-ELEMREF-2 a borrowed element that traces is never pushed as a root" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    name: str
        \\    count: i64
        \\
        \\
        \\def find(rows: list[Row], key: i64) -> i64:
        \\    i = 0
        \\    while i < len(rows):
        \\        row = rows[i]
        \\        if row.count == key:
        \\            return len(row.name)
        \\        i += 1
        \\    return - 1
        \\
        \\
        \\def main() -> i64:
        \\    return find([Row(name="a", count=1)], 1)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "find").?.il;
    // The element's `str` is reachable through the receiver, and the inert run
    // admits no collection, so the borrow costs neither a copy nor a root.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit "));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "=l add %root"));
}

// spec-case: QBE-ELEMREF-2
test "QBE-ELEMREF-2 a frame that opens an arena scope keeps the element copy" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    a: i64
        \\    b: i64
        \\
        \\
        \\def find(rows: list[Row], key: i64) -> i64:
        \\    with arena():
        \\        _ = len(rows)
        \\    row = rows[0]
        \\    return row.a + key
        \\
        \\
        \\def main() -> i64:
        \\    return find([Row(a=1, b=2)], 1)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "find").?.il;
    // Closing the scope scans every local declared before it through its slot,
    // which a borrowed element's one-word slot cannot answer.
    try std.testing.expect(std.mem.indexOf(u8, body, "blit ") != null);
}

// spec-case: QBE-ELEMREF-2
test "QBE-ELEMREF-2 a call inside the live range keeps the element copy" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    a: i64
        \\    b: i64
        \\
        \\
        \\def grow(rows: mut list[Row]) -> i64:
        \\    rows.append(Row(a=9, b=9))
        \\    return len(rows)
        \\
        \\
        \\def find(rows: mut list[Row]) -> i64:
        \\    row = rows[0]
        \\    _ = grow(mut rows)
        \\    return row.b
        \\
        \\
        \\def main() -> i64:
        \\    rows = [Row(a=1, b=2)]
        \\    return find(mut rows)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "find").?.il;
    // The append can reallocate the backing storage, so the element is
    // snapshotted before the call and `row` keeps the value it read.
    try std.testing.expect(std.mem.indexOf(u8, body, "blit ") != null);
}

// spec: QBE-LISTSET-1
test "QBE-LISTSET-1 a list element write stores through the element address" {
    var parsed = try emitted(std.testing.allocator,
        \\def store(values: mut list[i64], value: i64):
        \\    values[1] = value
        \\
        \\
        \\def main() -> i64:
        \\    values = [1, 2, 3]
        \\    store(mut values, 30)
        \\    return values[1]
    );
    defer parsed.deinit();
    const body = named(parsed.value, "store").?.il;
    // The runtime helper was a bounds test and one `copy_element`; both are
    // emitted here, so nothing calls into the runtime for the write.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_list_set"));
    try std.testing.expect(std.mem.indexOf(u8, body, "cultl") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "myl_qbe_fail_normalized_index_bounds") != null);
    // With no allocating callee left in the write, the frame pushes no root
    // record across it.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "%root0"));
}

// spec-case: QBE-LISTSET-1
test "QBE-LISTSET-1 a record element write over traced elements pushes no root" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    name: str
        \\    count: i64
        \\
        \\
        \\def relabel(rows: mut list[Row], row: Row):
        \\    rows[0] = row
        \\
        \\
        \\def main() -> i64:
        \\    rows = [Row(name="a", count=1)]
        \\    relabel(mut rows, Row(name="b", count=2))
        \\    return rows[0].count
    );
    defer parsed.deinit();
    const body = named(parsed.value, "relabel").?.il;
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "myl_native_list_set"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "%root0"));
    // The element itself lands in the receiver's storage through one copy of
    // its own size, the one the runtime helper used to make.
    try std.testing.expect(std.mem.indexOf(u8, body, "blit ") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, " =l mul ") != null);
}

/// Every lowered unit's text for one emission policy, joined so a test can
/// count guard sites across the whole program in one straight-line assertion.
fn lowered(a: std.mem.Allocator, input: []const u8, policy: language.native_interface.Policy) ![]u8 {
    var c = try language.Compilation.init(a, "qbe.my", input);
    defer c.deinit();
    const manifest = try c.emitQbeWithOptions(a, policy);
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(a);
    for (parsed.value.functions) |unit| try text.appendSlice(a, unit.il);
    return text.toOwnedSlice(a);
}

/// A program reaching every guard class the unchecked policy removes: a checked
/// add and multiply, a narrowing cast, a fixed-array index and a list index,
/// plus an append whose allocation failure the policy keeps.
const unchecked_program =
    \\def scale(xs: list[i64], at: i64, factor: i64) -> u8:
    \\    return u8(xs[at] * factor + 1)
    \\
    \\def main() -> i64:
    \\    fixed: [3]i64 = [1, 2, 3]
    \\    xs: list[i64] = []
    \\    xs.append(fixed[1])
    \\    return i64(scale(xs, 0, 2))
;

// spec: QBE-UNCHECKED-1
test "the unchecked policy emits no overflow cast or bounds guard and no frame record" {
    const a = std.testing.allocator;
    const guarded = try lowered(a, unchecked_program, .{ .step_checks = false, .frame_checks = false });
    defer a.free(guarded);
    const bare = try lowered(a, unchecked_program, .{ .step_checks = false, .frame_checks = false, .checks = false });
    defer a.free(bare);
    // The default unbounded policy carries every guard class and the frame
    // record the position stores are written into.
    try std.testing.expect(std.mem.indexOf(u8, guarded, "myl_qbe_fail_overflow_op") != null);
    try std.testing.expect(std.mem.indexOf(u8, guarded, "myl_qbe_fail_cast") != null);
    try std.testing.expect(std.mem.indexOf(u8, guarded, "myl_qbe_fail_normalized_index_bounds") != null);
    try std.testing.expect(std.mem.indexOf(u8, guarded, "myl_qbe_fail_array_bounds") != null);
    try std.testing.expect(std.mem.indexOf(u8, guarded, ", %position") != null);
    try std.testing.expect(std.mem.indexOf(u8, guarded, "_meta") != null);
    // The unchecked policy carries none of them.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, bare, "myl_qbe_fail_overflow_op"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, bare, "myl_qbe_fail_cast"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, bare, "myl_qbe_fail_index_bounds"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, bare, "myl_qbe_fail_normalized_index_bounds"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, bare, "myl_qbe_fail_array_bounds"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, bare, "%position"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, bare, "_meta"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, bare, "myl_qbe_fail_frame"));
    try std.testing.expect(bare.len < guarded.len);
}

// spec-case: QBE-UNCHECKED-1
test "the unchecked policy keeps allocation failure division by zero and the collector" {
    const a = std.testing.allocator;
    const bare = try lowered(a, unchecked_program, .{ .step_checks = false, .frame_checks = false, .checks = false });
    defer a.free(bare);
    const divide = try lowered(a,
        \\def half(left: i64, right: i64) -> i64:
        \\    return left // right
        \\
        \\def main() -> i64:
        \\    return half(8, 2)
    , .{ .step_checks = false, .frame_checks = false, .checks = false });
    defer a.free(divide);
    // Out of memory must still fail cleanly, so every allocating call keeps its
    // failure test and the collector keeps the heap handle it traces through.
    try std.testing.expect(std.mem.indexOf(u8, bare, "myl_qbe_fail_allocation") != null);
    try std.testing.expect(std.mem.indexOf(u8, bare, "%heap") != null);
    // A zero divisor and a signed `MIN // -1` fault the hardware divider, so
    // both tests stay even here; only their reported detail could be lost.
    try std.testing.expect(std.mem.indexOf(u8, divide, "myl_qbe_fail_division") != null);
    try std.testing.expect(std.mem.indexOf(u8, divide, "myl_qbe_fail_overflow_op") != null);
}

// spec-case: QBE-UNCHECKED-1
test "an unchecked build that was given a ceiling keeps the accounting that enforces it" {
    const a = std.testing.allocator;
    const bounded = try lowered(a, unchecked_program, .{ .checks = false });
    defer a.free(bounded);
    // Step and depth accounting are orthogonal to the value guards: the frame
    // record, the position stores and the step limit survive, while the
    // overflow, cast and bounds guards are gone.
    try std.testing.expect(std.mem.indexOf(u8, bounded, ", %position") != null);
    try std.testing.expect(std.mem.indexOf(u8, bounded, "_meta") != null);
    try std.testing.expect(std.mem.indexOf(u8, bounded, "@step_limit") != null);
    try std.testing.expect(std.mem.indexOf(u8, bounded, "myl_qbe_fail_frame") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, bounded, "myl_qbe_fail_cast"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, bounded, "myl_qbe_fail_overflow_op"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, bounded, "myl_qbe_fail_array_bounds"));
}

/// The number of root records each root push in `il` links, in program order.
/// A push loads the chain head right after computing the heap's root-field
/// address, and each record in it computes its descriptor field once; the push
/// ends at the safepoint's own call or at the next label.
fn rootsPerPush(a: std.mem.Allocator, il: []const u8) ![]usize {
    var counts: std.ArrayList(usize) = .empty;
    errdefer counts.deinit(a);
    var lines = std.mem.splitScalar(u8, il, '\n');
    var open = false;
    var previous: []const u8 = "";
    while (lines.next()) |line| {
        defer previous = line;
        if (std.mem.endsWith(u8, previous, "=l add %heap, 16") and std.mem.indexOf(u8, line, "=l loadl") != null) {
            try counts.append(a, 0);
            open = true;
            continue;
        }
        if (!open) continue;
        if (std.mem.indexOf(u8, line, "call ") != null or (line.len > 0 and line[0] == '@')) {
            open = false;
        } else if (std.mem.indexOf(u8, line, "=l add %root") != null and std.mem.endsWith(u8, line, ", 16")) {
            counts.items[counts.items.len - 1] += 1;
        }
    }
    return counts.toOwnedSlice(a);
}

// spec: QBE-ROOTLIVE-1
test "QBE-ROOTLIVE-1 a safepoint publishes only the locals live across it" {
    const a = std.testing.allocator;
    var parsed = try emitted(a,
        \\def make(n: i64) -> list[i64]:
        \\    return [n, n + 1]
        \\
        \\
        \\def main() -> i64:
        \\    first = make(1)
        \\    second = make(2)
        \\    third = make(len(first))
        \\    return len(second) + len(third)
    );
    defer parsed.deinit();
    const pushes = try rootsPerPush(a, named(parsed.value, "main").?.il);
    defer a.free(pushes);
    // `make(1)` runs before any list exists; `make(2)` runs while `first` is
    // still to be read; `make(len(first))` runs after `first`'s last read and
    // while `second` is still to be read. `third` is never live at a call.
    try std.testing.expectEqualSlices(usize, &.{ 1, 1 }, pushes);
}

// spec-case: QBE-ROOTLIVE-1
test "QBE-ROOTLIVE-1 hidden receiver temporaries die after their read" {
    const a = std.testing.allocator;
    var parsed = try emitted(a,
        \\def fresh(n: i64) -> list[i64]:
        \\    return [n, n]
        \\
        \\
        \\def bump(xs: mut list[i64], n: i64) -> i64:
        \\    total = 0
        \\    i = 0
        \\    while i < n:
        \\        xs[i] = xs[i] + xs[i + 1] + xs[i + 2]
        \\        extra = fresh(i)
        \\        total += xs[i] + extra[1]
        \\        i += 1
        \\    return total
        \\
        \\
        \\def main() -> i64:
        \\    values = [1, 2, 3, 4, 5]
        \\    return bump(mut values, 2)
    );
    defer parsed.deinit();
    const pushes = try rootsPerPush(a, named(parsed.value, "bump").?.il);
    defer a.free(pushes);
    // The one allocating call publishes `xs`, which the loop reads again; the
    // receiver temporaries of the four `xs[...]` expressions before it are
    // dead, and `extra` is written by the call.
    try std.testing.expectEqualSlices(usize, &.{1}, pushes);
}

// spec-case: QBE-ROOTLIVE-1
test "QBE-ROOTLIVE-1 an operand held only on the stack stays published" {
    const a = std.testing.allocator;
    var parsed = try emitted(a,
        \\def make(n: i64) -> list[i64]:
        \\    return [n, n + 1]
        \\
        \\
        \\def pair(left: list[i64], right: list[i64]) -> i64:
        \\    return left[0] + right[1]
        \\
        \\
        \\def main() -> i64:
        \\    return pair(make(1), make(2))
    );
    defer parsed.deinit();
    const pushes = try rootsPerPush(a, named(parsed.value, "main").?.il);
    defer a.free(pushes);
    // The first list lives only in an operand slot while `make(2)` runs; the
    // call to `pair` allocates nothing, so it needs no push.
    try std.testing.expectEqualSlices(usize, &.{1}, pushes);
}

// spec-case: QBE-ROOTLIVE-1
test "QBE-ROOTLIVE-1 a closing arena scope keeps the locals it scans published" {
    const a = std.testing.allocator;
    var parsed = try emitted(a,
        \\def make(n: i64) -> list[i64]:
        \\    return [n, n + 1]
        \\
        \\
        \\def main() -> i64:
        \\    keep = make(1)
        \\    n = 0
        \\    with arena():
        \\        scratch = make(2)
        \\        n = len(scratch)
        \\    return n
    );
    defer parsed.deinit();
    const pushes = try rootsPerPush(a, named(parsed.value, "main").?.il);
    defer a.free(pushes);
    // `keep` is never read again, but closing the scope scans it for a
    // reference into the region, so it is published at the call inside it.
    try std.testing.expectEqualSlices(usize, &.{1}, pushes);
}

// spec-case: QBE-ROOTLIVE-1
test "QBE-ROOTLIVE-1 a value read after a propagating call stays published" {
    const a = std.testing.allocator;
    var parsed = try emitted(a,
        \\def make(n: i64) -> list[i64]:
        \\    return [n, n + 1]
        \\
        \\
        \\def risky(n: i64) -> Result[i64, i64]:
        \\    if n == 0:
        \\        return Err(7)
        \\    return Ok(n)
        \\
        \\
        \\def run(n: i64) -> Result[i64, i64]:
        \\    keep = make(n)
        \\    other = make(n + 1)
        \\    got = risky(len(other))?
        \\    return Ok(got + keep[0])
        \\
        \\
        \\def main() -> i64:
        \\    match run(1):
        \\        case Ok(v):
        \\            return v
        \\        case Err(e):
        \\            return e
    );
    defer parsed.deinit();
    const pushes = try rootsPerPush(a, named(parsed.value, "run").?.il);
    defer a.free(pushes);
    // `keep` is live across the second allocation; `other` is dead after its
    // length is taken, and `risky` cannot allocate, so it needs no push.
    try std.testing.expectEqualSlices(usize, &.{1}, pushes);
}

// spec: QBE-INVOKE-SAFEPOINT-1
test "QBE-INVOKE-SAFEPOINT-1 invoking a function value publishes the live roots" {
    const a = std.testing.allocator;
    var parsed = try emitted(a,
        \\def churn(n: int) -> int:
        \\    ys = [n, n + 1]
        \\    return ys[1]
        \\
        \\
        \\def apply(f: def(int) -> int, n: int) -> int:
        \\    keep = [n, n + 1, n + 2]
        \\    r = f(n)
        \\    return r + keep[2]
        \\
        \\
        \\def main() -> int:
        \\    return apply(churn, 5)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "apply").?.il;
    // The indirect call is preceded by a push of `keep`, the one list the
    // caller reads after it, and followed by the restore.
    const call = std.mem.indexOf(u8, body, " call %").?;
    const pushes = try rootsPerPush(a, body[0..call]);
    defer a.free(pushes);
    try std.testing.expectEqual(@as(usize, 1), pushes[pushes.len - 1]);
    try std.testing.expect(std.mem.indexOf(u8, body[call..], "storel %root_mark, ") != null);
}

// spec: QBE-ELEMREF-3
test "QBE-ELEMREF-3 a second read with a runtime index keeps the borrow" {
    var parsed = try emitted(std.testing.allocator,
        \\record Row:
        \\    a: i64
        \\    b: i64
        \\
        \\
        \\def pick(rows: list[Row], counts: list[i64], i: i64) -> i64:
        \\    row = rows[i]
        \\    return row.a + counts[row.b]
        \\
        \\
        \\def main() -> i64:
        \\    return pick([Row(a=1, b=0)], [5], 0)
    );
    defer parsed.deinit();
    const body = named(parsed.value, "pick").?.il;
    // The negative-index normalization of `counts[row.b]` converts the
    // receiver length with an integer cast, which only traps.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit "));
}

// spec: QBE-ELEMREF-4
test "QBE-ELEMREF-4 a call that cannot reach the receiver keeps the borrow" {
    var parsed = try emitted(std.testing.allocator,
        \\record Vec:
        \\    x: float
        \\    y: float
        \\
        \\
        \\record Ball:
        \\    center: Vec
        \\    radius: float
        \\
        \\
        \\def reach(origin: Vec, ball: Ball) -> float:
        \\    dx = ball.center.x - origin.x
        \\    dy = ball.center.y - origin.y
        \\    return dx * dx + dy * dy - ball.radius
        \\
        \\
        \\def nearest(origin: Vec, balls: list[Ball]) -> i64:
        \\    best = -1
        \\    for k, ball in enumerate(balls):
        \\        if reach(origin, ball) < 0.0:
        \\            best = k
        \\    return best
        \\
        \\
        \\def main() -> i64:
        \\    return nearest(Vec(x=0.0, y=0.0), [Ball(center=Vec(x=0.0, y=0.0), radius=1.0)])
    );
    defer parsed.deinit();
    const body = named(parsed.value, "nearest").?.il;
    // `reach` allocates nothing and takes only plain data, so each ball is
    // handed to it where it lives instead of being copied per iteration.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit "));
}

// spec-case: QBE-ELEMREF-4
test "QBE-ELEMREF-4 a call that takes a traced parameter keeps the copy" {
    var parsed = try emitted(std.testing.allocator,
        \\record Vec:
        \\    x: float
        \\    y: float
        \\
        \\
        \\def reach(origin: Vec, ball: Vec, names: list[str]) -> float:
        \\    return ball.x - origin.x + float(len(names))
        \\
        \\
        \\def nearest(origin: Vec, balls: list[Vec], names: list[str]) -> i64:
        \\    best = -1
        \\    for k, ball in enumerate(balls):
        \\        if reach(origin, ball, names) < 0.0:
        \\            best = k
        \\    return best
        \\
        \\
        \\def main() -> i64:
        \\    return nearest(Vec(x=0.0, y=0.0), [Vec(x=0.0, y=0.0)], ["a"])
    );
    defer parsed.deinit();
    const body = named(parsed.value, "nearest").?.il;
    // `names` could alias the receiver as far as the types say, so the element
    // is snapshotted before the call.
    try std.testing.expect(std.mem.indexOf(u8, body, "blit ") != null);
}
