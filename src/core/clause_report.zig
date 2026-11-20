//! The clause report (proof steps S1): what Core's facts made of every contract clause (`@requires`, `@ensures`,
//! `@invariant`) and every `assert`, read from the final IR after the passes of the build mode being built.
//!
//! A clause is lowered as a branch to a trap block: an `unreachable` whose `data` carries `flags.assertion_trap`, the
//! clause kind and a message index (`build.zig` `assertStatement`), at the span of the clause's condition. That span,
//! the kind and the message already identify the clause on every copy of its check: a callee's copy cloned by the
//! inliner keeps its instructions' spans, and its ancestry (`inline_origins.zig`) names the callee and the call site.
//! An `@invariant` has one copy per construction or write site, a generic function one per instance, an `@ensures` one
//! per return. Nothing is added to the IR, so the report changes no emitted code and no cache format.
//!
//! Each copy is one of:
//! - **proved**: the facts state its trap block unreachable (the dead block of the fact certificate, check F5, which a
//!   Debug compiler validates and `--verify-facts` asserts at run time);
//! - **refuted**: its trap block is reachable and the block its check passes to is not, so every execution that
//!   reaches the check fails it;
//! - **kept**: anything else; a run-time check remains. A build without facts keeps every copy.
//! A clause is refuted when one copy is, kept when one copy is kept and none is refuted, and proved otherwise.
const std = @import("std");
const ir = @import("ir.zig");
const passes = @import("passes.zig");
const flags = @import("flags.zig");
const facts = @import("facts.zig");
const source_location = @import("source_location.zig");
const cost = @import("cost.zig");

/// What a trap guards: one of the three clause kinds, or an `assert` statement.
pub const Kind = enum { requires, ensures, invariant, assert };

/// What the facts made of one copy, or of a clause from its copies.
pub const Status = enum { proved, refuted, kept };

/// Copies by status. `unused` counts the copies in a function nothing calls after the passes (`callers`): they never
/// run, so they decide no status, and no fact states them dead either.
pub const Copies = struct {
    proved: u32 = 0,
    refuted: u32 = 0,
    kept: u32 = 0,
    unused: u32 = 0,

    /// Count one copy of `status`.
    pub fn count(self: *Copies, what: Status) void {
        switch (what) {
            .proved => self.proved += 1,
            .refuted => self.refuted += 1,
            .kept => self.kept += 1,
        }
    }

    /// Add every copy of `other`.
    pub fn add(self: *Copies, other: Copies) void {
        self.proved += other.proved;
        self.refuted += other.refuted;
        self.kept += other.kept;
        self.unused += other.unused;
    }

    /// The status of a clause with these copies; one with unused copies alone is kept, since no fact states it.
    pub fn verdict(self: Copies) Status {
        if (self.refuted != 0) return .refuted;
        if (self.kept != 0 or self.proved == 0) return .kept;
        return .proved;
    }
};

/// The call sites of a function with a `@requires` (proof steps S2), by what the facts made of the copy of the clause each one
/// runs: an inlined copy is its own site, and every reached direct call of a body runs that body's own copy, whose parameter
/// intervals join every caller's arguments, so a proof there covers each site. A call through a function value is not
/// counted.
pub const Sites = struct {
    proved: u32 = 0,
    refuted: u32 = 0,
    kept: u32 = 0,

    /// Count `n` sites whose copy has `status`.
    pub fn countMany(self: *Sites, status: Status, n: u32) void {
        switch (status) {
            .proved => self.proved += n,
            .refuted => self.refuted += n,
            .kept => self.kept += n,
        }
    }

    /// Add every site of `other`.
    pub fn add(self: *Sites, other: Sites) void {
        self.proved += other.proved;
        self.refuted += other.refuted;
        self.kept += other.kept;
    }
};

/// One copy the facts refuted: the emitted function it is in and, for a copy the inliner cloned, the call it was cloned
/// at (the call of the clause's own function).
pub const Witness = struct {
    /// The emitted (physical) function holding the copy.
    function: []const u8,
    /// The call site of an inlined copy; null for a copy in the function's own body.
    call: ?source_location.Location = null,
};

/// How a clause is named: the function or record it is written on, its condition as written (whitespace folded) and
/// which clause of its kind on that subject it is (1 for the first in the source).
pub const Name = struct { subject: []const u8, text: []const u8, ordinal: u32 = 1 };

