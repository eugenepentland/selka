//! Shared project runner for embedded guest fixtures: a fixture checked as a
//! project may `import` a standard module, which a single unit cannot.
const std = @import("std");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
/// Fixture diagnostics and trap detail go straight to the test's stderr.
const print = std.debug.print;

/// Everything a fixture run can report: loading, checking, execution and assertions.
pub const Error = language.embedded_project.InitError || native.Error ||
    error{ TestExpectedEqual, TestUnexpectedResult, TestExpectedError };

/// Source provider that serves one in-memory entry module to the project loader.
pub const Entry = struct {
    text: []const u8,
    /// Serve `main.selka` from the fixture text; every other path is a standard module.
    pub fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Entry = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
        if (self.text.len > limit) return error.TooLarge;
        return allocator.dupe(u8, self.text);
    }
};

/// Everything one project check reported, with the merged source its spans
/// render against; the caller's arena owns both.
pub const Report = struct {
    diagnostics: []const language.diagnostic.Diagnostic,
    src: language.source.Source,
    passed: bool,

    /// The first error diagnostic, or null when the program checked.
    pub fn firstError(self: Report) ?language.diagnostic.Diagnostic {
        for (self.diagnostics) |item| if (item.severity == .err) return item;
        return null;
    }

    /// The source text a merged span covers.
    pub fn text(self: Report, span: language.source.Span) []const u8 {
        return self.src.text(span);
    }

    /// Require that the fixture checked clean, naming its first error otherwise.
    pub fn expectAccepted(self: Report) error{TestUnexpectedResult}!void {
        if (!self.passed) print("fixture rejected: {s}: {s}\n", .{ self.diagnostics[0].code, self.diagnostics[0].message });
        try std.testing.expect(self.passed);
    }
};

/// Load and check a fixture into caller-owned storage, so the test can inspect
/// the checked program. The provider is read during loading only, so the
/// fixture text need not outlive the call; never copy the program.
pub fn load(program: *language.embedded_project.Program, allocator: std.mem.Allocator, text: []const u8) Error!void {
    var entry: Entry = .{ .text = text };
    return program.init(allocator, .{ .context = &entry, .read = Entry.read });
}

/// The report of a project whose load or parse failed: `project.problem` keeps
/// the parser's own diagnostics against the module it read, so a rejection
/// fixture sees the first error the single-unit path reported.
fn problemReport(arena: std.mem.Allocator, project: *language.project.Project) Error!Report {
    const problem = project.problem orelse return error.SourceError;
    const module = project.modules.items[problem.site.module];
    if (problem.recovered.len != 0) return .{ .diagnostics = problem.recovered, .src = module.src, .passed = false };
    const one = try arena.alloc(language.diagnostic.Diagnostic, 1);
    one[0] = .{
        .code = problem.code,
        .span = problem.site.span,
        .message = problem.message,
        .provenance = .{ .fix = if (problem.fix) |edit| .{ .edit = edit, .more = problem.fix_more } else null },
    };
    return .{ .diagnostics = one, .src = module.src, .passed = false };
}

/// Check a fixture as a project without running it and report every diagnostic.
/// `arena` owns the report, so pass an arena the test releases at its end.
pub fn check(arena: std.mem.Allocator, text: []const u8) Error!Report {
    var entry: Entry = .{ .text = text };
    var project = language.project.Project.init(arena);
    try project.load(.{ .context = &entry, .read = Entry.read }, "main", .{});
    var index = language.interfaces.build(&project) catch |failure| switch (failure) {
        error.SourceError => return problemReport(arena, &project),
        else => return failure,
    };
    var compilation = try language.project_compile.Compilation.init(&index);
    const passed = if (compilation.check()) |_| true else |failure| switch (failure) {
        error.SourceError => false,
        else => return failure,
    };
    return .{ .diagnostics = compilation.diagnostics.items.items, .src = compilation.src, .passed = passed };
}

/// Check a fixture and require it accepted, naming its first error otherwise.
pub fn accept(arena: std.mem.Allocator, text: []const u8) Error!void {
    try (try check(arena, text)).expectAccepted();
}

