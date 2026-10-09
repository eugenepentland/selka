//! Substring views (lane S1): slices used as text-dictionary keys borrow their source,
//! hash and compare in place, and allocate only on insert. Every expected output is
//! CPython's and the base compiler's (`main` cafe7fea7) for the same program.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const verify_ir = @import("verify_ir.zig");
const options = @import("core_test_options");
const report = std.debug.print;

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

const Ran = struct { stdout: []const u8, stderr: []const u8, status: u8 };

/// Build `test/core/NAME.my` with `flags` and run it under the leak check, with
/// `counters` (when not empty) naming the counting build's output file.
fn fixture(arena: std.mem.Allocator, root: []const u8, name: []const u8, flags: []const []const u8, counters: []const u8) !Ran {
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.my", .{ options.fixtures, name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{d}", .{ root, name, flags.len });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.core_path, "build", source, "-o", output, "--cache-dir", cache });
    try argv.appendSlice(arena, flags);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("build: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    if (counters.len != 0) try environment.put("MYLANG_COUNTERS", counters);
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited);
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = ran.term.exited };
}

/// Debug, release, and release with the facts verified.
const modes = [_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } };

/// What `test/core/s1_views.my` prints: CPython's answers.
const views_expected =
    \\A=10,C=2,G=7,T=19 AA=2,AC=2,AG=1,AT=5,CG=2,GG=2,GT=5,TA=8,TG=1,TT=9
    \\26 22 0 0
    \\ab=39,bc=25,ca=27|abcabcab!0123456
    \\=1,alp=2,be=1,bet=1|zz0,zz1,zz2,zz3,zz4 zz0
    \\ab=2,ac=1,ad=1,br=2,ca=1,da=1,ra=2|ab=0,ac=3,ad=5,br=1,ca=4,da=6,ra=2
    \\=6,a=3,h=1,hé=1,héé=1,é=2,éé=1,éé€=1,é€=1,é€😀=1,€=1,€😀=1,€😀a=1,😀=1,😀a=2
    \\=74,a=5,abc=5,abcd=10,abcdé=10,bc=2,bcd=4,bcdé=4,c=2,cd=4,cdé=4,d=4,dé=4,é=4
    \\0:0=2,s0:0=2,s0:2=1,s0:8=3,s0:15=4,s0:16=5,s0:17=6,1:1=2,s1:1=2,1:3=1,1:9=3,1:16=4,1:17=5,1:18=6,2:2=2,s2:2=2,3:3=2,s3:3=2,4:4=2,s4:4=2,5:5=2,s5:5=2,6:6=2,s6:6=2,7:7=2,s7:7=2,8:8=2,s8:8=2,9:9=2,s9:9=2,10:10=2,s10:10=2,11:11=2,s11:11=2,12:12=2,s12:12=2,13:13=2,s13:13=2,14:14=2,s14:14=2,15:15=2,s15:15=2,16:16=2,s16:16=2,17:17=2,s17:17=2
    \\21 210
    \\997290 4 99 25022 20 99
    \\ab=21,bc=11,bd=11,ca=11,d=1
    \\ab=8,bc=4,ca=4
    \\ab=4,ba=3 ab=3,bc=3,ca=2 ab=2,bc=2,cd=1,de=1,ef=1,fa=1
    \\zz=0|abc=2,bca=2,cab=2,zz=0
    \\1160 644 1
    \\622
    \\
;

const kmers =
    \\func frequencies(seq: str, k: int) -> dict[str, int]:
    \\    mut counts: dict[str, int] = {}
    \\    for i in range(len(seq) - k + 1):
    \\        mut key = seq[i:i + k]
    \\        counts[key] = counts.get(key, 0) + 1
    \\    return counts
    \\
    \\func keyed(seq: str, k: int) -> int:
    \\    mut counts: dict[str, int] = {}
    \\    mut kept: str[] = []
    \\    for i in range(len(seq) - k + 1):
    \\        mut key = seq[i:i + k]
    \\        counts[key] = 1
    \\        kept.append(key)
    \\    return len(counts) + len(kept)
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(len(frequencies("ACGTACGT", 2)), keyed("ACGT", 2))
    \\    return 0
    \\
;

/// The text of one function in a module's textual IR, from its header to the next function.
fn functionIr(arena: std.mem.Allocator, text: []const u8, name: []const u8) ![]const u8 {
    const header = try std.fmt.allocPrint(arena, "fn {s}(", .{name});
    const start = std.mem.indexOf(u8, text, header) orelse return "";
    const next = std.mem.indexOfPos(u8, text, start + header.len, "\nfn ") orelse text.len;
    return text[start..next];
}

