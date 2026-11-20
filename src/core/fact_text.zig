//! `fact-certificate-v1` text (docs/design/fact-certificates.md §10): the printer of a module's certificate and the reader
//! that takes the text back into the form of `fact_function.zig`. The text is what the exporter prints and what the Lean
//! checker reads; reading it here lets a test state a certificate in the format itself and shows that print and parse agree.
const std = @import("std");
const ir = @import("ir.zig");
const form = @import("fact_function.zig");

const Allocator = std.mem.Allocator;

/// The first line of every file.
pub const header_line = "fact-certificate-v1";

/// Why a line could not be read.
pub const Error = error{ Malformed, OutOfMemory };

/// Where and why the text was malformed.
pub const Problem = struct { line: usize = 0, reason: []const u8 = "" };

// ---- printing ---------------------------------------------------------------------------------------------------------

/// Print `module` as a certificate file.
pub fn write(a: Allocator, out: *std.ArrayList(u8), module: form.Module) Allocator.Error!void {
    try out.appendSlice(a, header_line ++ "\n");
    for (module.functions) |function| try writeFunction(a, out, function);
}

fn writeFunction(a: Allocator, out: *std.ArrayList(u8), function: form.Function) Allocator.Error!void {
    const head = function.header;
    try out.appendSlice(a, "function ");
    try writeName(a, out, head.name);
    try out.print(a, " linkage {s} addr {d} params ", .{ if (head.internal) "internal" else "other", @intFromBool(head.address_taken) });
    try writeTypes(a, out, head.params);
    try out.print(a, " ret {s}\n", .{head.ret.token()});
    for (head.params, 0..) |_, k| {
        try out.print(a, "param {d} ", .{k});
        try writeRange(a, out, if (k < function.boundary.params.len) function.boundary.params[k] else null);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "returns ");
    try writeRange(a, out, function.boundary.returns);
    try out.append(a, '\n');
    try out.appendSlice(a, "block b- reach preds -\n");
    for (function.pre) |inst| try writeInst(a, out, inst);
    for (function.blocks) |block| try writeBlock(a, out, block);
    for (function.aux.loops) |loop| try out.print(a, "loop header b{d} body b{d} latch b{d} exit b{d}\n", .{ loop.header, loop.body, loop.latch, loop.exit });
    for (function.aux.lists) |list| {
        try out.print(a, "list %{d} len ", .{list.value});
        try writeRange(a, out, list.len);
        try out.appendSlice(a, " elems ");
        try writeRange(a, out, list.elems);
        try out.appendSlice(a, " length ");
        if (list.length) |length| try out.print(a, "%{d}", .{length}) else try out.append(a, '-');
        try out.print(a, " pattern {d}\n", .{@intFromBool(list.pattern)});
    }
    for (function.aux.bounds) |bound| try out.print(a, "bound %{d} %{d} {s}\n", .{ bound.value, bound.list, if (bound.strict) "strict" else "loose" });
    for (function.aux.sites) |site| {
        try out.print(a, "site %{d}", .{site.value});
        for (site.parts) |part| {
            try out.append(a, ' ');
            if (part) |known| try out.print(a, "{d}:{d}", .{ known.lo, known.hi }) else try out.append(a, '-');
        }
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "end\n");
}

/// A function name is one token: a byte at or below `0x20`, `0x7f` or `\\` is written `\\xHH`.
pub fn writeName(a: Allocator, out: *std.ArrayList(u8), name: []const u8) Allocator.Error!void {
    for (name) |byte| {
        if (byte <= 0x20 or byte == 0x7f or byte == '\\') try out.print(a, "\\x{x:0>2}", .{byte}) else try out.append(a, byte);
    }
}

fn writeTypes(a: Allocator, out: *std.ArrayList(u8), types: []const form.Type) Allocator.Error!void {
    if (types.len == 0) return out.append(a, '-');
    for (types, 0..) |ty, k| {
        if (k != 0) try out.append(a, ',');
        try out.appendSlice(a, ty.token());
    }
}

