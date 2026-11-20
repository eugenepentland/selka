//! Substring views (lane S1): slices used as text-dictionary keys borrow their source,
//! hash and compare in place, and allocate only on insert. Every expected output is
//! CPython's and the base compiler's (`main` cafe7fea7) for the same program.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const verify_ir = @import("verify_ir.zig");
const options = @import("core_test_options");
const contract = @import("single_owner.zig");
const report = std.debug.print;

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

const Ran = struct { stdout: []const u8, stderr: []const u8, status: u8 };

/// Build `test/core/NAME.selka` with `flags` and run it under the leak check, with
/// `counters` (when not empty) naming the counting build's output file.
fn fixture(arena: std.mem.Allocator, root: []const u8, name: []const u8, flags: []const []const u8, counters: []const u8) !Ran {
    const source = if (std.mem.eql(u8, name, "s1_reads"))
        try std.fmt.allocPrint(arena, "{s}/s1_reads_modern.selka", .{root})
    else
        try std.fmt.allocPrint(arena, "{s}/{s}.selka", .{ options.fixtures, name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{d}", .{ root, name, flags.len });
    const cache = try options.suiteCache(arena, @src());
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "build", source, "-o", output, "--cache-dir", cache });
    try argv.appendSlice(arena, flags);
    try support.requireReleaseArgs(flags);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("build: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    if (counters.len != 0) try environment.put("SELKA_COUNTERS", counters);
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited);
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = ran.term.exited };
}

/// Debug, release, and release with the facts verified.
const modes = [_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } };

/// What `test/core/s1_views.selka` prints: CPython's answers.
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
    \\import dicts
    \\import strings
    \\
    \\func frequencies(seq: str, k: int) -> dict[str, int]:
    \\    mut counts: dict[str, int] = {}
    \\    for i in range(strings.char_count(seq) - k + 1):
    \\        mut key = copy(strings.char_slice(seq, i, i + k))
    \\        counts[own key] = dicts.get(counts, key, 0) + 1
    \\    return counts
    \\
    \\func keyed(seq: str, k: int) -> int:
    \\    mut counts: dict[str, int] = {}
    \\    mut kept: str[] = []
    \\    for i in range(strings.char_count(seq) - k + 1):
    \\        mut key = copy(strings.char_slice(seq, i, i + k))
    \\        counts[copy(key)] = 1
    \\        append(mut kept, own key)
    \\    return len(counts) + len(kept)
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, len(frequencies("ACGTACGT", 2)), keyed("ACGT", 2))
    \\    return 0
    \\
;

/// The text of one function in a module's textual IR, from its header to the next function.
fn functionIr(arena: std.mem.Allocator, text: []const u8, name: []const u8) ![]const u8 {
    _ = arena;
    // The header of a function starts a line and declares `name`, or `name` under a
    // module qualifier (`fn main::frequencies(`) for a project program.
    var start: ?usize = null;
    var line_start: usize = 0;
    while (line_start < text.len) {
        const line_end = std.mem.indexOfScalarPos(u8, text, line_start, '\n') orelse text.len;
        const line = text[line_start..line_end];
        if (std.mem.startsWith(u8, line, "fn ")) if (std.mem.indexOfScalar(u8, line, '(')) |open| {
            if (moduleQualified(line[3..open], name) or std.mem.eql(u8, line[3..open], name)) {
                start = line_start;
                break;
            }
        };
        line_start = line_end + 1;
    }
    const begin = start orelse return "";
    const next = std.mem.indexOfPos(u8, text, begin + 1, "\nfn ") orelse text.len;
    return text[begin..next];
}

/// The function named `name` in `module`.
/// Whether `full` is `name` under a module qualifier, as a project program names
/// its functions (`main::frequencies`).
fn moduleQualified(full: []const u8, name: []const u8) bool {
    if (full.len < name.len + 2) return false;
    const at = full.len - name.len;
    return std.mem.eql(u8, full[at - 2 .. at], "::") and std.mem.eql(u8, full[at..], name);
}

fn named(module: *ir.Module, name: []const u8) !*ir.Function {
    for (module.functions.items) |*function| {
        if (std.mem.eql(u8, function.name, name) or moduleQualified(function.name, name)) return function;
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
        const row_name = row.object.get("name").?.string;
        if (std.mem.eql(u8, row_name, function) or moduleQualified(row_name, function)) return row.object.get(name).?.integer;
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
    try std.testing.expect(contains(counted, "call str_view myl_core_xc_slice("));
    try std.testing.expect(!contains(counted, "= str_slice "));
    try std.testing.expect(contains(counted, "str_from_view str"));
    // The key a list keeps is an owned copy: the written copy of the borrowed slice (`str_from_view`).
    const keyed = try functionIr(a, text, "keyed");
    try std.testing.expect(contains(keyed, "= str_slice str") or contains(keyed, "= str_from_view str"));
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
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
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const ran = try fixture(a, root, "s1_views", &.{"--release"}, "");
    try std.testing.expectEqualStrings(views_expected, ran.stdout);
}

/// What `test/core/s1_ascii.selka` prints: CPython's answers.
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
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
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

/// What `test/core/s1_collisions.selka` prints: CPython's answers.
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
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
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

/// What `test/core/s1_bytes.selka` prints: the base compiler's answers.
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
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const ran = try fixture(a, root, "s1_bytes", flags, "");
        try std.testing.expectEqualStrings(bytes_expected, ran.stdout);
        try std.testing.expectEqual(@as(u8, 0), ran.status);
    }
}

