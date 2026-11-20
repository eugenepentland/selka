//! Bounded byte-regex normalization: one capture, explicit supported syntax.
//! No lookaround, backreferences or host regex dependency; advanced oracles use check.
const std = @import("std");
const d = @import("data.zig");
const Node = struct { kind: enum { bytes, sequence, choice, repeat, capture, start, end }, mask: [32]u8 = @splat(0), left: ?*Node = null, right: ?*Node = null, min: usize = 0, max: usize = 0 };
const Parser = struct {
    c: *d.Context,
    text: []const u8,
    at: usize = 0,
    captures: usize = 0,
    depth: usize = 0,
    fn node(p: *Parser, n: Node) !*Node {
        const result = try p.c.a.create(Node);
        result.* = n;
        return result;
    }
    fn choice(p: *Parser) anyerror!*Node {
        p.depth += 1;
        defer p.depth -= 1;
        if (p.depth > 64) return p.c.fail("normalization pattern nesting exceeds 64");
        var result = try p.sequence();
        while (p.at < p.text.len and p.text[p.at] == '|') {
            p.at += 1;
            result = try p.node(.{ .kind = .choice, .left = result, .right = try p.sequence() });
        }
        return result;
    }
    fn sequence(p: *Parser) anyerror!*Node {
        var result: ?*Node = null;
        while (p.at < p.text.len and p.text[p.at] != ')' and p.text[p.at] != '|') {
            const element = try p.term();
            result = if (result) |left| try p.node(.{ .kind = .sequence, .left = left, .right = element }) else element;
        }
        return result orelse p.node(.{ .kind = .sequence });
    }
    fn escaped(p: *Parser) ![32]u8 {
        if (p.at == p.text.len) return error.InvalidExperiment;
        const ch = p.text[p.at];
        p.at += 1;
        var mask: [32]u8 = @splat(0);
        switch (ch) {
            'd', 'D', 's', 'S', 'w', 'W' => {
                for (0..256) |i| {
                    const b: @TypeOf(ch) = @intCast(i);
                    const yes = switch (std.ascii.toLower(ch)) {
                        'd' => std.ascii.isDigit(b),
                        's' => std.ascii.isWhitespace(b),
                        else => std.ascii.isAlphanumeric(b) or b == '_',
                    };
                    if (yes != std.ascii.isUpper(ch)) set(&mask, b);
                }
            },
            'n' => set(&mask, '\n'),
            'r' => set(&mask, '\r'),
            't' => set(&mask, '\t'),
            else => {
                if (std.ascii.isAlphanumeric(ch)) return p.c.fail("unsupported normalization escape; use check for advanced oracles");
                set(&mask, ch);
            },
        }
        return mask;
    }
    fn atom(p: *Parser) anyerror!*Node {
        const ch = p.text[p.at];
        p.at += 1;
        if (ch == '(') {
            var capture = true;
            if (p.at < p.text.len and p.text[p.at] == '?') {
                if (!std.mem.startsWith(u8, p.text[p.at..], "?:")) return p.c.fail("normalization supports capture and (?:...) groups only");
                p.at += 2;
                capture = false;
            }
            if (capture) p.captures += 1;
            const child = try p.choice();
            if (p.at == p.text.len or p.text[p.at] != ')') return error.InvalidExperiment;
            p.at += 1;
            return if (capture) p.node(.{ .kind = .capture, .left = child }) else child;
        }
        if (ch == '^') return p.node(.{ .kind = .start });
        if (ch == '$') return p.node(.{ .kind = .end });
        var mask: [32]u8 = @splat(0);
        if (ch == '.') {
            mask = @splat(255);
        } else if (ch == '\\') {
            mask = try p.escaped();
        } else if (ch == '[') {
            const negated = p.at < p.text.len and p.text[p.at] == '^';
            if (negated) p.at += 1;
            var count: usize = 0;
            while (p.at < p.text.len and p.text[p.at] != ']') {
                var first = p.text[p.at];
                p.at += 1;
                if (first == '\\') {
                    const escaped_mask = try p.escaped();
                    for (&mask, escaped_mask) |*b, e| b.* |= e;
                } else if (p.at + 1 < p.text.len and p.text[p.at] == '-' and p.text[p.at + 1] != ']') {
                    p.at += 1;
                    const last = p.text[p.at];
                    p.at += 1;
                    if (last < first) return error.InvalidExperiment;
                    while (true) {
                        set(&mask, first);
                        if (first == last) break;
                        first += 1;
                    }
                } else set(&mask, first);
                count += 1;
            }
            if (p.at == p.text.len or count == 0) return error.InvalidExperiment;
            p.at += 1;
            if (negated) for (&mask) |*b| {
                b.* = ~b.*;
            };
        } else {
            if (std.mem.indexOfScalar(u8, "*+?{}", ch) != null) return error.InvalidExperiment;
            set(&mask, ch);
        }
        return p.node(.{ .kind = .bytes, .mask = mask });
    }
    fn integer(p: *Parser) !usize {
        const start = p.at;
        while (p.at < p.text.len and std.ascii.isDigit(p.text[p.at])) p.at += 1;
        if (start == p.at) return error.InvalidExperiment;
        return std.fmt.parseInt(usize, p.text[start..p.at], 10);
    }
    fn term(p: *Parser) anyerror!*Node {
        const child = try p.atom();
        if (p.at == p.text.len) return child;
        var min: usize = 0;
        var max: usize = std.math.maxInt(usize);
        switch (p.text[p.at]) {
            '*' => p.at += 1,
            '+' => {
                min = 1;
                p.at += 1;
            },
            '?' => {
                max = 1;
                p.at += 1;
            },
            '{' => {
                p.at += 1;
                min = try p.integer();
                max = min;
                if (p.at < p.text.len and p.text[p.at] == ',') {
                    p.at += 1;
                    max = if (p.at < p.text.len and p.text[p.at] == '}') std.math.maxInt(usize) else try p.integer();
                }
                if (p.at == p.text.len or p.text[p.at] != '}' or max < min) return error.InvalidExperiment;
                p.at += 1;
            },
            else => return child,
        }
        if (p.at < p.text.len and (p.text[p.at] == '?' or p.text[p.at] == '+')) return p.c.fail("lazy and possessive normalization repeats are unsupported; use check");
        return p.node(.{ .kind = .repeat, .left = child, .min = min, .max = max });
    }
};
fn set(mask: *[32]u8, ch: u8) void {
    mask[ch / 8] |= @as(u8, 1) << @intCast(ch % 8);
}
fn parsed(c: *d.Context, pattern: []const u8) !*Node {
    if (pattern.len > 4096) return c.fail("normalization pattern exceeds 4096 bytes");
    var p: Parser = .{ .c = c, .text = pattern };
    const node = try p.choice();
    if (p.at != pattern.len or p.captures != 1) return c.fail("stdout_regex must have exactly one capture group");
    return node;
}
/// Validate the portable normalization syntax before building a workload.
pub fn validate(c: *d.Context, pattern: []const u8) d.Error!void {
    return validateImpl(c, pattern) catch |err| d.failure(c, err);
}
fn validateImpl(c: *d.Context, pattern: []const u8) !void {
    _ = try parsed(c, pattern);
}
const State = struct { at: usize = 0, start: ?usize = null, end: ?usize = null };
const Matcher = struct {
    c: *d.Context,
    text: []const u8,
    budget: usize = 1_000_000,
    fn run(m: *Matcher, node: *Node, state: State) anyerror![]State {
        if (m.budget == 0) return m.c.fail("normalization work limit exceeded; use a simpler oracle");
        m.budget -= 1;
        switch (node.kind) {
            .bytes => {
                if (state.at >= m.text.len) return &.{};
                const ch = m.text[state.at];
                if (node.mask[ch / 8] & (@as(u8, 1) << @intCast(ch % 8)) == 0) return &.{};
                var next = state;
                next.at += 1;
                return m.c.a.dupe(State, &.{next});
            },
            .start => return if (state.at == 0) m.c.a.dupe(State, &.{state}) else &.{},
            .end => return if (state.at == m.text.len) m.c.a.dupe(State, &.{state}) else &.{},
            .capture => {
                var next = state;
                next.start = state.at;
                const states = try m.run(node.left.?, next);
                for (states) |*s| s.end = s.at;
                return states;
            },
            .choice => {
                const left = try m.run(node.left.?, state);
                const right = try m.run(node.right.?, state);
                return std.mem.concat(m.c.a, State, &.{ left, right });
            },
            .sequence => {
                if (node.left == null) return m.c.a.dupe(State, &.{state});
                var result: std.ArrayList(State) = .empty;
                for (try m.run(node.left.?, state)) |s| try result.appendSlice(m.c.a, try m.run(node.right.?, s));
                return result.toOwnedSlice(m.c.a);
            },
            .repeat => return m.repeated(node, state),
        }
    }
    fn repeated(m: *Matcher, node: *Node, state: State) anyerror![]State {
        var accepted: std.ArrayList(State) = .empty;
        var current = try m.c.a.dupe(State, &.{state});
        var count: usize = 0;
        while (current.len > 0) : (count += 1) {
            if (count >= node.min) try accepted.appendSlice(m.c.a, current);
            if (count >= node.max) break;
            var next: std.ArrayList(State) = .empty;
            for (current) |s| for (try m.run(node.left.?, s)) |n| {
                if (n.at != s.at) try next.append(m.c.a, n);
            };
            current = try next.toOwnedSlice(m.c.a);
        }
        std.mem.reverse(State, accepted.items);
        return accepted.toOwnedSlice(m.c.a);
    }
};
/// Full-match all output and return the one captured byte range.
pub fn apply(c: *d.Context, pattern: []const u8, text: []const u8) d.Error![]const u8 {
    return applyImpl(c, pattern, text) catch |err| d.failure(c, err);
}
fn applyImpl(c: *d.Context, pattern: []const u8, text: []const u8) ![]const u8 {
    var matcher: Matcher = .{ .c = c, .text = text };
    for (try matcher.run(try parsed(c, pattern), .{})) |state| if (state.at == text.len and state.start != null and state.end != null) return text[state.start.?..state.end.?];
    return c.fail("stdout does not full-match declared normalization");
}
