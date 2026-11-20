//! The headers a C file may ask for beside itself, found by reading its text.
//!
//! A compiler's dependency file lists the headers it opened. It cannot list the ones it looked
//! for and did not find: a quoted `#include` tries the including file's own directory first and
//! falls through to the system directories, and `__has_include` only asks whether a file is
//! there. A `--link` object is served while every listed header keeps its bytes, so a header
//! that appears next to the source later (one that shadows a system header, or one `__has_include`
//! tests for) would leave a stale object in use. The names this file finds are checked for
//! presence beside each file that names them, so the object is rebuilt when one appears or goes.
const std = @import("std");

/// The quoted header names `text` includes (`#include`, `#include_next`, `#import`) or tests with
/// `__has_include` and `__has_include_next`, in order. Angle-bracket names are searched in the
/// system directories only, which the toolchain's identity covers. Null when a directive or test
/// names its header through a macro or across lines: the names cannot be read from the text.
pub fn quotedNames(a: std.mem.Allocator, text: []const u8) error{OutOfMemory}!?[]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!try directives(a, line, &names)) return null;
        if (!try tests(a, line, &names)) return null;
    }
    return names.items;
}

/// Whether the include directive on `line`, if it has one, names its header readably.
fn directives(a: std.mem.Allocator, line: []const u8, names: *std.ArrayList([]const u8)) error{OutOfMemory}!bool {
    const start = std.mem.trimStart(u8, line, " \t");
    if (start.len == 0 or start[0] != '#') return true;
    const rest = std.mem.trimStart(u8, start[1..], " \t");
    for ([_][]const u8{ "include_next", "include", "import" }) |directive| {
        if (!std.mem.startsWith(u8, rest, directive)) continue;
        const after = rest[directive.len..];
        if (after.len != 0 and (std.ascii.isAlphanumeric(after[0]) or after[0] == '_')) continue;
        return argument(a, after, names);
    }
    return true;
}

/// Whether every `__has_include(...)` or `__has_include_next(...)` on `line` names its header readably.
fn tests(a: std.mem.Allocator, line: []const u8, names: *std.ArrayList([]const u8)) error{OutOfMemory}!bool {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, line, from, "__has_include")) |at| {
        var rest = line[at + "__has_include".len ..];
        from = at + "__has_include".len;
        if (std.mem.startsWith(u8, rest, "_next")) rest = rest["_next".len..];
        if (rest.len != 0 and (std.ascii.isAlphanumeric(rest[0]) or rest[0] == '_')) continue;
        const open = std.mem.trimStart(u8, rest, " \t");
        // `defined(__has_include)` and `#ifdef __has_include` ask about the feature, not about a file.
        if (open.len == 0 or open[0] != '(') continue;
        if (!try argument(a, open[1..], names)) return false;
    }
    return true;
}

/// Read one header argument: a quoted name is recorded, an angle-bracket name needs no check,
/// anything else (a macro, a line break) cannot be read.
fn argument(a: std.mem.Allocator, text: []const u8, names: *std.ArrayList([]const u8)) error{OutOfMemory}!bool {
    const trimmed = std.mem.trimStart(u8, text, " \t");
    if (trimmed.len == 0) return false;
    if (trimmed[0] == '<') return true;
    if (trimmed[0] != '"') return false;
    const end = std.mem.indexOfScalarPos(u8, trimmed, 1, '"') orelse return false;
    try names.append(a, trimmed[1..end]);
    return true;
}

test "quoted includes and has_include tests are read, angle names are not needed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = "#include <stdint.h>\n  # include \"local.h\"\n#if __has_include(\"opt.h\") && defined(__has_include)\n#endif\n#include_next \"next.h\"\nint x;\n";
    const names = (try quotedNames(arena.allocator(), text)).?;
    try std.testing.expectEqual(@as(usize, 3), names.len);
    try std.testing.expectEqualStrings("local.h", names[0]);
    try std.testing.expectEqualStrings("opt.h", names[1]);
    try std.testing.expectEqualStrings("next.h", names[2]);
}

test "a header named through a macro or across lines cannot be read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(?[]const []const u8, null), try quotedNames(arena.allocator(), "#define HEADER \"x.h\"\n#include HEADER\n"));
    try std.testing.expectEqual(@as(?[]const []const u8, null), try quotedNames(arena.allocator(), "#if __has_include(\n\"x.h\")\n#endif\n"));
    try std.testing.expectEqual(@as(?[]const []const u8, null), try quotedNames(arena.allocator(), "#if __has_include(OPTIONAL)\n#endif\n"));
    const plain = (try quotedNames(arena.allocator(), "#ifdef __has_include\n#endif\nint include = 1; // #include \"in a comment is harmless\"\n")).?;
    try std.testing.expectEqual(@as(usize, 0), plain.len);
}