/// One clause (or one `assert`) and what the facts made of its copies.
pub const Clause = struct {
    kind: Kind,
    name: Name,
    /// The position of the clause's condition.
    at: source_location.Location,
    status: Status = .proved,
    /// Copies in the function's own body (`own`) and copies the inliner cloned into callers (`inlined`).
    copies: struct { own: Copies = .{}, inlined: Copies = .{} } = .{},
    /// The first refuted copy, when there is one.
    refuted: ?Witness = null,
    /// For a `@requires`, its call sites by status (`Sites`); always empty for another kind.
    sites: Sites = .{},

    /// The JSON row: flat fields in a fixed order, `refuted_at` only on a refuted clause.
    pub fn jsonStringify(self: Clause, jw: anytype) !void {
        try jw.beginObject();
        inline for (.{ .{ "kind", @tagName(self.kind) }, .{ "function", self.name.subject }, .{ "clause", self.name.text } }) |field| {
            try jw.objectField(field[0]);
            try jw.write(field[1]);
        }
        try jw.objectField("ordinal");
        try jw.write(self.name.ordinal);
        try jw.objectField("path");
        try jw.write(self.at.path);
        try jw.objectField("line");
        try jw.write(self.at.line);
        try jw.objectField("column");
        try jw.write(self.at.column);
        try jw.objectField("status");
        try jw.write(@tagName(self.status));
        try jw.objectField("own");
        try jw.write(self.copies.own);
        try jw.objectField("inlined");
        try jw.write(self.copies.inlined);
        if (self.kind == .requires) {
            try jw.objectField("call_sites");
            try jw.write(self.sites);
        }
        if (self.refuted) |witness| {
            try jw.objectField("refuted_at");
            try jw.beginObject();
            try jw.objectField("function");
            try jw.write(witness.function);
            if (witness.call) |call| {
                try jw.objectField("call");
                try jw.write(call);
            }
            try jw.endObject();
        }
        try jw.endObject();
    }
};

/// Whole-program counts: clauses by status, clause copies in own bodies and inlined, `assert` copies, and the call sites
/// of every `@requires` by status.
pub const Totals = struct {
    clauses: Copies = .{},
    own: Copies = .{},
    inlined: Copies = .{},
    asserts: Copies = .{},
    call_sites: Sites = .{},

    /// Whether the program has any clause or `assert` copy at all.
    pub fn any(self: Totals) bool {
        const copies = [_]Copies{ self.own, self.inlined, self.asserts };
        for (copies) |c| if (c.proved + c.refuted + c.kept + c.unused != 0) return true;
        return false;
    }
};

/// Every clause and every `assert` of the final module, clauses first, each in source order.
pub const Report = struct {
    totals: Totals = .{},
    clauses: []const Clause = &.{},
    asserts: []const Clause = &.{},
};

/// Traps the compiler makes for its own checks with the statement kind; they are no `assert` of the program (S4 lists
/// such checks). Matched by their fixed messages.
const internal_messages = [_][]const u8{ "overlapping mut arguments", "invalidated Option narrowing", "range() arg 3 must not be zero" };

/// A clause is its kind, the span of its condition and its message text. The message's index is no part of it: a
/// build lowers each copy's message as its own string, and a cached lowering may share one.
const Key = struct { kind: Kind, span: u32, message: []const u8 };

/// Where the report finds source positions: `locator` resolves a span as the emitter does, `fallback_path` names the
/// entry source when it gives no path, and `text` is the checked program's source bytes (the offsets spans index),
/// read to find where an `@invariant` is written.
pub const Where = struct { locator: source_location.Locator, fallback_path: []const u8, text: []const u8 = "" };

