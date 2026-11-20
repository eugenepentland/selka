//! Rule C's guarantee (`copy_sites.zig`, `verify_ir.writtenCopies`): a copy site is written when
//! `copy(value)` made it, and the verifier refuses an unmarked one under facts verification. The
//! census columns (`cost --sites`' `written` and `hidden_copies`) render from the same marks.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const copy_sites = @import("copy_sites.zig");
const verify_ir = @import("verify_ir.zig");
const cost = @import("cost.zig");
const support = @import("test_support.zig");
const language = @import("selka");
const source_location = @import("source_location.zig");

const Hand = support.Hand;

/// The location the verifier's report names, as `emit_llvm.Location` supplies it.
const Where = source_location.Location;

/// A stand-in for the pipeline's source locator, so the report can name a position.
const Probe = struct {
    fn locate(context: *const anyopaque, offset: u32) Where {
        _ = context;
        _ = offset;
        return .{ .path = "copies.selka", .line = 1, .column = 1 };
    }
};

/// `copy_list(xs: int[]) -> int[]`: one list copy of the parameter, its `data` as given.
fn copyList(arena: std.mem.Allocator, module: *ir.Module, data: u64) !void {
    const list = try module.intern(arena, .{ .list = .i64 });
    var hand = try Hand.init(arena, module, "copy_list", .{ .params = try arena.dupe(ir.Type, &.{list}), .ret = list });
    const copied = try hand.emit(.{ .op = .list_copy, .ty = list, .a = try hand.param(0), .data = data, .span = 10 });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = copied });
    _ = try hand.finish();
}

test "a written list copy passes rule C, and an unmarked one is refused with its op, function and place" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var marker: u8 = 0;
    const locator: source_location.Locator = .{ .context = @as(*const anyopaque, &marker), .locate = Probe.locate };

    var written: ir.Module = .{};
    try copyList(a, &written, flags.written_copy);
    var report: std.ArrayList(u8) = .empty;
    try verify_ir.writtenCopies(a, &written, locator, true, &report);
    try std.testing.expectEqual(@as(usize, 0), report.items.len);

    var hidden: ir.Module = .{};
    try copyList(a, &hidden, 0);
    var refused: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.InvalidIr, verify_ir.writtenCopies(a, &hidden, locator, true, &refused));
    try std.testing.expect(std.mem.indexOf(u8, refused.items, "E_CORE_HIDDEN_COPY") != null);
    try std.testing.expect(std.mem.indexOf(u8, refused.items, "list_copy in copy_list at copies.selka:1:1") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, refused.items, "ownership rule C1"));
}

test "hidden copy source diagnostics carry C1 once in text and JSON" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var marker: u8 = 0;
    const locator: source_location.Locator = .{ .context = @as(*const anyopaque, &marker), .locate = Probe.locate };
    var hidden: ir.Module = .{};
    try copyList(a, &hidden, 0);
    const src = try language.source.Source.init(a, "copies.selka", "copy site here\n");
    var text: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.InvalidIr, verify_ir.writtenCopiesWithOptions(a, &hidden, locator, .{ .source = src }, &text));
    try std.testing.expect(std.mem.indexOf(u8, text.items, "list_copy in copy_list at copies.selka:1:1") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text.items, "ownership rule C1"));
    var json: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.InvalidIr, verify_ir.writtenCopiesWithOptions(a, &hidden, locator, .{ .source = src, .format = .json }, &json));
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, std.mem.trimEnd(u8, json.items, "\n"), .{});
    const diagnostic = parsed.object.get("diagnostic").?.object;
    try std.testing.expectEqualStrings("E_CORE_HIDDEN_COPY", diagnostic.get("code").?.string);
    try std.testing.expectEqualStrings("C1", diagnostic.get("rule").?.string);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, json.items, "\"rule\""));
}

test "the written mark rides beside an extra list without changing its start or length" {
    const data = (ir.ExtraSlice{ .start = 3, .len = 2 }).pack() | flags.written_copy;
    const slice = ir.ExtraSlice.unpack(data);
    try std.testing.expectEqual(@as(u32, 3), slice.start);
    try std.testing.expectEqual(@as(u32, 2), slice.len);
    try std.testing.expect(copy_sites.isWritten(.{ .op = .call, .ty = .str, .data = data }));
}

