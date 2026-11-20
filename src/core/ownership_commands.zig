//! The developer commands over ownership certificate files (docs/design/ownership-certificates.md §4.1, plan package C4):
//! `validate-certificates PATH` and `mutate-certificates FILE OUTDIR`. The gate action `ownership-proof` runs the first on
//! the certificates `selka test` writes and compares its verdicts with `lake exe certcheck`; it runs the second on a fixed
//! set of programs and requires both checkers to reject every mutant. Neither command lowers anything.
const std = @import("std");
const form = @import("ownership_function.zig");
const parse = @import("ownership_parse.zig");
const validate = @import("validate_ownership.zig");
const exporter = @import("ownership_export.zig");
const mutants = @import("ownership_mutants.zig");
const linker = @import("validate_ownership_link.zig");

/// What the commands can fail with beyond a status.
pub const Error = std.mem.Allocator.Error || std.Io.File.Writer.Error || error{ReadFailed};

/// The longest certificate file the commands read.
const file_limit: usize = 256 << 20;

/// What a `validate-certificates` run counted, for its summary line (the same fields `certcheck` prints).
pub const Counts = struct { files: usize = 0, functions: usize = 0, accept: usize = 0, reject: usize = 0, unchecked: usize = 0, errors: usize = 0 };

/// `validate-certificates PATH`: the Zig validator's verdict on each function of each certificate file under PATH (one file,
/// or a directory walked in path order whose files that do not start with `ownership-certificate-` are skipped), one line
/// per function, then a summary. Exit 0 when every function is accepted or unchecked, 1 when one is rejected, 2 for a usage
/// error or a malformed file.
pub fn validateCommand(init: std.process.Init, arguments: []const []const u8) Error!u8 {
    if (arguments.len != 1) return 2;
    if (std.mem.eql(u8, arguments[0], "--identity")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, identity_line);
        return 0;
    }
    const allocator = init.arena.allocator();
    const single = (std.Io.Dir.cwd().statFile(init.io, arguments[0], .{}) catch return 2).kind != .directory;
    const files = try collect(init, arguments[0], single);
    var counts: Counts = .{};
    var out: std.ArrayList(u8) = .empty;
    for (files) |path| {
        var scratch = std.heap.ArenaAllocator.init(init.gpa);
        defer scratch.deinit();
        const text = std.Io.Dir.cwd().readFileAlloc(init.io, path, scratch.allocator(), .limited(file_limit)) catch return error.ReadFailed;
        if (!single and !std.mem.startsWith(u8, text, "ownership-certificate-")) continue;
        try checkFile(scratch.allocator(), allocator, path, text, &counts, &out);
    }
    try out.print(allocator, "summary files={d} functions={d} accept={d} reject={d} unchecked={d} errors={d}\n", .{ counts.files, counts.functions, counts.accept, counts.reject, counts.unchecked, counts.errors });
    try std.Io.File.stdout().writeStreamingAll(init.io, out.items);
    return if (counts.errors != 0) 2 else if (counts.reject != 0) 1 else 0;
}

/// `validate-certificates --identity` prints this: the compiler's own identity, the digest of its sources, Zig version and
/// optimize mode that every compiler cache and test receipt is keyed by. The gate stamps the certificates a compiler wrote
/// with it, so it can tell certificates of another compiler from its own.
const identity_line = @import("build_identity").compiler_identity ++ "\n";

/// The files under `target`, sorted by path; just `target` for a single file. `selka verify-ir` walks its texts with it too.
pub fn collect(init: std.process.Init, target: []const u8, single: bool) Error![]const []const u8 {
    const allocator = init.arena.allocator();
    if (single) {
        const only = try allocator.alloc([]const u8, 1);
        only[0] = target;
        return only;
    }
    var directory = std.Io.Dir.cwd().openDir(init.io, target, .{ .iterate = true, .follow_symlinks = false }) catch return error.ReadFailed;
    defer directory.close(init.io);
    var walker = try directory.walk(allocator);
    defer walker.deinit();
    var found: std.ArrayList([]const u8) = .empty;
    while (walker.next(init.io) catch return error.ReadFailed) |item| {
        if (item.kind != .file) continue;
        try found.append(allocator, try std.fs.path.join(allocator, &.{ target, item.path }));
    }
    std.mem.sort([]const u8, found.items, {}, pathLess);
    return found.items;
}