fn writeRange(a: Allocator, out: *std.ArrayList(u8), range: ?form.Interval) Allocator.Error!void {
    if (range) |known| try out.print(a, "{d} {d}", .{ known.lo, known.hi }) else try out.append(a, '-');
}

fn writeValues(a: Allocator, out: *std.ArrayList(u8), values: []const u32) Allocator.Error!void {
    if (values.len == 0) return out.append(a, '-');
    for (values, 0..) |value, k| {
        if (k != 0) try out.append(a, ',');
        if (value == std.math.maxInt(u32)) try out.append(a, '-') else try out.print(a, "%{d}", .{value});
    }
}

fn writeInst(a: Allocator, out: *std.ArrayList(u8), inst: form.Inst) Allocator.Error!void {
    try out.print(a, "inst %{d} {s} {s} {s} a ", .{ inst.value, @tagName(inst.op), inst.ty.token(), @tagName(inst.check) });
    if (inst.operands.a) |first| {
        try out.print(a, "{c}{d}", .{ if (inst.op == .call) @as(u8, '#') else '%', first });
    } else try out.append(a, '-');
    try out.appendSlice(a, " b ");
    if (inst.operands.b) |second| try out.print(a, "%{d}", .{second}) else try out.append(a, '-');
    try out.appendSlice(a, " x ");
    try writeValues(a, out, inst.operands.x);
    try out.print(a, " imm {d} aux {d} range ", .{ inst.immediates.imm, inst.immediates.aux });
    try writeRange(a, out, inst.range);
    try out.append(a, '\n');
}

fn writeBlock(a: Allocator, out: *std.ArrayList(u8), block: form.Block) Allocator.Error!void {
    try out.print(a, "block b{d} {s} preds ", .{ block.id, if (block.dead) "dead" else "reach" });
    if (block.preds.len == 0) try out.append(a, '-');
    for (block.preds, 0..) |pred, k| {
        if (k != 0) try out.append(a, ',');
        try out.print(a, "b{d}", .{pred});
    }
    try out.append(a, '\n');
    for (block.phis) |phi| {
        try out.print(a, "phi %{d} {s} edges ", .{ phi.value, phi.ty.token() });
        for (phi.edges, 0..) |edge, k| {
            if (k != 0) try out.append(a, ',');
            try out.print(a, "b{d}:%{d}", .{ edge.block, edge.value });
        }
        try out.appendSlice(a, " range ");
        try writeRange(a, out, phi.range);
        try out.append(a, '\n');
    }
    for (block.insts) |inst| try writeInst(a, out, inst);
    switch (block.term) {
        .jump => |target| try out.print(a, "term jump b{d}\n", .{target}),
        .branch => |branch| try out.print(a, "term branch %{d} b{d} b{d}\n", .{ branch.condition, branch.then, branch.otherwise }),
        .ret => |value| if (value) |known| try out.print(a, "term ret %{d}\n", .{known}) else try out.appendSlice(a, "term ret -\n"),
        .unreachable_path => try out.appendSlice(a, "term unreachable\n"),
    }
}

// ---- reading ----------------------------------------------------------------------------------------------------------

/// The module a certificate file states.
// twin-drift-ok: the ownership reader and this one read different formats; they share the loop that numbers lines and nothing else
pub fn parse(a: Allocator, text: []const u8, problem: *Problem) Error!form.Module {
    var reader: Reader = .{ .a = a, .problem = problem };
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        reader.line += 1;
        if (line.len == 0) continue;
        try reader.take(line);
    }
    if (reader.open) return reader.fail("the file ends inside a function");
    if (!reader.seen_header) return reader.fail("the file does not start with the format line");
    return .{ .functions = reader.functions.items };
}

