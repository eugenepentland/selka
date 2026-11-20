//! The developer command over fact certificate files (docs/design/fact-certificates.md §10, plan package C7):
//! `validate-fact-certificates PATH`, which prints one verdict per function in the format the Lean checker will print.
const std = @import("std");
const text = @import("fact_text.zig");
const form = @import("fact_function.zig");
const validate = @import("validate_facts.zig");

/// What the commands can fail with beyond a status.
pub const Error = std.mem.Allocator.Error || std.Io.File.Writer.Error || error{ReadFailed};

/// The longest certificate file the commands read.
const file_limit: usize = 1 << 30;

/// What a `validate-fact-certificates` run counted, for its summary line.
pub const Counts = struct {
    files: usize = 0,
    functions: usize = 0,
    accept: usize = 0,
    reject: usize = 0,
    errors: usize = 0,
    stats: validate.Stats = .{},
};

/// `validate-fact-certificates PATH [--detail]`: the verdict on each function of each fact certificate file under PATH (one
/// file, or a directory walked in path order whose files that do not start with `fact-certificate-v1` are skipped), one line per
/// function, then a summary; with `--detail`, the operations whose intervals were accepted without a rule and the reasons
/// `proven` checks were left unchecked. Exit 0 when every function is accepted, 1 when one is rejected, 2 for a usage error or
/// a malformed file.
pub fn validateCommand(init: std.process.Init, arguments: []const []const u8) Error!u8 {
    var target: ?[]const u8 = null;
    var detail = false;
    var why = false;
    for (arguments) |argument| {
        if (std.mem.eql(u8, argument, "--detail")) detail = true else if (std.mem.eql(u8, argument, "--why")) why = true else if (target == null) target = argument else return 2;
    }
    const path = target orelse return 2;
    const allocator = init.arena.allocator();
    const single = (std.Io.Dir.cwd().statFile(init.io, path, .{}) catch return 2).kind != .directory;
    const files = try collect(init, path, single);
    var counts: Counts = .{};
    var histogram: validate.Histogram = .initFill(0);
    var out: std.ArrayList(u8) = .empty;
    for (files) |file| {
        var scratch = std.heap.ArenaAllocator.init(init.gpa);
        defer scratch.deinit();
        const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, file, scratch.allocator(), .limited(file_limit)) catch return error.ReadFailed;
        if (!single and !std.mem.startsWith(u8, bytes, text.header_line)) continue;
        try checkFile(.{ .work = scratch.allocator(), .keep = allocator, .backing = init.gpa }, .{ .path = file, .bytes = bytes }, .{ .counts = &counts, .histogram = &histogram, .why = why }, &out);
    }
    const stats = counts.stats;
    var unchecked_total: u32 = 0;
    for (stats.unchecked) |count| unchecked_total += count;
    const summary = "summary files={d} functions={d} accept={d} reject={d} errors={d} derived={d} assumed={d} proven={d} unchecked={d}\n";
    try out.print(allocator, summary, .{ counts.files, counts.functions, counts.accept, counts.reject, counts.errors, stats.derived, stats.assumed, stats.proven, unchecked_total });
    if (detail) {
        for (std.enums.values(validate.Unchecked)) |reason| try out.print(allocator, "unchecked {s} {d}\n", .{ reason.token(), stats.unchecked[@backingInt(reason)] });
        for (std.enums.values(@import("ir.zig").Op)) |op| if (histogram.get(op) != 0) try out.print(allocator, "assumed {s} {d}\n", .{ @tagName(op), histogram.get(op) });
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, out.items);
    return if (counts.errors != 0) 2 else if (counts.reject != 0) 1 else 0;
}

/// The files under `target`, sorted by path; just `target` for a single file.
// twin-drift-ok: this walker takes `.fact-certificate` files and the ownership one takes every file; the command output differs too
fn collect(init: std.process.Init, target: []const u8, single: bool) Error![]const []const u8 {
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
        // A link to a certificate is one (the facts half of the gate lays out the files it has to check as links).
        if ((item.kind != .file and item.kind != .sym_link) or !std.mem.endsWith(u8, item.path, ".fact-certificate")) continue;
        try found.append(allocator, try std.fs.path.join(allocator, &.{ target, item.path }));
    }
    std.mem.sort([]const u8, found.items, {}, pathLess);
    return found.items;
}

