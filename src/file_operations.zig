//! Shared shapes for the Python file surface: whole-path helpers and the
//! methods of an open handle. Representation lives in `file_resources.zig`.
const std = @import("std");

/// Whole-path filesystem helpers; each takes a `Filesystem` capability first.
pub const Access = enum {
    open,
    read_file,
    read_text,
    write_file,
    write_text,
    exists,
    listdir,
    mkdir,
    remove,
    atomic_write_file,
    lock_directory,
    sync_directory,
    read_regular_file,
    list_directory,
    /// Source argument count including the leading capability.
    pub fn arity(self: Access) usize {
        return switch (self) {
            .open, .write_file, .write_text, .atomic_write_file, .read_regular_file, .list_directory => 3,
            else => 2,
        };
    }
    /// Argument count of the qualified `fs.name(...)` spelling, whose receiver is
    /// the capability itself: one fewer than the free-function count.
    pub fn methodArity(self: Access) usize {
        return self.arity() - 1;
    }
};

/// Methods of an open file binding, whose receiver must be a `with` local.
pub const Method = enum {
    read,
    readline,
    readlines,
    write,
    flush,
    close,
    /// Whether this method accepts one optional or required argument.
    pub fn takesArgument(self: Method) bool {
        return self == .read or self == .write;
    }
    /// Whether the argument is required rather than optional.
    pub fn requiresArgument(self: Method) bool {
        return self == .write;
    }
};

/// Resolve a file method spelling, or null for an unknown member name.
pub fn method(name: []const u8) ?Method {
    return std.meta.stringToEnum(Method, name);
}

/// Resolve a whole-path helper spelling, or null for an ordinary call name.
pub fn access(name: []const u8) ?Access {
    return std.meta.stringToEnum(Access, name);
}

/// Decoded `open` mode: the provider request letter and whether reads are text.
/// The letters are the scoped provider's own request grammar.
pub const Mode = struct { letter: u8, text: bool };

/// Parse a Python open mode, rejecting combinations this surface does not offer.
pub fn parseMode(spelling: []const u8) ?Mode {
    if (spelling.len == 0 or spelling.len > 2) return null;
    const letter = switch (spelling[0]) {
        'r', 'w', 'a' => spelling[0],
        else => return null,
    };
    if (spelling.len == 1) return .{ .letter = letter, .text = true };
    return switch (spelling[1]) {
        'b' => .{ .letter = letter, .text = false },
        't' => .{ .letter = letter, .text = true },
        else => null,
    };
}