test "a copy site is a copy operation or a compiler runtime copy helper, and never a source extern" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    try module.functions.append(a, .{ .name = "myl_core_owned_octets_copy", .signature = .{ .params = &.{.str}, .ret = .str, .linkage = .runtime_c } });
    try module.functions.append(a, .{ .name = "copy_file", .signature = .{ .params = &.{.str}, .ret = .str, .linkage = .extern_c }, .span = 42 });
    try std.testing.expect(copy_sites.isSite(&module, .{ .op = .list_copy, .ty = .str }));
    try std.testing.expect(copy_sites.isSite(&module, .{ .op = .call, .a = @fromBackingInt(0), .ty = .str }));
    try std.testing.expect(!copy_sites.isSite(&module, .{ .op = .call, .a = @fromBackingInt(1), .ty = .str }));
    try std.testing.expect(!copy_sites.isSite(&module, .{ .op = .list_push, .ty = .str }));
}

test "cost sites render each copy row's reading and count the implicit copies by kind (W4)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = [_]cost.Site{
        .{ .function = "f", .path = "p.selka", .line = 1, .column = 2, .kind = .copy, .loop_depth = 0, .reading = .{ .label = .written } },
        .{ .function = "f", .path = "p.selka", .line = 3, .column = 4, .kind = .copy, .loop_depth = 1, .reading = .{ .label = .implicit, .implicit = .unwritten } },
        .{ .function = "f", .path = "p.selka", .line = 5, .column = 6, .kind = .growth, .loop_depth = 1 },
        .{ .function = "f", .path = "p.selka", .line = 7, .column = 8, .kind = .copy, .loop_depth = 1, .reading = .{ .label = .implicit, .implicit = .@"dictionary key" } },
        .{ .function = "f", .path = "p.selka", .line = 9, .column = 1, .kind = .copy, .loop_depth = 0, .reading = .{ .label = .@"named operation" } },
        .{ .function = "f", .path = "p.selka", .line = 10, .column = 1, .kind = .copy, .loop_depth = 1, .reading = .{ .label = .implicit, .implicit = .@"frame block" } },
    };
    const report: cost.Report = .{ .functions = &.{}, .totals = .{} };
    const text = try cost.renderSites(a, report, &rows, false);
    // The text counts the implicit rows and names their kinds; the dictionary-key copy is one of them.
    try std.testing.expect(std.mem.indexOf(u8, text, "hidden copies: 3 (1 frame block, 1 dictionary key, 1 unwritten)\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "p.selka:1:2  f  copy  written  loop 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "p.selka:3:4  f  copy  implicit (unwritten)  loop 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "p.selka:5:6  f  growth  loop 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "p.selka:7:8  f  copy  implicit (dictionary key)  loop 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "p.selka:9:1  f  copy  named operation  loop 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "p.selka:10:1  f  copy  implicit (frame block)  loop 1") != null);
    // JSON keeps `written` as the mark the check reads and adds the label; `hidden_copies` still counts the unmarked rows.
    const json = try cost.renderSites(a, report, &rows, true);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"copy\",\"loop_depth\":0,\"written\":true,\"hint\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"written\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"line\":7,\"column\":8,\"kind\":\"copy\",\"loop_depth\":1,\"written\":true,") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"label\":\"implicit\",\"implicit\":\"dictionary key\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"label\":\"named operation\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"label\":\"implicit\",\"implicit\":\"frame block\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hidden_copies\":2,\"implicit_copies\":3}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"growth\",\"loop_depth\":1,\"hint\":") != null);
}

test "the written-copy refusal joins facts verification by default, and SELKA_VERIFY_WRITTEN_COPIES=0 turns it off (CX-6)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var marker: u8 = 0;
    const locator: source_location.Locator = .{ .context = @as(*const anyopaque, &marker), .locate = Probe.locate };
    var hidden: ir.Module = .{};
    try copyList(a, &hidden, 0);
    var failure: @import("cli_args.zig").Failure = .usage;
    const verified = try @import("cli_args.zig").parse(a, .run, &.{ "app.selka", "--verify-facts" }, "zig", &failure);
    try std.testing.expect(verified.build.facts == .verify);
    try std.testing.expect(@import("pipeline.zig").writtenCopiesOn(null));
    try std.testing.expect(@import("pipeline.zig").writtenCopiesOn("1"));
    try std.testing.expect(!@import("pipeline.zig").writtenCopiesOn("0"));
    // By default the unmarked copy is refused under facts verification; with the switch at 0 the same module passes.
    var refused: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.InvalidIr, verify_ir.writtenCopies(a, &hidden, locator, @import("pipeline.zig").writtenCopiesOn(null), &refused));
    try std.testing.expect(std.mem.indexOf(u8, refused.items, "E_CORE_HIDDEN_COPY") != null);
    var quiet: std.ArrayList(u8) = .empty;
    try verify_ir.writtenCopies(a, &hidden, locator, @import("pipeline.zig").writtenCopiesOn("0"), &quiet);
    try std.testing.expectEqual(@as(usize, 0), quiet.items.len);
}

