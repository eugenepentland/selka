//! `selka lint --copies`: how many `copy(...)` calls a program writes, and which lint finding names each one.
//!
//! The count reads the checked program the lint run already holds and the findings that run produced; it adds no
//! finding and changes none. A copy is a `copy(...)` call spelled in a source file of the program that is not the
//! standard library (test files included). Each one is counted once, in the first of `L_NEEDLESS_COPY`, `L_COPY_MOVE`,
//! `L_COPY_FOR_STORE` and `L_COPY_IN_LOOP` whose finding sits on its position, else as named by nothing. A waiver comment
//! removes a finding and not the copy, so a waived copy is counted as named by nothing. When the analysis `L_COPY_IN_LOOP`
//! reads failed, the loop rule judged nothing: the count says the split between "in a loop" and "named by nothing" is not
//! known (`Report.split_known`) instead of printing a 0 it does not know.
const std = @import("std");
const lint = @import("lint.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");

/// The schema name of the JSON line.
pub const schema = "copy-count-v1";

/// The standard library's path prefix: its copies are the compiler's own and never counted.
const stdlib_prefix = "@stdlib/";

/// How many copies each category holds; every copy is in exactly one.
pub const Tally = struct {
    /// `L_NEEDLESS_COPY`: the copy `selka fix` removes.
    needless: usize = 0,
    /// `L_COPY_MOVE`: a move replaces the copy.
    move: usize = 0,
    /// `L_COPY_FOR_STORE`: a parameter copied into storage.
    for_store: usize = 0,
    /// `L_COPY_IN_LOOP`: a copy inside a loop.
    in_loop: usize = 0,
    /// No finding sits on the copy (or a waiver removed it).
    unnamed: usize = 0,

    /// Every copy counted.
    pub fn total(self: Tally) usize {
        return self.needless + self.move + self.for_store + self.in_loop + self.unnamed;
    }
};

/// One source file of the program: where it is, how many copies it writes and how many lines it has.
pub const FileCount = struct { path: []const u8, copies: usize, lines: usize };

/// One copy counted: the file it is written in, its position there, and the category that names it (the index of its
/// finding code in the printed order, 4 for none). A union of several entries needs this to count a copy once.
pub const Found = struct { path: []const u8, line: usize, column: usize, slot: usize };

/// The count of one program, or of several entries' programs: copies by category, every line of the files counted, and each
/// file's share.
pub const Report = struct {
    tally: Tally,
    lines: usize,
    /// Sorted by path; a file with no copy is listed with 0.
    files: []const FileCount,
    /// Every copy counted, in source order; empty in a union (`Total.report`).
    found: []const Found = &.{},
    /// How many entry files this count reads; only a count of two or more says so in the text.
    entries: usize = 1,
    /// False when the analysis `L_COPY_IN_LOOP` reads failed in some entry: `in_loop` and `unnamed` then hold what nothing
    /// knows (a copy that rule would have named is among the unnamed), and only their sum is a count.
    split_known: bool = true,

    /// Copies per 1,000 lines, 0 for a program with no lines.
    pub fn perThousand(self: Report) f64 {
        if (self.lines == 0) return 0;
        return @as(f64, @floatFromInt(self.tally.total())) * 1000.0 / @as(f64, @floatFromInt(self.lines));
    }
};

/// What one count reads: the checked program and its merged source, the entry's path (module paths are written
/// beside it) and the findings of the same lint run.
pub const Input = struct {
    program: typed.Program,
    src: source.Source,
    entry_path: []const u8,
    findings: []const lint.Finding,
    /// False when `L_COPY_IN_LOOP` is on and the analysis it reads failed (`lint.unjudged`).
    split_known: bool = true,
};

/// The four finding codes a copy is named by, in the order a copy takes the first that sits on it.
const named_codes = [_][]const u8{ "L_NEEDLESS_COPY", "L_COPY_MOVE", "L_COPY_FOR_STORE", "L_COPY_IN_LOOP" };

/// One written copy: where its text lies, where the statement that holds it starts, and the first category that names it.
const Copy = struct {
    start: usize,
    end: usize,
    /// The start of the outermost simple statement holding the copy, when the checked program has one.
    statement: ?usize = null,
    /// An index into `named_codes`, or `named_codes.len` for a copy no finding names.
    slot: usize = named_codes.len,
};

/// The positions the findings of each category start at, sorted.
const Positions = [named_codes.len][]usize;

