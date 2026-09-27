//! RC loop code generation: operand words stay promotable and loop copies
//! carry no ownership work the collector's copy does not.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };

fn emit(source: []const u8, mode: runtime.Selection) !std.json.Parsed(Manifest) {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(mode);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_loop_codegen.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = false, .frame_checks = false });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

/// Whether any `%sN` operand word's address reaches something other than a
/// load or store address: a call argument, arithmetic, a blit or a stored value.
fn operandEscapes(il: []const u8) bool {
    var aliases: [64][]const u8 = undefined;
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, il, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        const copy = std.mem.indexOf(u8, line, " =l copy %s") orelse std.mem.indexOf(u8, line, " =l add %s");
        if (copy) |at| {
            const rest = line[at + " =l copy %s".len ..];
            if (rest.len != 0 and std.ascii.isDigit(rest[0]) and count < aliases.len) {
                aliases[count] = line[0..at];
                count += 1;
            }
        }
    }
    lines = std.mem.splitScalar(u8, il, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        for (aliases[0..count]) |alias| {
            if (!mentions(line, alias)) continue;
            if (std.mem.startsWith(u8, line, alias)) continue;
            if (std.mem.indexOf(u8, line, " =l load") != null or std.mem.indexOf(u8, line, " =w load") != null) continue;
            if (std.mem.startsWith(u8, line, "store") and std.mem.endsWith(u8, line, alias)) continue;
            return true;
        }
    }
    return false;
}

fn mentions(line: []const u8, name: []const u8) bool {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, line, from, name)) |at| {
        const end = at + name.len;
        if (end == line.len or !std.ascii.isAlphanumeric(line[end])) return true;
        from = end;
    }
    return false;
}

const moves =
    \\def made(n: int) -> list[int]:
    \\    values: list[int] = []
    \\    for i in range(n):
    \\        values.append(i)
    \\    return values
    \\def main() -> int:
    \\    rows: list[list[int]] = []
    \\    for i in range(3):
    \\        row = made(i)
    \\        rows.append(row)
    \\    kept = rows
    \\    return len(kept)
;

// spec: RC-OPERAND-STAGE-1
test "RC-OPERAND-STAGE-1 ownership helpers receive staged cells, never operand words" {
    var rc = try emit(moves, .rc);
    defer rc.deinit();
    const main = try named(rc.value, "main");
    try t.expect(std.mem.indexOf(u8, main, "%rcstage") != null);
    try t.expect(std.mem.indexOf(u8, main, "copy %rcarg") != null);
    try t.expect(!operandEscapes(main));
    try t.expect(!operandEscapes(try named(rc.value, "made")));
    var gc = try emit(moves, .gc);
    defer gc.deinit();
    try t.expect(std.mem.indexOf(u8, try named(gc.value, "main"), "%rcstage") == null);
}

/// The text of the first check-free loop copy: from its `@fi` label to the
/// original loop's `@oi` label.
fn fastCopy(il: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, il, "\n@fi") orelse return null;
    const end = std.mem.indexOfPos(u8, il, start, "\n@oi") orelse return null;
    return il[start..end];
}

const comprehension =
    \\def main() -> int:
    \\    n = 1000
    \\    flags = [True for _ in range(n + 1)]
    \\    squares = [i * i for i in range(n)]
    \\    return len(flags) + squares[3]
;

// spec: RC-PRESIZED-APPEND-1
test "RC-PRESIZED-APPEND-1 a certified comprehension appends into guarded room without calls" {
    var rc = try emit(comprehension, .rc);
    defer rc.deinit();
    const main = try named(rc.value, "main");
    const guard = std.mem.indexOf(u8, main, "call $myl_rc_list_plain_ready") orelse return error.TestUnexpectedResult;
    const copy = fastCopy(main[guard..]) orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, copy, "call") == null);
    try t.expect(std.mem.indexOf(u8, copy, "%rcappend") == null);
    var counting = try emit(comprehension, .rc_counting);
    defer counting.deinit();
    try t.expect(std.mem.indexOf(u8, try named(counting.value, "main"), "@fi") != null);
}

const appends =
    \\def grown(n: int) -> int:
    \\    items: list[int] = []
    \\    for i in range(n):
    \\        items.append(i)
    \\    return len(items)
    \\def parameter(items: mut list[int], n: int) -> int:
    \\    for i in range(n):
    \\        items.append(i)
    \\    return len(items)
    \\def main() -> int:
    \\    return grown(3)
;

// spec: RC-FRESH-APPEND-GENERATION-1
test "RC-FRESH-APPEND-GENERATION-1 a certified fresh append loop tests room without the frozen generation" {
    var rc = try emit(appends, .rc);
    defer rc.deinit();
    const grown = try named(rc.value, "grown");
    try t.expect(std.mem.indexOf(u8, grown, "%rcappend0") != null);
    try t.expect(std.mem.indexOf(u8, grown, ", -1\n") == null);
    const parameter = try named(rc.value, "parameter");
    try t.expect(std.mem.indexOf(u8, parameter, "%rcappend0") == null);
    try t.expect(std.mem.indexOf(u8, parameter, ", -1\n") != null);
}