/// A function being read.
const Draft = struct {
    header: form.Header = undefined,
    params: std.ArrayList(?form.Interval) = .empty,
    returns: ?form.Interval = null,
    pre: std.ArrayList(form.Inst) = .empty,
    blocks: std.ArrayList(form.Block) = .empty,
    loops: std.ArrayList(form.Loop) = .empty,
    lists: std.ArrayList(form.ListFact) = .empty,
    bounds: std.ArrayList(form.Bound) = .empty,
    sites: std.ArrayList(form.Site) = .empty,
};

/// The block being read.
const Current = struct {
    id: u32 = 0,
    dead: bool = false,
    preds: []const u32 = &.{},
    phis: std.ArrayList(form.Phi) = .empty,
    insts: std.ArrayList(form.Inst) = .empty,
};

const Reader = struct {
    a: Allocator,
    problem: *Problem,
    line: usize = 0,
    seen_header: bool = false,
    functions: std.ArrayList(form.Function) = .empty,
    open: bool = false,
    draft: Draft = .{},
    in_pre: bool = true,
    in_block: bool = false,
    current: Current = .{},

    fn fail(self: *Reader, reason: []const u8) Error {
        self.problem.* = .{ .line = self.line, .reason = reason };
        return error.Malformed;
    }

    // twin-drift-ok: the dispatch on the first word names this format's lines, which are not the ownership format's
    fn take(self: *Reader, line: []const u8) Error!void {
        var words: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |word| try words.append(self.a, word);
        const w = words.items;
        if (std.mem.eql(u8, w[0], header_line)) {
            self.seen_header = true;
            return;
        }
        if (std.mem.eql(u8, w[0], "function")) return self.function(w);
        if (!self.open) return self.fail("a line outside a function");
        if (std.mem.eql(u8, w[0], "param")) return self.paramLine(w);
        if (std.mem.eql(u8, w[0], "returns")) return self.returnsLine(w);
        if (std.mem.eql(u8, w[0], "block")) return self.blockLine(w);
        if (std.mem.eql(u8, w[0], "phi")) return self.phi(w);
        if (std.mem.eql(u8, w[0], "inst")) return self.inst(w);
        if (std.mem.eql(u8, w[0], "term")) return self.term(w);
        if (std.mem.eql(u8, w[0], "loop")) return self.loop(w);
        if (std.mem.eql(u8, w[0], "list")) return self.list(w);
        if (std.mem.eql(u8, w[0], "bound")) return self.bound(w);
        if (std.mem.eql(u8, w[0], "site")) return self.site(w);
        if (std.mem.eql(u8, w[0], "end")) return self.end();
        return self.fail("an unknown line");
    }

    fn marked(w: []const []const u8, comptime marks: anytype) bool {
        inline for (marks) |mark| if (!std.mem.eql(u8, w[mark[0]], mark[1])) return false;
        return true;
    }

    fn function(self: *Reader, w: []const []const u8) Error!void {
        if (self.open) return self.fail("a function starts before the last one ends");
        if (w.len != 10 or !marked(w, .{ .{ 2, "linkage" }, .{ 4, "addr" }, .{ 6, "params" }, .{ 8, "ret" } })) return self.fail("a malformed function line");
        self.draft = .{};
        self.draft.header = .{
            .name = try self.unescape(w[1]),
            .internal = if (std.mem.eql(u8, w[3], "internal")) true else if (std.mem.eql(u8, w[3], "other")) false else return self.fail("an unknown linkage"),
            .address_taken = try self.flag(w[5]),
            .params = try self.types(w[7]),
            .ret = form.Type.fromToken(w[9]) orelse return self.fail("an unknown type"),
        };
        self.in_pre = true;
        self.in_block = false;
        self.current = .{};
        self.open = true;
    }

    fn flag(self: *Reader, word: []const u8) Error!bool {
        if (std.mem.eql(u8, word, "1")) return true;
        if (std.mem.eql(u8, word, "0")) return false;
        return self.fail("a flag is 0 or 1");
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

    fn types(self: *Reader, word: []const u8) Error![]const form.Type {
        if (std.mem.eql(u8, word, "-")) return &.{};
        var out: std.ArrayList(form.Type) = .empty;
        var it = std.mem.splitScalar(u8, word, ',');
        while (it.next()) |item| try out.append(self.a, form.Type.fromToken(item) orelse return self.fail("an unknown type"));
        return out.items;
    }

    fn number(self: *Reader, word: []const u8, comptime T: type) Error!T {
        return std.fmt.parseInt(T, word, 10) catch self.fail("a bad number");
    }

    fn value(self: *Reader, word: []const u8) Error!u32 {
        if (word.len < 2 or word[0] != '%') return self.fail("expected a value like %12");
        return self.number(word[1..], u32);
    }

    fn block(self: *Reader, word: []const u8) Error!u32 {
        if (word.len < 2 or word[0] != 'b') return self.fail("expected a block like b3");
        return self.number(word[1..], u32);
    }

    /// `lo hi` starting at `w[at]`, or `-`; returns the interval and how many words it took.
    fn rangeAt(self: *Reader, w: []const []const u8, at: usize) Error!struct { range: ?form.Interval, used: usize } {
        if (at >= w.len) return self.fail("a missing interval");
        if (std.mem.eql(u8, w[at], "-")) return .{ .range = null, .used = 1 };
        if (at + 1 >= w.len) return self.fail("an interval needs two numbers");
        const lo = try self.number(w[at], i128);
        const hi = try self.number(w[at + 1], i128);
        return .{ .range = .{ .lo = lo, .hi = hi }, .used = 2 };
    }

    fn paramLine(self: *Reader, w: []const []const u8) Error!void {
        if (w.len < 3) return self.fail("a malformed param line");
        const k = try self.number(w[1], usize);
        if (k != self.draft.params.items.len) return self.fail("parameters must be numbered 0, 1, … in order");
        const parsed = try self.rangeAt(w, 2);
        if (2 + parsed.used != w.len) return self.fail("a malformed param line");
        try self.draft.params.append(self.a, parsed.range);
    }

    fn returnsLine(self: *Reader, w: []const []const u8) Error!void {
        const parsed = try self.rangeAt(w, 1);
        if (1 + parsed.used != w.len) return self.fail("a malformed returns line");
        self.draft.returns = parsed.range;
    }

    fn closeBlock(self: *Reader, t: form.Term) Error!void {
        try self.draft.blocks.append(self.a, .{ .id = self.current.id, .dead = self.current.dead, .preds = self.current.preds, .phis = self.current.phis.items, .insts = self.current.insts.items, .term = t });
        self.current = .{};
    }

    fn blockLine(self: *Reader, w: []const []const u8) Error!void {
        if (w.len != 5 or !marked(w, .{.{ 3, "preds" }})) return self.fail("a malformed block line");
        if (std.mem.eql(u8, w[1], "b-")) {
            self.in_pre = true;
            return;
        }
        if (self.in_block) return self.fail("a block starts before the last one ends");
        self.in_pre = false;
        self.in_block = true;
        self.current.id = try self.block(w[1]);
        self.current.dead = if (std.mem.eql(u8, w[2], "dead")) true else if (std.mem.eql(u8, w[2], "reach")) false else return self.fail("a block is reach or dead");
        var preds: std.ArrayList(u32) = .empty;
        if (!std.mem.eql(u8, w[4], "-")) {
            var it = std.mem.splitScalar(u8, w[4], ',');
            while (it.next()) |item| try preds.append(self.a, try self.block(item));
        }
        self.current.preds = preds.items;
    }

    fn phi(self: *Reader, w: []const []const u8) Error!void {
        if (self.in_pre or w.len < 7 or !marked(w, .{ .{ 3, "edges" }, .{ 5, "range" } })) return self.fail("a malformed phi line");
        var edges: std.ArrayList(form.Edge) = .empty;
        var it = std.mem.splitScalar(u8, w[4], ',');
        while (it.next()) |item| {
            const colon = std.mem.indexOfScalar(u8, item, ':') orelse return self.fail("a phi edge needs bN:%V");
            try edges.append(self.a, .{ .block = try self.block(item[0..colon]), .value = try self.value(item[colon + 1 ..]) });
        }
        const parsed = try self.rangeAt(w, 6);
        if (6 + parsed.used != w.len) return self.fail("a malformed phi line");
        try self.current.phis.append(self.a, .{ .value = try self.value(w[1]), .ty = form.Type.fromToken(w[2]) orelse return self.fail("an unknown type"), .edges = edges.items, .range = parsed.range });
    }

    fn operand(self: *Reader, word: []const u8) Error!?u32 {
        if (std.mem.eql(u8, word, "-")) return null;
        if (word.len >= 2 and word[0] == '#') {
            const callee = try self.number(word[1..], u32);
            return callee;
        }
        const named = try self.value(word);
        return named;
    }

    fn inst(self: *Reader, w: []const []const u8) Error!void {
        if (w.len < 17 or !marked(w, .{ .{ 5, "a" }, .{ 7, "b" }, .{ 9, "x" }, .{ 11, "imm" }, .{ 13, "aux" }, .{ 15, "range" } })) return self.fail("a malformed inst line");
        const parsed = try self.rangeAt(w, 16);
        if (16 + parsed.used != w.len) return self.fail("a malformed inst line");
        var extra: std.ArrayList(u32) = .empty;
        if (!std.mem.eql(u8, w[10], "-")) {
            var it = std.mem.splitScalar(u8, w[10], ',');
            while (it.next()) |item| try extra.append(self.a, if (std.mem.eql(u8, item, "-")) std.math.maxInt(u32) else try self.value(item));
        }
        const line: form.Inst = .{
            .value = try self.value(w[1]),
            .op = std.meta.stringToEnum(ir.Op, w[2]) orelse return self.fail("an unknown operation"),
            .ty = form.Type.fromToken(w[3]) orelse return self.fail("an unknown type"),
            .check = std.meta.stringToEnum(ir.Check, w[4]) orelse return self.fail("an unknown check"),
            .operands = .{ .a = try self.operand(w[6]), .b = try self.operand(w[8]), .x = extra.items },
            .immediates = .{ .imm = try self.number(w[12], u64), .aux = try self.number(w[14], u64) },
            .range = parsed.range,
        };
        if (self.in_pre) try self.draft.pre.append(self.a, line) else try self.current.insts.append(self.a, line);
    }

    // twin-drift-ok: a terminator ends a block here and is refused in the pseudo-block there; the grammar differs
    fn term(self: *Reader, w: []const []const u8) Error!void {
        if (self.in_pre or !self.in_block) return self.fail("a terminator outside a block");
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
        self.in_block = false;
        try self.closeBlock(t);
    }

    fn loop(self: *Reader, w: []const []const u8) Error!void {
        if (w.len != 9 or !marked(w, .{ .{ 1, "header" }, .{ 3, "body" }, .{ 5, "latch" }, .{ 7, "exit" } })) return self.fail("a malformed loop line");
        try self.draft.loops.append(self.a, .{ .header = try self.block(w[2]), .body = try self.block(w[4]), .latch = try self.block(w[6]), .exit = try self.block(w[8]) });
    }

    fn list(self: *Reader, w: []const []const u8) Error!void {
        if (w.len < 9 or !marked(w, .{.{ 2, "len" }})) return self.fail("a malformed list line");
        const len = try self.rangeAt(w, 3);
        const at = 3 + len.used;
        if (at + 1 >= w.len or !std.mem.eql(u8, w[at], "elems")) return self.fail("a malformed list line");
        const elems = try self.rangeAt(w, at + 1);
        const rest = at + 1 + elems.used;
        if (rest + 4 != w.len) return self.fail("a malformed list line");
        if (!std.mem.eql(u8, w[rest], "length") or !std.mem.eql(u8, w[rest + 2], "pattern")) return self.fail("a malformed list line");
        try self.draft.lists.append(self.a, .{
            .value = try self.value(w[1]),
            .len = len.range,
            .elems = elems.range,
            .length = if (std.mem.eql(u8, w[rest + 1], "-")) null else try self.value(w[rest + 1]),
            .pattern = try self.flag(w[rest + 3]),
        });
    }

    fn bound(self: *Reader, w: []const []const u8) Error!void {
        if (w.len != 4) return self.fail("a malformed bound line");
        const strict = if (std.mem.eql(u8, w[3], "strict")) true else if (std.mem.eql(u8, w[3], "loose")) false else return self.fail("a bound is strict or loose");
        try self.draft.bounds.append(self.a, .{ .value = try self.value(w[1]), .list = try self.value(w[2]), .strict = strict });
    }

    fn site(self: *Reader, w: []const []const u8) Error!void {
        if (w.len < 2) return self.fail("a malformed site line");
        var parts: std.ArrayList(?form.Interval) = .empty;
        for (w[2..]) |word| {
            if (std.mem.eql(u8, word, "-")) {
                try parts.append(self.a, null);
                continue;
            }
            const colon = std.mem.indexOfScalar(u8, word, ':') orelse return self.fail("a site interval needs lo:hi");
            try parts.append(self.a, .{ .lo = try self.number(word[0..colon], i128), .hi = try self.number(word[colon + 1 ..], i128) });
        }
        try self.draft.sites.append(self.a, .{ .value = try self.value(w[1]), .parts = parts.items });
    }

    fn end(self: *Reader) Error!void {
        if (self.in_block) return self.fail("the function ends inside a block");
        try self.functions.append(self.a, .{
            .header = self.draft.header,
            .boundary = .{ .params = self.draft.params.items, .returns = self.draft.returns },
            .pre = self.draft.pre.items,
            .blocks = self.draft.blocks.items,
            .aux = .{ .loops = self.draft.loops.items, .lists = self.draft.lists.items, .bounds = self.draft.bounds.items, .sites = self.draft.sites.items },
        });
        self.open = false;
    }
};

const fixture =
    \\fact-certificate-v1
    \\function f linkage internal addr 0 params i64,list ret i64
    \\param 0 0 9
    \\param 1 -
    \\returns 0 100
    \\block b- reach preds -
    \\inst %0 param i64 none a - b - x - imm 0 aux 0 range 0 9
    \\inst %2 iconst i64 none a - b - x - imm 1 aux 0 range -
    \\block b0 reach preds -
    \\inst %3 add i64 proven a %0 b %2 x - imm 0 aux 0 range 1 10
    \\term jump b1
    \\block b1 reach preds b0,b1
    \\phi %4 i64 edges b0:%3,b1:%4 range 1 10
    \\term ret %4
    \\loop header b1 body b1 latch b1 exit b1
    \\list %1 len 0 5 elems - length - pattern 0
    \\bound %0 %1 strict
    \\site %3 0:9 1:1
    \\end
    \\
;

test "a module printed in the format reads back into the same module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var problem: Problem = .{};
    const module = try parse(a, fixture, &problem);
    try std.testing.expectEqual(@as(usize, 1), module.functions.len);
    const function = module.functions[0];
    try std.testing.expectEqualStrings("f", function.header.name);
    try std.testing.expectEqual(form.Interval{ .lo = 0, .hi = 9 }, function.boundary.params[0].?);
    try std.testing.expectEqual(@as(?form.Interval, null), function.boundary.params[1]);
    try std.testing.expectEqual(ir.Check.proven, function.blocks[0].insts[0].check);
    var printed: std.ArrayList(u8) = .empty;
    try write(a, &printed, module);
    try std.testing.expectEqualStrings(fixture, printed.items);
}

test "a malformed line names its number" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var problem: Problem = .{};
    try std.testing.expectError(error.Malformed, parse(arena.allocator(), "fact-certificate-v1\nfunction f linkage internal addr 0 params - ret i64\nblock b0 reach\nend\n", &problem));
    try std.testing.expectEqual(@as(usize, 3), problem.line);
}