/// Read every clause and `assert` copy of `module` after the passes that produced `result`.
pub fn collect(a: std.mem.Allocator, module: *const ir.Module, result: *const passes.Result, where: Where) std.mem.Allocator.Error!Report {
    const locator = where.locator;
    const fallback_path = where.fallback_path;
    var rows: std.ArrayList(Clause) = .empty;
    var keys: std.ArrayList(Key) = .empty;
    var index_of: std.StringHashMapUnmanaged(usize) = .empty;
    defer index_of.deinit(a);
    const called = try callers(a, module, result);
    const calls = try callCounts(a, module, result, called);
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        const known = if (index < result.known.len) result.known[index] else null;
        for (function.blocks.items, 0..) |block, b| for (block.insts.items) |ref| {
            const inst = function.inst(ref);
            if (inst.op != .@"unreachable" or inst.data & flags.assertion_trap == 0) continue;
            const kind = kindOf(module, inst) orelse continue;
            // An invariant's copies are checked at each construction or write and carry that site's span, so the
            // clause is its message alone; it is placed where the source writes it (`invariantOffset`).
            const key: Key = .{ .kind = kind, .span = if (kind == .invariant) 0 else inst.span, .message = messageOf(module, inst) };
            const entry = try index_of.getOrPut(a, try std.fmt.allocPrint(a, "{d}:{d}:{s}", .{ @backingInt(kind), key.span, key.message }));
            if (!entry.found_existing) {
                entry.value_ptr.* = rows.items.len;
                const name = nameOf(kind, key.message);
                const offset = if (kind == .invariant) invariantOffset(where.text, name) orelse inst.span else inst.span;
                try keys.append(a, .{ .kind = kind, .span = offset, .message = key.message });
                try rows.append(a, .{ .kind = kind, .name = name, .at = locate(locator, offset, fallback_path) });
            }
            const row = &rows.items[entry.value_ptr.*];
            const status = copyStatus(function, known, b);
            const frame = result.provenance.instruction(@intCast(index), @intCast(b), ref);
            const copies = if (frame == null) &row.copies.own else &row.copies.inlined;
            if (!called[index]) {
                copies.unused += 1;
                continue;
            }
            copies.count(status);
            if (kind == .requires) row.sites.countMany(status, if (frame == null) calls[index] else 1);
            if (status == .refuted and row.refuted == null) row.refuted = .{
                .function = function.name,
                .call = if (frame) |id| locate(locator, result.provenance.frames.items[id].call_span, fallback_path) else null,
            };
        };
    }
    for (rows.items) |*row| {
        var both = row.copies.own;
        both.add(row.copies.inlined);
        row.status = both.verdict();
    }
    return finish(a, rows.items, keys.items);
}

/// Which functions can run: the entry, every function a `func_ref` names (a function value could be called from
/// anywhere) and every function a `call` in a block the facts do not call unreachable names. An internal function
/// is reached only through these, the assumption the whole-program parameter intervals already make
/// (`passes.parameterRanges`); a body the inliner cloned into every caller and nothing calls any more never runs.
fn callers(a: std.mem.Allocator, module: *const ir.Module, result: *const passes.Result) std.mem.Allocator.Error![]bool {
    const count = module.functions.items.len;
    const called = try a.alloc(bool, count);
    @memset(called, false);
    if (module.entry < count) called[module.entry] = true;
    for (module.functions.items, 0..) |function, index| {
        if (function.signature.linkage != .internal) continue;
        const known = if (index < result.known.len) result.known[index] else null;
        for (function.insts.items) |inst| if (inst.op == .func_ref and inst.data < count) {
            called[@intCast(inst.data)] = true;
        };
        for (function.blocks.items, 0..) |block, b| {
            if (known) |table| if (b < table.reachable.len and !table.reachable[b]) continue;
            for (block.insts.items) |ref| {
                const inst = function.inst(ref);
                if (inst.op == .call and inst.a.index() < count) called[inst.a.index()] = true;
            }
        }
    }
    return called;
}

/// Per function, how many direct calls name it from a reached block of a function that can run (`callers`).
fn callCounts(a: std.mem.Allocator, module: *const ir.Module, result: *const passes.Result, called: []const bool) std.mem.Allocator.Error![]u32 {
    const count = module.functions.items.len;
    const out = try a.alloc(u32, count);
    @memset(out, 0);
    for (module.functions.items, 0..) |function, index| {
        if (function.signature.linkage != .internal or !called[index]) continue;
        const known = if (index < result.known.len) result.known[index] else null;
        for (function.blocks.items, 0..) |block, b| {
            if (known) |table| if (b < table.reachable.len and !table.reachable[b]) continue;
            for (block.insts.items) |ref| {
                const inst = function.inst(ref);
                if (inst.op == .call and inst.a.index() < count) out[inst.a.index()] += 1;
            }
        }
    }
    return out;
}