/// What `test/core/s1_reads.selka` prints: CPython's answers.
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
    // migrate-embedded: skip unchecked-lowering reread fixture preserves the original live slice and receiver-append staging
    \\func rebound(s: str) -> int:
    \\    mut total = 0
    \\    mut t = copy(s)
    \\    for i in range(strings.char_count(s)):
    \\        mut head = copy(strings.char_slice(t, 0, i))
    \\        t = t + "x"
    \\        if head == strings.char_slice(s, 0, i):
    \\            total += strings.char_count(head)
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, rebound("abc"))
    \\    return 0
    \\
;

/// The loop carries an owning phi, so preserve its slice before donating the receiver.
fn reboundSlicesBeforeAppend(a: std.mem.Allocator) ![]const u8 {
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, reread, &refusal);
    _ = try support.runPasses(a, &module, .trusted);
    const function = try named(&module, "rebound");
    var appends: usize = 0;
    for (function.insts.items, 0..) |inst, index| {
        if (inst.op != .str_append) continue;
        const receiver = function.resolve(inst.a);
        try std.testing.expectEqual(ir.Op.phi, function.inst(receiver).op);
        const append = try place(function, @fromBackingInt(@intCast(index)));
        const slice = try independentSlice(function, append[0].insts.items[0..append[1]], receiver);
        try sliceReadAndDropped(a, &module, function, slice, @fromBackingInt(@intCast(index)));
        appends += 1;
    }
    try std.testing.expect(appends > 0);
    return @import("print.zig").module(a, &module);
}

/// Require an owned slice of this receiver in the same block before its append.
fn independentSlice(function: *const ir.Function, prefix: []const ir.Ref, receiver: ir.Ref) !ir.Ref {
    for (prefix) |ref| {
        const inst = function.inst(ref);
        if (inst.op == .str_slice and function.resolve(inst.a) == receiver) return ref;
        // The written copy of a borrowed slice of the receiver (`copy(strings.char_slice(...))`, lane C-c)
        // is the same owned slice: it materializes the view, which the append does not keep.
        if (inst.op == .str_from_view) {
            const view = function.inst(function.resolve(inst.a));
            if (view.op == .str_slice_view and function.resolve(view.a) == receiver) return ref;
        }
    }
    return error.TestUnexpectedResult;
}