test "the print-view helper reads its text parameter, the second one, as a view" {
    const contract = @import("zero_rc.zig").contract("myl_core_print_view") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 1 << 1), contract.views);
}

/// The number of `myl_core_buffer_snapshot` calls in `module` whose written mark is `written`.
fn snapshotCalls(module: *const ir.Module, written: bool) usize {
    var count: usize = 0;
    for (module.functions.items) |f| for (f.insts.items) |inst| {
        if (inst.op != .call or inst.a.index() >= module.functions.items.len) continue;
        if (!std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_buffer_snapshot")) continue;
        if (copy_sites.isWritten(inst) == written) count += 1;
    };
    return count;
}

test "a spelled bytes(buffer) snapshot is a written copy, whatever reads it (CX-1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var marker: u8 = 0;
    const locator: source_location.Locator = .{ .context = @as(*const anyopaque, &marker), .locate = Probe.locate };
    const source =
        \\func same_octets() -> bool:
        \\    mut empty: int[] = []
        \\    const buffer = byte_buffer(empty)
        \\    return bytes(buffer) == b""
        \\func snapshot_of() -> bytes:
        \\    mut empty: int[] = []
        \\    const buffer = byte_buffer(empty)
        \\    return bytes(buffer)
        \\func main() -> int:
        \\    if same_octets() and len(snapshot_of()) == 0:
        \\        return 0
        \\    return 1
    ;
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(a, source, &refusal);
    var report: std.ArrayList(u8) = .empty;
    try verify_ir.writtenCopies(a, &module, locator, true, &report);
    try std.testing.expectEqual(@as(usize, 0), report.items.len);
    try std.testing.expectEqual(@as(usize, 2), snapshotCalls(&module, true));
    try std.testing.expectEqual(@as(usize, 0), snapshotCalls(&module, false));
}

/// The number of calls to `name` in the blocks of `module`'s functions.
fn callsNamed(module: *const ir.Module, name: []const u8) usize {
    var count: usize = 0;
    for (module.functions.items) |f| for (f.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = f.inst(ref);
        if (inst.op != .call or inst.a.index() >= module.functions.items.len) continue;
        if (std.mem.eql(u8, module.functions.items[inst.a.index()].name, name)) count += 1;
    };
    return count;
}

test "an owned trim that only a comparison reads borrows its octets, and the comparison reads the span (CX-4)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\import strings
        \\
        \\func explicit_text(text: str) -> bool:
        \\    return strings.strip_chars(text, " o") == "hell"
        \\func owned_text(text: str) -> str:
        \\    return strings.strip_chars(text, " o")
        \\func main() -> int:
        \\    if explicit_text(" hell o") and len(owned_text(" o hi o ")) == 2:
        \\        return 0
        \\    return 1
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    _ = try @import("fuse_slice_key.zig").run(a, &module);
    // The comparison's trim borrows; its equality reads the two spans in place.
    try std.testing.expectEqual(@as(usize, 1), callsNamed(&module, "myl_core_span_text_trim_view"));
    try std.testing.expectEqual(@as(usize, 1), callsNamed(&module, "myl_core_span_eq"));
    try std.testing.expectEqual(@as(usize, 0), callsNamed(&module, "myl_core_str_eq"));
    // The trim whose owned result is returned keeps its owned helper.
    try std.testing.expectEqual(@as(usize, 1), callsNamed(&module, "myl_core_text_trim_span") + callsNamed(&module, "myl_core_text_trim"));
}

