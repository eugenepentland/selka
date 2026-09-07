//! Strict ordinary JSON decoded into a generic preorder tape, independent of application schemas.
const std = @import("std");
const json = @import("typed_json.zig");
/// Parse failures preserve malformed-input and resource-limit distinctions.
pub const Error = json.ParseError;
/// Every node has kind, text start/end, subtree end, child count and integer payload.
/// Node zero is the missing sentinel. UTF-8 bytes follow the six-word node headers.
pub const stride = 6;
/// The owned tape uses decoded UTF-8, so escaped and literal field names compare identically.
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) Error![]i64 {
    if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidCharacter;
    try json.scanDocument(allocator, bytes, .{ .max_bytes = 1024 * 1024, .max_tokens = 2 * 1024 * 1024, .max_depth = 64 });
    var document = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{ .allocate = .alloc_always, .parse_numbers = false, .duplicate_field_behavior = .@"error" }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.DuplicateField => error.DuplicateField,
        else => error.SyntaxError,
    };
    defer document.deinit();
    var builder: Builder = .{ .allocator = allocator };
    defer builder.words.deinit(allocator);
    defer builder.text.deinit(allocator);
    try builder.words.appendNTimes(allocator, 0, stride);
    try builder.node(document.value);
    const offset = builder.words.items.len;
    var index: usize = stride;
    while (index < offset) : (index += stride) {
        if (builder.words.items[index] != 3) continue;
        builder.words.items[index + 1] += @intCast(offset);
        builder.words.items[index + 2] += @intCast(offset);
    }
    for (builder.text.items) |byte| try builder.words.append(allocator, byte);
    return builder.words.toOwnedSlice(allocator);
}
const Builder = struct {
    allocator: std.mem.Allocator,
    words: std.ArrayList(i64) = .empty,
    text: std.ArrayList(u8) = .empty,
    fn node(self: *Builder, value: std.json.Value) Error!void {
        const start = self.words.items.len;
        try self.words.appendNTimes(self.allocator, 0, stride);
        switch (value) {
            .object => |object| {
                self.words.items[start] = 1;
                self.words.items[start + 4] = @intCast(object.count());
                var entries = object.iterator();
                while (entries.next()) |entry| {
                    try self.node(.{ .string = entry.key_ptr.* });
                    try self.node(entry.value_ptr.*);
                }
            },
            .array => |array| {
                self.words.items[start] = 2;
                self.words.items[start + 4] = @intCast(array.items.len);
                for (array.items) |child| try self.node(child);
            },
            .string => |text| {
                if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidCharacter;
                self.words.items[start] = 3;
                self.words.items[start + 1] = @intCast(self.text.items.len);
                try self.text.appendSlice(self.allocator, text);
                self.words.items[start + 2] = @intCast(self.text.items.len);
            },
            .number_string => |number| {
                if (std.mem.indexOfAny(u8, number, ".eE") == null) {
                    self.words.items[start] = 4;
                    self.words.items[start + 5] = try std.fmt.parseInt(i64, number, 10);
                } else {
                    const parsed = try std.fmt.parseFloat(f64, number);
                    if (!std.math.isFinite(parsed)) return error.InvalidNumber;
                    self.words.items[start] = 5;
                }
            },
            .bool => |boolean| self.words.items[start] = if (boolean) 6 else 7,
            .null => self.words.items[start] = 8,
            .integer, .float => return error.InternalError,
        }
        self.words.items[start + 3] = @intCast(self.words.items.len / stride);
    }
};
