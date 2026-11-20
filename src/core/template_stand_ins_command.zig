//! `selka template-stand-ins PATH`, the developer count of W3, step 1: what judging generic bodies at their declaration would
//! refuse. It checks PATH as `check` does, through no cache, with every template (the standard library's and the instantiated
//! ones included) tried with each kind of stand-in type its bounds allow (`template_stand_ins.zig`), runs the ownership pass
//! over the checked program, and prints one line per template and choice: accepted, refused (the first refusal's code and
//! place, and how many the pass found), refused by the body's own check, or skipped with the reason. It refuses nothing and
//! writes no cache; its status is 0 whatever the lines say, 1 when PATH does not check, 2 for a usage error. The command is
//! not in the usage text: it is a measuring tool, and whether a generic body is judged at its declaration is not decided.
const std = @import("std");
const product = @import("selka").product;
const language = @import("selka");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const single_owner = @import("single_owner.zig");
const stand_ins = language.template_stand_ins;
const typed = language.typed;

/// What stops the count before it has a status: memory, an unwritable stream or an internal failure of the check.
pub const Error = frontend.Error || project_entry.Error || std.Io.File.Writer.Error || error{ReadFailed};

/// Run the count on `args` (the arguments after the command name: one path).
pub fn run(init: std.process.Init, args: []const []const u8) Error!u8 {
    if (args.len != 1) {
        try std.Io.File.stderr().writeStreamingAll(init.io, "usage: selka template-stand-ins FILE.selka|--standard-library\n");
        return 2;
    }
    const allocator = init.arena.allocator();
    // `--standard-library` judges every module of the standard library the compiler embeds, through one entry held in memory that
    // imports them all: the gate's judgment of the library, which a user's `check` skips (W3 step 2).
    const library = std.mem.eql(u8, args[0], "--standard-library");
    const here = if (library) std.Io.Dir.cwd().realPathFileAlloc(init.io, ".", allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => ".",
    } else "";
    const path = if (library) try std.fs.path.join(allocator, &.{ here, library_entry }) else args[0];
    var report: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(allocator, init.io, path, &report) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try std.Io.File.stderr().writeStreamingAll(init.io, report.items);
        return project_entry.status(err);
    };
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    session.setHoleTraps(false);
    session.validationOnly();
    var log: stand_ins.Log = .{ .allocator = allocator };
    session.countStandIns(&log);
    if (library) session.setProviders(&.{.{ .path = library_entry, .text = try libraryProgram(allocator) }});
    const checked = entry.checkLibrary(allocator, &session, &report) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InternalError => return error.InternalError,
        else => {
            try std.Io.File.stderr().writeStreamingAll(init.io, report.items);
            if (report.items.len == 0) try std.Io.File.stderr().writeStreamingAll(init.io, "template-stand-ins: the check failed with no diagnostic\n");
            return 1;
        },
    };
    const verdicts = try judge(allocator, init.gpa, checked.program, checked.src);
    const text = try render(allocator, .{ .program = checked.program, .src = checked.src, .log = &log, .verdicts = verdicts });
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    return 0;
}

/// The name of the in-memory entry `--standard-library` checks.
const library_entry = "template_stand_ins_library.selka";

/// A program that imports every embedded standard module and declares an empty `main`.
fn libraryProgram(a: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (language.standard_library.paths, 0..) |module, index| {
        const name = product.chopSource(module);
        try out.appendSlice(a, "import ");
        for (name) |byte| try out.append(a, if (byte == '/') '.' else byte);
        try out.print(a, " as standard_{d}\n", .{index});
    }
    try out.appendSlice(a, "\n\nfunc main() -> int:\n    return 0\n");
    return out.toOwnedSlice(a);
}

/// The ownership pass's verdict on one function: its first refusal, how many it found, and the texts of the edits of the first
/// refusal's certain repair (what `selka fix` would write), empty when it has none.
pub const Verdict = struct { code: []const u8, span: language.source.Span, count: usize, fix: []const []const u8 };

/// The ownership verdict of every function of `program`, null for an accepted one. One pass checks every function; each refused
/// function is then checked alone, so its refusals are its own.
pub fn judge(a: std.mem.Allocator, work: std.mem.Allocator, program: typed.Program, src: language.source.Source) error{OutOfMemory}![]?Verdict {
    const verdicts = try a.alloc(?Verdict, program.functions.len);
    @memset(verdicts, null);
    var every: single_owner.Every = .{ .work = work };
    try single_owner.checkEvery(a, program, null, src, &every);
    const selected = try a.alloc(bool, program.functions.len);
    for (every.rejected.items) |index| {
        @memset(selected, false);
        selected[index] = true;
        var alone: single_owner.Every = .{ .work = work };
        try single_owner.checkEvery(a, program, selected, src, &alone);
        const first = if (alone.failures.items.len != 0) alone.failures.items[0] else every.failures.items[0];
        const located = try single_owner.diagnosticOf(a, src, first);
        var edits: std.ArrayList([]const u8) = .empty;
        if (located.diagnostic.provenance.fix) |fix| {
            for (0..fix.count()) |i| try edits.append(a, fix.at(i).text);
        }
        verdicts[index] = .{ .code = first.code, .span = first.span, .count = alone.failures.items.len, .fix = edits.items };
    }
    return verdicts;
}