/// Split rows into clauses and asserts, order each by source position, number each subject's clauses of one kind, and
/// count the totals.
fn finish(a: std.mem.Allocator, rows: []Clause, keys: []const Key) std.mem.Allocator.Error!Report {
    const order = try a.alloc(usize, rows.len);
    for (order, 0..) |*slot, i| slot.* = i;
    std.mem.sort(usize, order, keys, struct {
        fn less(context: []const Key, x: usize, y: usize) bool {
            if (context[x].span != context[y].span) return context[x].span < context[y].span;
            if (context[x].kind != context[y].kind) return @backingInt(context[x].kind) < @backingInt(context[y].kind);
            return std.mem.order(u8, context[x].message, context[y].message) == .lt;
        }
    }.less);
    var clauses: std.ArrayList(Clause) = .empty;
    var asserts: std.ArrayList(Clause) = .empty;
    var totals: Totals = .{};
    for (order) |i| {
        var row = rows[i];
        if (row.kind == .assert) {
            totals.asserts.add(row.copies.own);
            totals.asserts.add(row.copies.inlined);
            try asserts.append(a, row);
            continue;
        }
        for (clauses.items) |earlier| {
            if (earlier.kind == row.kind and std.mem.eql(u8, earlier.name.subject, row.name.subject)) row.name.ordinal += 1;
        }
        totals.clauses.count(row.status);
        totals.own.add(row.copies.own);
        totals.inlined.add(row.copies.inlined);
        totals.call_sites.add(row.sites);
        try clauses.append(a, row);
    }
    return .{ .totals = totals, .clauses = clauses.items, .asserts = asserts.items };
}

fn kindOf(module: *const ir.Module, inst: ir.Inst) ?Kind {
    return switch (@as(u8, @truncate(inst.data >> 32))) {
        1 => .requires,
        2 => .ensures,
        3 => .invariant,
        0 => {
            const message = messageOf(module, inst);
            for (internal_messages) |internal| if (std.mem.eql(u8, message, internal)) return null;
            return .assert;
        },
        else => null,
    };
}

fn messageOf(module: *const ir.Module, inst: ir.Inst) []const u8 {
    const index: u32 = @truncate(inst.data);
    return if (index < module.strings.items.len) module.strings.items[index] else "";
}

/// A clause's trap message is `subject kind `condition`[: note]` (`sema_contracts.trapMessage`); an `assert` keeps its
/// own message, which names no subject.
fn nameOf(kind: Kind, message: []const u8) Name {
    if (kind == .assert) return .{ .subject = "", .text = message };
    const word = switch (kind) {
        .requires => " requires `",
        .ensures => " ensures `",
        .invariant => " invariant `",
        .assert => unreachable,
    };
    const at = std.mem.indexOf(u8, message, word) orelse return .{ .subject = "", .text = message };
    const rest = message[at + word.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '`') orelse rest.len;
    return .{ .subject = message[0..at], .text = rest[0..end] };
}

/// The offset of the condition of the one `@invariant(...)` in `text` whose condition, its whitespace folded, is
/// `name.text` and which is written on a record named `name.subject`; null when there is none or more than one.
pub fn invariantOffset(text: []const u8, name: Name) ?u32 {
    const opening = "@invariant(";
    var found: ?usize = null;
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, text, cursor, opening)) |at| {
        cursor = at + opening.len;
        var start = cursor;
        while (start < text.len and std.ascii.isWhitespace(text[start])) start += 1;
        const end = conditionEnd(text, start) orelse continue;
        if (!foldedEql(text[start..end], name.text) or !declares(text, end, name.subject)) continue;
        if (found != null) return null;
        found = start;
    }
    const offset = found orelse return null;
    return std.math.cast(u32, offset);
}

/// The end of a clause condition starting at `start`: the first `,` or `)` outside brackets and quotes.
fn conditionEnd(text: []const u8, start: usize) ?usize {
    var depth: usize = 0;
    var i = start;
    while (i < text.len) : (i += 1) switch (text[i]) {
        '(', '[', '{' => depth += 1,
        ')', ']', '}' => {
            if (depth == 0) return i;
            depth -= 1;
        },
        ',' => if (depth == 0) return i,
        '"', '\'' => |quote| {
            i += 1;
            while (i < text.len and text[i] != quote) : (i += 1) {
                if (text[i] == '\\') i += 1;
            }
        },
        else => {},
    };
    return null;
}

/// Whether `source`, with its whitespace runs folded to one space and trimmed, is `folded` (`trapMessage` folds so).
fn foldedEql(source: []const u8, folded: []const u8) bool {
    const trimmed = std.mem.trim(u8, source, " \t\r\n");
    var j: usize = 0;
    var space = false;
    for (trimmed) |byte| {
        const blank = byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
        if (blank and space) continue;
        space = blank;
        if (j >= folded.len or folded[j] != (if (blank) ' ' else byte)) return false;
        j += 1;
    }
    return j == folded.len;
}