fn pathLess(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// Parse one file and append a verdict line per function (or one error line) to `out`.
fn checkFile(work: std.mem.Allocator, keep: std.mem.Allocator, path: []const u8, text: []const u8, counts: *Counts, out: *std.ArrayList(u8)) Error!void {
    counts.files += 1;
    var problem: parse.Problem = .{};
    const functions = parse.parseFile(work, text, &problem) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Malformed => {
            counts.errors += 1;
            try out.print(keep, "{s} error line {d}: {s}\n", .{ path, problem.line, problem.reason });
            return;
        },
    };
    for (functions) |function| {
        counts.functions += 1;
        const name = try exporter.escapedName(work, function.name);
        switch (try validate.validate(work, function)) {
            .accepted => {
                counts.accept += 1;
                try out.print(keep, "{s} {s} accept\n", .{ path, name });
            },
            .unchecked => |reason| {
                counts.unchecked += 1;
                try out.print(keep, "{s} {s} unchecked {s}\n", .{ path, name, reason.token() });
            },
            .rejected => |failure| {
                counts.reject += 1;
                try out.print(keep, "{s} {s} reject {s} ", .{ path, name, failure.check.label() });
                if (failure.block) |block| try out.print(keep, "b{d} ", .{block}) else try out.appendSlice(keep, "b- ");
                if (failure.index) |index| try out.print(keep, "{d}\n", .{index}) else try out.appendSlice(keep, "-\n");
            },
        }
    }
}

/// What a `link-certificates` run counted, for its summary line.
const LinkCounts = struct { programs: usize = 0, functions: usize = 0, entries: usize = 0, reject: usize = 0, errors: usize = 0 };

/// `link-certificates PATH`: link the callee tables of each program under PATH (design §9, entry 57). A program is a directory
/// that holds certificate files directly (all the units of one build); PATH itself, given a file, is one program. One line per
/// entry that does not match its callee, `DIR CALLER link-reject ENTRY TAG`, then a summary. Exit 0 when every entry links, 1
/// when one does not, 2 for a usage error or a malformed file.
pub fn linkCommand(init: std.process.Init, arguments: []const []const u8) Error!u8 {
    if (arguments.len != 1) return 2;
    const allocator = init.arena.allocator();
    const single = (std.Io.Dir.cwd().statFile(init.io, arguments[0], .{}) catch return 2).kind != .directory;
    const files = try collect(init, arguments[0], single);
    var programs: std.array_hash_map.String(std.ArrayList([]const u8)) = .empty;
    for (files) |path| {
        const key = if (single) path else std.fs.path.dirname(path) orelse ".";
        const found = try programs.getOrPut(allocator, key);
        if (!found.found_existing) found.value_ptr.* = .empty;
        try found.value_ptr.append(allocator, path);
    }
    const Order = struct {
        keys: []const []const u8,
        pub fn lessThan(self: @This(), x: usize, y: usize) bool {
            return std.mem.lessThan(u8, self.keys[x], self.keys[y]);
        }
    };
    programs.sort(Order{ .keys = programs.keys() });
    var counts: LinkCounts = .{};
    var out: std.ArrayList(u8) = .empty;
    const run: LinkRun = .{ .init = init, .keep = allocator, .counts = &counts, .out = &out };
    for (programs.keys(), programs.values()) |directory, paths| {
        var scratch = std.heap.ArenaAllocator.init(init.gpa);
        defer scratch.deinit();
        try linkProgram(run, scratch.allocator(), directory, paths.items);
    }
    try out.print(allocator, "summary programs={d} functions={d} entries={d} reject={d} errors={d}\n", .{ counts.programs, counts.functions, counts.entries, counts.reject, counts.errors });
    try std.Io.File.stdout().writeStreamingAll(init.io, out.items);
    return if (counts.errors != 0) 2 else if (counts.reject != 0) 1 else 0;
}

/// What every program of one `link-certificates` run shares: the process, the allocator that outlives a program, the counts and
/// the output text.
const LinkRun = struct { init: std.process.Init, keep: std.mem.Allocator, counts: *LinkCounts, out: *std.ArrayList(u8) };

/// Read the certificate files of one program, link their callee tables and append a line per rejected entry to the run's output.
fn linkProgram(run: LinkRun, work: std.mem.Allocator, directory: []const u8, paths: []const []const u8) Error!void {
    const init = run.init;
    const keep = run.keep;
    const counts = run.counts;
    const out = run.out;
    var functions: std.ArrayList(form.Function) = .empty;
    var seen = false;
    for (paths) |path| {
        const text = std.Io.Dir.cwd().readFileAlloc(init.io, path, work, .limited(file_limit)) catch return error.ReadFailed;
        if (!std.mem.startsWith(u8, text, "ownership-certificate-")) continue;
        seen = true;
        var problem: parse.Problem = .{};
        const parsed = parse.parseFile(work, text, &problem) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Malformed => {
                counts.errors += 1;
                try out.print(keep, "{s} error line {d}: {s}\n", .{ path, problem.line, problem.reason });
                continue;
            },
        };
        try functions.appendSlice(work, parsed);
    }
    if (!seen) return;
    const report = try linker.link(work, functions.items);
    counts.programs += 1;
    counts.functions += functions.items.len;
    counts.entries += report.entries;
    counts.reject += report.rejections.len;
    for (report.rejections) |rejection| {
        const caller = try exporter.escapedName(work, functions.items[rejection.caller].name);
        try out.print(keep, "{s} {s} link-reject {d} {s}\n", .{ directory, caller, rejection.entry, rejection.tag.token() });
    }
}

