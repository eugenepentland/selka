//! A qualifier that names a module file of the project, in a file that does not import it, is answered with the import (lane FR32).
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const import_fix = @import("import_fix.zig");
const project = @import("project.zig");
const repair = @import("project_module_import.zig");
const source = @import("source.zig");
const unknown_qualifier = @import("unknown_qualifier.zig");

const call_text = "func main(out: Stream) -> int:\n    print(out, util.twice(2))\n    return 0\n";
const type_text = "func width(r: util.Row) -> int:\n    return r.a\n";

/// A project directory with `util.selka` and `shared/calc.selka` in it, and the arena its tests allocate from.
const Fixture = struct {
    temp: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    root: repair.Root,

    fn init(allocator: std.mem.Allocator) !Fixture {
        var temp = std.testing.tmpDir(.{});
        errdefer temp.cleanup();
        try temp.dir.writeFile(std.testing.io, .{ .sub_path = "util.selka", .data = "public func twice(n: int) -> int:\n    return n * 2\n" });
        try temp.dir.createDirPath(std.testing.io, "shared");
        try temp.dir.writeFile(std.testing.io, .{ .sub_path = "shared/calc.selka", .data = "public func f(n: int) -> int:\n    return n + 1\n" });
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const path = try temp.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
        return .{ .temp = temp, .arena = arena, .root = .{ .io = std.testing.io, .path = path } };
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
        self.temp.cleanup();
    }

    /// `explain` of the one refusal `item`, which is about `text` checked as `main.selka`.
    fn explained(self: *Fixture, text: []const u8, item: diagnostic.Diagnostic) !diagnostic.Diagnostic {
        const a = self.arena.allocator();
        const src = try source.Source.init(a, "main.selka", text);
        const items = [_]diagnostic.Diagnostic{item};
        const noted = try repair.explain(a, self.root, &items, src);
        return noted[0];
    }
};

/// A refusal with `code` and `message` at the first `marker` of `text`, `length` bytes long.
fn refusal(code: []const u8, message: []const u8, text: []const u8, marker: []const u8, length: usize) diagnostic.Diagnostic {
    const start = std.mem.indexOf(u8, text, marker).?;
    return .{ .code = code, .message = message, .span = .{ .start = start, .end = start + length } };
}

test "FR32: a call of a project module without its import is answered with the import, as for a standard module" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const item = refusal("E_UNKNOWN_TYPE", "type is not declared", call_text, "util", 4);
    const noted = try fixture.explained(call_text, item);
    try std.testing.expectEqualStrings(import_fix.code, noted.code);
    try std.testing.expectEqualStrings("`util` is a module of this project that this file does not import; add `import util`", noted.message);
    try std.testing.expectEqual(item.span.start, noted.span.start);
    try std.testing.expectEqualStrings("import util\n\n", noted.provenance.fix.?.edit.text);
    try std.testing.expectEqual(@as(usize, 0), noted.provenance.fix.?.edit.span.start);
}

test "FR34: the checker's message for a qualifier that names nothing is still answered with the import when a module file has the name" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const worded = try unknown_qualifier.message(fixture.arena.allocator(), "util", "");
    const noted = try fixture.explained(call_text, refusal("E_UNKNOWN_TYPE", worded, call_text, "util", 4));
    try std.testing.expectEqualStrings(import_fix.code, noted.code);
    try std.testing.expectEqualStrings("`util` is a module of this project that this file does not import; add `import util`", noted.message);
    try std.testing.expectEqualStrings("import util\n\n", noted.provenance.fix.?.edit.text);
    const unknown = "func main(out: Stream) -> int:\n    print(out, nothing.twice(2))\n    return 0\n";
    const kept = try fixture.explained(unknown, refusal("E_UNKNOWN_TYPE", try unknown_qualifier.message(fixture.arena.allocator(), "nothing", ""), unknown, "nothing", 7));
    try std.testing.expectEqualStrings("E_UNKNOWN_TYPE", kept.code);
}

test "FR32: a qualifier in a type's place is named at the name, not at the dot the parser stopped on" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const stopped = refusal("E_SYNTAX", "unexpected token; expected )", type_text, ".Row", 1);
    const noted = try fixture.explained(type_text, stopped);
    try std.testing.expectEqualStrings(import_fix.code, noted.code);
    try std.testing.expectEqualStrings("`util` is a module of this project that this file does not import; add `import util`", noted.message);
    try std.testing.expectEqual(std.mem.indexOf(u8, type_text, "util").?, noted.span.start);
    try std.testing.expectEqual(@as(usize, 4), noted.span.end - noted.span.start);
}

