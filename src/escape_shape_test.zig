//! Every refusal of the Escape rule says the same four things in the same order on one line: the matrix's refused rule-1 cells
//! (the grouped programs `test/fixtures/ownership-matrix/refused_<type>.selka` and their table `verdicts.tsv`, drawn from
//! `experiments/ownership-matrix-20261109/matrix.py` by lane OC's gate) and the shaped sites no cell reaches (`sites.selka`). Each
//! cell keeps the code and rule the table gives it. 57 of the 812 cells (730 since lane OC's H2, H3, H1, D8, H4 and H5) have a first
//! diagnostic about the written `own` and keep a marker wording that says what `own` gives and what the position needs: 47
//! refuse an `own` that takes nothing, and 10 are `own p[0:2]` of a text or bytes slice, whose own escape is the diagnostic
//! after it.
const std = @import("std");
const options = @import("test_paths");
const t = std.testing;
const report = std.debug.print;

const fixtures = "test/fixtures/ownership-matrix/";
const types = [_][]const u8{ "text", "item", "bytes", "ints" };

/// What a cell's first diagnostic is: a lent value that would outlive its lender, or a written `own` that takes nothing.
const Class = enum { escape, marker };

/// One cell of a fixture: its id, the code and rule the table gives it, and the lines of its function.
const Cell = struct { id: []const u8, code: []const u8, rule: []const u8, class: Class, first: usize, last: usize, message: ?[]const u8 = null };

/// The phrases no Escape message may use: a store with no name, a lender with no name.
const unnamed_phrases = [_][]const u8{ "this store", "the place it moves into", "a temporary value" };

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// Whether `message` opens by saying what is lent and who lends it, in one of the three forms the shape has.
fn opensWithLent(message: []const u8) bool {
    if (std.mem.startsWith(u8, message, "a bare `")) return contains(message, "` only lends ");
    if (std.mem.startsWith(u8, message, "`own ")) return contains(message, "` cannot give ") and contains(message, ", which only lends it, and ");
    return std.mem.startsWith(u8, message, "`") and contains(message, "` is lent by ");
}

/// Whether the part after the lender says where the value would outlive it or what the destination needs, then offers repairs.
fn closesWithRepairs(message: []const u8) bool {
    const split = std.mem.indexOf(u8, message, "; ") orelse return false;
    const before = message[0..split];
    const repairs = message[split + 2 ..];
    if (!contains(before, ", and ")) return false;
    if (!contains(before, " would keep it after ") and !std.mem.endsWith(u8, before, " needs its own value")) return false;
    const openers = [_][]const u8{ "write `", "wrap ", "declare the result `from ", "declare `", "remove `own`", "bind `" };
    for (openers) |opener| if (std.mem.startsWith(u8, repairs, opener)) return true;
    return false;
}

/// Whether `message` has the Escape rule's shape: one line, the lent value and its lender, the destination, the repairs.
fn isEscapeShape(message: []const u8) bool {
    if (contains(message, "\n")) return false;
    for (unnamed_phrases) |phrase| if (contains(message, phrase)) return false;
    return opensWithLent(message) and closesWithRepairs(message);
}

/// Whether `message` is one of the marker wordings of an `own` that takes nothing.
fn isMarkerWording(message: []const u8) bool {
    if (contains(message, "\n")) return false;
    const returned = "a return gives its value without `own`; remove `own`";
    const fresh = "a fresh value is already owned, so `own` adds nothing; remove `own`";
    if (std.mem.eql(u8, message, returned) or std.mem.eql(u8, message, fresh)) return true;
    return std.mem.startsWith(u8, message, "`own ") and contains(message, "` gives `") and std.mem.endsWith(u8, message, "; remove `own`");
}

fn parseClass(word: []const u8) !Class {
    return std.meta.stringToEnum(Class, word) orelse error.InvalidCell;
}

/// The cells a hand-written fixture declares: a `# cell: ID CODE RULE CLASS` comment line starts each, and its function runs
/// to the next.
fn declared(a: std.mem.Allocator, source: []const u8) ![]Cell {
    var found: std.ArrayList(Cell) = .empty;
    var lines = std.mem.splitScalar(u8, source, '\n');
    var number: usize = 0;
    while (lines.next()) |line| {
        number += 1;
        if (found.items.len != 0) found.items[found.items.len - 1].last = number;
        if (!std.mem.startsWith(u8, line, "# cell: ")) continue;
        var words = std.mem.tokenizeScalar(u8, line["# cell: ".len..], ' ');
        const id = words.next() orelse return error.InvalidCell;
        const code = words.next() orelse return error.InvalidCell;
        const rule = words.next() orelse return error.InvalidCell;
        const class = try parseClass(words.next() orelse return error.InvalidCell);
        try found.append(a, .{ .id = id, .code = code, .rule = rule, .class = class, .first = number, .last = number });
    }
    return found.toOwnedSlice(a);
}