/// The function named `name` in `module`.
fn named(module: *ir.Module, name: []const u8) !*ir.Function {
    for (module.functions.items) |*function| {
        if (std.mem.eql(u8, function.name, name)) return function;
    }
    return error.TestUnexpectedResult;
}

/// The first instruction of `f` with operation `op`.
fn first(f: *const ir.Function, op: ir.Op) !usize {
    for (f.insts.items, 0..) |inst, index| {
        if (inst.op == op) return index;
    }
    return error.TestUnexpectedResult;
}

/// The block holding `ref`, and its position there.
fn place(f: *ir.Function, ref: ir.Ref) !struct { *ir.Block, usize } {
    for (f.blocks.items) |*block| {
        if (std.mem.indexOfScalar(ir.Ref, block.insts.items, ref)) |at| return .{ block, at };
    }
    return error.TestUnexpectedResult;
}

fn sum(counts: std.json.Value, function: []const u8, name: []const u8) i64 {
    for (counts.object.get("functions").?.array.items) |row| {
        if (std.mem.eql(u8, row.object.get("name").?.string, function)) return row.object.get(name).?.integer;
    }
    return -1;
}

// spec: NEW-CORE-S1-VIEW-1
test "a slice used only as a text dictionary key borrows its source and allocates only for the keys it inserts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The release passes borrow the slice: one view, no copied slice, and the insert's key
    // materialized from the view right before the insert. A slice that escapes stays a copy.
    const text = try support.optimizedText(a, kmers);
    const counted = try functionIr(a, text, "frequencies");
    try std.testing.expect(contains(counted, "str_slice_view str_view param0"));
    try std.testing.expect(!contains(counted, "= str_slice "));
    try std.testing.expect(contains(counted, "str_from_view str"));
    try std.testing.expect(contains(try functionIr(a, text, "keyed"), "= str_slice str"));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    // Keys inserted then their source rebound or replaced, one slice keying two dictionaries,
    // Unicode, clamped and empty bounds, foreign and near-miss keys, deletions, a call that
    // changes the dictionary, `break`/`continue`/`return` between probe and insert, a shared
    // dictionary copied before the insert, index growth, and lookups only.
    for (modes) |flags| {
        const ran = try fixture(a, root, "s1_views", flags, "");
        try std.testing.expectEqualStrings(views_expected, ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        try std.testing.expectEqual(@as(u8, 0), ran.status);
    }
    // A counting build allocates in `frequencies` once per inserted key (4084 of 39994
    // positions) plus the table's growth, and copies text only for those keys.
    const json_path = try std.fmt.allocPrint(a, "{s}/counts.json", .{root});
    const ran = try fixture(a, root, "s1_view_counts", &.{ "--release", "--counters" }, json_path);
    try std.testing.expectEqualStrings("16 1296 4068 7\n", ran.stdout);
    const json = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, json_path, a, .limited(16 << 20));
    const counts = try std.json.parseFromSliceLeaky(std.json.Value, a, json, .{});
    try std.testing.expectEqual(@as(i64, 4084), sum(counts, "frequencies", "text_copies"));
    try std.testing.expect(sum(counts, "frequencies", "allocs") >= 4084);
    try std.testing.expect(sum(counts, "frequencies", "allocs") <= 4084 + 64);
}

// spec-case: NEW-CORE-S1-VIEW-1
test "an insert keyed by a view's materialized key may use the view's probe, and only that view's" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, kmers, &refusal);
    _ = try support.runPasses(a, &module, .trusted);
    var failure: verify_ir.Failure = .{};
    try verify_ir.verifyModule(a, &module, &failure);
    // Point the materialized key at a second view of the same slice: the probe no longer
    // looked up the octets the insert stores, and the verifier refuses it.
    const f = try named(&module, "frequencies");
    const key = try first(f, .str_from_view);
    const view = f.insts.items[f.resolve(f.insts.items[key].a).index()];
    const other: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(a, view);
    const block = try place(f, @fromBackingInt(@intCast(key)));
    try block[0].insts.insert(a, block[1], other);
    try verify_ir.verifyModule(a, &module, &failure);
    f.insts.items[key].a = other;
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &module, &failure));
}

