//! Reads `ownership-certificate-v2` text back into the form the validator checks
//! (docs/design/ownership-certificates.md §4.1).
//!
//! The text is what the exporter prints and what the Lean checker reads, so reading it here lets a test state a
//! certificate in the format itself, lets a printed file be checked again, and shows that print and parse agree.
const std = @import("std");
const ir = @import("ir.zig");
const ops = @import("ownership_ops.zig");
const form = @import("ownership_function.zig");

/// Why a line could not be read.
pub const Error = error{ Malformed, OutOfMemory };

/// Where and why the text was malformed.
pub const Problem = struct { line: usize = 0, reason: []const u8 = "" };

/// The format line every certificate file starts with.
const format_line = "ownership-certificate-v2";

/// The functions of a certificate text, in the order it lists them. The text may be bare functions (the validator's
/// fixtures are); a header or class line in it is skipped. Everything else is read as `parseFile` reads it.
pub fn parse(a: std.mem.Allocator, text: []const u8, problem: *Problem) Error![]const form.Function {
    return read(a, text, problem, false);
}

/// The functions of a certificate file, in the order the file lists them, read the way the checker's reader
/// (`proofs/ownership/Parse.lean`) reads it: the first line is the format line, `class OP CLASS` lines give the class
/// table and may not appear inside a function, and every instruction names an operation of that table.
pub fn parseFile(a: std.mem.Allocator, text: []const u8, problem: *Problem) Error![]const form.Function {
    return read(a, text, problem, true);
}

fn read(a: std.mem.Allocator, text: []const u8, problem: *Problem, file: bool) Error![]const form.Function {
    var reader: Reader = .{ .a = a, .problem = problem, .file = file };
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        reader.line += 1;
        if (file and reader.line == 1) {
            if (!std.mem.eql(u8, line, format_line)) {
                if (std.mem.eql(u8, line, "ownership-certificate-v1")) return reader.fail("format ownership-certificate-v1, which has no views extra: this reader reads ownership-certificate-v2 only");
                return reader.fail(if (std.mem.startsWith(u8, line, "ownership-certificate-")) "an unsupported format version" else "not an ownership certificate file");
            }
            continue;
        }
        if (line.len == 0) continue;
        try reader.take(line);
    }
    if (reader.open) return reader.fail("the file ends inside a function");
    return reader.functions.items;
}

