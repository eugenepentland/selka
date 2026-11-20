//! Canonical ordering of source names in parsed borrowing clauses.
const std = @import("std");
const ast = @import("ast.zig");
const lex = @import("lexer.zig");
const Span = @import("source.zig").Span;

/// Owned source and token copies with borrowing names in parameter order.
pub const Input = struct {
    bytes: []u8,
    tokens: []lex.Token,

    /// Release the source and token copies together.
    pub fn deinit(self: Input, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
        allocator.free(self.tokens);
    }
};

const Order = struct {
    bytes: []const u8,
    parameters: []const ast.Parameter,

    fn position(self: Order, name: Span) ?usize {
        var found: ?usize = null;
        for (self.parameters, 0..) |parameter, index| {
            if (!std.mem.eql(u8, self.bytes[name.start..name.end], self.bytes[parameter.name.start..parameter.name.end])) continue;
            if (found != null) return null;
            found = index;
        }
        return found;
    }

    fn before(self: Order, left: Span, right: Span) bool {
        return self.position(left).? < self.position(right).?;
    }
};

/// Reorder known names without resolving their types or rejecting draft source.
/// Null means the original source already has the order the formatter needs.
pub fn canonical(allocator: std.mem.Allocator, bytes: []const u8, tokens: []const lex.Token, functions: []const ast.Function) std.mem.Allocator.Error!?Input {
    var output: ?Input = null;
    errdefer if (output) |owned| owned.deinit(allocator);
    for (functions) |function| {
        const sources = function.signature.borrowing;
        if (sources.len < 2) continue;
        const order: Order = .{ .bytes = bytes, .parameters = function.signature.parameters };
        // Formatting unresolved drafts remains possible. A source with no
        // unique parameter position keeps its written order for checking.
        if (!knownSources(order, sources)) continue;
        const sorted = try allocator.dupe(Span, sources);
        defer allocator.free(sorted);
        std.mem.sort(Span, sorted, order, Order.before);
        if (sameNames(bytes, sources, sorted)) continue;
        if (output == null) {
            const owned_bytes = try allocator.dupe(u8, bytes);
            errdefer allocator.free(owned_bytes);
            const owned_tokens = try allocator.dupe(lex.Token, tokens);
            // Transfer both copies only after their allocations have succeeded.
            output = .{ .bytes = owned_bytes, .tokens = owned_tokens };
        }
        reorder(&output.?, bytes, tokens, sources, sorted);
    }
    return output;
}

fn knownSources(order: Order, sources: []const Span) bool {
    for (sources) |name| if (order.position(name) == null) return false;
    return true;
}

fn sameNames(bytes: []const u8, left: []const Span, right: []const Span) bool {
    for (left, right) |a, b| if (!std.mem.eql(u8, bytes[a.start..a.end], bytes[b.start..b.end])) return false;
    return true;
}

fn tokenAt(tokens: []const lex.Token, span: Span) usize {
    var first: usize = 0;
    var last = tokens.len;
    while (first < last) {
        const middle = first + (last - first) / 2;
        if (tokens[middle].span.start < span.start) first = middle + 1 else last = middle;
    }
    while (first < tokens.len and tokens[first].span.start == span.start) : (first += 1) {
        if (tokens[first].span.end == span.end) return first;
    }
    unreachable; // Every name came directly from a parsed token.
}

/// The names have the same combined length in either order. Retaining their
/// intervening gaps keeps every byte and token outside this clause in place.
fn reorder(output: *Input, bytes: []const u8, tokens: []const lex.Token, sources: []const Span, sorted: []const Span) void {
    var cursor = sources[0].start;
    var token_index = tokenAt(tokens, sources[0]);
    for (sources, sorted, 0..) |source, name, index| {
        const text = bytes[name.start..name.end];
        @memcpy(output.bytes[cursor..][0..text.len], text);
        output.tokens[token_index] = .{ .tag = tokens[tokenAt(tokens, name)].tag, .span = .{ .start = cursor, .end = cursor + text.len } };
        token_index += 1;
        cursor += text.len;
        const gap_end = if (index + 1 < sources.len) sources[index + 1].start else source.end;
        const gap = bytes[source.end..gap_end];
        @memcpy(output.bytes[cursor..][0..gap.len], gap);
        while (token_index < tokens.len and tokens[token_index].span.start < gap_end) : (token_index += 1) {
            const span = tokens[token_index].span;
            output.tokens[token_index].span = .{ .start = cursor + span.start - source.end, .end = cursor + span.end - source.end };
        }
        cursor += gap.len;
    }
    std.debug.assert(cursor == sources[sources.len - 1].end);
}