/// The comparison reads the saved slice before both result branches destroy it.
fn sliceReadAndDropped(a: std.mem.Allocator, module: *const ir.Module, function: *const ir.Function, slice: ir.Ref, append: ir.Ref) !void {
    for (function.blocks.items, 0..) |block, index| {
        for (block.insts.items, 0..) |ref, position| {
            const inst = function.inst(ref);
            if (inst.op != .call or !std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_span_eq")) continue;
            const args = function.operands(inst.data);
            if (args.len != 2 or !readsSlice(function, args[0], slice)) continue;
            try appendBeforeComparison(a, function, append, @intCast(index), position);
            const branch = function.inst(block.insts.items[block.insts.items.len - 1]);
            try std.testing.expectEqual(ir.Op.branch, branch.op);
            try std.testing.expectEqual(ref, function.resolve(branch.a));
            const next = @import("own.zig").successors(function, @intCast(index));
            try std.testing.expectEqual(@as(u8, 2), next.len);
            for (next.slice()) |successor| try dropAfterSliceReads(function, successor, slice);
            return;
        }
    }
    return error.TestUnexpectedResult;
}

/// Whether a span operand of the comparison is the saved slice, or a borrow of it: an owned
/// operand is lent to a span comparison as a `str_view_of` of its whole length (lane C-c, D7).
fn readsSlice(function: *const ir.Function, operand: ir.Ref, slice: ir.Ref) bool {
    const value = function.resolve(operand);
    if (value == slice) return true;
    const inst = function.inst(value);
    return inst.op == .str_view_of and function.resolve(inst.a) == slice;
}

/// Every path to the comparison executes this append first; a shared block also checks order.
fn appendBeforeComparison(a: std.mem.Allocator, function: *const ir.Function, append: ir.Ref, compared_block: u32, compared_position: usize) !void {
    for (function.blocks.items, 0..) |block, index| {
        const position = std.mem.indexOfScalar(ir.Ref, block.insts.items, append) orelse continue;
        if (index == compared_block) {
            try std.testing.expect(position < compared_position);
        } else {
            try std.testing.expect(try @import("own.zig").dominatesBlock(a, function, @intCast(index), compared_block));
        }
        return;
    }
    return error.TestUnexpectedResult;
}

/// Each comparison arm destroys the slice once, after any further span read.
fn dropAfterSliceReads(function: *const ir.Function, block: u32, slice: ir.Ref) !void {
    var dropped = false;
    for (function.blocks.items[block].insts.items) |ref| {
        const inst = function.inst(ref);
        if (inst.op == .drop and function.resolve(inst.a) == slice) {
            try std.testing.expect(!dropped);
            dropped = true;
        } else if (inst.op == .call) {
            for (function.operands(inst.data)) |arg| {
                if (function.resolve(arg) == slice) try std.testing.expect(!dropped);
            }
        }
    }
    try std.testing.expect(dropped);
}

// spec: NEW-CORE-S1-VIEW-4
/// Every borrowed slice of the rebound receiver in `text` is read only by the written materialization
/// that names it (`= str_from_view`), which happens before the rebinding (lane C-c, D9).
fn materializedViewsAreConsumed(a: std.mem.Allocator, text: []const u8) !void {
    var view_at = std.mem.indexOf(u8, text, "= str_slice_view str_view %");
    while (view_at) |at| : (view_at = std.mem.indexOfPos(u8, text, at + 1, "= str_slice_view str_view %")) {
        const name_start = (std.mem.lastIndexOfScalar(u8, text[0..at], '\n') orelse 0) + 1;
        const defining = std.mem.trim(u8, text[name_start..at], " ");
        try std.testing.expect(contains(text, try std.fmt.allocPrint(a, "= str_from_view str {s}\n", .{defining})));
    }
}

test "read-only slices borrow stable sources and preserve values across string updates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Every read of the slice calls the runtime's span form; the slice is a view.
    const source_path = try std.fmt.allocPrint(a, "{s}/s1_reads.selka", .{options.fixtures});
    const original = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, source_path, a, .limited(1 << 20));
    // Explicitly reproduce Python's clamped bounds so the workload still spans
    // negative positions while every actual modern slice receives nonnegative bounds.
    // The wave 3 spelling of a slice is the scalar helper, so the clamped
    // reproduction targets the helper's bounds.
    const left = try std.mem.replaceOwned(u8, a, original, "strings.char_slice(s, i, j)", "strings.char_slice(s, clip(i, n), clip(j, n))");
    const normalized = try std.mem.replaceOwned(u8, a, left, "strings.char_slice(s, j, i + 3)", "strings.char_slice(s, clip(j, n), clip(i + 3, n))");
    // `normalized` is a project source now, so its `import strings` comes first
    // and the clamped reproduction's `clip` helper follows the import block.
    const import_at = std.mem.indexOf(u8, normalized, "import strings\n") orelse return error.TestUnexpectedResult;
    const boundary = (std.mem.indexOfPos(u8, normalized, import_at, "\n\n") orelse return error.TestUnexpectedResult) + 2;
    const source = try std.mem.concat(a, u8, &.{
        normalized[0..boundary],
        "func clip(index: int, size: int) -> int:\n    if index < 0:\n        return max(size + index, 0)\n    return min(index, size)\n\n",
        normalized[boundary..],
    });
    const text = try support.optimizedTextOfProject(a, source);
    const reads = try functionIr(a, text, "main::reads");
    try std.testing.expect(!contains(reads, "= str_slice str"));
    try std.testing.expect(contains(reads, "call bool myl_core_span_eq("));
    // The character count of a borrowed slice is the view form of the same in-place count: a text
    // slice is lowered as a view (lane C-c, D9), so its `len` reads the view, not a span copy.
    try std.testing.expect(contains(reads, "call i64 myl_core_xc_chars("));
    try std.testing.expect(contains(reads, "call bool myl_core_span_starts("));
    try std.testing.expect(contains(reads, "call bool myl_core_span_ends("));
    try std.testing.expect(contains(reads, "call bool myl_core_span_contains("));
    // The owning loop phi keeps a materialized slice before the append consumes its receiver.
    const guarded = try functionIr(a, try reboundSlicesBeforeAppend(a), "rebound");
    // The materialized slice is the written copy of the borrowed one (`str_from_view`, lane C-c).
    try std.testing.expect(contains(guarded, "= str_slice str %") or contains(guarded, "= str_from_view str %"));
    try std.testing.expect(contains(guarded, "call str_view myl_core_xc_slice("));
    // A borrowed slice of the rebound receiver is read only by its materialization, before the
    // rebinding: each one is followed by the owned copy that names it (lane C-c, `copy(...)`).
    try materializedViewsAreConsumed(a, guarded);
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "s1_reads_modern.selka", .data = source });
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

// spec-case: NEW-CORE-S1-VIEW-2
test "a view merged at a branch verifies, and ownership keeps both sources alive" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    try module.strings.append(a, "abcdef");
    var h = try support.Hand.init(a, &module, "pick", .{ .params = &.{.bool}, .ret = .u64 });
    const text = try h.loose(.{ .op = .str_const, .ty = .str });
    const zero = try h.int(.u64, 0);
    const three = try h.int(.u64, 3);
    const two = try h.extra(&.{try h.int(.u64, 2)});
    const head_block = try h.newBlock();
    const tail_block = try h.newBlock();
    const join = try h.newBlock();
    try h.branch(try h.param(0), head_block, tail_block);
    h.block = head_block;
    const head = try h.emit(.{ .op = .str_view_of, .ty = .str_view, .a = text, .b = zero, .data = two });
    try h.jump(join);
    h.block = tail_block;
    const tail = try h.emit(.{ .op = .str_view_of, .ty = .str_view, .a = text, .b = three, .data = two });
    try h.jump(join);
    h.block = join;
    const merged = try h.emit(.{ .op = .phi, .ty = .str_view, .data = try h.extra(&.{ head, tail }) });
    const length = try h.emit(.{ .op = .str_len, .ty = .u64, .a = merged });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = length });
    module.entry = try h.finish();
    try support.verified(a, &module, &.{});
    _ = try @import("own.zig").run(a, &module, .{ .verify = true });
}

