//! RC-SITES-1: the C site records of a `--rc-runtime=sites` build.
//!
//! Each lowered unit of a sites build names its runtime and glue call sites
//! in `# myl-rcsite` marker lines (`qbe_rc_sites.zig`). The metadata unit
//! turns every marker into one mutable `myl_rc_site` record, which the
//! unit's code bumps and makes current before the call, plus the
//! `myl_rc_site_table` the runtime's exit report walks. A build of any other
//! runtime has no markers and gets nothing.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const lean = @import("qbe_build_units.zig");

/// A site marker line's start. The emitter's `qbe_rc_sites.marker_word`
/// spells the same word after `# `; the two live in different modules, and
/// the end-to-end sites test catches any drift.
const marker_prefix = "# myl-rcsite ";

/// Output failures while writing the generated C.
pub const Error = std.Io.Writer.Error || error{OutOfMemory};

/// One parsed marker line.
const Marker = struct { site: []const u8, unit: []const u8, pc: []const u8, operation: []const u8, type_hex: []const u8 };

/// Write every unit's site records and the site table, or nothing when no
/// unit names a site.
pub fn definitions(w: *std.Io.Writer, allocator: std.mem.Allocator, units: []const std.json.Value) Error!void {
    var markers: std.ArrayList(Marker) = .empty;
    defer markers.deinit(allocator);
    for (units) |unit| {
        var lines: Lines = .{ .il = lean.facts(unit) };
        while (lines.next()) |line| {
            const marker = parse(line) orelse continue;
            try markers.append(allocator, marker);
        }
    }
    if (markers.items.len == 0) return;
    std.mem.sort(Marker, markers.items, {}, before);
    try w.writeAll("#include \"native_rc_stats.h\"\n#if defined(MYL_NATIVE_RC_SITES) && MYL_NATIVE_RC_SITES\n");
    var previous: []const u8 = "";
    for (markers.items) |marker| {
        if (!std.mem.eql(u8, previous, marker.unit)) try w.print("extern const MylQbeFunction {s}_meta;\n", .{marker.unit});
        previous = marker.unit;
        try record(w, allocator, marker);
    }
    try w.writeAll("myl_rc_site *const myl_rc_site_table[] = {\n");
    for (markers.items) |marker| try w.print("&{s},\n", .{marker.site});
    try w.print("}};\nconst size_t myl_rc_site_count = {d};\n#endif\n", .{markers.items.len});
}

fn before(_: void, left: Marker, right: Marker) bool {
    return std.mem.lessThan(u8, left.site, right.site);
}

// spec-case: MODULE-COMPILE-1
test "site tables ignore whole-program versus module unit order" {
    const a = std.testing.allocator;
    const text =
        \\[{"il":"# myl-rcsite myl_f_b_rcsite0 myl_f_b 1 myl_retain -\n"},{"il":"# myl-rcsite myl_f_a_rcsite0 myl_f_a 2 myl_release -\n"}]
    ;
    const parsed = try std.json.parseFromSlice([]std.json.Value, a, text, .{});
    defer parsed.deinit();
    var original: std.Io.Writer.Allocating = .init(a);
    defer original.deinit();
    try definitions(&original.writer, a, parsed.value);
    std.mem.reverse(std.json.Value, parsed.value);
    var reversed: std.Io.Writer.Allocating = .init(a);
    defer reversed.deinit();
    try definitions(&reversed.writer, a, parsed.value);
    try std.testing.expectEqualStrings(original.written(), reversed.written());
}

fn record(w: *std.Io.Writer, allocator: std.mem.Allocator, marker: Marker) Error!void {
    try w.print("myl_rc_site {s} = {{0, &{s}_meta, ", .{ marker.site, marker.unit });
    if (std.mem.eql(u8, marker.pc, "entry")) {
        try w.writeAll("MYL_RC_SITE_ENTRY");
    } else if (std.mem.eql(u8, marker.pc, "exit")) {
        try w.writeAll("MYL_RC_SITE_EXIT");
    } else try w.print("UINT64_C({s})", .{marker.pc});
    try w.writeAll(", ");
    try v.quote(w, marker.operation);
    try w.writeAll(", ");
    const name = try allocator.alloc(u8, marker.type_hex.len / 2);
    defer allocator.free(name);
    const decoded = std.fmt.hexToBytes(name, marker.type_hex) catch name[0..0];
    try v.quote(w, decoded);
    try w.writeAll("};\n");
}