fn pathLess(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// The allocators of a check: the file's work, the text that outlives it, and the backing of the validator's per-function work.
const Memory = struct { work: std.mem.Allocator, keep: std.mem.Allocator, backing: std.mem.Allocator };

/// A certificate file read into memory.
const File = struct { path: []const u8, bytes: []const u8 };

/// Where a file's verdicts are counted, and whether a rejection prints its reason.
const Sink = struct { counts: *Counts, histogram: *validate.Histogram, why: bool = false };

/// Parse one file and append a verdict line per function (or one error line) to `out`.
fn checkFile(memory: Memory, file: File, sink: Sink, out: *std.ArrayList(u8)) Error!void {
    const work = memory.work;
    const keep = memory.keep;
    const path = file.path;
    const bytes = file.bytes;
    const counts = sink.counts;
    counts.files += 1;
    var problem: text.Problem = .{};
    const module = text.parse(work, bytes, &problem) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Malformed => {
            counts.errors += 1;
            try out.print(keep, "{s} error line {d}: {s}\n", .{ path, problem.line, problem.reason });
            return;
        },
    };
    const verdicts = try validate.validate(work, memory.backing, module, sink.histogram);
    for (module.functions, verdicts) |function, verdict| {
        counts.functions += 1;
        try out.print(keep, "{s} ", .{path});
        try text.writeName(keep, out, function.header.name);
        switch (verdict) {
            .accepted => |stats| {
                counts.accept += 1;
                counts.stats.derived += stats.derived;
                counts.stats.assumed += stats.assumed;
                counts.stats.proven += stats.proven;
                for (&counts.stats.unchecked, stats.unchecked) |*total, count| total.* += count;
                try out.appendSlice(keep, " accept\n");
            },
            .rejected => |failure| {
                counts.reject += 1;
                try out.print(keep, " reject {s} ", .{failure.check.label()});
                if (failure.block) |block| try out.print(keep, "b{d} ", .{block}) else try out.appendSlice(keep, "b- ");
                if (failure.value) |value| try out.print(keep, "%{d}\n", .{value}) else try out.appendSlice(keep, "-\n");
                if (sink.why) try out.print(keep, "  {s}\n", .{failure.detail});
            },
        }
    }
}

test "a verdict line has the format of the ownership checker: accept, or reject with the check, block and value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "fact-certificate-v1\nfunction ok linkage other addr 0 params - ret i64\nreturns -\nblock b- reach preds -\ninst %0 iconst i64 none a - b - x - imm 1 aux 0 range -\nblock b0 reach preds -\nterm ret %0\nend\n" ++
        "function bad linkage other addr 0 params - ret i64\nreturns -\nblock b- reach preds -\ninst %0 iconst i64 none a - b - x - imm 1 aux 0 range 2 3\nblock b0 reach preds -\nterm ret %0\nend\n";
    var counts: Counts = .{};
    var histogram: validate.Histogram = .initFill(0);
    var out: std.ArrayList(u8) = .empty;
    try checkFile(.{ .work = a, .keep = a, .backing = std.testing.allocator }, .{ .path = "dir/x.fact-certificate", .bytes = source }, .{ .counts = &counts, .histogram = &histogram }, &out);
    try std.testing.expectEqualStrings("dir/x.fact-certificate ok accept\ndir/x.fact-certificate bad reject F2 b- %0\n", out.items);
    try std.testing.expectEqual(@as(usize, 1), counts.accept);
    try std.testing.expectEqual(@as(usize, 1), counts.reject);
}

test "a malformed file is one error line and counts as an error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var counts: Counts = .{};
    var histogram: validate.Histogram = .initFill(0);
    var out: std.ArrayList(u8) = .empty;
    try checkFile(.{ .work = a, .keep = a, .backing = std.testing.allocator }, .{ .path = "bad.fact-certificate", .bytes = "fact-certificate-v1\nfunction broken\n" }, .{ .counts = &counts, .histogram = &histogram }, &out);
    try std.testing.expect(std.mem.startsWith(u8, out.items, "bad.fact-certificate error line 2: "));
    try std.testing.expectEqual(@as(usize, 1), counts.errors);
}