test "HC an owned trim names a new value and is written, and a bytes trim that a read-only slice reads borrows with its slice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var marker: u8 = 0;
    const locator: source_location.Locator = .{ .context = @as(*const anyopaque, &marker), .locate = Probe.locate };
    const source =
        \\import bytes
        \\import strings
        \\
        \\func owned_bytes(line: bytes) -> bytes:
        \\    return bytes.strip(line)
        \\func owned_set(text: str) -> str:
        \\    return strings.strip_chars(text, " o")
        \\func fields(line: bytes) -> int:
        \\    const t = bytes.strip(line)
        \\    if not bytes.starts_with(t, b"(at "):
        \\        return 0
        \\    return len(bytes.split(t[4:len(t) - 1], b" "))
        \\func main() -> int:
        \\    if len(owned_bytes(b" a ")) == 1 and owned_set(" hi o") == "hi" and fields(b" (at 1 2) ") == 2:
        \\        return 0
        \\    return 1
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    // The release passes inline `bytes.strip` into its callers, where the fusion sees each trim and its readers.
    _ = try support.runPasses(a, &module, .trusted);
    // The returned trims keep their owned helpers, and their copies are written: the verifier refuses none.
    var report: std.ArrayList(u8) = .empty;
    try verify_ir.writtenCopies(a, &module, locator, true, &report);
    try std.testing.expectEqualStrings("", report.items);
    try std.testing.expect(callsNamed(&module, "myl_core_text_trim_span") + callsNamed(&module, "myl_core_text_trim") >= 1);
    try std.testing.expect(callsNamed(&module, "myl_core_bytes_trim") + callsNamed(&module, "myl_core_span_bytes_trim") >= 1);
    // The sliced trim borrows: its slice is a slice of the borrowed trim, read by the split in place.
    try std.testing.expectEqual(@as(usize, 1), callsNamed(&module, "myl_core_span_bytes_trim_view"));
    try std.testing.expectEqual(@as(usize, 1), callsNamed(&module, "myl_core_span_bytes_slice_view"));
}

test "HC a spelled copy inlined into its caller stays written" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var marker: u8 = 0;
    const locator: source_location.Locator = .{ .context = @as(*const anyopaque, &marker), .locate = Probe.locate };
    // `snapshot`'s copy is a call with an operand list; the inliners repacked the list without the written mark, so the copy
    // inlined into `borrowed_snapshot` was refused as hidden under `--verify-facts` (main `41c2b5d5c`).
    const source =
        \\record Saved:
        \\    values: dict[str, str[]]
        \\func snapshot(values: dict[str, str[]]) -> Saved:
        \\    return Saved(values=copy(values))
        \\func borrowed_snapshot(values: dict[str, str[]]) -> Saved:
        \\    return snapshot(values)
        \\func main() -> int:
        \\    const values: dict[str, str[]] = {"a": ["b"]}
        \\    return len(borrowed_snapshot(values).values)
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    _ = try support.runPasses(a, &module, .verify);
    var report: std.ArrayList(u8) = .empty;
    try verify_ir.writtenCopies(a, &module, locator, true, &report);
    try std.testing.expectEqualStrings("", report.items);
}

test "a bytes(...) of a byte buffer's slice names the copy the slice makes, which is written (CX-1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var marker: u8 = 0;
    const locator: source_location.Locator = .{ .context = @as(*const anyopaque, &marker), .locate = Probe.locate };
    const source =
        \\func tail_is_two(buffer: byte_buffer) -> bool:
        \\    mut tail = bytes(buffer[1:len(buffer)])
        \\    return tail == b"\x02"
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    const buffer = byte_buffer(empty)
        \\    if tail_is_two(buffer):
        \\        return 0
        \\    return 1
    ;
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(a, source, &refusal);
    var report: std.ArrayList(u8) = .empty;
    try verify_ir.writtenCopies(a, &module, locator, true, &report);
    try std.testing.expectEqual(@as(usize, 0), report.items.len);
    try std.testing.expectEqual(@as(usize, 1), callsNamed(&module, "myl_core_bytes_slice"));
}

test "a read of a byte buffer's slice names its copy, and a whitespace split of a borrowed bytes copies only its pieces (FR25)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var marker: u8 = 0;
    const locator: source_location.Locator = .{ .context = @as(*const anyopaque, &marker), .locate = Probe.locate };
    // The slice of a buffer has no borrowed form, so it is a copy that the slice expression names; the split of a borrowed
    // `bytes` reads the octets in place, so no copy of the whole receiver (`myl_core_view_copy_bytes`) is made first.
    const source =
        \\import bytes
        \\func shown(buffer: byte_buffer) -> int:
        \\    return len(f"{buffer[0:1]}") + len(buffer[1:3])
        \\func pieces(b: bytes) -> int:
        \\    return len(bytes.words(b))
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    const buffer = byte_buffer(empty)
        \\    return shown(buffer) + pieces(b"a b")
    ;
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(a, source, &refusal);
    var report: std.ArrayList(u8) = .empty;
    try verify_ir.writtenCopies(a, &module, locator, true, &report);
    try std.testing.expectEqualStrings("", report.items);
    // FR27: a buffer's slice is a new buffer, made by one helper (no `bytes` made and converted).
    try std.testing.expectEqual(@as(usize, 2), callsNamed(&module, "myl_core_buffer_slice"));
    try std.testing.expectEqual(@as(usize, 0), callsNamed(&module, "myl_core_bytes_slice"));
    try std.testing.expectEqual(@as(usize, 0), callsNamed(&module, "myl_core_buffer_from_bytes"));
    try std.testing.expectEqual(@as(usize, 0), callsNamed(&module, "myl_core_view_copy_bytes"));
    try std.testing.expectEqual(@as(usize, 1), callsNamed(&module, "myl_core_str_split_whitespace") + callsNamed(&module, "myl_core_span_str_split_whitespace"));
}

