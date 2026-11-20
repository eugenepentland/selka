//! FR34: a call's qualifier that is nothing at all.
//!
//! `nosuch.f(1)` where `nosuch` is no local, no parameter, no type and no imported module was refused as `E_UNKNOWN_TYPE:
//! type is not declared`, which says nothing about a call or about `nosuch` being a qualifier. The message here says what is
//! true: the name is not in scope, and which names that are in scope are close to it. The checker words it where it resolves
//! the qualifier; the session's FR32 pass (`project_module_import.zig`) still recognises it, so a qualifier that is a module
//! file of the project is told to import it.
const std = @import("std");

/// The words that follow the qualifier in the message, and that `isMessage` looks for.
const fixed = " is not a name in scope here: it is no local, parameter, type or imported module, and no module file of this project has that name";

/// The message for a qualifier `name` that names nothing. `near` is the `; did you mean ...?` clause for the names in scope that
/// are close to it, or an empty string.
pub fn message(allocator: std.mem.Allocator, name: []const u8, near: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "`{s}`{s}{s}", .{ name, fixed, near });
}

/// Whether `text` is the message `message` builds.
pub fn isMessage(text: []const u8) bool {
    if (!std.mem.startsWith(u8, text, "`")) return false;
    const close = std.mem.indexOfScalarPos(u8, text, 1, '`') orelse return false;
    return std.mem.startsWith(u8, text[close + 1 ..], fixed);
}
