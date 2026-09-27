//! Small C entry and diagnostic adapters emitted by the native build driver.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const host = @import("qbe_build_host.zig");
const frame_map = @import("qbe_frame_map.zig");
const lean = @import("qbe_build_units.zig");
/// One packed-argument cleanup shared by every early grant exit.
const free_arguments = "free(arguments);";
// The argv owner surrounds capability grants and the borrowed guest call. Its
// construction flag needs only a pointer-sized type, not a registered list
// slot descriptor. A trap never returns here: heap teardown releases it.
const argv_frame =
    \\#if defined(MYL_NATIVE_RC) && MYL_NATIVE_RC
    \\static const myl_native_type argv_pointer={.size=sizeof(void *)};
    \\void *argv_owner=NULL; uint32_t argv_initialized=1;
    \\MylQbeRcSlot argv_slot={&argv_pointer,&argv_owner,&argv_initialized,MYL_QBE_RC_CONSTRUCTION};
    \\#endif
    \\
;
const argv_cleanup =
    \\
    \\#if defined(MYL_NATIVE_RC) && MYL_NATIVE_RC
    \\myl_qbe_rc_slot_drop(ctx,&argv_slot);
    \\#endif
    \\
;
/// Marker the managed lowering writes into a unit's IL for each frozen
/// `str`/`bytes` literal. QBE reads it as a comment; this unit turns it into the
/// C data object the IL loads. The line is `# ` followed by this word and
/// `<symbol> <element> <width> <count> [hex]`, with element bytes in lowercase
/// hex.
const literal_word = "myl-lit ";
/// The inline-frame fields that name the callee-local start pc and the caller
/// pc of the call site.
const callee_start_key = "callee_start";
const call_position_key = "call_position";
/// Metadata, allocation, and unsupported executable-entry failures.
pub const Error = host.Error || error{UnsupportedNativeEntry};
/// Emit typed runtime descriptors, host bridges, and source-location tables.
pub fn metadata(allocator: std.mem.Allocator, manifest: std.json.Value) Error![]const u8 {
    return metadataUnit(allocator, manifest, true);
}
/// QBE-BATCH-3: the part of `metadata` a batched build still compiles as one
/// C unit — typed runtime descriptors, host bridges and literals, naming no
/// function (QBE-FRAMEMAP-ROOTS-1). Each batch carries
/// its own functions' location, message and inline tables instead
/// (`metadataAssembly`), so an edit that moves one module's lines recompiles
/// that module's tables, not the whole program's.
pub fn sharedMetadata(allocator: std.mem.Allocator, manifest: std.json.Value) Error![]const u8 {
    return metadataUnit(allocator, manifest, false);
}
/// The metadata C unit, with every function's tables or with none of them.
fn metadataUnit(allocator: std.mem.Allocator, manifest: std.json.Value, tables: bool) Error![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    errdefer buffer.deinit();
    const w = &buffer.writer;
    const host_source = try host.source(allocator, v.get(manifest, "host"));
    defer allocator.free(host_source);
    try w.print("#include \"qbe_runtime.h\"\n{s}\n{s}\n", .{ v.text(v.get(manifest, "runtime_data")), host_source });
    const functions = v.array(v.get(manifest, "functions"));
    try literalDefinitions(w, allocator, functions);
    try @import("qbe_build_sites.zig").definitions(w, allocator, functions);
    // Every inline table names another unit's metadata, which may be defined
    // later in this file, so declare them all before the first definition.
    // QBE-FRAMEMAP-ROOTS-1: the roots exist for full LTO, which only the
    // full-table unit of the LLVM arm can be built under. A batched QBE unit
    // is never LTO, and its frame-map section already names every `_meta` the
    // table can reach, so it declares none and adding or removing a function
    // leaves this, the largest single compile, unchanged (QBE-BATCH-4).
    const roots = tables and usesFrameMap(functions);
    if (tables or roots) for (functions) |unit| {
        try w.print("extern const MylQbeFunction {s}_meta;\n", .{v.text(v.get(unit, "symbol"))});
    };
    if (tables) try functionTables(w, functions);
    if (roots) try frameMapRoots(w, functions);
    return buffer.toOwnedSlice();
}
/// Whether any unit was lowered for the frame map (QBE-FRAMEMAP-1).
fn usesFrameMap(functions: []const std.json.Value) bool {
    for (functions) |unit| {
        if (frame_map.usesFrameMap(lean.facts(unit))) return true;
    }
    return false;
}
/// Every function's location, message and inline tables and its
/// `MylQbeFunction` record, in C.
fn functionTables(w: *std.Io.Writer, functions: []const std.json.Value) Error!void {
    for (functions) |unit| {
        const symbol = v.text(v.get(unit, "symbol"));
        var positions: lean.Positions = .init(unit);
        const count = positions.count;
        try w.print("static const MylQbeLocation {s}_meta_locations[] = {{\n", .{symbol});
        while (positions.next()) |position| {
            try w.writeByte('{');
            try v.quote(w, position.path);
            try w.print(",{d},{d}}},\n", .{ position.line, position.column });
        }
        if (count == 0) try w.writeAll("{0,0,0},\n");
        // One message per pc, `""` when the instruction is not an assertion. Pad
        // to the location count so the runtime's `position < count` check always
        // names a real entry, even for a hand-written manifest.
        try w.print("}};\nstatic const char *{s}_meta_messages[] = {{\n", .{symbol});
        for (0..count) |pc| {
            try v.quote(w, positions.message(pc));
            try w.writeAll(",\n");
        }
        if (count == 0) try w.writeAll("\"\",\n");
        try w.writeAll("};\n");
        // One record per inlined splice: the callee's metadata, the caller pc
        // range its body occupies, the callee-local pc it starts at, and the
        // caller pc whose location entry is the call site.
        const inlines = v.array(v.get(unit, "inlines"));
        if (inlines.len != 0) {
            try w.print("static const MylQbeInlineFrame {s}_meta_inlines[] = {{\n", .{symbol});
            for (inlines) |frame| {
                try w.print("{{&{s}_meta,{d},{d},{d},{d}}},\n", .{
                    v.text(v.get(frame, "callee")),
                    v.number(v.get(frame, "start")),
                    v.number(v.get(frame, "end")),
                    v.number(v.get(frame, callee_start_key)),
                    v.number(v.get(frame, call_position_key)),
                });
            }
            try w.writeAll("};\n");
        }
        try w.print("const MylQbeFunction {s}_meta = {{", .{symbol});
        try v.quote(w, v.text(v.get(unit, "name")));
        try w.print(",{s}_meta_locations,{d},{s}_meta_messages,", .{ symbol, count, symbol });
        if (inlines.len != 0) try w.print("{s}_meta_inlines,{d}", .{ symbol, inlines.len }) else try w.writeAll("NULL,0");
        try w.writeAll("};\n");
    }
}
/// QBE-BATCH-3: the metadata of the functions `units` names, as assembly: for
/// each one the `MylQbeFunction` record `metadata` spells in C (name,
/// locations, location count, messages, inline frames, inline count — six
/// 8-byte words), then its location table (path, line, column per pc, one
/// zero entry when there are none), its message table (one string per pc, a
/// single `""` when there are none) and its inline frames (callee metadata,
/// start, end, callee start, call position). Each function's tables share one
/// `.data.rel.ro.<symbol>_meta` section, so the final link keeps or drops them
/// with the function; every distinct string is stored once, in a mergeable
/// string section. `qbe_runtime.h` asserts the three record sizes this relies on.
pub fn metadataAssembly(allocator: std.mem.Allocator, units: []const std.json.Value) Error![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    errdefer buffer.deinit();
    const w = &buffer.writer;
    var strings: std.array_hash_map.String(void) = .empty;
    defer strings.deinit(allocator);
    for (units, 0..) |unit, index| {
        const symbol = v.text(v.get(unit, "symbol"));
        var positions: lean.Positions = .init(unit);
        const count = positions.count;
        const inlines = v.array(v.get(unit, "inlines"));
        try w.print("\t.section\t.data.rel.ro.{s}_meta,\"aw\",@progbits\n\t.p2align\t3\n\t.globl\t{s}_meta\n\t.type\t{s}_meta,@object\n\t.size\t{s}_meta,48\n{s}_meta:\n", .{ symbol, symbol, symbol, symbol, symbol });
        try w.print("\t.quad\t.Lmyl_s_{d}\n\t.quad\t.Lmyl_l_{d}\n\t.quad\t{d}\n\t.quad\t.Lmyl_m_{d}\n", .{ try stringIndex(allocator, &strings, v.text(v.get(unit, "name"))), index, count, index });
        if (inlines.len != 0) try w.print("\t.quad\t.Lmyl_i_{d}\n\t.quad\t{d}\n", .{ index, inlines.len }) else try w.writeAll("\t.quad\t0\n\t.quad\t0\n");
        try w.print(".Lmyl_l_{d}:\n", .{index});
        while (positions.next()) |position| {
            const path = try stringIndex(allocator, &strings, position.path);
            try w.print("\t.quad\t.Lmyl_s_{d}\n\t.quad\t{d}\n\t.quad\t{d}\n", .{ path, position.line, position.column });
        }
        if (count == 0) try w.writeAll("\t.quad\t0\n\t.quad\t0\n\t.quad\t0\n");
        try w.print(".Lmyl_m_{d}:\n", .{index});
        for (0..@max(1, count)) |pc| {
            try w.print("\t.quad\t.Lmyl_s_{d}\n", .{try stringIndex(allocator, &strings, positions.message(pc))});
        }
        if (inlines.len == 0) continue;
        try w.print(".Lmyl_i_{d}:\n", .{index});
        for (inlines) |frame| {
            try w.print("\t.quad\t{s}_meta\n\t.quad\t{d}\n\t.quad\t{d}\n\t.quad\t{d}\n\t.quad\t{d}\n", .{
                v.text(v.get(frame, "callee")),
                v.number(v.get(frame, "start")),
                v.number(v.get(frame, "end")),
                v.number(v.get(frame, callee_start_key)),
                v.number(v.get(frame, call_position_key)),
            });
        }
    }
    try w.writeAll("\t.section\t.rodata.str1.1,\"aMS\",@progbits,1\n");
    for (strings.keys(), 0..) |text, index| {
        try w.print(".Lmyl_s_{d}:\n\t.asciz\t", .{index});
        try v.quote(w, text);
        try w.writeByte('\n');
    }
    try w.writeAll("\t.section\t.note.GNU-stack,\"\",@progbits\n");
    return buffer.toOwnedSlice();
}
/// BUILD-METADATA-KEY-1: the BLAKE3 digest of everything `metadataAssembly`
/// reads from `units`, in order — each unit's symbol and name, its positions in
/// whichever spelling it carries (the compact `paths`, `positions` and
/// `assertions`, or the spelled-out `locations` and `messages`) and its inline
/// frames — so a batch's assembled tables are found in the object cache
/// without rendering them. Rendering every batch's tables only to key them cost
/// a warm build more than the rest of its planning.
pub fn metadataDigest(units: []const std.json.Value) [32]u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("qbe-batch-metadata-digest-v1");
    for (units) |unit| {
        digestText(&hash, v.text(v.get(unit, "symbol")));
        // EMIT-META-1: a lean unit's name, positions, messages and inline
        // frames are its stored metadata record, which its digest names.
        const stored = v.get(unit, lean.meta_key);
        if (stored == .string) {
            digestText(&hash, "stored");
            digestText(&hash, stored.string);
            continue;
        }
        digestText(&hash, v.text(v.get(unit, "name")));
        const compact = v.get(unit, "positions");
        if (compact == .string) {
            digestText(&hash, "compact");
            digestNumber(&hash, v.array(v.get(unit, "paths")).len);
            for (v.array(v.get(unit, "paths"))) |path| digestText(&hash, v.text(path));
            digestText(&hash, compact.string);
            digestNumber(&hash, v.array(v.get(unit, "assertions")).len);
            for (v.array(v.get(unit, "assertions"))) |assertion| {
                const pair = v.array(assertion);
                digestNumber(&hash, pair.len);
                if (pair.len != 2) continue;
                digestNumber(&hash, v.number(pair[0]));
                digestText(&hash, v.text(pair[1]));
            }
        } else {
            digestText(&hash, "spelled");
            digestNumber(&hash, v.array(v.get(unit, "locations")).len);
            for (v.array(v.get(unit, "locations"))) |location| {
                digestText(&hash, v.text(v.get(location, "path")));
                digestNumber(&hash, v.number(v.get(location, "line")));
                digestNumber(&hash, v.number(v.get(location, "column")));
            }
            digestNumber(&hash, v.array(v.get(unit, "messages")).len);
            for (v.array(v.get(unit, "messages"))) |message| digestText(&hash, v.text(message));
        }
        const inlines = v.array(v.get(unit, "inlines"));
        digestNumber(&hash, inlines.len);
        for (inlines) |frame| {
            digestText(&hash, v.text(v.get(frame, "callee")));
            for ([_][]const u8{ "start", "end", callee_start_key, call_position_key }) |field| digestNumber(&hash, v.number(v.get(frame, field)));
        }
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}
fn digestText(hash: *std.crypto.hash.Blake3, text: []const u8) void {
    digestNumber(hash, text.len);
    hash.update(text);
}
fn digestNumber(hash: *std.crypto.hash.Blake3, number: u64) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, number, .little);
    hash.update(&bytes);
}
/// The label index of `text` in a batch's string table, adding it when new.
fn stringIndex(allocator: std.mem.Allocator, strings: *std.array_hash_map.String(void), text: []const u8) Error!usize {
    const slot = try strings.getOrPut(allocator, text);
    return slot.index;
}
/// QBE-FRAMEMAP-1: a frame-map unit's code never names its metadata; only the
/// return-address table does, and under full LTO that table is written after
/// the optimizer has already run. Holding every unit's metadata in one `used`
/// array keeps each one — under its own name — through LTO for the table to
/// name. Units lowered under another protocol reference their metadata from
/// code, so they need nothing here.
fn frameMapRoots(w: *std.Io.Writer, functions: []const std.json.Value) Error!void {
    try w.writeAll("__attribute__((used)) static const MylQbeFunction *const mylang_frame_map_functions[] = {\n");
    for (functions) |unit| try w.print("&{s}_meta,\n", .{v.text(v.get(unit, "symbol"))});
    try w.writeAll("};\n");
}
/// One frozen image literal parsed from the emitted metadata marker: the data
/// symbol the generated C defines, the element descriptor its managed header
/// stores, the element width — zero for a text, whose payload is UTF-8 octets —
/// the payload unit count, and for a text its scalar count and whether every
/// scalar is below 0x80, plus the payload bytes in lowercase hex.
const Literal = struct {
    symbol: []const u8,
    element: []const u8,
    width: usize,
    count: usize,
    scalars: usize,
    ascii: bool,
    hex: []const u8,
};
/// Emit one C definition for every frozen `str`/`bytes` literal the emitted IL
/// names. The marker carries the exact payload, so equal literals share one data
/// object even across units.
/// Every line of one unit's IL that starts with the literal marker. It
/// searches for the marker instead of splitting every line: a program's IL is
/// hundreds of megabytes and a warm build reads all of it to find a few
/// literals.
const MarkerLines = struct {
    il: []const u8,
    at: usize = 0,
    fn next(self: *MarkerLines) ?[]const u8 {
        while (std.mem.indexOfPos(u8, self.il, self.at, "# " ++ literal_word)) |found| {
            const end = std.mem.indexOfScalarPos(u8, self.il, found, '\n') orelse self.il.len;
            self.at = end;
            if (found == 0 or self.il[found - 1] == '\n') return self.il[found..end];
        }
        self.at = self.il.len;
        return null;
    }
};
fn literalDefinitions(w: *std.Io.Writer, allocator: std.mem.Allocator, units: []const std.json.Value) Error!void {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(allocator);
    var header = false;
    for (units) |unit| {
        // A stored unit's facts hold its marker lines (`QBE-FRAGMENT-REUSE-1`).
        var lines: MarkerLines = .{ .il = lean.facts(unit) };
        while (lines.next()) |line| {
            var tokens = std.mem.tokenizeScalar(u8, line[2 + literal_word.len ..], ' ');
            const symbol = tokens.next() orelse continue;
            const element = tokens.next() orelse continue;
            const width_text = tokens.next() orelse continue;
            const count_text = tokens.next() orelse continue;
            if (seen.contains(symbol)) continue;
            try seen.put(allocator, symbol, {});
            const width = std.fmt.parseInt(usize, width_text, 10) catch continue;
            const count = std.fmt.parseInt(usize, count_text, 10) catch continue;
            var literal: Literal = .{ .symbol = symbol, .element = element, .width = width, .count = count, .scalars = count, .ascii = false, .hex = "" };
            if (width == 0) {
                const scalars_text = tokens.next() orelse continue;
                const ascii_text = tokens.next() orelse continue;
                literal.scalars = std.fmt.parseInt(usize, scalars_text, 10) catch continue;
                literal.ascii = !std.mem.eql(u8, ascii_text, "0");
            }
            literal.hex = tokens.next() orelse "";
            if (!header) {
                try w.writeAll("#include \"native_text.h\"\n");
                header = true;
            }
            try emitLiteral(w, literal);
        }
    }
}
/// Emit one static literal block: the managed header and payload object the
/// collector expects around the bytes, plus the storage the literal owns. The
/// block's payload is published as the symbol the IL loads. A text is a header,
/// its scalar and octet counts and flags, and the UTF-8 payload behind them; a
/// `bytes` literal keeps the list header and its element storage.
fn emitLiteral(w: *std.Io.Writer, literal: Literal) Error!void {
    const symbol = literal.symbol;
    // A text's payload is `count` octets with no element stride; every other
    // literal's payload is its elements at `width` bytes each.
    const bytes = if (literal.width == 0) literal.count else literal.count * literal.width;
    const storage = if (bytes == 0) 1 else bytes;
    if (literal.width == 0) {
        try w.print("typedef struct {{ myl_native_object header; myl_native_text value; unsigned char storage[{d}]; }} {s}_block;\n", .{ storage, symbol });
        try w.print("static {s}_block {s}_instance = {{\n", .{ symbol, symbol });
        try w.print(" .header = {{.mark = MYL_NATIVE_OBJECT_LITERAL_MARK, .element = &{s}}},\n", .{literal.element});
        try w.print(" .value = {{.length = {d}, .bytes = {d}, .flags = {d}, .hash = 0}},\n", .{ literal.scalars, literal.count, @as(u32, if (literal.ascii) 1 else 0) });
    } else {
        try w.print("typedef struct {{ myl_native_object header; myl_native_list value; myl_native_object storage_header; unsigned char storage[{d}]; }} {s}_block;\n", .{ storage, symbol });
        try w.print("static {s}_block {s}_instance = {{\n", .{ symbol, symbol });
        try w.print(" .header = {{.mark = MYL_NATIVE_OBJECT_LITERAL_MARK, .element = &{s}}},\n", .{literal.element});
        try w.print(" .value = {{.length = {d}, .capacity = {d}, .generation = 0, .element = &{s}", .{ literal.count, literal.count, literal.element });
        if (bytes == 0) try w.writeAll(", .storage = 0") else try w.print(", .storage = {s}_instance.storage", .{symbol});
        try w.writeAll(", .region = 0},\n");
        try w.print(" .storage_header = {{.mark = MYL_NATIVE_OBJECT_LITERAL_MARK, .element = &{s}}},\n", .{literal.element});
    }
    if (bytes == 0) {
        try w.writeAll(" .storage = {0},\n");
    } else {
        try w.writeAll(" .storage = {");
        var index: usize = 0;
        while (index + 1 < literal.hex.len) : (index += 2) {
            const high = std.fmt.charToDigit(literal.hex[index], 16) catch 0;
            const low = std.fmt.charToDigit(literal.hex[index + 1], 16) catch 0;
            try w.print("0x{x:0>2},", .{high * 16 + low});
        }
        try w.writeAll("},\n");
    }
    try w.writeAll("};\n");
    try w.print("const void *const {s} = &{s}_instance.value;\n", .{ symbol, symbol });
}
/// Emit an executable entry that initializes host calls and grants capabilities.
pub fn entry(allocator: std.mem.Allocator, manifest: std.json.Value, provider: bool, final: bool) Error![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    errdefer buffer.deinit();
    const w = &buffer.writer;
    const name = v.text(v.get(manifest, "entry"));
    if (name.len == 0) return error.UnsupportedNativeEntry;
    const parameters = v.array(v.get(manifest, "entry_parameters"));
    const parameter_names = v.array(v.get(manifest, "entry_parameter_names"));
    const argv_element = v.text(v.get(manifest, "entry_argv_element"));
    if (argv_element.len != 0 and parameters.len == 0) return error.UnsupportedNativeEntry;
    const uses_packed = parameters.len > 128;
    try w.writeAll("#include \"qbe_grants.h\"\n#include \"native_providers.h\"\n#include <stdlib.h>\nextern void myl_qbe_host_begin(void *);\n");
    if (argv_element.len != 0) try w.print("extern const myl_native_type {s};\n", .{argv_element});
    try w.print("extern uint64_t {s}(void *", .{name});
    if (uses_packed) try w.writeAll(",uint64_t *") else for (parameters) |_| try w.writeAll(",uint64_t");
    try w.writeAll(");\nstatic uint64_t entry_run(void *ctx) {\n myl_qbe_host_begin(ctx); if(myl_qbe_failed(ctx))return 0;\n");
    if (uses_packed) try w.print("uint64_t *arguments=calloc({d},sizeof *arguments);if(!arguments){{myl_qbe_fail_allocation(ctx);return 0;}}\n", .{parameters.len});
    if (argv_element.len != 0) try w.writeAll(argv_frame);
    for (parameters, 0..) |parameter, index| {
        if (uses_packed) try w.print("arguments[{d}]=", .{index}) else try w.print("uint64_t arg{d}=", .{index});
        if (index == 0 and argv_element.len != 0) {
            try w.print("(uint64_t)myl_qbe_argv_list(ctx,&{s});\n", .{argv_element});
            try w.writeAll("#if defined(MYL_NATIVE_RC) && MYL_NATIVE_RC\nargv_owner=(void *)");
            try w.writeAll(if (uses_packed) "arguments[0]" else "arg0");
            try w.writeAll(";\n#endif\n");
        } else if (std.mem.eql(u8, v.text(parameter), "stream_cap")) {
            const parameter_name = if (index < parameter_names.len) v.text(parameter_names[index]) else "";
            const sentinel: u64 = if (std.mem.eql(u8, parameter_name, "err")) 2 else 1;
            try w.print("UINT64_C({d});\n", .{sentinel});
        } else {
            try w.print("{s};\n", .{try grant(v.text(parameter))});
        }
        try w.writeAll("if(myl_qbe_failed(ctx)){");
        if (argv_element.len != 0) try w.writeAll(argv_cleanup);
        if (uses_packed) try w.writeAll(free_arguments);
        try w.writeAll("return 0;}\n");
    }
    try w.writeAll("if(myl_qbe_failed(ctx)){");
    if (argv_element.len != 0) try w.writeAll(argv_cleanup);
    if (uses_packed) try w.writeAll(free_arguments);
    try w.print("return 0;}} uint64_t answer={s}(ctx", .{name});
    if (uses_packed) try w.writeAll(",arguments") else for (parameters, 0..) |_, index| try w.print(",arg{d}", .{index});
    try w.writeAll(");");
    if (argv_element.len != 0) try w.writeAll(argv_cleanup);
    if (uses_packed) try w.writeAll(free_arguments);
    try w.writeAll("return answer;}\nint main(int argc,char **argv){");
    // A final run is the whole process: the OS releases the heap, so the runner
    // skips freeing every live object first. A Debug build keeps the sweep as a
    // heap check, and the library entry never claims to be final.
    if (final) try w.writeAll("myl_qbe_exit_without_sweep();");
    if (provider) try w.writeAll("MylangNativeProviders providers=mylang_native_providers();");
    try w.print("return mylang_qbe_run_grants(entry_run,argc,argv,{s});}}\n", .{if (provider) "&providers" else "NULL"});
    return buffer.toOwnedSlice();
}
fn grant(name: []const u8) Error![]const u8 {
    const names = [_][]const u8{ "allocator", "clock_cap", "random_cap", "environment_cap", "filesystem_cap", "network_cap", "host_cap" };
    const calls = [_][]const u8{
        "UINT64_C(1)",
        "myl_qbe_grant_external_checked(ctx,0,\"--allow-clock\")",
        "myl_qbe_grant_external_checked(ctx,1,\"--allow-random\")",
        "myl_qbe_grant_external_checked(ctx,2,\"--allow-env\")",
        "myl_qbe_grant_resource_checked(ctx,0,\"--allow-read=DIR\")",
        "myl_qbe_grant_resource_checked(ctx,1,\"--allow-endpoint=IP:PORT\")",
        "myl_qbe_grant_host_checked(ctx,\"--allow-host\")",
    };
    for (names, calls) |type_name, call| if (std.mem.eql(u8, name, type_name)) return call;
    return error.UnsupportedNativeEntry;
}

