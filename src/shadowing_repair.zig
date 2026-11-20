//! The repair note on an `E_SHADOWING` refusal of a binding that hides a module-level name or an import alias (lane
//! FR18): the `selka rename` command line that renames the binding, complete but for the new name, which is the
//! author's to choose (so the refusal carries no `fix`). When more than one refusal of one check hides the same name, the
//! note gives the command that renames them all (`hiding:NAME`) with their count.
//!
//! The note is added where diagnostics are rendered, after the check and every cache, so no stored diagnostic changes;
//! its paths are relative to the working directory, so the command runs as printed from where the check ran.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");

/// Where the check ran: the project root its diagnostic paths are relative to, the working directory, and the entry
/// file's path relative to the root. All three absolute or all relative to one directory.
pub const Paths = struct { root: []const u8, cwd: []const u8, entry: []const u8 };

/// What one refusal's message says it hides.
pub const Hidden = struct { name: []const u8, module_level: bool };

/// The name a refusal of `module_names.shadowingMessage` hides, and whether it is a module-level name or an import alias
/// (not another local, a parameter or a length parameter); null for any other message.
pub fn hiddenBy(message: []const u8) ?Hidden {
    const marker = "` would hide ";
    const tail = ": a name is bound once where it is visible, so choose another name";
    if (!std.mem.endsWith(u8, message, tail)) return null;
    const open = std.mem.indexOfScalar(u8, message, '`') orelse return null;
    const close = std.mem.indexOfPos(u8, message, open + 1, marker) orelse return null;
    const name = message[open + 1 .. close];
    const kind = message[close + marker.len .. message.len - tail.len];
    const expected = std.mem.lastIndexOf(u8, kind, " `") orelse return null;
    const local = for ([_][]const u8{ "the local", "the parameter", "the length parameter" }) |word| {
        if (std.mem.eql(u8, kind[0..expected], word)) break true;
    } else false;
    return .{ .name = name, .module_level = !local };
}

/// `items` with the repair note added to every `E_SHADOWING` refusal of a binding that hides a module-level name or an
/// import alias; `items` itself when there is none.
pub fn annotate(allocator: std.mem.Allocator, items: []const diagnostic.Diagnostic, src: source.Source, paths: Paths) std.mem.Allocator.Error![]const diagnostic.Diagnostic {
    var counts: std.array_hash_map.String(usize) = .empty;
    defer counts.deinit(allocator);
    for (items) |item| {
        const hidden = repairable(item) orelse continue;
        const slot = try counts.getOrPut(allocator, hidden.name);
        slot.value_ptr.* = if (slot.found_existing) slot.value_ptr.* + 1 else 1;
    }
    if (counts.count() == 0) return items;
    const noted = try allocator.dupe(diagnostic.Diagnostic, items);
    const entry = try relative(allocator, paths, paths.entry);
    for (noted) |*item| {
        const hidden = repairable(item.*) orelse continue;
        const count = counts.get(hidden.name).?;
        const message = if (count > 1)
            try std.fmt.allocPrint(allocator, "{d} bindings of this program hide `{s}`; rename them all with `selka rename {s} hiding:{s} <new-name>`", .{ count, hidden.name, entry, hidden.name })
        else at: {
            const location = src.locate(item.span.start);
            const file = try relative(allocator, paths, location.path);
            break :at try std.fmt.allocPrint(allocator, "rename the binding with `selka rename {s} {s}:{d}:{d} <new-name>`", .{ entry, file, location.line, location.column });
        };
        item.provenance.requirement = .{ .span = item.span, .message = message };
    }
    return noted;
}

fn repairable(item: diagnostic.Diagnostic) ?Hidden {
    if (!std.mem.eql(u8, item.code, diagnostic.shadowing) or item.provenance.requirement != null) return null;
    const hidden = hiddenBy(item.message) orelse return null;
    return if (hidden.module_level) hidden else null;
}

/// A path the diagnostics print relative to the root, as a path relative to the working directory.
fn relative(allocator: std.mem.Allocator, paths: Paths, path: []const u8) std.mem.Allocator.Error![]const u8 {
    const absolute = try std.fs.path.resolve(allocator, &.{ paths.root, path });
    return std.fs.path.relative(allocator, paths.cwd, null, paths.cwd, absolute);
}