const Reader = struct {
    a: std.mem.Allocator,
    problem: *Problem,
    line: usize = 0,
    functions: std.ArrayList(form.Function) = .empty,
    open: bool = false,
    name: []const u8 = "",
    result: form.ResultKind = .scalar,
    from: []const u32 = &.{},
    unchecked: ?form.Reason = null,
    params: std.ArrayList(form.Param) = .empty,
    callees: std.ArrayList(form.Callee) = .empty,
    pre: std.ArrayList(form.Inst) = .empty,
    blocks: std.ArrayList(form.Block) = .empty,
    // The block being read.
    in_pre: bool = true,
    id: u32 = 0,
    preds: []const u32 = &.{},
    phis: std.ArrayList(form.Phi) = .empty,
    insts: std.ArrayList(form.Inst) = .empty,
    abandons: std.ArrayList(form.Abandon) = .empty,
    /// The values the function defines so far: a value is defined once (§4.1).
    defined: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Reading a whole file: the format line, the class table and the table's operations are checked.
    file: bool = false,
    /// The class table of the file, by operation name.
    classes: std.StringHashMapUnmanaged(void) = .empty,
    /// A block `bN` has been read in this function (no `param`, `callee` or pseudo-block may follow).
    seen_block: bool = false,
    /// A block `bN` is open, and whether its terminator has been read (nothing may follow that).
    open_block: bool = false,
    terminated: bool = false,
    /// The id of the last block read: ids ascend.
    last_block: ?u32 = null,

    fn fail(self: *Reader, reason: []const u8) Error {
        self.problem.* = .{ .line = self.line, .reason = reason };
        return error.Malformed;
    }

    /// Where a line must carry a keyword.
    const Mark = struct { at: usize, word: []const u8 };

    /// Whether each of `marks` finds its keyword in `w`; the caller has checked that `w` is long enough.
    fn marked(w: []const []const u8, marks: []const Mark) bool {
        for (marks) |mark| if (!std.mem.eql(u8, w[mark.at], mark.word)) return false;
        return true;
    }

    fn take(self: *Reader, line: []const u8) Error!void {
        var words: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |word| try words.append(self.a, word);
        const w = words.items;
        if (!self.file and (std.mem.eql(u8, w[0], format_line) or std.mem.eql(u8, w[0], "class"))) return;
        if (std.mem.eql(u8, w[0], "class")) return self.classLine(w);
        if (std.mem.eql(u8, w[0], "function")) return self.function(w);
        if (!self.open) return self.fail("a line outside a function");
        if (std.mem.eql(u8, w[0], "param")) return self.param(w);
        if (std.mem.eql(u8, w[0], "callee")) return self.callee(w);
        if (std.mem.eql(u8, w[0], "block")) return self.blockHeader(w);
        if (std.mem.eql(u8, w[0], "abandon")) return self.abandon(w);
        if (std.mem.eql(u8, w[0], "phi")) return self.phi(w);
        if (std.mem.eql(u8, w[0], "inst")) return self.inst(w);
        if (std.mem.eql(u8, w[0], "term")) return self.term(w);
        if (std.mem.eql(u8, w[0], "end")) return self.end(w);
        return self.fail("an unknown line");
    }

    /// `class OP CLASS`: one line of the class table; the table is read before any function and not inside one.
    fn classLine(self: *Reader, w: []const []const u8) Error!void {
        if (self.open) return self.fail("class line inside a function");
        if (w.len != 3) return self.fail("a malformed class line");
        if (classOf(w[2]) == null) return self.fail("an unknown class");
        try self.classes.put(self.a, w[1], {});
    }

    fn function(self: *Reader, w: []const []const u8) Error!void {
        if (self.open) return self.fail("a function starts before the last one ends");
        if (w.len != 8 or !marked(w, &.{ .{ .at = 2, .word = "result" }, .{ .at = 4, .word = "from" }, .{ .at = 6, .word = "unchecked" } })) return self.fail("a malformed function line");
        self.name = try self.unescape(w[1]);
        self.result = std.meta.stringToEnum(form.ResultKind, w[3]) orelse return self.fail("an unknown result kind");
        self.from = try self.numbers(w[5], "");
        self.unchecked = if (std.mem.eql(u8, w[7], "-")) null else if (std.mem.eql(u8, w[7], "task-group")) .task_group else return self.fail("an unknown unchecked reason");
        self.params = .empty;
        self.callees = .empty;
        self.pre = .empty;
        self.blocks = .empty;
        self.defined = .empty;
        self.in_pre = true;
        self.seen_block = false;
        self.open_block = false;
        self.terminated = false;
        self.last_block = null;
        self.open = true;
    }

    /// Record the definition of `value`; a second definition of one value is malformed input, not a verdict.
    fn define(self: *Reader, value_number: u32) Error!void {
        const entry = try self.defined.getOrPut(self.a, value_number);
        if (entry.found_existing) return self.fail("a value is defined twice");
    }

    fn unescape(self: *Reader, text: []const u8) Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            if (text[i] == '\\' and i + 3 < text.len + 0 and text[i + 1] == 'x') {
                const byte = std.fmt.parseInt(u8, text[i + 2 .. i + 4], 16) catch return self.fail("a bad escape in a name");
                try out.append(self.a, byte);
                i += 3;
            } else try out.append(self.a, text[i]);
        }
        return out.items;
    }

    /// A decimal number: digits only, as the checker's reader takes it (no sign, no separators).
    fn decimal(self: *Reader, word: []const u8, reason: []const u8) Error!u32 {
        if (word.len == 0) return self.fail(reason);
        for (word) |c| if (c < '0' or c > '9') return self.fail(reason);
        return std.fmt.parseInt(u32, word, 10) catch self.fail(reason);
    }

    fn value(self: *Reader, word: []const u8) Error!u32 {
        if (word.len < 2 or word[0] != '%') return self.fail("expected a value like %12");
        return self.decimal(word[1..], "a bad value number");
    }

    fn block(self: *Reader, word: []const u8) Error!u32 {
        if (word.len < 2 or word[0] != 'b') return self.fail("expected a block like b3");
        return self.decimal(word[1..], "a bad block number");
    }

    /// A comma list of numbers, each after `prefix`; `-` is empty.
    fn numbers(self: *Reader, word: []const u8, prefix: []const u8) Error![]const u32 {
        if (std.mem.eql(u8, word, "-")) return &.{};
        var out: std.ArrayList(u32) = .empty;
        var it = std.mem.splitScalar(u8, word, ',');
        while (it.next()) |item| {
            if (!std.mem.startsWith(u8, item, prefix)) return self.fail("a bad list item");
            try out.append(self.a, try self.decimal(item[prefix.len..], "a bad list number"));
        }
        return out.items;
    }

    fn parents(self: *Reader, word: []const u8) Error![]const form.Parent {
        if (std.mem.eql(u8, word, "-")) return &.{};
        var out: std.ArrayList(form.Parent) = .empty;
        var it = std.mem.splitScalar(u8, word, ',');
        while (it.next()) |item| {
            if (item.len < 2) return self.fail("a bad parent");
            const n = try self.decimal(item[1..], "a bad parent number");
            try out.append(self.a, switch (item[0]) {
                '%' => .{ .value = n },
                '^' => .{ .caller = n },
                else => return self.fail("a bad parent"),
            });
        }
        return out.items;
    }

    fn state(self: *Reader, word: []const u8) Error!form.State {
        return std.meta.stringToEnum(form.State, word) orelse self.fail("an unknown state");
    }

    fn param(self: *Reader, w: []const []const u8) Error!void {
        if (w.len != 4) return self.fail("a malformed param line");
        if (self.seen_block) return self.fail("param line after a block");
        if (try self.decimal(w[1], "expected a number") != self.params.items.len) return self.fail("parameters must be numbered 0, 1, ... in order");
        try self.params.append(self.a, .{ .value = try self.value(w[2]), .state = try self.state(w[3]) });
    }

    /// `callee N NAME KIND PARAMS RESULT FROM` (design §9, entry 57): a line of the function's callee table.
    fn callee(self: *Reader, w: []const []const u8) Error!void {
        if (w.len != 7) return self.fail("a malformed callee line");
        if (self.seen_block) return self.fail("callee line after a block");
        var params: std.ArrayList(form.ParamMode) = .empty;
        if (!std.mem.eql(u8, w[4], "-")) {
            var it = std.mem.splitScalar(u8, w[4], ',');
            while (it.next()) |word| try params.append(self.a, parseMode(word) orelse return self.fail("an unknown parameter mode"));
        }
        try self.callees.append(self.a, .{
            .id = try self.decimal(w[1], "a bad callee number"),
            .name = if (std.mem.eql(u8, w[2], "-")) "" else try self.unescape(w[2]),
            .kind = std.meta.stringToEnum(form.CalleeKind, w[3]) orelse return self.fail("an unknown callee kind"),
            .params = params.items,
            .result = std.meta.stringToEnum(form.ResultKind, w[5]) orelse return self.fail("an unknown callee result"),
            .from = try self.numbers(w[6], ""),
        });
    }

    fn blockHeader(self: *Reader, w: []const []const u8) Error!void {
        if (w.len != 4 or !std.mem.eql(u8, w[2], "preds")) return self.fail("a malformed block line");
        if (std.mem.eql(u8, w[1], "b-")) {
            // The pseudo-block holds the parameters' lines and the constants; only `block b- preds -` names it.
            if (!std.mem.eql(u8, w[3], "-")) return self.fail("expected a block bN");
            if (self.seen_block) return self.fail("pseudo-block b- must come before b0");
            self.in_pre = true;
            return;
        }
        try self.closeBlock();
        const id = try self.block(w[1]);
        if (self.last_block) |previous| {
            if (id <= previous) return self.fail("blocks must be numbered in increasing order");
        }
        self.in_pre = false;
        self.seen_block = true;
        self.open_block = true;
        self.terminated = false;
        self.last_block = id;
        self.id = id;
        self.preds = try self.numbersOfBlocks(w[3]);
        self.phis = .empty;
        self.insts = .empty;
        self.abandons = .empty;
    }

    /// The block being read ends here: it needs its terminator.
    fn closeBlock(self: *Reader) Error!void {
        if (self.open_block and !self.terminated) return self.fail("a block has no term line");
        self.open_block = false;
    }

    /// Whether a line may still belong to the open block: nothing follows its terminator.
    fn beforeTerminator(self: *Reader) Error!void {
        if (self.terminated) return self.fail("a line after the terminator of its block");
    }

    /// `abandon bP %V,%V,…`: the owners the edge from block P into this block abandons.
    fn abandon(self: *Reader, w: []const []const u8) Error!void {
        if (self.in_pre) return self.fail("an abandon line outside a block");
        try self.beforeTerminator();
        if (w.len != 3) return self.fail("a malformed abandon line");
        try self.abandons.append(self.a, .{ .from = try self.block(w[1]), .values = try self.numbers(w[2], "%") });
    }

    fn numbersOfBlocks(self: *Reader, word: []const u8) Error![]const u32 {
        return self.numbers(word, "b");
    }

    fn phi(self: *Reader, w: []const []const u8) Error!void {
        if (self.in_pre) return self.fail("a phi line outside a block");
        try self.beforeTerminator();
        if (self.insts.items.len != 0) return self.fail("a phi line after an inst line");
        if (w.len != 7 or !marked(w, &.{ .{ .at = 3, .word = "parents" }, .{ .at = 5, .word = "edges" } })) return self.fail("a malformed phi line");
        var edges: std.ArrayList(form.Edge) = .empty;
        var it = std.mem.splitScalar(u8, w[6], ',');
        while (it.next()) |item| {
            const colon = std.mem.indexOfScalar(u8, item, ':') orelse return self.fail("a phi edge needs bN:%V");
            try edges.append(self.a, .{ .block = try self.block(item[0..colon]), .value = try self.value(item[colon + 1 ..]) });
        }
        const defined = try self.value(w[1]);
        try self.define(defined);
        try self.phis.append(self.a, .{ .value = defined, .result = .{ .state = try self.state(w[2]), .parents = try self.parents(w[4]) }, .edges = edges.items });
    }

    fn inst(self: *Reader, w: []const []const u8) Error!void {
        if (w.len < 11 or !marked(w, &.{ .{ .at = 4, .word = "reads" }, .{ .at = 6, .word = "consumes" }, .{ .at = 8, .word = "state" }, .{ .at = 10, .word = "parents" } })) return self.fail("a malformed inst line");
        if (w.len < 12) return self.fail("an inst line needs its parents");
        if (!self.in_pre) try self.beforeTerminator();
        if (self.file and !self.classes.contains(w[2])) return self.fail("an operation that is not in the class table");
        const op = std.meta.stringToEnum(ir.Op, w[2]) orelse return self.fail("an unknown operation");
        var line: form.Inst = .{
            .value = if (std.mem.eql(u8, w[1], "-")) null else try self.value(w[1]),
            .op = op,
            .class = classOf(w[3]) orelse return self.fail("an unknown class"),
            .reads = try self.numbers(w[5], "%"),
            .consumes = try self.numbers(w[7], "%"),
            .result = .{ .state = try self.state(w[9]), .parents = try self.parents(w[11]) },
        };
        // A line that names no value has none to give a state: the checker's reader refuses it as well.
        if (line.value == null and line.result.state != .none) return self.fail("inst - must have state none");
        var seen: [extra_keys.len]bool = @splat(false);
        var at: usize = 12;
        while (at < w.len) : (at += 2) {
            const key = w[at];
            // `noloans` is a flag: it stands alone.
            if (std.mem.eql(u8, key, "noloans")) {
                if (line.extras.loans.noloans) return self.fail("noloans twice");
                line.extras.loans.noloans = true;
                at -= 1;
                continue;
            }
            if (at + 1 >= w.len) return self.fail("an extra without a value");
            const word = w[at + 1];
            // An extra is given once; the checker's reader refuses a second `slot`, `callee`, `lent` or `imm`.
            if (extraIndex(key)) |which| {
                if (seen[which]) return self.fail("an extra twice");
                seen[which] = true;
            }
            try self.extra(&line, key, word);
        }
        if (line.value) |defined| try self.define(defined);
        if (self.in_pre) try self.pre.append(self.a, line) else try self.insts.append(self.a, line);
    }

    /// One `KEY VALUE` extra of an inst line; each key is given once (the caller checks), so no value is set twice.
    fn extra(self: *Reader, line: *form.Inst, key: []const u8, word: []const u8) Error!void {
        if (std.mem.eql(u8, key, "slot")) {
            line.extras.slot = word;
        } else if (std.mem.eql(u8, key, "released")) {
            line.extras.released = try self.partsOf(word);
        } else if (std.mem.eql(u8, key, "taken")) {
            line.extras.taken = try self.partsOf(word);
        } else if (std.mem.eql(u8, key, "slots")) {
            var keys: std.ArrayList([]const u8) = .empty;
            if (!std.mem.eql(u8, word, "-")) {
                var it = std.mem.splitScalar(u8, word, ',');
                while (it.next()) |item| try keys.append(self.a, item);
            }
            line.extras.slots = keys.items;
        } else if (std.mem.eql(u8, key, "from")) {
            line.extras.call.from = try self.numbers(word, "%");
        } else if (std.mem.eql(u8, key, "callee")) {
            line.extras.call.callee = try self.decimal(word, "a bad callee number");
        } else if (std.mem.eql(u8, key, "lent")) {
            line.extras.loans.lent = try self.value(word);
        } else if (std.mem.eql(u8, key, "views")) {
            line.extras.loans.views = try self.numbers(word, "%");
        } else if (std.mem.eql(u8, key, "imm")) {
            line.extras.imm = decimal64(word) orelse return self.fail("imm needs a decimal u64");
        } else return self.fail("an unknown extra");
    }

    fn partsOf(self: *Reader, word: []const u8) Error!form.Parts {
        var parts: form.Parts = .{};
        if (std.mem.eql(u8, word, "-")) return parts;
        var it = std.mem.splitScalar(u8, word, ',');
        while (it.next()) |item| {
            if (std.mem.eql(u8, item, "old")) {
                parts.old = true;
            } else if (std.mem.eql(u8, item, "key")) {
                parts.key = true;
            } else if (std.mem.eql(u8, item, "value")) {
                parts.value = true;
            } else return self.fail("an unknown part");
        }
        return parts;
    }

    fn term(self: *Reader, w: []const []const u8) Error!void {
        if (self.in_pre) return self.fail("a terminator in the pseudo-block");
        if (self.terminated) return self.fail("a block has two term lines");
        if (w.len < 2) return self.fail("a malformed terminator");
        const t: form.Term = if (std.mem.eql(u8, w[1], "jump") and w.len == 3)
            .{ .jump = try self.block(w[2]) }
        else if (std.mem.eql(u8, w[1], "branch") and w.len == 5)
            .{ .branch = .{ .condition = try self.value(w[2]), .then = try self.block(w[3]), .otherwise = try self.block(w[4]) } }
        else if (std.mem.eql(u8, w[1], "ret") and w.len == 3)
            .{ .ret = if (std.mem.eql(u8, w[2], "-")) null else try self.value(w[2]) }
        else if (std.mem.eql(u8, w[1], "unreachable") and w.len == 2)
            .unreachable_path
        else
            return self.fail("a malformed terminator");
        try self.blocks.append(self.a, .{ .id = self.id, .preds = self.preds, .abandons = self.abandons.items, .phis = self.phis.items, .insts = self.insts.items, .term = t });
        self.terminated = true;
    }

    fn end(self: *Reader, w: []const []const u8) Error!void {
        if (w.len != 1) return self.fail("an unknown or malformed line");
        try self.closeBlock();
        // Every edge leads to a block the function defines.
        for (self.blocks.items) |done| {
            const targets: [2]?u32 = switch (done.term) {
                .jump => |target| .{ target, null },
                .branch => |branch| .{ branch.then, branch.otherwise },
                .ret, .unreachable_path => .{ null, null },
            };
            for (targets) |target| if (target) |id| {
                if (!self.defines(id)) return self.fail("an edge targets a block the file does not define");
            };
        }
        try self.functions.append(self.a, .{
            .name = self.name,
            .returns = .{ .kind = self.result, .from = self.from },
            .unchecked = self.unchecked,
            .params = self.params.items,
            .callees = self.callees.items,
            .pre = self.pre.items,
            .blocks = self.blocks.items,
        });
        self.open = false;
    }

    /// Whether the function being read has a block `id`.
    fn defines(self: *Reader, id: u32) bool {
        for (self.blocks.items) |known| if (known.id == id) return true;
        return false;
    }
};