// spec-case: ARGV-1
test "entry metadata rejects ordinary values as implicit capability grants" {
    try std.testing.expectError(error.UnsupportedNativeEntry, grant("i64"));
}
// spec-case: RC-ARGV-OWNERSHIP-1
test "entry metadata guards optional argv ownership before calling the borrowed guest" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"entry":"main_native","entry_parameters":["str_list"],"entry_argv_element":"myl_t_str","functions":[{"symbol":"main_native","name":"main","locations":[]}]}
    , .{});
    defer parsed.deinit();
    const generated = try entry(std.testing.allocator, parsed.value, false, false);
    defer std.testing.allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "myl_qbe_argv_list(ctx,&myl_t_str)") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "MYL_QBE_RC_CONSTRUCTION") != null);
    const guard = std.mem.indexOf(u8, generated, "MylQbeRcSlot argv_slot=").?;
    const allocate = std.mem.indexOf(u8, generated, "myl_qbe_argv_list(ctx,&myl_t_str)").?;
    const publish = std.mem.indexOf(u8, generated, "argv_owner=(void *)arg0;").?;
    const call = std.mem.indexOf(u8, generated, "uint64_t answer=main_native(ctx,arg0);").?;
    try std.testing.expect(guard < allocate and allocate < publish and publish < call);
    try std.testing.expect(std.mem.indexOf(u8, generated[call..], "myl_qbe_rc_slot_drop(ctx,&argv_slot)") != null);
}
test "entry and location metadata retain provider setup and byte-escaped source paths" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"entry":"main_native","entry_parameters":["clock_cap"],"functions":[{"symbol":"main_native","name":"main","locations":[{"path":"a\\b.my","line":2,"column":3}]}]}
    , .{});
    defer parsed.deinit();
    const generated = try entry(std.testing.allocator, parsed.value, true, true);
    defer std.testing.allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "myl_qbe_grant_external_checked(ctx,0,\"--allow-clock\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "mylang_qbe_run_grants(entry_run,argc,argv,&providers)") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "argv_slot") == null);
    const locations = try metadata(std.testing.allocator, parsed.value);
    defer std.testing.allocator.free(locations);
    try std.testing.expect(std.mem.indexOf(u8, locations, "main_native_meta_locations,1") != null);
}
// spec-case: NATIVE-TEST-10
test "assert messages are emitted once per pc and linked into the function metadata" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"entry":"main_native","entry_parameters":[],"functions":[{"symbol":"main_native","name":"main","locations":[{"path":"a.my","line":1,"column":1},{"path":"a.my","line":4,"column":5}],"messages":["","x should be two"]}]}
    , .{});
    defer parsed.deinit();
    const generated = try metadata(std.testing.allocator, parsed.value);
    defer std.testing.allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "static const char *main_native_meta_messages[] = {") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "\n\"\",\n\"x should be two\",\n};\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, ",main_native_meta_locations,2,main_native_meta_messages,NULL,0};") != null);
    const without = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"entry":"main_native","entry_parameters":[],"functions":[{"symbol":"main_native","name":"main","locations":[{"path":"a.my","line":1,"column":1}]}]}
    , .{});
    defer without.deinit();
    const padded = try metadata(std.testing.allocator, without.value);
    defer std.testing.allocator.free(padded);
    try std.testing.expect(std.mem.indexOf(u8, padded, "static const char *main_native_meta_messages[] = {\n\"\",\n};\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, padded, ",main_native_meta_locations,1,main_native_meta_messages,NULL,0};") != null);
}
// spec-case: BYTECODE-INLINE-2
test "inline records name the callee metadata and link into the function metadata" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"entry":"main_native","entry_parameters":[],"functions":[{"symbol":"main_native","name":"main","locations":[{"path":"a.my","line":1,"column":1}],"inlines":[{"callee":"myl_f_abc","start":1,"end":4,"callee_start":0,"call_position":0}]}]}
    , .{});
    defer parsed.deinit();
    const generated = try metadata(std.testing.allocator, parsed.value);
    defer std.testing.allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "extern const MylQbeFunction main_native_meta;") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "static const MylQbeInlineFrame main_native_meta_inlines[] = {\n{&myl_f_abc_meta,1,4,0,0},\n};\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, ",main_native_meta_messages,main_native_meta_inlines,1};") != null);
}

