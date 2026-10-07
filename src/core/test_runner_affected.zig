//! `mylang test --affected --against REF` on the new core (NEW-CORE-S5-AFFECTED-1):
//! narrow the discovered tests to the ones that reach a declaration whose own source
//! lines changed since the git revision REF.
//!
//! The changed declarations come from the front end's derivation
//! (`affected_tests.changes`, AFFECTED-TEST-2): one `git diff` under the project root
//! and a line scan of the changed files, no compilation of its own. A test is kept
//! when a function its Core IR build reaches (the same reachable set its receipt is
//! keyed on) is a changed declaration or lies in a wholly changed module. A changed
//! name that no checked `def` carries (a constant, whose value the front end folds
//! into its readers, or a deleted function) could be read anywhere, so it keeps every
//! test; so does a test the new core cannot build, which the run then reports.
const std = @import("std");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const build = @import("build.zig");
const discover = @import("test_runner_discover.zig");

/// What stops the narrowing: memory, or standard error cannot be written.
pub const Error = error{ OutOfMemory, WriteFailed };

/// The narrowing's outcome: the tests left to run, or the exit status of a command
/// whose reference `git` cannot resolve (2, a host failure, never an empty selection).
pub const Narrowed = union(enum) { kept: []const discover.Case, exit: u8 };

/// One narrowing's inputs: `arena` holds the result, `backing` the per-test scratch,
/// `root` is the project root every module path is relative to.
pub const Request = struct {
    arena: std.mem.Allocator,
    backing: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    entry: []const u8,
    reference: []const u8,
};

/// Keep the `cases` (already filtered) that reach a declaration changed since
/// `request.reference`, printing the selected count and every skipped test on stderr.
pub fn narrow(request: Request, checked: frontend.Checked, cases: []const discover.Case) Error!Narrowed {
    const a = request.arena;
    const changes = language.affected_tests.changes(.{ .memory = a, .io = request.io, .git_root = request.root, .entry = request.entry, .reference = request.reference }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.GitFailed => {
            try write(request.io, "mylang test: --against names a revision git cannot resolve\n");
            return .{ .exit = 2 };
        },
        error.InvalidEntry => {
            try write(request.io, "mylang test: --affected needs a .my entry file\n");
            return .{ .exit = 2 };
        },
    };
    const everything = untraced(changes, checked);
    var kept: std.ArrayList(discover.Case) = .empty;
    var skipped: std.ArrayList([]const u8) = .empty;
    for (cases) |case| {
        if (everything or try reaches(request.backing, checked, case, changes)) {
            try kept.append(a, case);
        } else try skipped.append(a, case.name);
    }
    var text: std.ArrayList(u8) = .empty;
    try text.print(a, "affected: {d} selected, {d} skipped against {s}\n", .{ kept.items.len, skipped.items.len, request.reference });
    for (skipped.items) |name| try text.print(a, "skipped {s}: no changed declaration is reachable\n", .{name});
    try write(request.io, text.items);
    return .{ .kept = kept.items };
}

/// Whether a changed name is carried by no checked `def`: a constant (the checker keeps
/// its initializer as a function, but every reader folds its value) or a deleted
/// function. Such a change cannot be traced through calls, so every test is affected.
fn untraced(changes: language.affected_tests.Changes, checked: frontend.Checked) bool {
    for (changes.names) |changed| {
        const traced = for (checked.program.functions) |function| {
            const named = std.mem.startsWith(u8, function.name, changed) and (function.name.len == changed.len or function.name[changed.len] == '[');
            if (named and !constant(checked.src.bytes, function.declaration.start)) break true;
        } else false;
        if (!traced) return true;
    }
    return false;
}

/// Whether the declaration line holding `offset` declares a constant.
fn constant(bytes: []const u8, offset: usize) bool {
    const at = @min(offset, bytes.len);
    const start = if (std.mem.lastIndexOfScalar(u8, bytes[0..at], '\n')) |newline| newline + 1 else 0;
    var line = std.mem.trimStart(u8, bytes[start..], " \t");
    if (std.mem.startsWith(u8, line, "public ")) line = std.mem.trimStart(u8, line["public ".len..], " \t");
    return std.mem.startsWith(u8, line, "const ");
}

/// Whether a function `case`'s Core IR build reaches is changed. A test the new core
/// cannot build is kept, so the run reports why.
fn reaches(backing: std.mem.Allocator, checked: frontend.Checked, case: discover.Case, changes: language.affected_tests.Changes) Error!bool {
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    var refusal: build.Refusal = .{};
    const module = build.buildRootsSource(scratch.allocator(), checked.program, &.{case.function}, checked.src, &refusal) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return true,
    };
    for (module.functions.items) |function| if (changes.reaches(function.name)) return true;
    return false;
}

fn write(io: std.Io, text: []const u8) Error!void {
    std.Io.File.stderr().writeStreamingAll(io, text) catch return error.WriteFailed;
}