// spec: NEW-CORE-S1-VIEW-2
test "a borrowed key probe is inline for small, deleted-from and indexed tables and asks the runtime only past a full group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const llvm = try support.releaseLlvmText(a, kmers);
    const start = std.mem.indexOf(u8, llvm, ".find_span(ptr %dict") orelse return error.TestUnexpectedResult;
    const probe = llvm[start..(std.mem.indexOfPos(u8, llvm, start, "\n}\n") orelse llvm.len)];
    // One hash of the span, the first control group, the small scan that skips dead entries,
    // and the runtime only on the `slow` path.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, probe, "call i32 @myl_core_span_hash"));
    try std.testing.expect(contains(probe, "load <16 x i8>"));
    try std.testing.expect(contains(probe, "scan_dead:"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, probe, "@myl_core_dict_find_span"));
    try std.testing.expect(contains(probe, "slow:\n  %result = call i64 @myl_core_dict_find_span"));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const ran = try fixture(a, root, "s1_views", &.{"--release"}, "");
    try std.testing.expectEqualStrings(views_expected, ran.stdout);
}

/// What `test/core/s1_ascii.my` prints: CPython's answers.
const ascii_expected =
    \\hé/2/é/-1
    \\llo/3/o/0
    \\wörld/5/d/3
    \\rld/3/d/1
    \\ell/3/l/1
    \\ld/2/d/0
    \\/0//-1
    \\héllo wörld/11/d/2
    \\é/1/é/-1
    \\ab/2/b/-1
    \\hlowrd/6/d/1
    \\hlowrd/6/d/1
    \\dlröw olléh/11/h/1
    \\dlrow olleh/11/h/1
    \\14 659485
    \\1 2 a 12 é 11
    \\
;

// spec: NEW-CORE-S1-ASCII-1
test "a text copied from part of an ASCII text is ASCII without a re-scan, and any other copy is scanned" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A view's materialized key passes its source's ASCII flag to the runtime.
    const llvm = try support.releaseLlvmText(a, kmers);
    try std.testing.expect(contains(llvm, "call ptr @myl_core_ir_str_from_span(ptr %view."));
    try std.testing.expect(contains(llvm, ", i1 zeroext %viewascii."));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    // Slices, trims, stepped slices, view keys and copy-on-write copies of ASCII and
    // non-ASCII texts: lengths, indexes and searches all read the flag.
    for (modes) |flags| {
        const ran = try fixture(a, root, "s1_ascii", flags, "");
        try std.testing.expectEqualStrings(ascii_expected, ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        try std.testing.expectEqual(@as(u8, 0), ran.status);
    }
}

/// What `test/core/s1_collisions.my` prints: CPython's answers.
const collisions_expected = "50\n" ++ collisions_row ++ "\n" ++ collisions_row ++ "\n";
/// Every pair: a miss, both values intact, a hit, two keys.
const collisions_row = collisions_ten ++ collisions_ten ++ collisions_ten ++ collisions_ten ++ collisions_last;
const collisions_ten = "01212,01212,01212,01212,01212,01212,01212,01212,01212,01212,";
const collisions_last = "01212,01212,01212,01212,01212,01212,01212,01212,01212,01212";

// spec: NEW-CORE-S1-VIEW-3
test "a borrowed key of at most 16 octets is compared inline by overlapping words and every octet counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const llvm = try support.releaseLlvmText(a, kmers);
    const start = std.mem.indexOf(u8, llvm, ".span_same(ptr %stored") orelse return error.TestUnexpectedResult;
    const same = llvm[start..(std.mem.indexOfPos(u8, llvm, start, "\n}\n") orelse llvm.len)];
    // Words of eight and four octets, three single octets below four, `memcmp` only past 16.
    try std.testing.expect(contains(same, "%short = icmp ule i64 %length, 16"));
    try std.testing.expect(contains(same, ".span_pair.i64(ptr %bytes, ptr %data, i64 %tail8)"));
    try std.testing.expect(contains(same, ".span_pair.i32(ptr %bytes, ptr %data, i64 %tail4)"));
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, same, ".span_octet("));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, same, "@memcmp"));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    // Keys of 3 to 20 octets whose hashes are equal and which differ only at the start, the
    // middle or the end: each probe reaches the compare, which must tell them apart.
    for (modes) |flags| {
        const ran = try fixture(a, root, "s1_collisions", flags, "");
        try std.testing.expectEqualStrings(collisions_expected, ran.stdout);
        try std.testing.expectEqual(@as(u8, 0), ran.status);
    }
}

/// What `test/core/s1_bytes.my` prints: the base compiler's answers.
const bytes_expected =
    \\3 hé 2 False -1
    \\2 é 1 False -1
    \\1 !invalid UTF-8 in byte string 29 False -1
    \\0  0 False -1
    \\3 ell 3 True 1
    \\5 world 5 False 3
    \\3 wö 2 False -1
    \\4 !invalid UTF-8 in byte string 29 False 2
    \\13 héllo wörld 11 False 3
    \\3 hel 3 False 2
    \\10 3 3
    \\hellohé 7 h 6 elloh
    \\