/// Whether the matrix cell `id` (`TYPE__SOURCE__POSITION__VERB`) is a refusal of a written `own` that takes nothing: the
/// argument of a plain parameter, `return own` of an owner, or `own p[0:2]` of a text or bytes slice that is stored.
fn markerCell(id: []const u8) bool {
    var parts = std.mem.splitSequence(u8, id, "__");
    const kind = parts.next() orelse return false;
    const source = parts.next() orelse return false;
    const position = parts.next() orelse return false;
    const verb = parts.next() orelse return false;
    if (!std.mem.eql(u8, verb, "own")) return false;
    if (std.mem.eql(u8, position, "arg_plain")) return true;
    if (std.mem.eql(u8, position, "return_owned")) return std.mem.eql(u8, source, "local") or std.mem.eql(u8, source, "own_param");
    if (!std.mem.eql(u8, source, "param_slice") or std.mem.eql(u8, kind, "ints")) return false;
    const storing = [_][]const u8{ "record_local", "record_returned", "list_local", "list_returned", "list_out_param" };
    for (storing) |name| if (std.mem.eql(u8, position, name)) return true;
    return false;
}

/// The code and rule of a refused cell in the table (`id`, `refused`, code, rule, tab separated).
fn verdictOf(a: std.mem.Allocator, verdicts: []const u8, id: []const u8) !struct { code: []const u8, rule: []const u8 } {
    const needle = try std.fmt.allocPrint(a, "\n{s}\trefused\t", .{id});
    const at = std.mem.indexOf(u8, verdicts, needle) orelse return error.MissingVerdict;
    var fields = std.mem.tokenizeAny(u8, verdicts[at + needle.len ..], "\t\n");
    const code = fields.next() orelse return error.MissingVerdict;
    const rule = fields.next() orelse return error.MissingVerdict;
    return .{ .code = code, .rule = rule };
}

/// The refused rule-1 cells of one matrix program: each `func probe_ID(` line starts one, with the code and rule `verdicts`
/// (the table's text) gives it. The 27 cells of `E_BORROW_MIXED` are the next rule's and are left out.
fn matrixCells(a: std.mem.Allocator, source: []const u8, verdicts: []const u8) ![]Cell {
    var found: std.ArrayList(Cell) = .empty;
    var lines = std.mem.splitScalar(u8, source, '\n');
    var number: usize = 0;
    var open = false;
    while (lines.next()) |line| {
        number += 1;
        if (open and std.mem.startsWith(u8, line, "func ")) open = false;
        if (open) found.items[found.items.len - 1].last = number;
        const prefix = "func probe_";
        if (!std.mem.startsWith(u8, line, prefix)) continue;
        const id = line[prefix.len .. std.mem.indexOfScalar(u8, line, '(') orelse return error.InvalidCell];
        const verdict = try verdictOf(a, verdicts, id);
        if (std.mem.eql(u8, verdict.code, "E_BORROW_MIXED")) continue;
        const class: Class = if (markerCell(id)) .marker else .escape;
        try found.append(a, .{ .id = id, .code = verdict.code, .rule = verdict.rule, .class = class, .first = number, .last = number });
        open = true;
    }
    return found.toOwnedSlice(a);
}

/// Record each error diagnostic of a check's output on the cell whose lines hold its location, the first one only.
fn assign(a: std.mem.Allocator, cells: []Cell, output: []const u8) !void {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "{")) continue;
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, line, .{});
        const diagnostic = (if (parsed == .object) parsed.object.get("diagnostic") else null) orelse continue;
        if (diagnostic != .object) continue;
        const severity = diagnostic.object.get("severity") orelse continue;
        if (severity != .string or !std.mem.eql(u8, severity.string, "error")) continue;
        const location = diagnostic.object.get("location") orelse continue;
        const start = location.object.get("start") orelse continue;
        const row: usize = @intCast(start.object.get("line").?.integer);
        for (cells) |*cell| {
            if (row < cell.first or row > cell.last or cell.message != null) continue;
            const code = diagnostic.object.get("code").?.string;
            const rule = (diagnostic.object.get("rule") orelse return error.MissingRule).string;
            if (!std.mem.eql(u8, code, cell.code) or !std.mem.eql(u8, rule, cell.rule)) return error.ChangedVerdict;
            cell.message = diagnostic.object.get("message").?.string;
        }
    }
}

