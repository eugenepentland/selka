//! The checked program's type identities: builtin scalars, capability and
//! resource kinds, and nominal records by index (`record_base` onward), plus the
//! collection shape a managed record carries. Front end and new core read them.
const std = @import("std");
const external_resources = @import("external_resources.zig");

/// Scalar and nominal type identities shared by checked syntax and runtime values.
pub const Type = enum(usize) {
    i64,
    bool,
    i8,
    i16,
    i32,
    u8,
    u16,
    u32,
    u64,
    clock_cap,
    random_cap,
    filesystem_cap,
    network_cap,
    environment_cap,
    /// The authority behind an `extern def` or `host def`; checked at every call
    /// and dropped before the foreign call itself.
    host_cap,
    unit,
    /// An open byte-oriented file owned by the guest through a `with` scope.
    file,
    /// An open UTF-8 text file; its reads produce `str` rather than `bytes`.
    text_file,
    /// A standard output capability; its value's sentinel selects stdout or stderr.
    stream_cap,
    _,
    pub const record_base: usize = 19;
    /// Return the compact builtin capability index, or null for non-capabilities.
    pub fn capabilityIndex(self: Type) ?u3 {
        return switch (self) {
            .clock_cap => 0,
            .random_cap => 1,
            .filesystem_cap => 2,
            .network_cap => 3,
            .environment_cap => 4,
            .stream_cap => 5,
            .host_cap => 6,
            else => null,
        };
    }
    /// Whether this capability kind is the standard output stream.
    pub fn isStream(self: Type) bool {
        return self == .stream_cap;
    }
    /// Return the external resource family represented by this builtin type.
    pub fn resourceKind(self: Type) ?external_resources.Kind {
        return switch (self) {
            .filesystem_cap => .filesystem,
            .network_cap => .network,
            else => null,
        };
    }
    /// Identify an open file handle, whose cleanup closes a provider resource.
    pub fn isFile(self: Type) bool {
        return self == .file or self == .text_file;
    }
    /// Integer width and signedness used for range checks and native layout.
    pub const Integer = struct { bits: u7, signed: bool };
    /// Return integer width and signedness, or null for other types.
    pub fn integer(self: Type) ?Integer {
        return switch (self) {
            .i8 => .{ .bits = 8, .signed = true },
            .i16 => .{ .bits = 16, .signed = true },
            .i32 => .{ .bits = 32, .signed = true },
            .i64 => .{ .bits = 64, .signed = true },
            .u8 => .{ .bits = 8, .signed = false },
            .u16 => .{ .bits = 16, .signed = false },
            .u32 => .{ .bits = 32, .signed = false },
            .u64 => .{ .bits = 64, .signed = false },
            else => null,
        };
    }
    /// Identify builtin signed and unsigned integer types.
    pub fn isInteger(self: Type) bool {
        return self.integer() != null;
    }
    /// Identify a nominal aggregate identity rather than a builtin scalar.
    pub fn isAggregate(self: Type) bool {
        return @backingInt(self) >= record_base;
    }
    /// Convert a nominal type identity into its schema table index.
    pub fn recordIndex(self: Type) usize {
        return @backingInt(self) - record_base;
    }
    /// Return the mathematical lower bound for this integer type.
    pub fn min(self: Type) i128 {
        const info = self.integer().?;
        return if (info.signed) -(@as(i128, 1) << (info.bits - 1)) else 0;
    }
    /// Return the mathematical upper bound for this integer type.
    pub fn max(self: Type) i128 {
        const info = self.integer().?;
        return (@as(i128, 1) << (info.bits - @as(u7, if (info.signed) 1 else 0))) - 1;
    }
    /// Check whether a mathematical integer lies within this type's bounds.
    pub fn fits(self: Type, value: i128) bool {
        return value >= self.min() and value <= self.max();
    }
    /// Canonical external decimal spelling shared by manifests and codecs.
    /// Language source literals have their own lexer and may use width suffixes.
    pub fn parseDecimal(self: Type, text: []const u8) error{ InvalidInteger, IntegerOutOfRange }!i128 {
        if (!self.isInteger() or text.len == 0 or text.len > 20) return error.InvalidInteger;
        const negative = text[0] == '-';
        const digits = text[@intFromBool(negative)..];
        if (digits.len == 0 or (digits[0] == '0' and (digits.len != 1 or negative))) return error.InvalidInteger;
        for (digits) |digit| if (!std.ascii.isDigit(digit)) return error.InvalidInteger;
        const value = std.fmt.parseInt(i128, text, 10) catch return error.InvalidInteger;
        if (!self.fits(value)) return error.IntegerOutOfRange;
        return value;
    }
    /// Resolve a builtin type spelling without consulting nominal schemas.
    pub fn fromName(name: []const u8) ?Type {
        if (name.len == 0 or std.mem.eql(u8, name, "None")) return .unit;
        if (std.mem.eql(u8, name, "int")) return .i64;
        if (name.len >= 2 and name[0] == '(' and name[name.len - 1] == ')') {
            if (std.mem.trim(u8, name[1 .. name.len - 1], " \t\r\n").len == 0) return .unit;
        }
        return std.meta.stringToEnum(Type, name);
    }
    pub fn format(self: Type, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.isAggregate()) try writer.print("type#{d}", .{@backingInt(self)}) else try writer.writeAll(@tagName(self));
    }
};

/// Managed collection representation family.
pub const ManagedKind = enum { list, string, dictionary, bytes };

/// Representation metadata shared by checked schemas and GC headers.
/// `set` marks a `set[T]`: a dictionary-kind collection whose keys are the
/// elements and whose values are unit, so every dictionary path — hashing,
/// iteration, equality, tracing, arena escape — serves it unchanged.
/// `box` marks the one-field managed record the backend stores a recursive
/// value's boxed field in (RECURSIVE-VALUES-2): it is never written after it
/// is built, and equality, hashing and printing look through it.
pub const CollectionShape = struct { kind: ManagedKind = .list, key: ?Type = null, contains_cell: bool = false, set: bool = false, box: bool = false };