;

// spec-case: NEW-CORE-S1-ASCII-1
test "a byte-string slice copies its octets without a scan and decodes, compares, searches and keys as before" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const ran = try fixture(a, root, "s1_bytes", flags, "");
        try std.testing.expectEqualStrings(bytes_expected, ran.stdout);
        try std.testing.expectEqual(@as(u8, 0), ran.status);
    }
}

/// What `test/core/s1_reads.my` prints: CPython's answers.
const reads_expected =
    "0:66,0:66,1:2,0:2,0:66,0:66,0:66,1:2,2:55,2:55,2:55,0:66,0:66,0:2,0:2,0:66,0:66,0:66,1:16,1:16,1:16,4:42,0:2,1:10,2:10,3:58,4:42,5:58,5:58,5:58,0:2,0:" ++
    "2,1:2,2:55,3:34,4:50,4:50,4:50,0:2,0:2,1:16,2:2,3:50,3:50,3:50,0:2,0:2,1:2,2:55,2:55,2:55,0:2,0:2,1:16,1:16,1:16,0:2,0:66,0:66,0:66,0:66,0:66,0:66\n" ++
    "0:66,0:66,1:10,0:2,0:66,0:66,0:66,1:10,2:15,2:15,2:15,0:66,0:66,0:2,0:2,0:66,0:66,0:66,1:2,1:2,1:2,4:10,0:2,1:10,2:15,3:10,4:10,5:10,5:10,5:10,0:2,0:2" ++
    ",1:2,2:2,3:2,4:2,4:2,4:2,0:2,0:2,1:2,2:2,3:2,3:2,3:2,0:2,0:2,1:10,2:15,2:15,2:15,0:2,0:2,1:2,1:2,1:2,0:2,0:66,0:66,0:66,0:66,0:66,0:66\n" ++
    "0:71,0:71,0:71,0:71,0:71,0:71,0:71,0:71,0:71,0:71,0:71,0:71,0:71,0:71,0:71,0:71,0:71,0:71\n" ++
    "614 300\n" ++
    "ba\n" ++
    "2\n" ++
    "same+abcdef!?3 xé!?3\n";

const reread =
    \\func rebound(s: str) -> int:
    \\    mut total = 0
    \\    mut t = s
    \\    for i in range(len(s)):
    \\        mut head = t[0:i]
    \\        t = t + "x"
    \\        if head == s[0:i]:
    \\            total += len(head)
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(rebound("abc"))
    \\    return 0
    \\
;

// spec: NEW-CORE-S1-VIEW-4
test "a slice that is only compared, measured or searched borrows its source unless the source is updated in place" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Every read of the slice calls the runtime's span form; the slice is a view.
    const source_path = try std.fmt.allocPrint(a, "{s}/s1_reads.my", .{options.fixtures});
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, source_path, a, .limited(1 << 20));
    const text = try support.optimizedText(a, source);
    const reads = try functionIr(a, text, "reads");
    try std.testing.expect(!contains(reads, "= str_slice str"));
    try std.testing.expect(contains(reads, "call bool myl_core_span_eq("));
    try std.testing.expect(contains(reads, "call u64 myl_core_span_chars("));
    try std.testing.expect(contains(reads, "call bool myl_core_span_starts("));
    try std.testing.expect(contains(reads, "call bool myl_core_span_ends("));
    try std.testing.expect(contains(reads, "call bool myl_core_span_contains("));
    // A source updated in place (`t = t + "x"`), or flowing into a phi that is (`s`, the
    // first `t`), keeps its slices copies, so the update stays in place.
    const guarded = try functionIr(a, try support.optimizedText(a, reread), "rebound");
    try std.testing.expect(contains(guarded, "= str_slice str %"));
    try std.testing.expect(contains(guarded, "= str_slice str param0"));
    try std.testing.expect(!contains(guarded, "str_slice_view"));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    // Equality both ways, inequality, prefixes, suffixes, containment and lengths over
    // ASCII and non-ASCII text with clamped, empty and reversed bounds; a source rebound
    // or handed to a list and extended while the slice is live; a slice also printed.
    for (modes) |flags| {
        const ran = try fixture(a, root, "s1_reads", flags, "");
        try std.testing.expectEqualStrings(reads_expected, ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        try std.testing.expectEqual(@as(u8, 0), ran.status);
    }
}
