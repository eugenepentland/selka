//! The ownership checker's side of the storing functions' `own` (lane A, F71):
//! a borrowed name given to `append`, to a declared `own` callee or to a storing
//! library function is refused with the copy its checker writes, and a value an
//! owned binding gave away is refused as moved, with no repair.
const std = @import("std");
const language = @import("selka");
const contract = @import("single_owner.zig");
const support = @import("test_support.zig");

/// Supplies one in-memory entry module to the project loader.
const ProjectEntry = struct {
    source: []const u8,
    /// Serve the entry module to the project loader; other paths are not found.
    pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const entry: *ProjectEntry = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
        return a.dupe(u8, entry.source);
    }
};

/// The first ownership refusal `source` draws from the checker, or a test failure
/// when the program checks clean. The checker runs on every function `main` reaches.
fn firstRefusal(parent: std.mem.Allocator, source: []const u8) !contract.Failure {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const program = try checkedProgram(arena.allocator(), source);
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.check(arena.allocator(), program, &failure));
    return failure;
}

/// Parse and check `source` to a typed program, as `refuses` does in `zero_rc_test.zig`.
fn checkedProgram(a: std.mem.Allocator, source: []const u8) !language.typed.Program {
    if (support.needsModules(source)) {
        var entry: ProjectEntry = .{ .source = source };
        var project: language.embedded_project.Program = undefined;
        try project.init(a, .{ .context = &entry, .read = ProjectEntry.read });
        return project.compilation.program.?;
    }
    var unit = try language.Compilation.init(a, "own-append.selka", source);
    try unit.check();
    return unit.program.?;
}

test "a borrowed parameter given to append is refused, and the checker writes copy around it" {
    const failure = try firstRefusal(std.testing.allocator,
        // migrate-embedded: skip original borrowed operand ownership refusal and copy-repair witness
        \\func fill(s: str, mut rows: str[]):
        \\    append(mut rows, s)
        \\
        \\
        \\func main() -> int:
        \\    mut rows: str[] = []
        \\    fill("a", mut rows)
        \\    return len(rows)
    );
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_BORROW", failure.code);
    try std.testing.expect(failure.copy.span != null);
}

test "a match payload given to append is refused, and the checker writes copy around it" {
    const failure = try firstRefusal(std.testing.allocator,
        // migrate-embedded: skip original borrowed operand ownership refusal and copy-repair witness
        \\func payload(maybe: str?, mut out: str[]):
        \\    match maybe:
        \\        case Some(v):
        \\            append(mut out, v)
        \\        case None:
        \\            return
        \\
        \\
        \\func main() -> int:
        \\    mut out: str[] = []
        \\    payload(Some("a"), mut out)
        \\    return len(out)
    );
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
    try std.testing.expect(failure.copy.span != null);
}

test "an own parameter given to append is accepted by the checker" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try checkedProgram(arena.allocator(),
        \\func fill(own s: str, mut rows: str[]):
        \\    append(mut rows, own s)
        \\
        \\
        \\func main() -> int:
        \\    mut rows: str[] = []
        \\    fill("a", mut rows)
        \\    return len(rows)
    );
    var failure: contract.Failure = .{};
    try contract.check(arena.allocator(), program, &failure);
}

test "a borrowed parameter given to a declared own callee is refused with its copy" {
    const failure = try firstRefusal(std.testing.allocator,
        // migrate-embedded: skip original borrowed operand ownership refusal and copy-repair witness
        \\func my_take(own s: str) -> int:
        \\    return len(s)
        \\
        \\
        \\func keep(s: str) -> int:
        \\    return my_take(s)
        \\
        \\
        \\func main() -> int:
        \\    return keep("abc")
    );
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_BORROW", failure.code);
    try std.testing.expect(failure.copy.span != null);
}

test "a borrowed name given to a storing library function is refused with its copy" {
    const failure = try firstRefusal(std.testing.allocator,
        // migrate-embedded: skip original borrowed operand ownership refusal and copy-repair witness
        \\import sets
        \\
        \\
        \\func fill(mut seen: set[str], word: str):
        \\    sets.add(mut seen, word)
        \\
        \\
        \\func main() -> int:
        \\    mut seen: set[str] = set()
        \\    fill(mut seen, "x")
        \\    return len(seen)
    );
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_BORROW", failure.code);
    try std.testing.expect(failure.copy.span != null);
}

test "a value an owned binding gave to a storing library function is moved, with no repair" {
    const failure = try firstRefusal(std.testing.allocator,
        \\import sets
        \\
        \\
        \\func main() -> int:
        \\    mut seen: set[str] = set()
        \\    const word = "ab" + "cd"
        \\    sets.add(mut seen, own word)
        \\    return len(word)
    );
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_MOVED", failure.code);
    try std.testing.expect(failure.copy.span == null);
}
