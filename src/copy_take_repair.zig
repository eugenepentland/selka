//! The edits behind the `W_NEEDLESS_COPY` repairs that replace a copy by `take(mut place)` of a `const` local (case x) or by
//! `options.take_or(own option, default)` (case xi). The pass decides whether the rewrite is certain; this file writes the
//! parts of it that are text: the `mut` that replaces a declaration's `const`, the call, and the `import options` line.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const import_fix = @import("import_fix.zig");
const source = @import("source.zig");

/// The `const` word of the declaration of the local `name` whose name starts at `declaration`: `const name = ...` and
/// `const name: Type = ...` (also `const name: Type`, assigned later) have one, a name that is a loop variable, a pattern
/// binding, one of several names (`const a, b = pair()`), a name after a comma, or any other text has none. The word is what
/// `mut` replaces; null leaves the local alone.
pub fn constWord(bytes: []const u8, declaration: source.Span, name: []const u8) ?source.Span {
    if (declaration.end > bytes.len or declaration.start >= declaration.end) return null;
    if (!std.mem.eql(u8, bytes[declaration.start..declaration.end], name)) return null;
    var end = declaration.start;
    while (end > 0 and (bytes[end - 1] == ' ' or bytes[end - 1] == '\t')) end -= 1;
    // `constx` and `x.const` are not the word, and the word needs a blank before the name.
    if (end == declaration.start or end < "const".len) return null;
    const start = end - "const".len;
    if (!std.mem.eql(u8, bytes[start..end], "const")) return null;
    if (start > 0 and std.mem.indexOfScalar(u8, "_.", bytes[start - 1]) != null) return null;
    if (start > 0 and std.ascii.isAlphanumeric(bytes[start - 1])) return null;
    // A declaration of several names (`const a, b = ...`) makes all of them `mut` or none.
    var after = declaration.end;
    while (after < bytes.len and (bytes[after] == ' ' or bytes[after] == '\t')) after += 1;
    if (after >= bytes.len or std.mem.indexOfScalar(u8, "=:\r\n", bytes[after]) == null) return null;
    return .{ .start = start, .end = end };
}

/// The edit that makes the `const` local of `word` mutable.
pub fn mutEdit(word: source.Span) diagnostic.Edit {
    return .{ .span = word, .text = "mut" };
}

/// The call that replaces a copy of `option.unwrap_or(default)`: `options.take_or(own option, default)` for a named option
/// (`named`), `options.take_or(option, default)` for a call's result.
pub fn takeOrCall(allocator: std.mem.Allocator, named: bool, option: []const u8, default: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "options.take_or({s}{s}, {s})", .{ if (named) "own " else "", option, default });
}

/// The `import options` line the unit of `at` needs, or null when it has the import already.
pub fn importEdit(allocator: std.mem.Allocator, src: source.Source, at: source.Span) (std.mem.Allocator.Error || error{InternalError})!?diagnostic.Edit {
    return import_fix.moduleEdit(allocator, src, at, "options");
}