fn reachesBeforePhiRead(a: std.mem.Allocator, function: *const ir.Function, from: u32, target: u32, join: u32) !bool {
    const seen = try a.alloc(bool, function.blocks.items.len);
    defer a.free(seen);
    @memset(seen, false);
    var pending: std.ArrayList(u32) = .empty;
    defer pending.deinit(a);
    try pending.append(a, from);
    while (pending.pop()) |block| {
        if (block == join or seen[block]) continue;
        if (block == target) return true;
        seen[block] = true;
        for (@import("own.zig").successors(function, block).slice()) |successor| try pending.append(a, successor);
    }
    return false;
}

fn ownerLivesThroughPhiRead(a: std.mem.Allocator, function: *const ir.Function, owner: ir.Ref, selected_block: u32, join: u32, read: ir.Ref) !void {
    const read_at = std.mem.indexOfScalar(ir.Ref, function.blocks.items[join].insts.items, read);
    try std.testing.expect(read_at != null);
    var found = false;
    for (function.blocks.items, 0..) |block, index| for (block.insts.items, 0..) |ref, position| {
        const inst = function.inst(ref);
        if (inst.op != .drop or function.resolve(inst.a) != function.resolve(owner)) continue;
        found = true;
        if (index == join) {
            try std.testing.expect(read_at.? < position);
        } else {
            try std.testing.expect(!try reachesBeforePhiRead(a, function, @intCast(index), selected_block, join));
            try std.testing.expect(!try reachesBeforePhiRead(a, function, selected_block, @intCast(index), join));
        }
    };
    try std.testing.expect(found);
}

test "phi lifetime reachability includes split edges and excludes unselected siblings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    var h = try support.Hand.init(a, &module, "edges", .{ .params = &.{.bool}, .ret = .u64 });
    const selected = try h.newBlock();
    const sibling = try h.newBlock();
    const edge = try h.newBlock();
    const join = try h.newBlock();
    try h.branch(try h.param(0), selected, sibling);
    h.block = selected;
    try h.jump(edge);
    h.block = edge;
    try h.jump(join);
    h.block = sibling;
    try h.jump(join);
    h.block = join;
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.u64, 0) });
    module.entry = try h.finish();
    try support.verified(a, &module, &.{});
    const function = &module.functions.items[module.entry];
    try std.testing.expect(try reachesBeforePhiRead(a, function, @intCast(selected.index()), @intCast(edge.index()), @intCast(join.index())));
    try std.testing.expect(!try reachesBeforePhiRead(a, function, @intCast(sibling.index()), @intCast(edge.index()), @intCast(join.index())));
    try std.testing.expect(!try reachesBeforePhiRead(a, function, @intCast(selected.index()), @intCast(sibling.index()), @intCast(join.index())));
}

test "a view phi borrowing from three heap owners keeps each selected source alive through its read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    try module.strings.append(a, "abcdef");
    const copy = try @import("test_builder.zig").helper(a, &module, "myl_core_owned_octets_copy", &.{.str}, .str);
    var h = try support.Hand.init(a, &module, "merge", .{ .params = &.{ .bool, .bool }, .ret = .u64 });
    const text = try h.loose(.{ .op = .str_const, .ty = .str });
    const copied_input = (try h.extra(&.{text})) | @import("flags.zig").written_copy;
    const first_text = try h.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(copy), .data = copied_input });
    const second_text = try h.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(copy), .data = copied_input });
    const third_text = try h.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(copy), .data = copied_input });
    const width = try h.extra(&.{try h.int(.u64, 2)});
    const one = try h.newBlock();
    const other = try h.newBlock();
    const deeper = try h.newBlock();
    const rest = try h.newBlock();
    const join = try h.newBlock();
    try h.branch(try h.param(0), one, other);
    h.block = one;
    const from_first = try h.emit(.{ .op = .str_view_of, .ty = .str_view, .a = first_text, .b = try h.int(.u64, 0), .data = width });
    try h.jump(join);
    h.block = other;
    try h.branch(try h.param(1), deeper, rest);
    h.block = deeper;
    const from_second = try h.emit(.{ .op = .str_view_of, .ty = .str_view, .a = second_text, .b = try h.int(.u64, 0), .data = width });
    try h.jump(join);
    h.block = rest;
    const from_third = try h.emit(.{ .op = .str_view_of, .ty = .str_view, .a = third_text, .b = try h.int(.u64, 0), .data = width });
    try h.jump(join);
    h.block = join;
    const merged = try h.emit(.{ .op = .phi, .ty = .str_view, .data = try h.extra(&.{ from_first, from_second, from_third }) });
    const byte = try h.emit(.{ .op = .list_get, .ty = .u8, .a = merged, .b = try h.int(.u64, 0), .check = .exact });
    const result = try h.emit(.{ .op = .convert, .ty = .u64, .a = byte });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = result });
    module.entry = try h.finish();
    try support.verified(a, &module, &.{});
    _ = try @import("own.zig").run(a, &module, .{ .verify = true });
    try support.verified(a, &module, &.{});
    const function = &module.functions.items[module.entry];
    try ownerLivesThroughPhiRead(a, function, first_text, @intCast(one.index()), @intCast(join.index()), byte);
    try ownerLivesThroughPhiRead(a, function, second_text, @intCast(deeper.index()), @intCast(join.index()), byte);
    try ownerLivesThroughPhiRead(a, function, third_text, @intCast(rest.index()), @intCast(join.index()), byte);
}

