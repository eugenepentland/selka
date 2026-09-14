//! Bounded byte input/output only; parsing and schematic decisions belong to the guest.
//! The operations themselves are compiled into the guest's own native executable
//! (`native_schematic.c`); this module describes that boundary to the driver.
const std = @import("std");
/// The trusted provider translation unit linked into every guest executable.
pub const provider = @embedFile("native_schematic.c");
/// Manifest and issue-transport failures of one trusted boundary.
pub const Error = error{ InvalidNativeManifest, OutOfMemory };
/// Located guest failure, separate from native traps and host failures.
pub const Issue = struct { code: i64, file: i64, position: i64 };
/// Every trusted byte operation this host is prepared to serve.
pub const operations = [_][]const u8{
    "io::circuit_input", "io::pinout_input", "io::interface_input",
    "io::length",        "io::byte",         "io::put",
    "io::issue",
};
/// Name the operations this guest actually declares. Older guests omit the named
/// input providers, and a provider that registered one the guest never declared
/// would be rejected before the first call.
pub fn declared(allocator: std.mem.Allocator, manifest: []const u8) Error![]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, manifest, .{ .allocate = .alloc_always }) catch return error.InvalidNativeManifest;
    if (parsed.value != .object) return error.InvalidNativeManifest;
    const host = parsed.value.object.get("host") orelse return error.InvalidNativeManifest;
    if (host != .object) return error.InvalidNativeManifest;
    const list = host.object.get("declarations") orelse return error.InvalidNativeManifest;
    var found: std.ArrayList([]const u8) = .empty;
    for (operations) |name| {
        if (list != .array) break;
        for (list.array.items) |item| {
            const declaration = if (item == .object) item.object.get("name") orelse continue else continue;
            if (declaration == .string and std.mem.eql(u8, declaration.string, name)) try found.append(allocator, name);
        }
    }
    return std.mem.join(allocator, ",", found.items);
}
/// Decode the first located issue a guest reported during one invocation.
pub fn decode(bytes: []const u8) ?Issue {
    var fields = std.mem.tokenizeAny(u8, bytes, " \n");
    var numbers: [3]i64 = undefined;
    for (&numbers) |*number| number.* = std.fmt.parseInt(i64, fields.next() orelse return null, 10) catch return null;
    return .{ .code = numbers[0], .file = numbers[1], .position = numbers[2] };
}
/// Reject invalid UTF-8 and characters XML 1.0 cannot represent before handing bytes to the guest.
pub fn validateDocuments(documents: []const []const u8) ?Issue {
    for (documents, 0..) |bytes, file| {
        if (bytes.len > 1024 * 1024) return .{ .code = 7, .file = @intCast(file), .position = 0 };
        var i: usize = 0;
        while (i < bytes.len) {
            const length = std.unicode.utf8ByteSequenceLength(bytes[i]) catch return .{ .code = 8, .file = @intCast(file), .position = @intCast(i) };
            if (i + length > bytes.len) return .{ .code = 8, .file = @intCast(file), .position = @intCast(i) };
            const cp = std.unicode.utf8Decode(bytes[i..][0..length]) catch return .{ .code = 8, .file = @intCast(file), .position = @intCast(i) };
            const forbidden_control = cp < 32 and cp != 9 and cp != 10 and cp != 13;
            if (forbidden_control or cp == 0xfffe or cp == 0xffff) return .{ .code = 8, .file = @intCast(file), .position = @intCast(i) };
            i += length;
        }
    }
    return null;
}