/// `mutate-certificates FILE OUTDIR`: for every function of FILE that the validator accepts, every single-edit mutant
/// (`ownership_mutants.zig`) written as a certificate file `OUTDIR/<n>.certificate`, and a manifest on standard output,
/// one line `<n>.certificate <class> <function>` per mutant. Exit 0.
pub fn mutateCommand(init: std.process.Init, arguments: []const []const u8) Error!u8 {
    if (arguments.len != 2) return 2;
    const allocator = init.arena.allocator();
    const text = std.Io.Dir.cwd().readFileAlloc(init.io, arguments[0], allocator, .limited(file_limit)) catch return error.ReadFailed;
    var problem: parse.Problem = .{};
    const functions = parse.parseFile(allocator, text, &problem) catch return 2;
    std.Io.Dir.cwd().createDirPath(init.io, arguments[1]) catch return error.ReadFailed;
    var manifest: std.ArrayList(u8) = .empty;
    var written: usize = 0;
    for (functions) |function| {
        if (function.unchecked != null) continue;
        switch (try validate.validate(allocator, function)) {
            .accepted => {},
            else => continue,
        }
        for (std.enums.values(mutants.Class)) |class| {
            var made: mutants.Mutants = .empty;
            try mutants.mutate(allocator, class, function, &made);
            for (made.items) |mutant| {
                var file: std.ArrayList(u8) = .empty;
                try exporter.writeHeader(allocator, &file);
                try exporter.write(allocator, &file, mutant);
                const name = try std.fmt.allocPrint(allocator, "{d}.certificate", .{written});
                const path = try std.fs.path.join(allocator, &.{ arguments[1], name });
                std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = file.items }) catch return error.ReadFailed;
                try manifest.print(allocator, "{s} {s} {s}\n", .{ name, @tagName(class), try exporter.escapedName(allocator, function.name) });
                written += 1;
            }
        }
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, manifest.items);
    return 0;
}

const fixture_accepted =
    \\ownership-certificate-v2
    \\class iconst Constant
    \\class list_new Fresh
    \\class drop Drop
    \\function ok result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\inst - drop Drop reads - consumes %2 state none parents -
    \\term ret %1
    \\end
    \\function leaks result scalar from - unchecked -
    \\block b- preds -
    \\inst %1 iconst Constant reads - consumes - state scalar parents - imm 1
    \\block b0 preds -
    \\inst %2 list_new Fresh reads %1 consumes - state owned parents -
    \\term ret %1
    \\end
    \\function task result owned from - unchecked task-group
    \\block b- preds -
    \\block b0 preds -
    \\term ret -
    \\end
    \\
;

test "a verdict line has the format of certcheck: accept, reject with the judgment, block and instruction, unchecked" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var counts: Counts = .{};
    var out: std.ArrayList(u8) = .empty;
    try checkFile(a, a, "dir/x.certificate", fixture_accepted, &counts, &out);
    try std.testing.expectEqualStrings(
        "dir/x.certificate ok accept\ndir/x.certificate leaks reject J2 b0 1\ndir/x.certificate task unchecked task-group\n",
        out.items,
    );
    try std.testing.expectEqual(Counts{ .files = 1, .functions = 3, .accept = 1, .reject = 1, .unchecked = 1, .errors = 0 }, counts);
}

// spec-case: OWNERSHIP-PROOF-1
test "the identity line is a lowercase 64 digit hex digest and one line" {
    try std.testing.expectEqual(@as(usize, 65), identity_line.len);
    try std.testing.expect(identity_line[64] == '\n');
    try std.testing.expect(isLowerHex(identity_line[0..64]));
}

fn isLowerHex(text: []const u8) bool {
    for (text) |digit| if (!std.ascii.isDigit(digit) and (digit < 'a' or digit > 'f')) return false;
    return true;
}

test "a malformed file is one error line and counts as an error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var counts: Counts = .{};
    var out: std.ArrayList(u8) = .empty;
    try checkFile(a, a, "bad.certificate", "ownership-certificate-v2\nfunction broken\n", &counts, &out);
    try std.testing.expect(std.mem.startsWith(u8, out.items, "bad.certificate error line 2: "));
    try std.testing.expectEqual(@as(usize, 1), counts.errors);
    try std.testing.expectEqual(@as(usize, 0), counts.functions);
}
