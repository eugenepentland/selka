//! Python string methods: trimming, case, search, classification and parsing.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const values = @import("runtime_values.zig");

const text_type: values.Type = @fromBackingInt(@intCast(32));
const list_type: values.Type = @fromBackingInt(@intCast(33));

fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "strings.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

/// The entry module a project program serves to the loader; the standard
/// modules come from the normal loader.
const ProjectEntry = struct {
    text: []const u8,

    /// Supply `main.selka`; any other path belongs to the standard loader.
    pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
        return a.dupe(u8, (@as(*const @This(), @ptrCast(@alignCast(context.?)))).text);
    }
};

// spec-case: PY-STR-2
test "string methods are rejected on lists and empty split separators trap" {
    try reject(
        \\func main() -> int:
        \\    mut values = [1, 2]
        \\    _ = values.strip()
        \\    return 0
    , "E_COLLECTION_METHOD");
    try reject(
        \\func main() -> int:
        \\    mut counts: dict[str, int] = {}
        \\    _ = counts.upper()
        \\    return 0
    , "E_COLLECTION_METHOD");
    // The recognized home lowers to the same split, so the empty separator still
    // traps; the program imports `strings`, so it checks as an embedded project.
    var entry: ProjectEntry = .{ .text = "import strings\n\nfunc main() -> int:\n    return len(strings.split(\"ab\", \"\"))\n" };
    var project: language.embedded_project.Program = undefined;
    try project.init(t.allocator, .{ .context = &entry, .read = ProjectEntry.read });
    defer project.deinit();
    const result = try native.run(&project.compilation);
    try t.expect(result.trapped());
    try t.expectEqualStrings("R_EMPTY_SEPARATOR", result.trap.code);
}