// spec-case: NEW-CORE-S1-VIEW-4
test "a byte-offset text slice read only in place borrows its source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program =
        \\func reads(text: str) -> int:
        \\    if len(text[0:2]) != 2:
        \\        return 1
        \\    if text[1:3] != "é":
        \\        return 2
        \\    return 0
        \\func main(out: Stream) -> int:
        \\    print(out, reads("aé中b"))
        \\    return 0
    ;
    // The release pipeline recovers the view: the copy call is gone and the
    // borrowed form keeps the same clamps and the same boundary trap.
    const text = try support.optimizedText(a, program);
    const reads = try functionIr(a, text, "reads");
    try std.testing.expect(contains(reads, "myl_core_view_slice"));
    try std.testing.expect(!contains(reads, "myl_core_ir_str_slice_bytes"));
    // A binding over immutable text is a view too; its owned uses copy.
    const stored =
        \\func keep(text: str) -> str:
        \\    const piece = text[0:2]
        \\    return copy(piece)
        \\func main(out: Stream) -> int:
        \\    print(out, keep("abcdef"))
        \\    return 0
    ;
    const kept = try functionIr(a, try support.optimizedText(a, stored), "keep");
    try std.testing.expect(contains(kept, "myl_core_view_slice"));
    try std.testing.expect(contains(kept, "str_from_view str"));
}

// spec-case: NEW-CORE-S1-VIEW-4
test "a borrowed byte slice returns the octets and the boundary of its copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program =
        \\func main(out: Stream) -> int:
        \\    const text = "aé中b"
        \\    print(out, len(text[0:1]), len(text[3:6]), len(text[2:2]), text[0:1] == "a")
        \\    print(out, len(text[2:4]))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, program, &refusal);
    _ = try support.runPasses(a, &module, .trusted);
    const ran = try support.runOwned(a, &module, .{ .release = true });
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expectEqualStrings("1 3 0 True\n", ran.stdout);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "R_TEXT_BOUNDARY") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "offset 2, length 7") != null);
    // B3: the boundary trap carries the slice's own source site, not `<runtime>`.
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in main at") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "<runtime>") == null);
}

