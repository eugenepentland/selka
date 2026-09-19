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
    const manifest = try c.emitQbeWithOptions(a, false, false, true);
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
    const bare = try without.emitQbeWithOptions(a, false, true, false);
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
    const accounted = try with.emitQbeWithOptions(a, false, true, true);
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
    const manifest = try c.emitQbeWithOptions(a, false, true, false);
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, named(parsed.value, "leaf").?.il, "myl_qbe_fail_frame"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, named(parsed.value, "rec").?.il, "myl_qbe_fail_frame"));
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
// spec: QBE-POSITION-1
test "a build without a ceiling stores a position only where a diagnostic reads it" {
    const a = std.testing.allocator;
    var plain = try language.Compilation.init(a, "qbe.my",
        \\def main() -> i64:
        \\    return 7
    );
    defer plain.deinit();
    const elided = try plain.emitQbeWithOptions(a, false, false, true);
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
    const observable = try calls.emitQbeWithOptions(a, false, false, true);
    defer a.free(observable);
    var kept = try std.json.parseFromSlice(Manifest, a, observable, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer kept.deinit();
    try std.testing.expect(std.mem.count(u8, named(kept.value, "main").?.il, "%position") > 0);
    try std.testing.expect(std.mem.count(u8, named(kept.value, "helper").?.il, "%position") > 0);
}
// spec-case: QBE-STEP-ACCOUNTING-1
test "a requested ceiling keeps the exact per-instruction step check" {
    const a = std.testing.allocator;
    var c = try language.Compilation.init(a, "qbe.my",
        \\def main() -> i64:
        \\    return 7
    );
    defer c.deinit();
    const manifest = try c.emitQbeWithOptions(a, false, true, true);
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
        \\    return values[0]
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
    // The head is loaded once and each live root's 24-byte slot is filled in
    // place — previous at +0, traced address at +8, descriptor at +16 — then
    // linked into the heap's chain and restored with one store to the mark.
    try std.testing.expect(std.mem.indexOf(u8, body, "=l add %heap, 16") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=l loadl") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=l add %root0, 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "=l add %root0, 16") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "storel extern $") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "storel %root_mark, ") != null);
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