const records =
    \\record Row:
    \\    a: int
    \\    b: int
    \\    c: int
    \\    d: int
    \\record Named:
    \\    label: str
    \\    size: int
    \\def build(n: int) -> list[Row]:
    \\    rows: list[Row] = []
    \\    for i in range(n):
    \\        rows.append(Row(a=i, b=i + 1, c=i + 2, d=i + 3))
    \\    return rows
    \\def sum_c(rows: list[Row]) -> int:
    \\    total = 0
    \\    for row in rows:
    \\        total += row.c
    \\    return total
    \\def named(n: int) -> Named:
    \\    return Named(label="x", size=n)
    \\def main() -> int:
    \\    return sum_c(build(3)) + named(2).size
;

// spec: RC-PLAIN-CONSTRUCT-1
test "RC-PLAIN-CONSTRUCT-1 a plain record is built without zeroing or a cleanup entry" {
    var rc = try emit(records, .rc);
    defer rc.deinit();
    const build = try named(rc.value, "build");
    try t.expect(std.mem.indexOf(u8, build, "w 0, l 32)") == null);
    try t.expect(std.mem.indexOf(u8, try named(rc.value, "named"), "w 0, l 16)") != null);
}

// spec: RC-PLAIN-READ-IN-PLACE-1
test "RC-PLAIN-READ-IN-PLACE-1 a plain element read with no owning input is not snapshotted twice" {
    var rc = try emit(records, .rc);
    defer rc.deinit();
    var gc = try emit(records, .gc);
    defer gc.deinit();
    const rc_sum = try named(rc.value, "sum_c");
    const gc_sum = try named(gc.value, "sum_c");
    try t.expect(std.mem.indexOf(u8, rc_sum, "copy %agg") == null);
    try t.expect(std.mem.count(u8, rc_sum, " blit ") <= std.mem.count(u8, gc_sum, " blit ") + 2);
}

// spec: RC-READ-RECORD-VERSION-1
test "RC-READ-RECORD-VERSION-1 a read-only loop over plain records keeps its guarded version" {
    var rc = try emit(records, .rc);
    defer rc.deinit();
    const sum = try named(rc.value, "sum_c");
    const guard = std.mem.indexOf(u8, sum, "# RC-READ-LIST-VERSION-1") orelse return error.TestUnexpectedResult;
    const copy = fastCopy(sum[guard..]) orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, copy, "myl_qbe_fail_iteration") == null);
    try t.expect(std.mem.indexOf(u8, copy, "myl_qbe_fail_normalized_index_bounds") == null);
    try t.expect(std.mem.indexOf(u8, copy, "slot_drop") == null);
}

const parameter_reads =
    \\def weight(i: int, j: int) -> float:
    \\    return 1.0 / float((i + j) * (i + j + 1) // 2 + i + 1)
    \\def dot(v: list[float], i: int) -> float:
    \\    s = 0.0
    \\    for j in range(len(v)):
    \\        s = s + weight(i, j) * v[j]
    \\    return s
    \\def mul(v: list[float], out: mut list[float]) -> None:
    \\    n = len(v)
    \\    for i in range(n):
    \\        s = 0.0
    \\        for j in range(n):
    \\            s = s + weight(i, j) * v[j]
    \\        out[i] = s
    \\def rebound(v: list[float], out: mut list[float]) -> None:
    \\    s = 0.0
    \\    for j in range(len(v)):
    \\        s = s + v[j]
    \\    v = [1.0]
    \\    out[0] = s + v[0]
    \\def main() -> int:
    \\    out = [0.0, 0.0]
    \\    mul([1.0, 2.0], mut out)
    \\    rebound([3.0], mut out)
    \\    return int(dot([1.0, 2.0], 1) + out[0])
;

// spec: RC-READ-LIST-VERSION-2
test "RC-READ-LIST-VERSION-2 read-only parameter lists version float loops through receiver captures" {
    var rc = try emit(parameter_reads, .rc);
    defer rc.deinit();
    const mul = try named(rc.value, "mul");
    const guard = std.mem.indexOf(u8, mul, "# RC-READ-LIST-VERSION-1") orelse return error.TestUnexpectedResult;
    const copy = fastCopy(mul[guard..]) orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, copy, "myl_qbe_fail_normalized_index_bounds") == null);
    // The caller anchors `v`, so no journal guard precedes the range guard.
    try t.expect(std.mem.indexOf(u8, mul[guard..], "@rcreadloop") == null);
    // A rebound parameter is no caller anchor; only its live token may admit.
    const rebound = try named(rc.value, "rebound");
    const tested = std.mem.indexOf(u8, rebound, "# RC-READ-LIST-VERSION-1") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, rebound[tested..], "@rcreadloop") != null);
    try t.expect(!operandEscapes(mul));
}

// spec: RC-READONLY-LOOP-VERSION-1
test "RC-READONLY-LOOP-VERSION-1 a raw readonly body versions its loops like the collector" {
    var rc = try emit(parameter_reads, .rc);
    defer rc.deinit();
    const dot = try named(rc.value, "dot");
    try t.expect(std.mem.indexOf(u8, dot, "%rcframe") == null);
    const copy = fastCopy(dot) orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, copy, "myl_qbe_fail_normalized_index_bounds") == null);
}