/// Count the copies of `input`. Results live in `memory`.
pub fn count(memory: std.mem.Allocator, input: Input) std.mem.Allocator.Error!Report {
    const copies = try writtenCopies(memory, input);
    holdingStatements(input.program, copies);
    const positions = try findingPositions(memory, input.findings);
    const files = try programFiles(memory, input);
    var tally: Tally = .{};
    var found: std.ArrayList(Found) = .empty;
    for (copies) |*copy| {
        copy.slot = firstCategory(positions, copy.*);
        const at = input.src.locate(copy.start);
        const path = try beside(memory, input.entry_path, at.path);
        try found.append(memory, .{ .path = path, .line = at.line, .column = at.column, .slot = copy.slot });
        if (fileNamed(files.items, path)) |file| file.copies += 1;
        switch (copy.slot) {
            0 => tally.needless += 1,
            1 => tally.move += 1,
            2 => tally.for_store += 1,
            3 => tally.in_loop += 1,
            else => tally.unnamed += 1,
        }
    }
    std.mem.sort(FileCount, files.items, {}, pathLess);
    var lines: usize = 0;
    for (files.items) |file| lines += file.lines;
    return .{ .tally = tally, .lines = lines, .files = files.items, .found = found.items, .split_known = input.split_known };
}

/// Where one copy is written, for counting it once across entries: the file's index in `Total.files`, and the position.
const Place = struct { file: usize, line: usize, column: usize };

/// The union of the counts of several entries (`selka lint --copies A.selka B.selka`): each file counted once, with its lines
/// once, and each copy counted once in the best category any entry gave it, `L_NEEDLESS_COPY` first and "named by nothing"
/// last, so an entry whose rules could not see a caller never turns a named copy into an unnamed one. The count of each
/// entry is added as it is made and may be freed: the total keeps its own copy of what it needs.
pub const Total = struct {
    arena: std.heap.ArenaAllocator,
    entries: usize = 0,
    /// False once an entry added a count whose split is not known.
    split_known: bool = true,
    /// Each file by its path, written plainly (`./a.selka` and `a.selka` are one file), with its line count.
    files: std.array_hash_map.String(usize) = .empty,
    /// The best category found for each copy.
    copies: std.array_hash_map.Auto(Place, usize) = .empty,

    /// An empty total whose storage comes from `gpa`; `deinit` returns it.
    pub fn init(gpa: std.mem.Allocator) Total {
        return .{ .arena = std.heap.ArenaAllocator.init(gpa) };
    }

    /// Free everything the total holds.
    pub fn deinit(self: *Total) void {
        self.arena.deinit();
    }

    /// Add the count of one more entry.
    pub fn add(self: *Total, one: Report) std.mem.Allocator.Error!void {
        const memory = self.arena.allocator();
        self.entries += 1;
        if (!one.split_known) self.split_known = false;
        for (one.files) |file| _ = try self.fileIndex(memory, file.path, file.lines);
        for (one.found) |copy| {
            const place: Place = .{ .file = try self.fileIndex(memory, copy.path, 0), .line = copy.line, .column = copy.column };
            const best = try self.copies.getOrPut(memory, place);
            if (!best.found_existing or copy.slot < best.value_ptr.*) best.value_ptr.* = copy.slot;
        }
    }

    /// The index of the file written as `path`, listed with `lines` when it is new.
    fn fileIndex(self: *Total, memory: std.mem.Allocator, path: []const u8, lines: usize) std.mem.Allocator.Error!usize {
        const listed = try self.files.getOrPut(memory, try plainly(memory, path));
        if (!listed.found_existing) listed.value_ptr.* = lines;
        return listed.index;
    }

    /// The union so far as one report, its files sorted by path. Results live in `memory`.
    pub fn report(self: *const Total, memory: std.mem.Allocator) std.mem.Allocator.Error!Report {
        const files = try memory.alloc(FileCount, self.files.count());
        var lines: usize = 0;
        for (self.files.keys(), self.files.values(), files) |path, count_of_lines, *file| {
            file.* = .{ .path = path, .copies = 0, .lines = count_of_lines };
            lines += count_of_lines;
        }
        var tally: Tally = .{};
        for (self.copies.keys(), self.copies.values()) |place, slot| {
            files[place.file].copies += 1;
            switch (slot) {
                0 => tally.needless += 1,
                1 => tally.move += 1,
                2 => tally.for_store += 1,
                3 => tally.in_loop += 1,
                else => tally.unnamed += 1,
            }
        }
        std.mem.sort(FileCount, files, {}, pathLess);
        return .{ .tally = tally, .lines = lines, .files = files, .entries = self.entries, .split_known = self.split_known };
    }
};

/// `path` with its `.` and `name/..` parts taken out, so one file reached by two spellings is one file. A path is never
/// resolved against the disk: a link is not followed.
fn plainly(memory: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error![]const u8 {
    const rooted = std.mem.startsWith(u8, path, "/");
    var kept: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.tokenizeScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, ".")) continue;
        const backs = std.mem.eql(u8, part, "..");
        const last_is_name = kept.items.len != 0 and !std.mem.eql(u8, kept.items[kept.items.len - 1], "..");
        if (backs and last_is_name) {
            _ = kept.pop();
        } else if (!(backs and rooted)) {
            try kept.append(memory, part);
        }
    }
    const joined = try std.mem.join(memory, "/", kept.items);
    return if (rooted) std.fmt.allocPrint(memory, "/{s}", .{joined}) else joined;
}