fn decimal64(word: []const u8) ?u64 {
    if (word.len == 0) return null;
    for (word) |c| if (c < '0' or c > '9') return null;
    return std.fmt.parseInt(u64, word, 10) catch null;
}

/// The extras of an inst line that take a value (the flag `noloans` stands alone).
const extra_keys = [_][]const u8{ "slot", "released", "taken", "slots", "from", "callee", "lent", "imm", "views" };

/// Which of `extra_keys` `word` is.
fn extraIndex(word: []const u8) ?usize {
    for (extra_keys, 0..) |key, which| if (std.mem.eql(u8, word, key)) return which;
    return null;
}

fn parseMode(word: []const u8) ?form.ParamMode {
    for (std.enums.values(form.ParamMode)) |mode| if (std.mem.eql(u8, mode.token(), word)) return mode;
    return null;
}

fn classOf(word: []const u8) ?ops.Class {
    for (std.enums.values(ops.Class)) |class| if (std.mem.eql(u8, class.token(), word)) return class;
    return null;
}

test "a function printed in the format reads back into the same lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text =
        \\function demo result owned from - unchecked -
        \\param 0 %0 owned
        \\block b- preds -
        \\inst %0 param Parameter reads - consumes - state owned parents -
        \\block b0 preds -
        \\inst %1 record_get Project reads %0 consumes - state owned parents - slot f0
        \\term ret %0
        \\end
        \\
    ;
    var problem: Problem = .{};
    const functions = try parse(arena.allocator(), text, &problem);
    try std.testing.expectEqual(@as(usize, 1), functions.len);
    try std.testing.expectEqualStrings("demo", functions[0].name);
    try std.testing.expectEqual(@as(usize, 1), functions[0].blocks[0].insts.len);
    try std.testing.expectEqualStrings("f0", functions[0].blocks[0].insts[0].extras.slot.?);
}