/// Check a fixture and require its first diagnostic to carry `code`.
pub fn rejectsWith(arena: std.mem.Allocator, text: []const u8, code: []const u8) Error!void {
    const checked = try check(arena, text);
    try std.testing.expect(!checked.passed);
    try std.testing.expectEqualStrings(code, checked.diagnostics[0].code);
}

/// Print every diagnostic checking `text` as a project reports, as a failed
/// fixture's context; a load failure itself has nothing to print.
fn report(allocator: std.mem.Allocator, text: []const u8) void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const checked = check(arena.allocator(), text) catch return;
    for (checked.diagnostics) |item| print("{s}: {s} [{s}]\n", .{ item.code, item.message, checked.text(item.span) });
}

/// Load a fixture for execution, printing its diagnostics when it does not check.
fn loaded(program: *language.embedded_project.Program, allocator: std.mem.Allocator, text: []const u8) Error!void {
    load(program, allocator, text) catch |failure| {
        report(allocator, text);
        return failure;
    };
}

/// Compile a fixture against the embedded standard modules and run it natively.
pub fn expect(allocator: std.mem.Allocator, text: []const u8, options: native.Options, wanted: i64) Error!void {
    var program: language.embedded_project.Program = undefined;
    try loaded(&program, allocator, text);
    defer program.deinit();
    const outcome = try native.runWithOptions(&program.compilation, options);
    try std.testing.expect(!outcome.trapped());
    try std.testing.expectEqual(wanted, outcome.value);
}

/// Compile a fixture, run it under `options` and return the whole run (value, output and trap) without judging it.
pub fn runOutcome(allocator: std.mem.Allocator, text: []const u8, options: native.Options) Error!native.Run {
    var program: language.embedded_project.Program = undefined;
    try loaded(&program, allocator, text);
    defer program.deinit();
    return native.runWithOptions(&program.compilation, options);
}

/// Compile a fixture and report the native trap that ended its run.
pub fn trap(allocator: std.mem.Allocator, text: []const u8, options: native.Options, code: []const u8) Error!void {
    var program: language.embedded_project.Program = undefined;
    try loaded(&program, allocator, text);
    defer program.deinit();
    const outcome = try native.runWithOptions(&program.compilation, options);
    try std.testing.expect(outcome.trapped());
    try std.testing.expectEqualStrings(code, outcome.trap.code);
}

/// Compile a fixture and require the named trap at `line` of the entry module.
pub fn trappedAt(allocator: std.mem.Allocator, text: []const u8, code: []const u8, line: u64) Error!void {
    var program: language.embedded_project.Program = undefined;
    try loaded(&program, allocator, text);
    defer program.deinit();
    const outcome = try native.runWithOptions(&program.compilation, .{});
    try std.testing.expect(outcome.trapped());
    try std.testing.expectEqualStrings(code, outcome.trap.code);
    try std.testing.expectEqual(line, outcome.trap.line);
}

/// Compile a fixture and require its entry value.
pub fn value(allocator: std.mem.Allocator, text: []const u8) Error!i64 {
    var program: language.embedded_project.Program = undefined;
    try loaded(&program, allocator, text);
    defer program.deinit();
    const outcome = try native.runWithOptions(&program.compilation, .{});
    if (outcome.trapped()) print("trap {s}: {s}\n", .{ outcome.trap.code, outcome.stderr });
    try std.testing.expect(!outcome.trapped());
    return outcome.value;
}

/// Run a fixture with the native runtime's default budgets and grants.
pub fn run(allocator: std.mem.Allocator, text: []const u8, wanted: i64) Error!void {
    try expect(allocator, text, .{}, wanted);
}

/// Check that a program using the standard modules fails to compile.
pub fn reject(allocator: std.mem.Allocator, text: []const u8) Error!void {
    var program: language.embedded_project.Program = undefined;
    load(&program, allocator, text) catch |failure| {
        if (failure == error.SourceError) return;
        return failure;
    };
    program.deinit();
    return error.TestExpectedError;
}