/// Hold every cell to the wording of its class; a cell with no refusal at all is an error.
fn holdCells(cells: []const Cell) !void {
    for (cells) |cell| {
        const message = cell.message orelse {
            report("escape shape: {s} has no refusal\n", .{cell.id});
            return error.MissingRefusal;
        };
        const fits = switch (cell.class) {
            .escape => isEscapeShape(message),
            .marker => isMarkerWording(message),
        };
        if (!fits) report("escape shape: {s} {s} {s}: {s}\n", .{ cell.id, cell.code, cell.rule, message });
        try t.expect(fits);
    }
}

/// Check one program with one compiler run and hold every cell to the wording of its class.
fn checkProgram(a: std.mem.Allocator, path: []const u8, cells: []Cell) !void {
    const argv = [_][]const u8{ options.corePath(), "check", path, "--no-cache", "--diagnostics=json" };
    const result = try std.process.run(a, t.io, .{ .argv = &argv });
    try assign(a, cells, result.stdout);
    try assign(a, cells, result.stderr);
    try holdCells(cells);
}

/// Check the refused programs of every matrix type and return how many cells they held and how many were markers.
fn checkMatrix(a: std.mem.Allocator) ![2]usize {
    const verdicts = try std.Io.Dir.cwd().readFileAlloc(t.io, fixtures ++ "verdicts.tsv", a, .limited(1 << 22));
    var held: [2]usize = .{ 0, 0 };
    for (types) |kind| {
        const path = try std.fmt.allocPrint(a, "{s}refused_{s}.selka", .{ fixtures, kind });
        const source = try std.Io.Dir.cwd().readFileAlloc(t.io, path, a, .limited(1 << 22));
        const cells = try matrixCells(a, source, verdicts);
        try checkProgram(a, path, cells);
        held[0] += cells.len;
        for (cells) |cell| held[1] += @intFromBool(cell.class == .marker);
    }
    return held;
}

test "the matrix's refused rule-1 cells (730 since H5) keep their codes and rules and say the escape shape or the marker wording" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const held = try checkMatrix(arena.allocator());
    // 812 on 10 November; lane OC's H2 accepts 32 `Some(place)` locals, H3 four `from` record results and H1 36 `mut`
    // locals stored once from a place; D8 refuses two text and bytes slices given to an `own` parameter; H4 accepts six
    // `mut` locals stored from a slice of a parameter, once or rebound; H5 accepts six bare text, bytes and list parameters
    // stored in a local list or dictionary.
    try t.expectEqual(@as(usize, 730), held[0]);
    try t.expectEqual(@as(usize, 57), held[1]);
}

/// The cells of `sites.selka`: R6 (a selection stored, a selection binding moved), V4, V5, B9 (a `const` alias moved) and B2 at
/// a write through a `mut` local stored once from a place (D4, `escape_message.composeWrite`). The other B9 messages (a borrowing `mut` local, a record or collection of borrows, an owner made again in each iteration) are
/// shaped too, but a refusal by one of them is replaced by the owner's refusal before it is reported (`finishFunction`).
const sites_count = 6;

test "the shaped sites no matrix cell reaches say the escape shape" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(t.io, fixtures ++ "sites.selka", a, .limited(1 << 20));
    const cells = try declared(a, source);
    try t.expectEqual(sites_count, cells.len);
    try checkProgram(a, fixtures ++ "sites.selka", cells);
}

test "the escape shape is one line that opens with what is lent and closes with repairs" {
    try t.expect(isEscapeShape("a bare `p` only lends the plain parameter `p`, and field `value` of `TextBox` needs its own value; write `copy(p)` to keep both"));
    try t.expect(isEscapeShape("`p[0:2]` is lent by the plain parameter `p`, and the returned value would keep it after the call returns; write `copy(p[0:2])` to keep both"));
    try t.expect(isEscapeShape("a bare `p` only lends the plain parameter `p`, and the list `out` needs its own value; " ++
        "declare `p` as `own p: str` and write `own p` here to take it (a caller then gives it with `own p`, " ++
        "or copies if it reads it again), or write `copy(p)` to keep both"));
    try t.expect(isEscapeShape("`own p` cannot give the plain parameter `p`, which only lends it, and the local `c` needs its own value; write `copy(p)` to keep both"));
    try t.expect(isEscapeShape("`part` is lent by the local `left` or the local `right`, and the local `part` needs its own value; wrap what each branch assigns in `copy(...)` to keep both"));
}