test "a value defined twice is malformed input, by an instruction or by a phi" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var problem: Problem = .{};
    const head = "function f result scalar from - unchecked -\nblock b- preds -\nblock b0 preds -\n";
    const twice = "inst %1 iconst Constant reads - consumes - state scalar parents - imm 1\n";
    try std.testing.expectError(error.Malformed, parse(arena.allocator(), head ++ twice ++ twice ++ "term ret %1\nend\n", &problem));
    try std.testing.expectEqualStrings("a value is defined twice", problem.reason);
    try std.testing.expectEqual(@as(usize, 5), problem.line);
    const phi = head ++ twice ++ "phi %1 scalar parents - edges b0:%1\nterm ret %1\nend\n";
    try std.testing.expectError(error.Malformed, parse(arena.allocator(), phi, &problem));
    const apart = "function g result scalar from - unchecked -\nblock b0 preds -\n" ++ twice ++ "term ret %1\nend\n";
    try std.testing.expectEqual(@as(usize, 2), (try parse(arena.allocator(), "ownership-certificate-v2\n" ++ head ++ twice ++ "term ret %1\nend\n" ++ apart, &problem)).len);
}

test "a malformed line names its number" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var problem: Problem = .{};
    try std.testing.expectError(error.Malformed, parse(arena.allocator(), "function f result owned from - unchecked -\nparam 0 %0\nend\n", &problem));
    try std.testing.expectEqual(@as(usize, 2), problem.line);
}