// spec: QBE-BATCH-3
test "a batch's function metadata is assembly holding the C unit's records, and the shared unit keeps none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try std.json.parseFromSlice(std.json.Value, a,
        \\{"entry":"main_native","entry_parameters":[],"functions":[
        \\{"symbol":"main_native","name":"main","locations":[{"path":"a.my","line":3,"column":5},{"path":"a.my","line":4,"column":1}],
        \\ "messages":["","x \"two\""],"inlines":[{"callee":"myl_f_abc","start":1,"end":4,"callee_start":0,"call_position":0}]},
        \\{"symbol":"myl_f_abc","name":"m::f","locations":[]}]}
    , .{});
    const functions = v.array(v.get(parsed.value, "functions"));
    const assembly = try metadataAssembly(a, functions);
    // The record: name, locations, count, messages, inline frames, inline count.
    try std.testing.expect(std.mem.indexOf(u8, assembly, "\t.section\t.data.rel.ro.main_native_meta,\"aw\",@progbits\n\t.p2align\t3\n\t.globl\tmain_native_meta\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, assembly, "main_native_meta:\n\t.quad\t.Lmyl_s_0\n\t.quad\t.Lmyl_l_0\n\t.quad\t2\n\t.quad\t.Lmyl_m_0\n\t.quad\t.Lmyl_i_0\n\t.quad\t1\n") != null);
    // One location per pc, sharing one copy of the path; one message per pc.
    try std.testing.expect(std.mem.indexOf(u8, assembly, ".Lmyl_l_0:\n\t.quad\t.Lmyl_s_1\n\t.quad\t3\n\t.quad\t5\n\t.quad\t.Lmyl_s_1\n\t.quad\t4\n\t.quad\t1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, assembly, ".Lmyl_m_0:\n\t.quad\t.Lmyl_s_2\n\t.quad\t.Lmyl_s_3\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, assembly, ".Lmyl_i_0:\n\t.quad\tmyl_f_abc_meta\n\t.quad\t1\n\t.quad\t4\n\t.quad\t0\n\t.quad\t0\n") != null);
    // A function with no locations keeps one zero location and one empty message.
    const empty = "myl_f_abc_meta:\n\t.quad\t.Lmyl_s_4\n\t.quad\t.Lmyl_l_1\n\t.quad\t0\n\t.quad\t.Lmyl_m_1\n\t.quad\t0\n\t.quad\t0\n" ++
        ".Lmyl_l_1:\n\t.quad\t0\n\t.quad\t0\n\t.quad\t0\n.Lmyl_m_1:\n\t.quad\t.Lmyl_s_2\n";
    try std.testing.expect(std.mem.indexOf(u8, assembly, empty) != null);
    try std.testing.expect(std.mem.indexOf(u8, assembly, "\t.section\t.rodata.str1.1,\"aMS\",@progbits,1\n.Lmyl_s_0:\n\t.asciz\t\"main\"\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, assembly, ".Lmyl_s_3:\n\t.asciz\t\"x \\\"two\\\"\"\n") != null);
    // The shared C unit defines no function's metadata, and without a frame
    // map it names none either (QBE-BATCH-4).
    const shared = try sharedMetadata(a, parsed.value);
    try std.testing.expect(std.mem.indexOf(u8, shared, "main_native_meta") == null);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    // The allocating writer reports a failed allocation as a failed write.
    try std.testing.expectError(error.WriteFailed, metadataAssembly(failing.allocator(), functions));
}

// spec: QBE-BATCH-4
// spec: QBE-FRAMEMAP-ROOTS-1
test "the shared metadata unit names no function, so a new function leaves it unchanged, and only the full-table unit roots them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const one = try std.json.parseFromSliceLeaky(std.json.Value, a,
        \\{"entry":"main_native","functions":[{"symbol":"main_native","name":"main","il":"export function $main_native() {\n@s\n ret\n}\n"}]}
    , .{});
    const two = try std.json.parseFromSliceLeaky(std.json.Value, a,
        \\{"entry":"main_native","functions":[{"symbol":"main_native","name":"main","il":"export function $main_native() {\n@s\n ret\n}\n"},
        \\{"symbol":"myl_f_abc","name":"m::f","il":"export function $myl_f_abc() {\n@s\n ret\n}\n"}]}
    , .{});
    try std.testing.expectEqualStrings(try sharedMetadata(a, one), try sharedMetadata(a, two));
    // A frame-map program's batched shared unit names no function either: its
    // frame-map sections keep each `_meta` the table reaches, and it is never LTO.
    const mapped_one = try std.json.parseFromSliceLeaky(std.json.Value, a,
        \\{"entry":"main_native","functions":[{"symbol":"main_native","name":"main","il":"dbgfile \"main_native\"\nexport function $main_native() {\n@s\n ret\n}\n"}]}
    , .{});
    const mapped = try std.json.parseFromSliceLeaky(std.json.Value, a,
        \\{"entry":"main_native","functions":[{"symbol":"main_native","name":"main","il":"dbgfile \"main_native\"\nexport function $main_native() {\n@s\n ret\n}\n"},
        \\{"symbol":"myl_f_abc","name":"m::f","il":"export function $myl_f_abc() {\n@s\n ret\n}\n"}]}
    , .{});
    const shared = try sharedMetadata(a, mapped);
    try std.testing.expectEqualStrings(try sharedMetadata(a, mapped_one), shared);
    try std.testing.expect(std.mem.indexOf(u8, shared, "myl_f_abc_meta") == null);
    try std.testing.expect(std.mem.indexOf(u8, shared, "mylang_frame_map_functions") == null);
    // The full-table unit, which an LTO build links, still roots every function's metadata.
    const rooted = try metadata(a, mapped);
    try std.testing.expect(std.mem.indexOf(u8, rooted, "extern const MylQbeFunction myl_f_abc_meta;") != null);
    try std.testing.expect(std.mem.indexOf(u8, rooted, "&myl_f_abc_meta,") != null);
}

