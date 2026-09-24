//! One manifest unit's text, digest and build facts, whether the unit carries
//! its QBE text inline (`il`) or, in a lean manifest, names the text the
//! compiler stored in its fragment store (`il_digest`, `il_file`, `il_facts`;
//! `QBE-FRAGMENT-REUSE-1`). The driver reads a stored text only when the object
//! it names has to be built, so an unchanged unit costs a digest, not its text.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");

/// A stored unit whose file is missing or no longer matches its digest.
pub const Error = fs.Error || error{InvalidNativeManifest};

const inline_key = "il";
const digest_key = "il_digest";
const file_key = "il_file";
const facts_key = "il_facts";

/// Whether a unit carries its text, or a complete stored reference to it.
pub fn wellFormed(unit: std.json.Value) bool {
    if (v.get(unit, inline_key) == .string) return true;
    const named = v.get(unit, digest_key);
    if (named != .string or named.string.len != 64) return false;
    for (named.string) |byte| if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) return false;
    return v.get(unit, file_key) == .string and v.get(unit, facts_key) == .string;
}

/// The lines of the unit text the driver reads without compiling it: the whole
/// text for an inline unit, the recorded `dbgfile` and `# ` marker lines for a
/// stored one. Both answer `usesFrameMap` and the literal scan identically.
pub fn facts(unit: std.json.Value) []const u8 {
    const il = v.get(unit, inline_key);
    if (il == .string) return il.string;
    return v.text(v.get(unit, facts_key));
}

/// The lowercase hex BLAKE3 digest of the unit text, which names its object;
/// the compiler's fragment store names a stored text by the same digest.
pub fn digest(allocator: std.mem.Allocator, unit: std.json.Value) error{OutOfMemory}![]const u8 {
    const il = v.get(unit, inline_key);
    if (il != .string) return v.text(v.get(unit, digest_key));
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(il.string, &hash, .{});
    return allocator.dupe(u8, &std.fmt.bytesToHex(hash, .lower));
}

/// The unit text: inline, or read from the fragment store and checked against
/// its digest, so a damaged or replaced file can never build a wrong object.
pub fn text(context: fs.Context, unit: std.json.Value) Error![]const u8 {
    const il = v.get(unit, inline_key);
    if (il == .string) return il.string;
    const bytes = context.read(v.text(v.get(unit, file_key))) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return missing(context, unit),
    };
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &hash, .{});
    if (!std.mem.eql(u8, &std.fmt.bytesToHex(hash, .lower), v.text(v.get(unit, digest_key)))) return missing(context, unit);
    return bytes;
}

/// Name the unit whose stored text is gone, then refuse the manifest.
fn missing(context: fs.Context, unit: std.json.Value) Error {
    const message = std.fmt.allocPrint(
        context.allocator,
        "mylang: the stored QBE text of `{s}` is missing or damaged ({s}); rebuild with --no-cache\n",
        .{ v.text(v.get(unit, "name")), v.text(v.get(unit, file_key)) },
    ) catch return error.OutOfMemory;
    std.Io.File.stderr().writeStreamingAll(context.io, message) catch return error.InvalidNativeManifest;
    return error.InvalidNativeManifest;
}

// spec-case: QBE-FRAGMENT-REUSE-1
test "an inline and a stored unit with the same text share one digest and one fact set" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const il = "dbgfile \"myl_f_x\"\nexport function $myl_f_x() {\n@start\n ret\n}\n";
    const inline_unit = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"name\":\"m::x\",\"il\":\"dbgfile \\\"myl_f_x\\\"\\nexport function $myl_f_x() {\\n@start\\n ret\\n}\\n\"}", .{});
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(il, &hash, .{});
    const hex = std.fmt.bytesToHex(hash, .lower);
    const stored_text = try std.fmt.allocPrint(a, "{{\"name\":\"m::x\",\"il_digest\":\"{s}\",\"il_file\":\"/nonexistent/unit\",\"il_facts\":\"dbgfile \\\"myl_f_x\\\"\\n\"}}", .{&hex});
    const stored = try std.json.parseFromSliceLeaky(std.json.Value, a, stored_text, .{});
    try std.testing.expect(wellFormed(inline_unit));
    try std.testing.expect(wellFormed(stored));
    try std.testing.expectEqualStrings(try digest(a, inline_unit), try digest(a, stored));
    try std.testing.expect(std.mem.startsWith(u8, facts(stored), "dbgfile "));
    // A truncated digest is not a stored reference.
    const short = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"il_digest\":\"ab\",\"il_file\":\"f\",\"il_facts\":\"\"}", .{});
    try std.testing.expect(!wellFormed(short));
}
