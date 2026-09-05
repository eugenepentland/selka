//! Typed scalar input declarations with deterministic, injection-free module output.
const std = @import("std");
const lexer = @import("lexer.zig");
const Type = @import("typed.zig").Type;
pub const Entry = struct { name: []const u8, type: []const u8, value: []const u8 };
pub const Document = struct { version: u32, module: []const u8, values: []const Entry };
pub const Manifest = struct {
    parsed: std.json.Parsed(Document),
    digest: [32]u8,
    pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) !Manifest {
        if (bytes.len > 1024 * 1024) return error.ManifestTooLarge;
        const parsed = try std.json.parseFromSlice(Document, allocator, bytes, .{ .allocate = .alloc_always });
        errdefer parsed.deinit();
        const document = parsed.value;
        if (document.version != 1) return error.UnsupportedInputVersion;
        if (document.module.len == 0 or document.module.len > 256) return error.InvalidInputModule;
        var segments = std.mem.splitScalar(u8, document.module, '.');
        while (segments.next()) |part| if (!lexer.isIdentifier(part)) return error.InvalidInputModule;
        if (document.values.len > 1024) return error.TooManyInputs;
        var names: std.StringHashMapUnmanaged(void) = .empty;
        defer names.deinit(allocator);
        for (document.values) |entry| {
            if (entry.name.len > 128 or !lexer.isIdentifier(entry.name)) return error.InvalidInputName;
            if ((try names.getOrPut(allocator, entry.name)).found_existing) return error.DuplicateInputName;
            try validateValue(entry);
        }
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        return .{ .parsed = parsed, .digest = digest };
    }
    pub fn deinit(self: *Manifest) void {
        self.parsed.deinit();
    }
    pub fn generate(self: Manifest, allocator: std.mem.Allocator) ![]u8 {
        return self.generateInner(allocator) catch |err| switch (err) {
            error.WriteFailed => error.OutOfMemory,
            else => return err,
        };
    }
    fn generateInner(self: Manifest, allocator: std.mem.Allocator) ![]u8 {
        var output: std.Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();
        const writer = &output.writer;
        try writer.print("// generated input manifest v1 sha256={s}\nmodule {s};\n", .{ std.fmt.bytesToHex(self.digest, .lower), self.parsed.value.module });
        for (self.parsed.value.values) |entry| try writer.print("export {s};\n", .{entry.name});
        for (self.parsed.value.values) |entry| {
            const suffix = if (std.mem.eql(u8, entry.type, "bool") or std.mem.eql(u8, entry.type, "i64")) "" else entry.type;
            try writer.print("fn {s}() -> {s} {{\n    return {s}{s};\n}}\n", .{ entry.name, entry.type, entry.value, suffix });
        }
        return output.toOwnedSlice();
    }
};
fn validateValue(entry: Entry) !void {
    const ty = std.meta.stringToEnum(Type, entry.type) orelse return error.InvalidInputType;
    if (ty == .bool) {
        if (!std.mem.eql(u8, entry.value, "true") and !std.mem.eql(u8, entry.value, "false")) return error.InvalidInputValue;
        return;
    }
    if (!ty.isInteger()) return error.InvalidInputType;
    if (entry.value.len == 0 or entry.value.len > 20) return error.InvalidInputValue;
    const negative = entry.value[0] == '-';
    const digits = entry.value[@intFromBool(negative)..];
    if (digits.len == 0 or (digits[0] == '0' and (digits.len != 1 or negative))) return error.InvalidInputValue;
    for (digits) |digit| if (!std.ascii.isDigit(digit)) return error.InvalidInputValue;
    const value = std.fmt.parseInt(i128, entry.value, 10) catch return error.InvalidInputValue;
    if (!ty.fits(value)) return error.InputValueOutOfRange;
}