// spec: BUILD-METADATA-KEY-1
test "a batch's metadata digest changes exactly when its rendered tables can" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const frame = ",\"inlines\":[{\"callee\":\"myl_f_b\",\"start\":0,\"end\":1,\"callee_start\":0,\"call_position\":1}]}";
    const base = "{\"symbol\":\"myl_f_a\",\"name\":\"m::a\",\"paths\":[\"m.my\"],\"positions\":\"0:3:5 0:4:1\",\"assertions\":[[1,\"x\"]]" ++ frame;
    const variants = [_][]const u8{
        base,
        "{\"symbol\":\"myl_f_a\",\"name\":\"m::a\",\"paths\":[\"m.my\"],\"positions\":\"0:3:5 0:5:1\",\"assertions\":[[1,\"x\"]]" ++ frame,
        "{\"symbol\":\"myl_f_a\",\"name\":\"m::a\",\"paths\":[\"n.my\"],\"positions\":\"0:3:5 0:4:1\",\"assertions\":[[1,\"x\"]]" ++ frame,
        "{\"symbol\":\"myl_f_a\",\"name\":\"m::a\",\"paths\":[\"m.my\"],\"positions\":\"0:3:5 0:4:1\",\"assertions\":[[1,\"y\"]]" ++ frame,
        "{\"symbol\":\"myl_f_a\",\"name\":\"m::c\",\"paths\":[\"m.my\"],\"positions\":\"0:3:5 0:4:1\",\"assertions\":[[1,\"x\"]]" ++ frame,
        "{\"symbol\":\"myl_f_a\",\"name\":\"m::a\",\"paths\":[\"m.my\"],\"positions\":\"0:3:5 0:4:1\",\"assertions\":[[1,\"x\"]]," ++
            "\"inlines\":[{\"callee\":\"myl_f_b\",\"start\":0,\"end\":2,\"callee_start\":0,\"call_position\":1}]}",
        "{\"symbol\":\"myl_f_a\",\"name\":\"m::a\",\"locations\":[{\"path\":\"m.my\",\"line\":3,\"column\":5},{\"path\":\"m.my\",\"line\":4,\"column\":1}]," ++
            "\"messages\":[\"\",\"x\"]" ++ frame,
    };
    try std.testing.expectEqual(variants.len, try distinctDigests(a, &variants));
    // The same fields give the same digest, and so the same cached object.
    const first = metadataDigest(&.{try std.json.parseFromSliceLeaky(std.json.Value, a, base, .{})});
    const again = metadataDigest(&.{try std.json.parseFromSliceLeaky(std.json.Value, a, base, .{})});
    try std.testing.expectEqualSlices(u8, &first, &again);
}
/// How many distinct metadata digests the one-unit batches `texts` have.
fn distinctDigests(a: std.mem.Allocator, texts: []const []const u8) !usize {
    var seen: std.array_hash_map.Auto([32]u8, void) = .empty;
    for (texts) |text| try seen.put(a, metadataDigest(&.{try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{})}), {});
    return seen.count();
}