test "a byte buffer's slice is one new buffer for a write, a call and a return, and a comparison or bytes() reads it as octets (FR27)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var marker: u8 = 0;
    const locator: source_location.Locator = .{ .context = @as(*const anyopaque, &marker), .locate = Probe.locate };
    const source =
        \\import buffers
        \\func grown(buffer: byte_buffer) -> int:
        \\    mut piece = copy(buffer[1:3])
        \\    _ = buffers.append(mut piece, b"x")
        \\    return len(piece)
        \\func measured(piece: byte_buffer) -> int:
        \\    return len(piece)
        \\func passed(buffer: byte_buffer) -> int:
        \\    return measured(buffer[1:3])
        \\func same(buffer: byte_buffer, other: byte_buffer) -> bool:
        \\    return buffer[1:3] == other and buffer[0:1] == b"a"
        \\func octets(buffer: byte_buffer) -> int:
        \\    return len(bytes(buffer[1:3]))
        \\func main() -> int:
        \\    mut empty: int[] = []
        \\    const buffer = byte_buffer(empty)
        \\    if same(buffer, buffer):
        \\        return grown(buffer) + passed(buffer) + octets(buffer)
        \\    return 1
    ;
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(a, source, &refusal);
    var report: std.ArrayList(u8) = .empty;
    try verify_ir.writtenCopies(a, &module, locator, true, &report);
    try std.testing.expectEqualStrings("", report.items);
    // `copy(buffer[1:3])`, `measured(buffer[1:3])` and the slice beside a buffer are new buffers; the slice beside `b"a"` is read in
    // place, and `bytes(buffer[1:3])` is the one copy as octets.
    try std.testing.expectEqual(@as(usize, 3), callsNamed(&module, "myl_core_buffer_slice"));
    try std.testing.expectEqual(@as(usize, 1), callsNamed(&module, "myl_core_bytes_slice"));
    try std.testing.expectEqual(@as(usize, 0), callsNamed(&module, "myl_core_buffer_from_bytes"));
    try std.testing.expectEqual(@as(usize, 0), callsNamed(&module, "myl_core_buffer_snapshot"));
}

/// Declare a runtime helper named `name` at the next index of `module` (CX2).
fn declareHelper(a: std.mem.Allocator, module: *ir.Module, name: []const u8) !void {
    try module.functions.append(a, .{ .name = name, .signature = .{ .params = &.{.str}, .ret = .str, .linkage = .runtime_c } });
}

test "a runtime helper that copies a spelled new value is a copy site, written only when the source named it (CX2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    try declareHelper(a, &module, "myl_core_str_split");
    try declareHelper(a, &module, "myl_core_owned_sort_keyed");
    try declareHelper(a, &module, "myl_core_text_encode");
    try declareHelper(a, &module, "myl_core_span_encode");
    try declareHelper(a, &module, "myl_core_str_split_whitespace");
    try std.testing.expect(copy_sites.isSite(&module, .{ .op = .call, .a = @fromBackingInt(0), .ty = .str }));
    try std.testing.expect(copy_sites.isSite(&module, .{ .op = .call, .a = @fromBackingInt(1), .ty = .str }));
    try std.testing.expect(copy_sites.isSite(&module, .{ .op = .call, .a = @fromBackingInt(2), .ty = .str }));
    try std.testing.expect(copy_sites.isSite(&module, .{ .op = .call, .a = @fromBackingInt(3), .ty = .str }));
    try std.testing.expect(copy_sites.isSite(&module, .{ .op = .call, .a = @fromBackingInt(4), .ty = .str }));
    try std.testing.expect(!copy_sites.isWritten(.{ .op = .call, .a = @fromBackingInt(0), .ty = .str }));
    try std.testing.expect(copy_sites.isWritten(.{ .op = .call, .a = @fromBackingInt(0), .ty = .str, .data = flags.written_copy }));
}

