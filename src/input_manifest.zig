//! Typed scalar input declarations with deterministic, injection-free module output.
/// Failures returned by parse; callers must handle these boundary errors.
pub const ParseError = error{
    InternalError,
    DuplicateField,
    DuplicateInputName,
    InputValueOutOfRange,
    InvalidCharacter,
    InvalidInputModule,
    InvalidInputName,
    InvalidInputType,
    InvalidInputValue,
    InvalidNumber,
    ManifestTooLarge,
    MissingField,
    OutOfMemory,
    Overflow,
    SyntaxError,
    TooManyInputs,
    UnexpectedEndOfInput,
    UnexpectedToken,
    UnknownField,
    UnsupportedInputVersion,
};
/// Failures returned by generate; callers must handle these boundary errors.
pub const GenerateError = error{
    OutOfMemory,
    WriteFailed,
};

const std = @import("std");
const lexer = @import("lexer.zig");
const Type = @import("typed.zig").Type;
/// Named scalar input with explicit type and canonical textual value.
pub const Entry = struct { name: []const u8, type: []const u8, value: []const u8 };
/// Versioned generated-module input manifest containing named scalar values.
pub const Document = struct { version: u32, module: []const u8, values: []const Entry };
/// Parsed and validated manifest owning its JSON parse storage.
pub const Manifest = struct {
    parsed: std.json.Parsed(Document),
    digest: [32]u8,
    /// Validate manifest keys, scalar spellings, ranges, and duplicate input names.
    pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) ParseError!Manifest {
        if (bytes.len > 1024 * 1024) return error.ManifestTooLarge;
        // parseFromSlice supplies complete input and uses its length as max_value_len.
        // These concrete documents contain no fixed-size arrays; generic parser-only
        // failures indicate an internal contract mismatch, not a caller input category.
        const parsed = std.json.parseFromSlice(Document, allocator, bytes, .{ .allocate = .alloc_always }) catch |err| switch (err) {
            error.BufferUnderrun, error.LengthMismatch, error.ValueTooLong, error.InvalidEnumTag => return error.InternalError,
            else => |failure| return failure,
        };
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
    /// Allocate source for the manifest's checked constant input module.
    pub fn generate(self: Manifest, allocator: std.mem.Allocator) GenerateError![]u8 {
        return self.generateInner(allocator) catch |err| switch (err) {
            error.WriteFailed => error.OutOfMemory,
            else => return err,
        };
    }
    fn generateInner(self: Manifest, allocator: std.mem.Allocator) ![]u8 {
        var output: std.Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();
        const writer = &output.writer;
        try writer.print("# generated input manifest v1 sha256={s}\nmodule {s}\n", .{ std.fmt.bytesToHex(self.digest, .lower), self.parsed.value.module });
        for (self.parsed.value.values, 0..) |entry, index| {
            const boolean = std.mem.eql(u8, entry.type, "bool");
            const suffix = if (boolean or std.mem.eql(u8, entry.type, "i64")) "" else entry.type;
            // A manifest spells a boolean the way JSON does; the source spells it the way the guest does.
            const value = if (!boolean) entry.value else if (std.mem.eql(u8, entry.value, "true")) "True" else "False";
            // The canonical layout has one blank line after the header directive
            // group and two between top-level declarations.
            if (index == 0) try writer.print("\n", .{}) else try writer.print("\n\n", .{});
            try writer.print("public def {s}() -> {s} effects():\n    return {s}{s}\n", .{ entry.name, entry.type, value, suffix });
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
    _ = ty.parseDecimal(entry.value) catch |err| return switch (err) {
        error.InvalidInteger => error.InvalidInputValue,
        error.IntegerOutOfRange => error.InputValueOutOfRange,
    };
}