// spec-case: QBE-BATCH-3
test "literal markers are found only where a line starts with one" {
    const il = "# myl-lit a t 1 1 00\nexport function l $f() {\n@s\n %x =l copy 1 # myl-lit b t 1 1 00\n ret 0\n}\n# myl-lit c t 1 1 01";
    var lines: MarkerLines = .{ .il = il };
    try std.testing.expectEqualStrings("# myl-lit a t 1 1 00", lines.next().?);
    try std.testing.expectEqualStrings("# myl-lit c t 1 1 01", lines.next().?);
    try std.testing.expectEqual(@as(?[]const u8, null), lines.next());
    var none: MarkerLines = .{ .il = "export function l $f() {\n@s\n ret 0\n}" };
    try std.testing.expectEqual(@as(?[]const u8, null), none.next());
}

// spec: QBE-TEARDOWN-1
test "QBE-TEARDOWN-1 a final run skips the exit sweep and any other run keeps it" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"entry":"main_native","entry_parameters":[],"functions":[{"symbol":"main_native","name":"main","locations":[]}]}
    , .{});
    defer parsed.deinit();
    const last = try entry(std.testing.allocator, parsed.value, false, true);
    defer std.testing.allocator.free(last);
    try std.testing.expect(std.mem.indexOf(u8, last, "myl_qbe_exit_without_sweep();") != null);
    const first = try entry(std.testing.allocator, parsed.value, false, false);
    defer std.testing.allocator.free(first);
    try std.testing.expect(std.mem.indexOf(u8, first, "myl_qbe_exit_without_sweep") == null);
}