fn copyRepair(allocator: std.mem.Allocator, text: []const u8) !language.diagnostic.Edit {
    const checked = try support.checkSource(allocator, text);
    try std.testing.expect(checked.passed);
    var result: ?language.diagnostic.Edit = null;
    for (checked.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, "W_NEEDLESS_COPY")) continue;
        try std.testing.expect(result == null);
        const fix = item.provenance.fix orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(@as(usize, 1), fix.count());
        result = fix.edit;
    }
    return result orelse error.TestUnexpectedResult;
}

fn withoutListCopies(module: *const ir.Module) !void {
    for (module.functions.items) |function| for (function.insts.items) |inst| {
        try std.testing.expect(inst.op != .list_copy);
    };
}

test "O4 final-use copy repair spells a move and passes Core with no runtime copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // migrate-embedded: skip exact copy-repair input; this test applies and verifies its own fix.
    const text =
        \\func build() -> int[]:
        \\    mut values = [3, 5, 7]
        \\    const kept = copy(values)
        \\    return kept
        \\func main() -> int:
        \\    return len(build())
    ;
    const edit = try copyRepair(a, text);
    try std.testing.expectEqualStrings("own values", edit.text);
    const fixed = try std.mem.concat(a, u8, &.{ text[0..edit.span.start], edit.text, text[edit.span.end..] });
    const checked = try support.checkSource(a, fixed);
    try std.testing.expect(checked.passed);
    var failure: @import("single_owner.zig").Failure = .{};
    try @import("single_owner.zig").checkWithSource(a, checked.program.?, checked.src.?, &failure);
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, fixed, &refusal);
    try withoutListCopies(&module);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 3), ran.status);
    try std.testing.expectEqualStrings("", ran.stderr);
}

/// A program with one copy of each reading (W4): a written `copy(xs)`, a named `sorted(xs)`, a dictionary
/// store's copy of a borrowed key, and a frame block for a text parameter a record holds.
const every_reading =
    \\record Line:
    \\    text: str
    \\    n: int
    \\func line_len(l: Line) -> int:
    \\    return len(l.text) + l.n
    \\func total(text: str) -> int:
    \\    mut sum = 0
    \\    for i in range(3):
    \\        sum += line_len(Line(text=text, n=i))
    \\    return sum
    \\func index(names: str[]) -> dict[str, int]:
    \\    mut out: dict[str, int] = {}
    \\    for name in names:
    \\        out[name] = len(name)
    \\    return out
    \\func kinds(xs: int[]) -> int:
    \\    mut a = copy(xs)
    \\    append(mut a, 1)
    \\    const b = sorted(xs)
    \\    return len(a) + len(b)
    \\func main() -> int:
    \\    const words = "hello world"
    \\    return total(words) + total(words[0:1]) + len(index(["a"])) + kinds([2, 1])
;

/// The copy rows of `rows` whose reading is `reading`, and the lines they name.
fn rowsReading(rows: []const cost.Site, reading: copy_sites.Reading, lines: *std.ArrayList(u32), a: std.mem.Allocator) !u32 {
    var count: u32 = 0;
    for (rows) |row| if (row.reading) |found| if (std.meta.eql(found, reading)) {
        count += 1;
        try lines.append(a, row.line);
    };
    return count;
}

test "W4 cost --sites and the hidden-copy check read one list: the same sites, each written, named or implicit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "readings.selka", every_reading);
    try unit.check();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try @import("build.zig").buildModule(a, unit.program.?, &refusal);
    const result = try support.runPasses(a, &module, .verify);
    const locator = @import("pipeline.zig").locator(&unit.src);
    const rows = try cost.sites(a, &module, &result, locator, "readings.selka", unit.src.bytes);
    var census: copy_sites.Census = .{};
    var report: std.ArrayList(u8) = .empty;
    try verify_ir.writtenCopiesWithOptions(a, &module, locator, .{ .source = unit.src, .known = result.known, .census = &census }, &report);
    // The check refuses nothing here: the frame block and the key copy are counted, not refused.
    try std.testing.expectEqualStrings("", report.items);
    var written: std.ArrayList(u32) = .empty;
    var named: std.ArrayList(u32) = .empty;
    var keys: std.ArrayList(u32) = .empty;
    var frames: std.ArrayList(u32) = .empty;
    // The check counts exactly the copy rows `cost --sites` prints, reading by reading.
    try std.testing.expectEqual(census.written, try rowsReading(rows, .{ .label = .written }, &written, a));
    try std.testing.expectEqual(census.named, try rowsReading(rows, .{ .label = .@"named operation" }, &named, a));
    try std.testing.expectEqual(census.dictionary_keys, try rowsReading(rows, .{ .label = .implicit, .implicit = .@"dictionary key" }, &keys, a));
    try std.testing.expectEqual(census.frame_blocks, try rowsReading(rows, .{ .label = .implicit, .implicit = .@"frame block" }, &frames, a));
    try std.testing.expectEqual(@as(u32, 0), census.unwritten);
    // Each kind is where the source puts it: `copy(xs)` on line 17, `sorted(xs)` on 19, the store on 14, the frame on 9.
    try std.testing.expect(written.items.len >= 1 and std.mem.allEqual(u32, written.items, 17));
    try std.testing.expect(named.items.len >= 1 and std.mem.allEqual(u32, named.items, 19));
    try std.testing.expect(keys.items.len >= 1 and std.mem.allEqual(u32, keys.items, 14));
    try std.testing.expect(frames.items.len >= 1 and std.mem.allEqual(u32, frames.items, 9));
    // `written` stays the mark the check reads: true for all but the frame block.
    try std.testing.expect(markedUnlessFrame(rows));
}