/// What `render` reads: the checked program, the count's log and the ownership verdicts.
pub const Inputs = struct {
    program: typed.Program,
    src: language.source.Source,
    log: *const stand_ins.Log,
    verdicts: []const ?Verdict,
};

/// The report: a header naming the type each kind stood for, one line per template and choice, a line per refused function
/// the count made that no choice names (an instance a stand-in body called) or that the program itself made, and the totals.
pub fn render(a: std.mem.Allocator, given: Inputs) error{OutOfMemory}![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "template-stand-ins-v1");
    for (stand_ins.kinds, given.log.types) |kind, name| try out.print(a, " {s}={s}", .{ kind.word(), if (name.len == 0) "-" else name });
    try out.append(a, '\n');
    const named = try a.alloc(bool, given.program.functions.len);
    @memset(named, false);
    var totals: struct { accepted: usize = 0, refused: usize = 0, check: usize = 0, skipped: usize = 0 } = .{};
    for (given.log.rows.items) |row| {
        try place(a, &out, given.src, row.at);
        try out.print(a, " {s}[", .{row.name});
        for (row.chosen, 0..) |kind, i| try out.print(a, "{s}{s}", .{ if (i == 0) "" else ",", kind.word() });
        try out.appendSlice(a, "] ");
        switch (row.outcome) {
            .skipped => |reason| {
                totals.skipped += 1;
                try out.print(a, "skipped {s}\n", .{reason});
            },
            .instance => |index| {
                named[index] = true;
                if (given.log.refused.get(index)) |refusal| {
                    totals.check += 1;
                    try out.print(a, "refused-in-check {s} ", .{refusal.code});
                    try place(a, &out, given.src, refusal.span);
                    try out.append(a, '\n');
                } else if (given.verdicts[index]) |verdict| {
                    totals.refused += 1;
                    try out.print(a, "refused {s} ", .{verdict.code});
                    try place(a, &out, given.src, verdict.span);
                    try out.print(a, " ({d})", .{verdict.count});
                    try fixText(a, &out, verdict.fix);
                    try out.append(a, '\n');
                } else {
                    totals.accepted += 1;
                    try out.appendSlice(a, "accepted\n");
                }
            },
        }
    }
    var others: usize = 0;
    for (given.program.functions, given.verdicts, 0..) |function, maybe, index| {
        if (named[index]) continue;
        const verdict = maybe orelse continue;
        others += 1;
        const origin = if (index >= given.log.first_stand_in) "derived" else "program";
        try out.print(a, "{s} {s} refused {s} ", .{ origin, function.name, verdict.code });
        try place(a, &out, given.src, verdict.span);
        try out.print(a, " ({d})\n", .{verdict.count});
    }
    // The instances the program itself makes, with the kind of each type argument, so a refused choice can be compared with
    // the types its callers pass.
    for (given.program.functions[0..@min(given.log.first_stand_in, given.program.functions.len)]) |function| {
        if (function.type_arguments.len == 0) continue;
        try out.appendSlice(a, "instance ");
        try place(a, &out, given.src, function.declaration);
        try out.print(a, " {s} kinds=", .{function.name});
        for (function.type_arguments, 0..) |argument, i| try out.print(a, "{s}{s}", .{ if (i == 0) "" else ",", kindOf(argument, given.program.records) });
        try out.append(a, '\n');
    }
    try out.print(a, "totals: rows {d}, accepted {d}, refused {d}, refused-in-check {d}, skipped {d}, other refused functions {d}\n", .{
        given.log.rows.items.len, totals.accepted, totals.refused, totals.check, totals.skipped, others,
    });
    return out.toOwnedSlice(a);
}

/// The kind of stand-in a real type argument corresponds to: a scalar or a record of scalars is `int`, `str` is `str`, a list is
/// `list`, a resource or a record holding one is `move-only`, and any other managed type (a record, a dictionary, a set, an
/// option, bytes) is `record`.
pub fn kindOf(ty: typed.Type, records: []const typed.Record) []const u8 {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return stand_ins.Kind.int.word();
    const record = records[ty.recordIndex()];
    if (record.contract.move_only) return stand_ins.Kind.move_only.word();
    if (!record.managed) return stand_ins.Kind.int.word();
    if (record.isCollection() and record.collection.kind == .string) return stand_ins.Kind.text.word();
    if (record.isCollection() and record.collection.kind == .list and !record.collection.set) return stand_ins.Kind.list.word();
    return stand_ins.Kind.record.word();
}

/// ` fix=` and the certain repair's edit texts, each quoted, or ` fix=none`.
fn fixText(a: std.mem.Allocator, out: *std.ArrayList(u8), edits: []const []const u8) error{OutOfMemory}!void {
    try out.appendSlice(a, " fix=");
    if (edits.len == 0) return out.appendSlice(a, "none");
    for (edits, 0..) |text, i| try out.print(a, "{s}\"{s}\"", .{ if (i == 0) "" else ",", text });
}

fn place(a: std.mem.Allocator, out: *std.ArrayList(u8), src: language.source.Source, span: language.source.Span) error{OutOfMemory}!void {
    const at = src.locate(span.start);
    try out.print(a, "{s}:{d}:{d}", .{ at.path, at.line, at.column });
}