/// The copies the program writes outside the standard library, one for each source position, sorted by position.
fn writtenCopies(memory: std.mem.Allocator, input: Input) std.mem.Allocator.Error![]Copy {
    var found: std.ArrayList(Copy) = .empty;
    for (input.program.nodes) |node| {
        if (!isWrittenCopy(input.src, node)) continue;
        if (std.mem.startsWith(u8, input.src.locate(node.span.start).path, stdlib_prefix)) continue;
        try found.append(memory, .{ .start = node.span.start, .end = node.span.end });
    }
    std.mem.sort(Copy, found.items, {}, copyLess);
    // One written copy can stand for several nodes (a copy of a record copies each field): keep its position once.
    var kept: usize = 0;
    for (found.items) |copy| {
        if (kept != 0 and found.items[kept - 1].start == copy.start) continue;
        found.items[kept] = copy;
        kept += 1;
    }
    return found.items[0..kept];
}

fn copyLess(_: void, left: Copy, right: Copy) bool {
    return left.start < right.start;
}

/// Record, for each copy, where the outermost simple statement that holds it starts.
fn holdingStatements(program: typed.Program, copies: []Copy) void {
    for (program.statements) |statement| {
        switch (statement.data) {
            .ret, .discard, .initialize, .assign, .assertion => {},
            else => continue,
        }
        var at = firstAtOrAfter(Copy, copies, statement.span.start);
        while (at < copies.len and copies[at].start < statement.span.end) : (at += 1) {
            if (copies[at].end > statement.span.end) continue;
            // The checker stages operands in statements of its own, inside the statement the source wrote: take the outermost.
            if (copies[at].statement == null or statement.span.start < copies[at].statement.?) copies[at].statement = statement.span.start;
        }
    }
}

/// The index of the first element of `items` whose position is at or after `position`.
fn firstAtOrAfter(comptime Item: type, items: []const Item, position: usize) usize {
    var low: usize = 0;
    var high = items.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const at = if (Item == usize) items[middle] else items[middle].start;
        if (at < position) low = middle + 1 else high = middle;
    }
    return low;
}

/// The sorted start of every finding of the four categories.
fn findingPositions(memory: std.mem.Allocator, findings: []const lint.Finding) std.mem.Allocator.Error!Positions {
    var positions: Positions = undefined;
    for (named_codes, 0..) |code, slot| {
        var found: std.ArrayList(usize) = .empty;
        for (findings) |finding| {
            if (std.mem.eql(u8, finding.code, code)) try found.append(memory, finding.span.start);
        }
        std.mem.sort(usize, found.items, {}, std.sort.asc(usize));
        positions[slot] = found.items;
    }
    return positions;
}

/// The first category with a finding that sits on `copy`: one that starts inside the copy's text, or where the statement
/// holding the copy starts (a store is reported at its statement). `named_codes.len` when there is none.
fn firstCategory(positions: Positions, copy: Copy) usize {
    for (positions, 0..) |starts, slot| {
        if (startsIn(starts, copy.start, copy.end)) return slot;
        if (copy.statement) |statement| if (startsIn(starts, statement, statement + 1)) return slot;
    }
    return named_codes.len;
}

/// Whether one of the sorted `starts` is at least `low` and below `high`.
fn startsIn(starts: []const usize, low: usize, high: usize) bool {
    const at = firstAtOrAfter(usize, starts, low);
    return at < starts.len and starts[at] < high;
}

/// Whether `node` is a `copy(...)` the source wrote: a copy operation with no operands of its own whose text begins `copy(`.
fn isWrittenCopy(src: source.Source, node: typed.Node) bool {
    if (node.view) return false;
    const operation = switch (node.data) {
        .buffer_operation => |operation| operation,
        else => return false,
    };
    if (operation.kind != .copy or operation.arguments.len != 0) return false;
    if (node.span.end > src.bytes.len or node.span.start >= node.span.end) return false;
    const text = src.bytes[node.span.start..node.span.end];
    if (!std.mem.startsWith(u8, text, "copy")) return false;
    const after = std.mem.trimStart(u8, text["copy".len..], " \t");
    return after.len != 0 and after[0] == '(';
}

/// The entry of `files` with this path, or null.
fn fileNamed(files: []FileCount, path: []const u8) ?*FileCount {
    for (files) |*file| {
        if (std.mem.eql(u8, file.path, path)) return file;
    }
    return null;
}

fn pathLess(_: void, left: FileCount, right: FileCount) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}