test "a message with a nameless store, a nameless lender, a second line or no repairs is not the escape shape" {
    try t.expect(!isEscapeShape("a borrowed value cannot be stored or returned; make an explicit copy(value)"));
    try t.expect(!isEscapeShape("`p` is lent by the plain parameter `p`, and this store needs its own value; write `copy(p)` to keep both"));
    try t.expect(!isEscapeShape("`p` is lent by a temporary value, and the local `c` needs its own value; write `copy(p)` to keep both"));
    try t.expect(!isEscapeShape("`p` is lent by the plain parameter `p`, and the local `c` needs its own value;\nwrite `copy(p)` to keep both"));
    try t.expect(!isEscapeShape("`p` is lent by the plain parameter `p`, and the local `c` needs its own value"));
}

test "the marker wordings are the verbs' words for an own that takes nothing" {
    try t.expect(isMarkerWording("`own p` gives `p`, but this argument is only read; remove `own`"));
    try t.expect(isMarkerWording("a return gives its value without `own`; remove `own`"));
    try t.expect(isMarkerWording("a fresh value is already owned, so `own` adds nothing; remove `own`"));
    try t.expect(!isMarkerWording("a fresh value needs no own marker; remove own"));
}

test "a marker cell is an own that takes nothing: a plain argument, a return of an owner, a stored text or bytes slice" {
    try t.expect(markerCell("text__param__arg_plain__own"));
    try t.expect(markerCell("item__local__return_owned__own"));
    try t.expect(markerCell("bytes__param_slice__list_local__own"));
    try t.expect(!markerCell("ints__param_slice__list_local__own"));
    try t.expect(!markerCell("text__param__arg_plain__bare"));
    try t.expect(!markerCell("text__param__return_owned__own"));
}

test "a cell comment that is incomplete or names an unknown class is refused, and so is a cell with no refusal" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectError(error.InvalidCell, declared(a, "# cell: only_an_id\n"));
    try t.expectError(error.InvalidCell, declared(a, "# cell: id E_CODE R1 neither\nfunc f():\n"));
    const cells = try declared(a, "# cell: id E_OWN_MARKER B2 escape\nfunc f():\n    pass\n");
    try t.expectEqual(@as(usize, 1), cells.len);
    try t.expectError(error.MissingRefusal, holdCells(cells));
}

test "a table without a cell's verdict is refused, and one with it gives the code and rule" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const table = "# cell\tverdict\tcode\trule\ntext__a__b__bare\trefused\tE_OWN_MARKER\tB2\ntext__a__c__bare\tok\t-\t-\n";
    const found = try verdictOf(a, table, "text__a__b__bare");
    try t.expectEqualStrings("E_OWN_MARKER", found.code);
    try t.expectEqualStrings("B2", found.rule);
    try t.expectError(error.MissingVerdict, verdictOf(a, table, "text__a__c__bare"));
}

test "a diagnostic that changes a cell's code or rule, or names none, is refused" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cells = try declared(a, "# cell: id E_OWN_MARKER B2 escape\nfunc f():\n    pass\n");
    const right = "{\"diagnostic\":{\"code\":\"E_OWN_MARKER\",\"severity\":\"error\",\"rule\":\"B2\",\"message\":\"m\",\"location\":{\"start\":{\"line\":2}}}}\n";
    const wrong = "{\"diagnostic\":{\"code\":\"E_OWN_MARKER\",\"severity\":\"error\",\"rule\":\"W2\",\"message\":\"m\",\"location\":{\"start\":{\"line\":2}}}}\n";
    const bare = "{\"diagnostic\":{\"code\":\"E_OWN_MARKER\",\"severity\":\"error\",\"message\":\"m\",\"location\":{\"start\":{\"line\":2}}}}\n";
    try t.expectError(error.ChangedVerdict, assign(a, cells, wrong));
    try t.expectError(error.MissingRule, assign(a, cells, bare));
    try assign(a, cells, right);
    try t.expectEqualStrings("m", cells[0].message.?);
}