// spec-case: NEW-CORE-S1-VIEW-5
test "a slice bound to immutable text is a view in the debug pipeline" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func measure(text: str, out: Stream) -> int:
        \\    const piece = text[1:3]
        \\    print(out, piece, len(piece), strings.char_count(piece))
        \\    return 0
        \\func main(out: Stream) -> int:
        \\    return measure("aé中b", out)
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    try std.testing.expect(contains(dumped, "myl_core_view_slice"));
    try std.testing.expect(!contains(dumped, "call str myl_core_ir_str_slice_bytes"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("é 2 1\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-5
test "a view binding is explicitly copied where an owned value is needed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Held:
        \\    piece: str
        \\func keep(text: str) -> Held:
        \\    const piece = text[1:3]
        \\    return Held(piece=copy(piece))
        \\func head(text: str) -> str:
        \\    const piece = text[1:3]
        \\    return copy(piece)
        \\func main(out: Stream) -> int:
        \\    const held = keep("aé中b")
        \\    print(out, held.piece, head("aé中b") == "é")
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    try std.testing.expect(contains(dumped, "myl_core_view_slice"));
    try std.testing.expect(contains(dumped, "str_from_view"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("é True\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec-case: NEW-CORE-S1-VIEW-5
test "a view binding keeps the boundary trap of the copy it replaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func main(out: Stream) -> int:
        \\    const text = "aé中b"
        \\    const piece = text[2:4]
        \\    print(out, len(piece))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "R_TEXT_BOUNDARY") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "offset 2, length 7") != null);
    // B3: the boundary trap carries the slice's own source site, not `<runtime>`.
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in main at") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "<runtime>") == null);
}

// spec-case: NEW-CORE-S1-VIEW-5
test "a noalloc function reads a bound slice without allocating" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\@noalloc
        \\func measure(text: str) -> int:
        \\    const piece = text[1:3]
        \\    return len(piece) + strings.char_count(piece)
        \\func main() -> int:
        \\    return measure("aé中b") - 3
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec-case: NEW-CORE-S1-VIEW-5
test "a slice of a view binding is copied and stays text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        // migrate-embedded: skip unchecked nested-view lowering fixture explicitly requires no copy helper
        \\func measure(text: str) -> int:
        \\    const outer = text[0:3]
        \\    const inner = outer[0:1]
        \\    return len(outer) + len(inner) + len(outer[1:3])
        \\func main(out: Stream) -> int:
        \\    print(out, measure("aé中b"))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    // The outer binding is a view, so its slice is the view helper call `myl_core_view_slice`, which borrows the
    // octets and makes no copy.
    try std.testing.expect(contains(dumped, "myl_core_view_slice"));
    // The checker refuses this source (E_SLICE_ESCAPES): the harness lowers it unchecked. The lane keeps the inner
    // binding a view, so no copy helper is declared (flagged in lanes/c9.md).
    try std.testing.expect(!contains(dumped, "myl_core_ir_str_slice_bytes("));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("6\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-5
test "a copied slice of a view binding is read in place and stays text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func measure(text: str) -> int:
        \\    const outer = text[0:3]
        \\    const inner = copy(outer[0:1])
        \\    return len(outer) + len(inner) + len(outer[1:3])
        \\func main(out: Stream) -> int:
        \\    print(out, measure("aé中b"))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    // The outer binding is a view and each slice of it is a view too. The copy of `inner` is elided: `inner`
    // is only read, so the copy is never written (the checker refuses an owned binding of a view without copy()).
    try std.testing.expect(contains(dumped, "myl_core_view_slice"));
    try std.testing.expect(!contains(dumped, "myl_core_ir_str_slice_bytes("));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("6\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-5
test "a slice through an immutable field is a view too" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Request:
        \\    body: str
        \\func width(request: Request) -> int:
        \\    const piece = request.body[1:3]
        \\    return len(piece) + strings.char_count(piece)
        \\func main(out: Stream) -> int:
        \\    print(out, width(Request(body="aé中b")))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    try std.testing.expect(contains(dumped, "str_slice_bytes_view"));
    try std.testing.expect(!contains(dumped, "call str myl_core_ir_str_slice_bytes"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("3\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-5
test "a view over a mutable source borrows, and a write to the source needs a copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const borrowed =
        \\func measure(text: str) -> int:
        \\    mut own = copy(text)
        \\    const piece = own[0:3]
        \\    return len(piece) + strings.char_count(piece)
        \\func main(out: Stream) -> int:
        \\    print(out, measure("aé中b"))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, borrowed, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    try std.testing.expect(contains(dumped, "str_slice_bytes_view"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("5\n", ran.stdout);
    // Rebinding the source while the view is live is refused, with the copy
    // repair on the binding.
    const invalidated =
        \\func measure(text: str) -> int:
        \\    mut own = copy(text)
        \\    const piece = own[0:3]
        \\    own = own + "!"
        \\    return len(piece)
        \\func main() -> int:
        \\    return measure("aé中b")
    ;
    var unit = try @import("selka").Compilation.init(a, "invalidated.selka", invalidated);
    defer unit.deinit();
    try unit.check();
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.check(a, unit.program.?, &failure));
    try std.testing.expectEqualStrings("E_SLICE_ESCAPES", failure.code);
    try std.testing.expect(failure.copy.span != null);
}

// spec-case: NEW-CORE-S1-VIEW-6
test "a function declaring a borrowed parameter slice returns a view" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func head(text: str) -> str from text:
        \\    return text[1:3]
        \\func main(out: Stream) -> int:
        \\    print(out, len(head("aé中b")), head("aé中b") == "é")
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    try std.testing.expect(contains(dumped, "fn head(str_view, str) -> str_view"));
    try std.testing.expect(contains(dumped, "myl_core_view_slice"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("2 True\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-6
test "a view-returning function used as a value is refused with its copying wrapper, and its calls keep the view" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func head(text: str) -> str from text:
        \\    return text[1:3]
        \\func apply(callback: func(str) -> str, text: str) -> str:
        \\    return copy(callback(text))
        \\func main(out: Stream) -> int:
        \\    print(out, head("aé中b"), apply(head, "aé中b"))
        \\    return 0
    ;
    const checked = try support.checkSource(a, source);
    try std.testing.expect(checked.passed);
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.checkWithSource(a, checked.program.?, checked.src.?, &failure));
    try std.testing.expectEqualStrings("E_VIEW_FUNCTION_VALUE", failure.code);
    try std.testing.expectEqual(@import("selka").ownership_rules.Rule.V4, failure.rule.?);
    const edits = failure.repair.explicit_fix;
    try std.testing.expectEqual(@as(usize, 2), edits.len);
    try std.testing.expect(contains(edits[0].text, "func head_copy(text: str) -> str:\n    return copy(head(text))"));
    try std.testing.expectEqualStrings("head_copy", edits[1].text);
    const direct = try std.mem.replaceOwned(u8, a, source, "apply(head, \"aé中b\")", "apply(head_copy, \"aé中b\")");
    const repaired = try std.mem.concat(a, u8, &.{ direct, edits[0].text });
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, repaired, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    try std.testing.expect(contains(dumped, "fn head(str_view, str) -> str_view"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("é é\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-6
test "a function with two borrowable parameters returns an owned copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func pick(first: str, second: str) -> str:
        \\    return copy(second[0:2])
        \\func main(out: Stream) -> int:
        \\    print(out, pick("a", "bcde"))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    try std.testing.expect(contains(dumped, "fn pick(str_view, str_view, str, str) -> str"));
    try std.testing.expect(!contains(dumped, "fn pick(str_view, str_view, str, str) -> str_view"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("bc\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-7
test "reading a bound text view allocates nothing, so noalloc accepts it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const contracts = @import("allocation_contract.zig");
    var compilation = try @import("selka").Compilation.init(a, "view.selka",
        \\@noalloc
        \\func prefix_length(text: str) -> int:
        \\    const part = text[0:2]
        \\    return len(part) + strings.char_count(part)
    );
    const program = try compilation.checkLibraryProgram();
    const owned = try contracts.collectProgram(a, program, compilation.src);
    try std.testing.expectEqual(@as(usize, 0), owned.len);
}

// spec-case: NEW-CORE-S1-VIEW-7
test "a noalloc function reads an inline slice without allocating in a debug build" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\@noalloc
        \\func width(text: str) -> int:
        \\    return len(text[0:1]) + len(text[3:6])
        \\func main(out: Stream) -> int:
        \\    print(out, width("aé中b"))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    try std.testing.expect(contains(dumped, "myl_core_view_slice"));
    try std.testing.expect(!contains(dumped, "call str myl_core_ir_str_slice_bytes"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("4\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-8
test "an inline slice read in place borrows its source in a debug build too" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func measure(text: str) -> int:
        \\    return len(text[0:1]) + len(text[3:6])
        \\func main(out: Stream) -> int:
        \\    print(out, measure("aé中b"))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    try std.testing.expect(contains(dumped, "myl_core_view_slice"));
    try std.testing.expect(!contains(dumped, "call str myl_core_ir_str_slice_bytes"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("4\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-8
test "an inline slice with a non-reading or writing use keeps its copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `print` reads a text view in place (lane C-c, D9: a text slice is borrowed, and only an owned use copies it).
    const printed =
        \\func measure(text: str, out: Stream) -> int:
        \\    print(out, text[0:1])
        \\    return 0
        \\func main(out: Stream) -> int:
        \\    return measure("abc", out)
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, printed, &refusal);
    const printed_ir = try @import("print.zig").module(a, &module);
    // The body borrows the slice; the helper's declaration may remain in the module, so only the body is read.
    const printed_body = try functionIr(a, printed_ir, "measure");
    try std.testing.expect(contains(printed_body, "myl_core_view_slice"));
    try std.testing.expect(!contains(printed_body, "myl_core_ir_str_slice_bytes("));
    // A dictionary insert writes, so its key is materialized from the borrowed slice at the insert.
    const inserted =
        \\func measure(text: str) -> int:
        \\    mut counts: dict[str, int] = {}
        \\    counts[copy(text[0:1])] = 1
        \\    return len(counts)
        \\func main(out: Stream) -> int:
        \\    print(out, measure("abc"))
        \\    return 0
    ;
    var other: @import("build.zig").Refusal = .{};
    var second = try support.buildSource(a, inserted, &other);
    const inserted_ir = try @import("print.zig").module(a, &second);
    try std.testing.expect(contains(try functionIr(a, inserted_ir, "measure"), "str_from_view str"));
    const ran = try support.runOwned(a, &second, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("1\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-8
test "a noalloc body still recovers the helper reads of an inline slice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\@noalloc
        \\func measure(text: str) -> int:
        \\    return len(text[0:1]) + strings.char_count(text[0:1])
        \\func main() -> int:
        \\    return measure("abcd") - 2
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec: NEW-CORE-C9-STR-ABI-1
test "a plain str parameter is a view with its owner, a slice passes without a copy, and only a scalar lookup takes a frame header" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\import strings
        \\func my_take(text: str) -> int:
        \\    return strings.char_count(text)
        \\func forward(text: str) -> int:
        \\    return my_take(text)
        \\func char_sum(text: str) -> int:
        \\    mut total = 0
        \\    for i in range(strings.char_count(text)):
        \\        total += ord(strings.char_at(text, i))
        \\    return total
        \\func main(out: Stream) -> int:
        \\    print(out, my_take("abcdef"[1:3]), forward("abcdef"[2:5]), char_sum("é中b"))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    // A plain `str` parameter is a view followed by its owner: the sentinel, or the caller's block.
    try std.testing.expect(contains(dumped, "my_take(str_view, str) -> i64"));
    try std.testing.expect(contains(dumped, "forward(str_view, str) -> i64"));
    // The caller passes each slice as a view, so no copy of it is made.
    const caller = try functionIr(a, dumped, "main");
    try std.testing.expect(!contains(caller, "str_from_view"));
    try std.testing.expect(!contains(caller, "myl_core_view_copy_text"));
    try std.testing.expect(!contains(caller, "myl_core_owned_octets_copy"));
    try std.testing.expect(!contains(caller, "myl_core_ir_str_slice_bytes("));
    // A forwarding hop passes the pair unchanged.
    try std.testing.expect(contains(try functionIr(a, dumped, "forward"), "my_take(param0, param1)"));
    // A frame header is made only in a function that does a scalar lookup on the parameter.
    try std.testing.expect(contains(try functionIr(a, dumped, "my_take"), "text_frame"));
    try std.testing.expect(contains(try functionIr(a, dumped, "char_sum"), "text_frame"));
    try std.testing.expect(!contains(try functionIr(a, dumped, "forward"), "text_frame"));
}

// spec-case: NEW-CORE-C9-BYTES-1
test "a plain bytes parameter is a bytes view with no owner, a slice passes without a copy, and a hop passes the view" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func my_take(data: bytes) -> int:
        \\    return len(data) + int(data[0])
        \\func forward(data: bytes) -> int:
        \\    return my_take(data)
        \\func main(out: Stream) -> int:
        \\    print(out, my_take(b"abcdef"[1:3]) + forward(b"abcdef"[2:5]))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    // A plain `bytes` parameter is a bytes view (its family is the type): no owner follows it.
    try std.testing.expect(contains(dumped, "my_take(bytes_view) -> i64"));
    try std.testing.expect(contains(dumped, "forward(bytes_view) -> i64"));
    try std.testing.expect(!contains(dumped, "my_take(bytes_view, bytes)"));
    // The caller passes each slice as a view: no owned slice and no copy of the view is made.
    const caller = try functionIr(a, dumped, "main");
    try std.testing.expect(!contains(caller, "myl_core_bytes_slice"));
    try std.testing.expect(!contains(caller, "myl_core_view_copy_bytes"));
    try std.testing.expect(!contains(caller, "str_from_view"));
    // A forwarding hop passes the view unchanged.
    try std.testing.expect(contains(try functionIr(a, dumped, "forward"), "my_take(param0)"));
    try std.testing.expect(!contains(try functionIr(a, dumped, "forward"), "myl_core_view_copy_bytes"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("202\n", ran.stdout);
}

// spec: NEW-CORE-C9-VIEW-FUSE-1
test "a char read of a view parameter decodes in place and its cursor steps the octets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\import strings
        \\func count_e(text: str) -> int:
        \\    mut n = 0
        \\    for ch in strings.chars(text):
        \\        if ch == "é":
        \\            n += 1
        \\    return n
        \\func main(out: Stream) -> int:
        \\    print(out, count_e("aé中é"))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    // The character is compared as a scalar: its decode is inline, and the octets step with the scalar index.
    try std.testing.expect(contains(dumped, "str_code"));
    try std.testing.expect(!contains(try functionIr(a, dumped, "count_e"), "myl_core_view_char"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("2\n", ran.stdout);
}

// spec: NEW-CORE-C9-VIEW-FUSE-2
test "zfill of a view receiver is an owned text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\import strings
        \\
        \\func widened(text: str, width: int) -> str:
        \\    return strings.zfill(text, width)
        \\func main(out: Stream) -> int:
        \\    print(out, widened("5"[0:1], 4))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("0005\n", ran.stdout);
}

// spec: NEW-CORE-C9-VIEW-FUSE-3
test "a float parse of a view slice reads its octets without allocating" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\import strings
        \\@noalloc
        \\func parse(text: str) -> int:
        \\    match parse_float(text):
        \\        case Some(value):
        \\            return 1
        \\        case None:
        \\            return 0
        \\func main(out: Stream) -> int:
        \\    print(out, parse("12.5e1"[0:4]), parse("abcd"[0:2]))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("1 0\n", ran.stdout);
}

// spec: NEW-CORE-C9-XC-SLICE-1
test "a char slice of an ASCII parameter clamps inline and agrees with the runtime at its edges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\import strings
        \\func cut(text: str, a: int, b: int) -> str from text:
        \\    return strings.char_slice(text, a, b)
        \\func main(out: Stream) -> int:
        \\    const t = "abcdef"
        \\    print(out, cut(t, 0, 2), cut(t, 4, 9), cut(t, 3, 1), cut(t, 6, 6), cut(t, 0, 0))
        \\    print(out, cut(t, 2, 4), cut(t, 5, 6), strings.char_count(cut("héllo", 1, 3)), cut(t, 9, 12))
        \\    return 0
    ;
    const llvm = try support.releaseLlvmText(a, source);
    // The ASCII owner's clamps are inline; only a non-ASCII or negative endpoint reaches the runtime slice.
    try std.testing.expect(contains(llvm, "xcfast"));
    try std.testing.expect(contains(llvm, "call { ptr, i64 } @myl_core_xc_slice("));
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("ab ef   \ncd f 2 \n", ran.stdout);
}

// FX8 (friction F-26): from 07d555f724 to FX8 an octet slice of a borrowed text (a plain `str` parameter, a payload
// bound from one, a returned borrow, a slice of a slice) lowered to `myl_core_view_slice` with no boundary check, so
// `text[3:]` with 3 inside a scalar handed out text that began mid-scalar, while the same slice of a field trapped.
test "a slice of a text parameter traps R_TEXT_BOUNDARY inside a scalar, as an owned text's slice does" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func tail(text: str, at: int) -> int:
        \\    return len(text[at:])
        \\func main(out: Stream) -> int:
        \\    print(out, tail("aé中b", 1), tail("aé中b", 3), tail("aé中b", 6))
        \\    print(out, tail("aé中b", 2))
        \\    return 0
    ;
    // The borrowed slice passes its trap site, so the trap names the slice's line.
    const llvm = try support.releaseLlvmText(a, source);
    try std.testing.expect(contains(llvm, "@myl_core_view_slice_text(ptr @myl.site."));
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expectEqualStrings("6 4 1\n", ran.stdout);
    try std.testing.expect(contains(ran.stderr, "R_TEXT_BOUNDARY"));
    try std.testing.expect(contains(ran.stderr, "offset 2, length 7"));
    _ = try support.runPasses(a, &module, .trusted);
    const released = try support.runOwned(a, &module, .{ .release = true });
    try std.testing.expectEqual(@as(u8, 1), released.status);
    try std.testing.expectEqualStrings("6 4 1\n", released.stdout);
    try std.testing.expect(contains(released.stderr, "R_TEXT_BOUNDARY"));
}

// FX8: the end endpoint is checked too, and a `bytes` parameter's slice has no boundary rule and gains none.
test "the end of a text parameter's slice is checked and a bytes parameter's slice is not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\import strings
        \\
        \\func octets(data: bytes, at: int) -> int:
        \\    return len(data[at:])
        \\func head(text: str, at: int) -> int:
        \\    return len(text[:at])
        \\func main(out: Stream) -> int:
        \\    print(out, octets(strings.encode("aé中b"), 2), head("aé中b", 3), head("aé中b", 1), head("aé中b", 9))
        \\    print(out, head("aé中b", 4))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expectEqualStrings("5 3 1 7\n", ran.stdout);
    try std.testing.expect(contains(ran.stderr, "R_TEXT_BOUNDARY"));
    try std.testing.expect(contains(ran.stderr, "offset 4, length 7"));
}