/// Split one marker line, refusing anything that is not exactly five
/// well-formed fields: a symbol-shaped site, unit and operation, a pc that is
/// a number, `entry` or `exit`, and a hex type name or `-`.
fn parse(line: []const u8) ?Marker {
    var tokens = std.mem.tokenizeScalar(u8, line[marker_prefix.len..], ' ');
    const marker: Marker = .{
        .site = tokens.next() orelse return null,
        .unit = tokens.next() orelse return null,
        .pc = tokens.next() orelse return null,
        .operation = tokens.next() orelse return null,
        .type_hex = tokens.next() orelse return null,
    };
    if (tokens.next() != null) return null;
    for ([_][]const u8{ marker.site, marker.unit, marker.operation }) |name| if (!symbol(name)) return null;
    const pc_ok = std.mem.eql(u8, marker.pc, "entry") or std.mem.eql(u8, marker.pc, "exit") or digits(marker.pc);
    if (!pc_ok) return null;
    if (std.mem.eql(u8, marker.type_hex, "-")) return .{ .site = marker.site, .unit = marker.unit, .pc = marker.pc, .operation = marker.operation, .type_hex = "" };
    if (marker.type_hex.len % 2 != 0) return null;
    for (marker.type_hex) |char| if (!std.ascii.isHex(char)) return null;
    return marker;
}

fn symbol(name: []const u8) bool {
    if (name.len == 0 or std.ascii.isDigit(name[0])) return false;
    for (name) |char| if (!std.ascii.isAlphanumeric(char) and char != '_') return false;
    return true;
}

fn digits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |char| if (!std.ascii.isDigit(char)) return false;
    return true;
}

/// The marker lines of one unit's facts, each at the start of a line.
const Lines = struct {
    il: []const u8,
    at: usize = 0,
    fn next(self: *Lines) ?[]const u8 {
        while (std.mem.indexOfPos(u8, self.il, self.at, marker_prefix)) |found| {
            const end = std.mem.indexOfScalarPos(u8, self.il, found, '\n') orelse self.il.len;
            self.at = end;
            if (found == 0 or self.il[found - 1] == '\n') return self.il[found..end];
        }
        self.at = self.il.len;
        return null;
    }
};

// spec-case: RC-SITES-1
test "site markers become C site records and one table" {
    const a = std.testing.allocator;
    const text =
        \\{"functions":[{"il":"export function l $myl_f_a(l %ctx) {\n@entry\n ret 0\n}\n# myl-rcsite myl_f_a_rcsite0 myl_f_a 12 rcg_loan 4e6f6465\n# myl-rcsite myl_f_a_rcsite1 myl_f_a exit myl_qbe_rc_frame_leave -\n# myl-rcsite bad; myl_f_a 1 x -\n"},{"il":"export function l $myl_f_b(l %ctx) {\n@entry\n ret 0\n}\n"}]}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, a, text, .{});
    defer parsed.deinit();
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    try definitions(&out.writer, a, v.array(v.get(parsed.value, "functions")));
    const c = out.written();
    try std.testing.expect(std.mem.indexOf(u8, c, "extern const MylQbeFunction myl_f_a_meta;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "myl_rc_site myl_f_a_rcsite0 = {0, &myl_f_a_meta, UINT64_C(12), \"rcg_loan\", \"Node\"};") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "myl_rc_site myl_f_a_rcsite1 = {0, &myl_f_a_meta, MYL_RC_SITE_EXIT, \"myl_qbe_rc_frame_leave\", \"\"};") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "bad;") == null);
    try std.testing.expect(std.mem.indexOf(u8, c, "const size_t myl_rc_site_count = 2;") != null);
    var none: std.Io.Writer.Allocating = .init(a);
    defer none.deinit();
    try definitions(&none.writer, a, v.array(v.get(parsed.value, "functions"))[1..]);
    try std.testing.expectEqual(@as(usize, 0), none.written().len);
}