/// Whether every copy row's `written` is false exactly when it is a frame block.
fn markedUnlessFrame(rows: []const cost.Site) bool {
    for (rows) |row| if (row.reading) |reading| {
        const frame = reading.implicit != null and reading.implicit.? == .@"frame block";
        if (frame != (row.written() == false)) return false;
    };
    return true;
}

test "N5 the hidden-copy check runs in every validating build with no flag, and --no-validate builds the copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var marker: u8 = 0;
    const locator: source_location.Locator = .{ .context = @as(*const anyopaque, &marker), .locate = Probe.locate };
    const pipeline = @import("pipeline.zig");
    var hidden: ir.Module = .{};
    try copyList(a, &hidden, 0);
    // No flag: a debug and a release build run the check, as they run the ownership validator.
    const plain: pipeline.Options = .{ .zig = "zig", .mode = .lean_debug };
    const release: pipeline.Options = .{ .zig = "zig", .mode = .release };
    try std.testing.expect(pipeline.checksWrittenCopies(plain) and pipeline.checksWrittenCopies(release));
    var refused: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.InvalidIr, verify_ir.writtenCopies(a, &hidden, locator, pipeline.checksWrittenCopies(plain), &refused));
    try std.testing.expect(std.mem.indexOf(u8, refused.items, "E_CORE_HIDDEN_COPY") != null);
    // `--no-validate` is the way out, and `--verify-written-copies` still asks for the check under it.
    const skipped: pipeline.Options = .{ .zig = "zig", .mode = .lean_debug, .show = .{ .verify = .{ .skip = true, .testing = .{ .like_optimised = true } } } };
    try std.testing.expect(!pipeline.checksWrittenCopies(skipped));
    var built: std.ArrayList(u8) = .empty;
    try verify_ir.writtenCopies(a, &hidden, locator, pipeline.checksWrittenCopies(skipped), &built);
    try std.testing.expectEqual(@as(usize, 0), built.items.len);
    const asked: pipeline.Options = .{ .zig = "zig", .mode = .lean_debug, .facts = .verify_written, .show = .{ .verify = .{ .skip = true } } };
    try std.testing.expect(pipeline.checksWrittenCopies(asked));
}

test "N5 a final body with a hidden copy does not hold, so its record never says validated and is not served as such" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var written: ir.Module = .{};
    try copyList(a, &written, flags.written_copy);
    var hidden: ir.Module = .{};
    try copyList(a, &hidden, 0);
    // `passes.validatedFinal` ands this with the ownership validator and the IR verifier: a record a build made of the hidden
    // body says `validated: false`, which a validating build refuses (`cachedFinal`, `serveByMetadata`) and makes again.
    try std.testing.expect(try verify_ir.functionWrittenCopies(a, &written, 0));
    try std.testing.expect(!try verify_ir.functionWrittenCopies(a, &hidden, 0));
    // The IR verifier accepts both bodies: only the hidden-copy check tells them apart.
    try std.testing.expect(try verify_ir.functionHolds(a, &written, 0));
    try std.testing.expect(try verify_ir.functionHolds(a, &hidden, 0));
}

test "N5 a body served from a record alone has no blocks, and the check reads none of it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var marker: u8 = 0;
    const locator: source_location.Locator = .{ .context = @as(*const anyopaque, &marker), .locate = Probe.locate };
    var module: ir.Module = .{};
    // A demand build leaves a body it served by its metadata out of the module: a function with a signature and no blocks.
    try module.functions.append(a, .{ .name = "served", .signature = .{ .params = &.{}, .ret = .void } });
    try std.testing.expectEqual(@as(usize, 0), (try verify_ir.reachableBlocks(a, &module, &module.functions.items[0])).len);
    var report: std.ArrayList(u8) = .empty;
    try verify_ir.writtenCopies(a, &module, locator, true, &report);
    try std.testing.expectEqualStrings("", report.items);
}