/// Whether the next record declared after offset `from` is named `subject` (its last `.`- or `::`-separated part).
fn declares(text: []const u8, from: usize, subject: []const u8) bool {
    const keyword = "record ";
    var at = std.mem.indexOfPos(u8, text, from, keyword) orelse return false;
    at += keyword.len;
    while (at < text.len and text[at] == ' ') at += 1;
    var end = at;
    while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_')) end += 1;
    var short = subject;
    if (std.mem.lastIndexOfAny(u8, short, ".:")) |separator| short = short[separator + 1 ..];
    return std.mem.eql(u8, text[at..end], short);
}

fn locate(locator: source_location.Locator, span: u32, fallback_path: []const u8) source_location.Location {
    var location = locator.locate(locator.context, span);
    if (location.path.len == 0) location.path = fallback_path;
    return location;
}

/// What the facts made of the copy whose trap is in block `trap`. The block its check passes to is the one the
/// builder made right after the trap block (`assertStatement` makes `failed`, then `passed`), which block cloning keeps
/// adjacent; it is accepted only when a branch of the function goes to exactly those two blocks. Without that shape
/// a reachable trap is kept.
pub fn copyStatus(function: *const ir.Function, known: ?facts.Facts, trap: usize) Status {
    const table = known orelse return .kept;
    if (trap >= table.reachable.len) return .kept;
    if (!table.reachable[trap]) return .proved;
    const pass = passBlock(function, trap) orelse return .kept;
    return if (pass < table.reachable.len and !table.reachable[pass]) .refuted else .kept;
}

fn passBlock(function: *const ir.Function, trap: usize) ?usize {
    const next = trap + 1;
    if (next >= function.blocks.items.len) return null;
    for (function.blocks.items) |block| {
        const insts = block.insts.items;
        if (insts.len == 0) continue;
        const last = function.inst(insts[insts.len - 1]);
        if (last.op != .branch) continue;
        const targets = ir.unpackTargets(last.data);
        const then = targets.then.index();
        const otherwise = targets.otherwise.index();
        if ((then == trap and otherwise == next) or (then == next and otherwise == trap)) return next;
    }
    return null;
}

/// Rows whose subject (the clause's function or record) is `filter`, compared as cost compares function rows; the
/// totals are recounted over the selected rows.
pub fn select(a: std.mem.Allocator, report: Report, filter: ?[]const u8) std.mem.Allocator.Error!Report {
    const chosen = filter orelse return report;
    var rows: std.ArrayList(Clause) = .empty;
    var totals: Totals = .{ .asserts = report.totals.asserts };
    for (report.clauses) |row| if (matches(row.name.subject, chosen)) {
        totals.clauses.count(row.status);
        totals.own.add(row.copies.own);
        totals.inlined.add(row.copies.inlined);
        totals.call_sites.add(row.sites);
        try rows.append(a, row);
    };
    return .{ .totals = totals, .clauses = rows.items, .asserts = report.asserts };
}

fn matches(name: []const u8, chosen: []const u8) bool {
    if (std.mem.eql(u8, name, chosen)) return true;
    const separator = std.mem.lastIndexOf(u8, name, "::") orelse return false;
    return std.mem.eql(u8, name[separator + 2 ..], chosen);
}

/// The versioned `--clauses` document: the unchanged cost rows and totals, then the clause totals and rows.
pub const Document = struct {
    /// The document version (`cost-clauses-v1`).
    version: []const u8 = "cost-clauses-v1",
    /// The same emitted-function rows as `cost-v1`, already filtered.
    functions: []const cost.Function,
    /// The same totals as `cost-v1`, already filtered.
    totals: cost.Counts,
    /// Clauses by status, clause copies (own and inlined) and `assert` copies.
    clause_totals: Totals,
    /// One row per clause, in source order.
    clauses: []const Clause,
    /// One row per `assert`, only when `--asserts` asked for them.
    asserts: []const Clause,
};

/// What `--clauses` prints, and whether `--asserts` adds the `assert` rows.
pub const Rendering = struct { json: bool = false, asserts: bool = false };