test "a lend names the group it is lent to" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const head = "function f result scalar from - unchecked -\nblock b- preds -\nblock b0 preds -\n";
    var problem: Problem = .{};
    const good = head ++ "inst %3 box_make Construct reads %2,%1 consumes - state owned parents - lent %1\nterm ret -\nend\n";
    const functions = try parse(arena.allocator(), good, &problem);
    try std.testing.expectEqual(@as(?u32, 1), functions[0].blocks[0].insts[0].extras.loans.lent);
    // The shape of a lend is the validator's to judge (J1), as the Lean checker does: the reader only reads the extra.
    const swapped = head ++ "inst %3 box_make Construct reads %1,%2 consumes - state owned parents - lent %1\nterm ret -\nend\n";
    try std.testing.expectEqual(@as(usize, 1), (try parse(arena.allocator(), swapped, &problem)).len);
    const twice = head ++ "inst %3 box_make Construct reads %2,%1 consumes - state owned parents - lent %1 lent %1\nterm ret -\nend\n";
    try std.testing.expectError(error.Malformed, parse(arena.allocator(), twice, &problem));
}

test "a constructor names the views it holds, once, and a file of the format before views is refused by name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const head = "function f result scalar from - unchecked -\nblock b- preds -\nblock b0 preds -\n";
    var problem: Problem = .{};
    const good = head ++ "inst %3 record_make Construct reads %2,%1 consumes - state owned parents %2 views %2\nterm ret -\nend\n";
    const functions = try parse(arena.allocator(), good, &problem);
    try std.testing.expectEqualSlices(u32, &.{2}, functions[0].blocks[0].insts[0].extras.loans.views);
    const twice = head ++ "inst %3 record_make Construct reads %2,%1 consumes - state owned parents %2 views %2 views -\nterm ret -\nend\n";
    try std.testing.expectError(error.Malformed, parse(arena.allocator(), twice, &problem));
    // Format v1 has no `views` extra: an owned constructor would read as holding no view, so a v1 file is refused, never read.
    try std.testing.expectError(error.Malformed, parseFile(arena.allocator(), "ownership-certificate-v1\nclass record_make Construct\n" ++ good, &problem));
    try std.testing.expect(std.mem.indexOf(u8, problem.reason, "ownership-certificate-v1") != null);
    try std.testing.expectEqual(@as(usize, 1), (try parseFile(arena.allocator(), "ownership-certificate-v2\nclass record_make Construct\n" ++ good, &problem)).len);
}