/// The number of `op` instructions in the blocks of the function `name` of `module`.
fn opsIn(module: *const ir.Module, name: []const u8, op: ir.Op) usize {
    var count: usize = 0;
    for (module.functions.items) |f| if (std.mem.endsWith(u8, f.name, name)) for (f.blocks.items) |block| for (block.insts.items) |ref| {
        if (f.inst(ref).op == op) count += 1;
    };
    return count;
}

test "N5 strings.char_stride of a borrowed text passes the view to its helper and makes no hidden copy of it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var marker: u8 = 0;
    const locator: source_location.Locator = .{ .context = @as(*const anyopaque, &marker), .locate = Probe.locate };
    // Before N5 this body copied `s` (`str_from_view`, unmarked), handed the helper the view itself, and dropped the copy.
    const source =
        \\import strings
        \\func scan(s: str) -> int:
        \\    return ord(strings.char_at(strings.char_stride(s, None, None, -1), 0))
        \\func main() -> int:
        \\    return scan("héllo")
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    try std.testing.expectEqual(@as(usize, 0), opsIn(&module, "scan", .str_from_view));
    _ = try support.runPasses(a, &module, .trusted);
    try std.testing.expectEqual(@as(usize, 0), opsIn(&module, "scan", .str_from_view));
    try std.testing.expectEqual(@as(usize, 1), callsNamed(&module, "myl_core_str_slice_step"));
    var report: std.ArrayList(u8) = .empty;
    try verify_ir.writtenCopies(a, &module, locator, true, &report);
    try std.testing.expectEqualStrings("", report.items);
}

test "FX lists.stride of a list view reads the view in place and copies only the elements it selects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var marker: u8 = 0;
    const locator: source_location.Locator = .{ .context = @as(*const anyopaque, &marker), .locate = Probe.locate };
    // Before lane FX the build refused `pick` with E_CORE_UNSUPPORTED (slice_step) because `xs` is a list view.
    const source =
        \\import lists
        \\func pick(xs: int[]) -> int:
        \\    return len(lists.stride(xs, None, None, -2)) + len(lists.stride(xs[1:3], 0, None, 2))
        \\func main() -> int:
        \\    return pick([1, 2, 3, 4, 5])
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    // No whole copy of the view: the stepped loop reads each selected element and pushes it into a fresh list.
    try std.testing.expectEqual(@as(usize, 0), opsIn(&module, "pick", .list_copy));
    try std.testing.expect(opsIn(&module, "pick", .list_new) >= 2);
    _ = try support.runPasses(a, &module, .trusted);
    var report: std.ArrayList(u8) = .empty;
    try verify_ir.writtenCopies(a, &module, locator, true, &report);
    try std.testing.expectEqualStrings("", report.items);
}

test "FR28 a text parse of a borrowed parameter reads the view in place and copies nothing, parse_f32 as parse_float does" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func half_f32(text: str) -> f32:
        \\    return parse_f32(text).unwrap_or(0.0) / 2.0
        \\func half_float(text: str) -> float:
        \\    return parse_float(text).unwrap_or(0.0) / 2.0
        \\func whole(text: str) -> int:
        \\    return parse_int(text).unwrap_or(0)
        \\func main() -> int:
        \\    if whole("4") == 4 and half_f32("3.5") == 1.75f32 and half_float("3.5") == 1.75:
        \\        return 0
        \\    return 1
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    try std.testing.expectEqual(@as(usize, 0), opsIn(&module, "half_f32", .str_from_view));
    try std.testing.expectEqual(@as(usize, 0), opsIn(&module, "half_float", .str_from_view));
    try std.testing.expectEqual(@as(usize, 0), opsIn(&module, "whole", .str_from_view));
    _ = try support.runPasses(a, &module, .trusted);
    try std.testing.expectEqual(@as(usize, 0), opsIn(&module, "half_f32", .str_from_view));
    try std.testing.expectEqual(@as(usize, 1), callsNamed(&module, "myl_core_span_parse_f32_range"));
    try std.testing.expect(@import("build_borrowed_view.zig").spanReceiver(.parse_f32, true));
    try std.testing.expect(@import("build_borrowed_view.zig").spanReceiver(.parse_float, true));
    try std.testing.expect(@import("build_borrowed_view.zig").spanReceiver(.parse_int, true));
}