test "FR32: a nested module is named by its dotted path, written in full or by its last segment" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const full = "func main(out: Stream) -> int:\n    print(out, shared.calc.f(2))\n    return 0\n";
    const written = try fixture.explained(full, refusal("E_UNKNOWN_NAME", "name is not defined in this scope", full, "shared", 6));
    try std.testing.expectEqualStrings("`shared.calc` is a module of this project that this file does not import; add `import shared.calc`", written.message);
    const last = "func main(out: Stream) -> int:\n    print(out, calc.f(2))\n    return 0\n";
    const short = try fixture.explained(last, refusal("E_UNKNOWN_TYPE", "type is not declared", last, "calc", 4));
    try std.testing.expectEqualStrings("`calc` is the module `shared.calc` of this project, which this file does not import; add `import shared.calc`", short.message);
    try std.testing.expectEqualStrings("import shared.calc\n\n", short.provenance.fix.?.edit.text);
}

test "FR32: a qualifier that is no module file keeps its refusal, and so does a module's own name inside it" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    const unknown = "func main(out: Stream) -> int:\n    print(out, nothing.twice(2))\n    return 0\n";
    const item = refusal("E_UNKNOWN_TYPE", "type is not declared", unknown, "nothing", 7);
    const kept = try fixture.explained(unknown, item);
    try std.testing.expectEqualStrings("E_UNKNOWN_TYPE", kept.code);
    try std.testing.expectEqualStrings("type is not declared", kept.message);
    try std.testing.expect(kept.provenance.fix == null);
    // A file does not import itself: `util` written inside `util.selka`.
    const src = try source.Source.init(a, "util.selka", call_text);
    const own = [_]diagnostic.Diagnostic{refusal("E_UNKNOWN_TYPE", "type is not declared", call_text, "util", 4)};
    const same = try repair.explain(a, fixture.root, &own, src);
    try std.testing.expectEqual(@as(*const diagnostic.Diagnostic, &own[0]), &same[0]);
}

test "FR32: the project's refusal of an unknown symbol is answered the same way, with the edit in the module's own bytes" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    const text = "import strings\n\nfunc main(out: Stream) -> int:\n    print(out, util.twice(2))\n    return 0\n";
    const start = std.mem.indexOf(u8, text, "util").?;
    var found: project.Problem = .{ .code = "E_UNKNOWN_SYMBOL", .message = "this module declares no `util`", .site = .{ .module = 0, .span = .{ .start = start, .end = start + 4 } } };
    try repair.explainProblem(a, fixture.root, &found, try source.Source.init(a, "main.selka", text));
    try std.testing.expectEqualStrings(import_fix.code, found.code);
    try std.testing.expectEqualStrings("`util` is a module of this project that this file does not import; add `import util`", found.message);
    try std.testing.expectEqualStrings("import util\n", found.fix.?.text);
    try std.testing.expectEqual(std.mem.indexOf(u8, text, "\n\nfunc").? + 1, found.fix.?.span.start);
}

test "FR32: the parser's stop at a qualifier in a type's place, found while the project loads, is answered the same way" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    const text = "import strings\n\nfunc width(r: util.Row) -> int:\n    return r.a\n";
    const dot = std.mem.indexOf(u8, text, ".Row").?;
    var found: project.Problem = .{ .code = "E_SYNTAX", .message = "unexpected token; expected )", .site = .{ .module = 0, .span = .{ .start = dot, .end = dot + 1 } } };
    try repair.explainProblem(a, fixture.root, &found, try source.Source.init(a, "main.selka", text));
    try std.testing.expectEqualStrings(import_fix.code, found.code);
    try std.testing.expectEqual(dot - 4, found.site.span.start);
    try std.testing.expectEqualStrings("import util\n", found.fix.?.text);
    // The same text inside `util.selka` is a file naming itself, which no import repairs.
    var own: project.Problem = .{ .code = "E_SYNTAX", .message = "unexpected token; expected )", .site = .{ .module = 0, .span = .{ .start = dot, .end = dot + 1 } } };
    try repair.explainProblem(a, fixture.root, &own, try source.Source.init(a, "util.selka", text));
    try std.testing.expectEqualStrings("E_SYNTAX", own.code);
    // The parser's recovered diagnostics are rewritten one by one.
    const stopped = diagnostic.Diagnostic{ .code = "E_SYNTAX", .message = "unexpected token; expected )", .span = .{ .start = dot, .end = dot + 1 } };
    var recovering: project.Problem = .{ .code = "E_SYNTAX", .message = stopped.message, .site = .{ .module = 0, .span = stopped.span }, .recovered = &.{stopped} };
    try repair.explainProblem(a, fixture.root, &recovering, try source.Source.init(a, "main.selka", text));
    try std.testing.expectEqualStrings(import_fix.code, recovering.recovered[0].code);
    try std.testing.expectEqualStrings("import util\n", recovering.recovered[0].provenance.fix.?.edit.text);
}