/// Render `--clauses`: as text, the unchanged `cost-v1` text followed by the clause section; as JSON, one
/// `cost-clauses-v1` document whose `functions` and `totals` are unchanged.
pub fn render(a: std.mem.Allocator, report: cost.Report, clauses: Report, how: Rendering) std.mem.Allocator.Error![]const u8 {
    const asserts = if (how.asserts) clauses.asserts else &.{};
    if (how.json) {
        const document: Document = .{ .functions = report.functions, .totals = report.totals, .clause_totals = clauses.totals, .clauses = clauses.clauses, .asserts = asserts };
        return std.fmt.allocPrint(a, "{s}\n", .{try std.json.Stringify.valueAlloc(a, document, .{})});
    }
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, try cost.render(a, report, false));
    try out.appendSlice(a, "\ncost-clauses-v1 (contract clauses after Core passes; proved: cannot fail, refuted: fails whenever reached, kept: checked at run time)\n");
    try totalsLine(a, &out, clauses.totals, "");
    for (clauses.clauses) |row| try clauseLine(a, &out, row);
    for (asserts) |row| try clauseLine(a, &out, row);
    return out.toOwnedSlice(a);
}

fn totalsLine(a: std.mem.Allocator, out: *std.ArrayList(u8), t: Totals, prefix: []const u8) std.mem.Allocator.Error!void {
    const c = t.clauses;
    try out.print(a, "{s}clauses {d}: {d} proved, {d} refuted, {d} kept; ", .{ prefix, c.proved + c.refuted + c.kept, c.proved, c.refuted, c.kept });
    try out.print(a, "copies: own {d} proved / {d} refuted / {d} kept, inlined {d} / {d} / {d}; ", .{ t.own.proved, t.own.refuted, t.own.kept, t.inlined.proved, t.inlined.refuted, t.inlined.kept });
    try out.print(a, "asserts: {d} proved / {d} refuted / {d} kept", .{ t.asserts.proved, t.asserts.refuted, t.asserts.kept });
    const unused = t.own.unused + t.inlined.unused + t.asserts.unused;
    if (unused != 0) try out.print(a, "; {d} unused copies in functions nothing calls", .{unused});
    const sites = t.call_sites;
    if (sites.proved + sites.refuted + sites.kept != 0) try out.print(a, "; requires at call sites: {d} proved / {d} refuted / {d} kept", .{ sites.proved, sites.refuted, sites.kept });
    try out.append(a, '\n');
}

fn clauseLine(a: std.mem.Allocator, out: *std.ArrayList(u8), row: Clause) std.mem.Allocator.Error!void {
    try out.print(a, "{s}:{d}:{d}  ", .{ row.at.path, row.at.line, row.at.column });
    if (row.kind == .assert) {
        try out.print(a, "assert  `{s}`", .{row.name.text});
    } else try out.print(a, "{s} {d}  {s}  `{s}`", .{ @tagName(row.kind), row.name.ordinal, row.name.subject, row.name.text });
    const own = row.copies.own;
    const inlined = row.copies.inlined;
    try out.print(a, "  {s}  own {d}/{d}/{d}  inlined {d}/{d}/{d}", .{ @tagName(row.status), own.proved, own.refuted, own.kept, inlined.proved, inlined.refuted, inlined.kept });
    if (own.unused + inlined.unused != 0) try out.print(a, "  unused {d}", .{own.unused + inlined.unused});
    if (row.kind == .requires) try out.print(a, "  call sites {d}/{d}/{d}", .{ row.sites.proved, row.sites.refuted, row.sites.kept });
    if (row.refuted) |witness| try refutedNote(a, out, witness);
    try out.append(a, '\n');
}

fn refutedNote(a: std.mem.Allocator, out: *std.ArrayList(u8), witness: Witness) std.mem.Allocator.Error!void {
    try out.print(a, "  fails whenever this program reaches it (in {s}", .{witness.function});
    if (witness.call) |call| try out.print(a, ", inlined at {s}:{d}:{d}", .{ call.path, call.line, call.column });
    try out.append(a, ')');
}

/// The `--stats` lines: the totals, then one line per refuted clause. A program with no clause and no `assert` prints
/// nothing, so its `--stats` output is what it was before the report.
pub fn stats(a: std.mem.Allocator, out: *std.ArrayList(u8), report: Report) std.mem.Allocator.Error!void {
    if (!report.totals.any()) return;
    try totalsLine(a, out, report.totals, "selka-core: ");
    for (report.clauses) |row| if (row.status == .refuted) {
        try out.print(a, "selka-core: refuted: {s}:{d}:{d} {s} {s} `{s}`", .{ row.at.path, row.at.line, row.at.column, row.name.subject, @tagName(row.kind), row.name.text });
        try refutedNote(a, out, row.refuted.?);
        try out.append(a, '\n');
    };
}