/// Every source file of the program that is not the standard library, each with its line count and no copies yet.
fn programFiles(memory: std.mem.Allocator, input: Input) std.mem.Allocator.Error!std.ArrayList(FileCount) {
    var files: std.ArrayList(FileCount) = .empty;
    if (input.src.origins.len == 0) {
        try addFile(memory, &files, input, input.src);
        return files;
    }
    for (input.src.origins) |origin| try addFile(memory, &files, input, origin.original);
    return files;
}

/// Add `original` once, unless it is the standard library or already listed.
fn addFile(memory: std.mem.Allocator, files: *std.ArrayList(FileCount), input: Input, original: source.Source) std.mem.Allocator.Error!void {
    if (std.mem.startsWith(u8, original.path, stdlib_prefix)) return;
    const path = try beside(memory, input.entry_path, original.path);
    if (fileNamed(files.items, path) != null) return;
    try files.append(memory, .{ .path = path, .copies = 0, .lines = lineCount(original.bytes) });
}

/// The lines of `bytes`: each newline ends one, and a last line with no newline is one more.
fn lineCount(bytes: []const u8) usize {
    if (bytes.len == 0) return 0;
    const newlines = std.mem.count(u8, bytes, "\n");
    return if (bytes[bytes.len - 1] == '\n') newlines else newlines + 1;
}

/// A module's path as the command line reaches it: written beside the entry's folder when the entry names one.
fn beside(memory: std.mem.Allocator, entry_path: []const u8, path: []const u8) std.mem.Allocator.Error![]const u8 {
    if (std.fs.path.isAbsolute(path)) return path;
    const folder = std.fs.path.dirname(entry_path) orelse return path;
    return std.fs.path.join(memory, &.{ folder, path });
}

/// The text the command prints: `entries: N` first when the count reads two or more entries, the totals line, then one line
/// for each category.
pub fn renderText(memory: std.mem.Allocator, report: Report) std.mem.Allocator.Error![]u8 {
    const tally = report.tally;
    var out: std.ArrayList(u8) = .empty;
    if (report.entries >= 2) try out.print(memory, "entries: {d}\n", .{report.entries});
    try out.print(memory, "copies: {d} in {d} lines, {d:.1} per 1000 lines\n", .{ tally.total(), report.lines, report.perThousand() });
    try out.print(memory, "{d:>6} selka fix removes them (L_NEEDLESS_COPY)\n", .{tally.needless});
    try out.print(memory, "{d:>6} a move replaces them (L_COPY_MOVE)\n", .{tally.move});
    try out.print(memory, "{d:>6} stored from a parameter (L_COPY_FOR_STORE)\n", .{tally.for_store});
    if (!report.split_known) {
        const both = tally.in_loop + tally.unnamed;
        try out.appendSlice(memory, "     ? in a loop (L_COPY_IN_LOOP): not known, the analysis failed\n");
        try out.print(memory, "     ? named by nothing: not known, the analysis failed (the two lines share {d} {s})\n", .{ both, if (both == 1) "copy" else "copies" });
        return out.items;
    }
    try out.print(memory, "{d:>6} in a loop (L_COPY_IN_LOOP)\n", .{tally.in_loop});
    try out.print(memory, "{d:>6} named by nothing\n", .{tally.unnamed});
    return out.items;
}

/// The one-line JSON the command prints with `--json`; `entries` follows the schema name, always (one for one entry).
pub fn renderJson(memory: std.mem.Allocator, report: Report) std.mem.Allocator.Error![]u8 {
    const tally = report.tally;
    var out: std.ArrayList(u8) = .empty;
    try out.print(memory, "{{\"schema\":\"{s}\",\"entries\":{d},\"copies\":{d},\"lines\":{d},\"per_1000\":{d:.1},", .{
        schema, report.entries, tally.total(), report.lines, report.perThousand(),
    });
    if (report.split_known) {
        try out.print(memory, "\"needless\":{d},\"move\":{d},\"for_store\":{d},\"in_loop\":{d},\"unnamed\":{d},\"files\":[", .{
            tally.needless, tally.move, tally.for_store, tally.in_loop, tally.unnamed,
        });
    } else {
        try out.print(memory, "\"needless\":{d},\"move\":{d},\"for_store\":{d},\"in_loop\":null,\"unnamed\":null,\"split_known\":false,\"in_loop_or_unnamed\":{d},\"files\":[", .{
            tally.needless, tally.move, tally.for_store, tally.in_loop + tally.unnamed,
        });
    }
    for (report.files, 0..) |file, index| {
        if (index != 0) try out.append(memory, ',');
        const quoted = try std.json.Stringify.valueAlloc(memory, file.path, .{});
        try out.print(memory, "{{\"path\":{s},\"copies\":{d},\"lines\":{d}}}", .{ quoted, file.copies, file.lines });
    }
    try out.appendSlice(memory, "]}\n");
    return out.items;
}