test "a file written before C6 may still mark a function unchecked with the task-group reason" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var problem: Problem = .{};
    const functions = try parse(arena.allocator(), "function old result owned from - unchecked task-group\nblock b- preds -\nblock b0 preds -\nterm ret -\nend\n", &problem);
    try std.testing.expectEqual(@as(?form.Reason, .task_group), functions[0].unchecked);
}

test "noloans is a flag that stands alone, in any place among the extras" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const head = "function f result scalar from - unchecked -\nblock b- preds -\nblock b0 preds -\n";
    var problem: Problem = .{};
    const last = head ++ "inst %3 record_take Take reads - consumes %2 state owned parents - noloans\nterm ret -\nend\n";
    const before = head ++ "inst %3 box_make Construct reads %2,%1 consumes - state owned parents - noloans lent %1\nterm ret -\nend\n";
    const twice = head ++ "inst %3 record_take Take reads - consumes %2 state owned parents - noloans noloans\nterm ret -\nend\n";
    try std.testing.expect((try parse(arena.allocator(), last, &problem))[0].blocks[0].insts[0].extras.loans.noloans);
    const mixed = (try parse(arena.allocator(), before, &problem))[0].blocks[0].insts[0].extras.loans;
    try std.testing.expect(mixed.noloans);
    try std.testing.expectEqual(@as(?u32, 1), mixed.lent);
    try std.testing.expectError(error.Malformed, parse(arena.allocator(), twice, &problem));
}

test "an abandon line names a predecessor and the owners its edge abandons" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var problem: Problem = .{};
    const text = "function f result scalar from - unchecked -\nblock b- preds -\nblock b0 preds -\nterm jump b1\nblock b1 preds b0\nabandon b0 %2,%5\nterm unreachable\nend\n";
    const functions = try parse(arena.allocator(), text, &problem);
    const gone = functions[0].blocks[1].abandons;
    try std.testing.expectEqual(@as(usize, 1), gone.len);
    try std.testing.expectEqual(@as(u32, 0), gone[0].from);
    try std.testing.expectEqualSlices(u32, &.{ 2, 5 }, gone[0].values);
    const outside = "function f result scalar from - unchecked -\nblock b- preds -\nabandon b0 %2\nblock b0 preds -\nterm unreachable\nend\n";
    try std.testing.expectError(error.Malformed, parse(arena.allocator(), outside, &problem));
    const bare = "function f result scalar from - unchecked -\nblock b0 preds -\nabandon b0\nterm unreachable\nend\n";
    try std.testing.expectError(error.Malformed, parse(arena.allocator(), bare, &problem));
}

test "a callee table line and the callee a call line names are read back" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var problem: Problem = .{};
    const text = "function f result scalar from - unchecked -\ncallee 0 weigh program take,read-scalar,read borrowed 2\ncallee 1 - indirect - scalar -\nblock b- preds -\nblock b0 preds -\n" ++
        "inst %3 call Call reads %1 consumes %2 state scalar parents - from - callee 0\nterm ret -\nend\n";
    const function = (try parse(arena.allocator(), text, &problem))[0];
    try std.testing.expectEqual(@as(usize, 2), function.callees.len);
    try std.testing.expectEqualStrings("weigh", function.callees[0].name);
    try std.testing.expectEqual(form.CalleeKind.program, function.callees[0].kind);
    try std.testing.expectEqualSlices(form.ParamMode, &.{ .take, .read_scalar, .read }, function.callees[0].params);
    try std.testing.expectEqual(form.ResultKind.borrowed, function.callees[0].result);
    try std.testing.expectEqualSlices(u32, &.{2}, function.callees[0].from);
    try std.testing.expectEqualStrings("", function.callees[1].name);
    try std.testing.expectEqual(@as(usize, 0), function.callees[1].params.len);
    try std.testing.expectEqual(@as(?u32, 0), function.blocks[0].insts[0].extras.call.callee);
    const unknown = "function f result scalar from - unchecked -\ncallee 0 weigh program grab scalar -\nblock b- preds -\nblock b0 preds -\nterm ret -\nend\n";
    try std.testing.expectError(error.Malformed, parse(arena.allocator(), unknown, &problem));
    const late = "function f result scalar from - unchecked -\nblock b- preds -\nblock b0 preds -\ncallee 0 weigh program - scalar -\nterm ret -\nend\n";
    try std.testing.expectError(error.Malformed, parse(arena.allocator(), late, &problem));
}
