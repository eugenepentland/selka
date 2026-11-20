//! Pure Python-doctest transcript grammar, shared by overview, lint and tests.
const std = @import("std");

/// One prompt-stripped source line, with its original one-based source position.
pub const Line = struct { text: []const u8, line: usize };

/// One prompt and its continuation lines, followed by exact expected output.
/// Source text borrows the input; `lines` and `expected` are allocator-owned.
pub const Example = struct { lines: []const Line, expected: []const u8, line: usize };

const Reading = struct {
    lines: std.mem.SplitIterator(u8, .scalar),
    indentation: usize,
    line: usize = 0,

    fn init(text: []const u8) Reading {
        var lines = std.mem.splitScalar(u8, text, '\n');
        _ = lines.next();
        var indentation: usize = std.math.maxInt(usize);
        while (lines.next()) |raw| {
            const trimmed = std.mem.trimStart(u8, raw, " \t");
            if (std.mem.trim(u8, trimmed, "\r").len == 0) continue;
            indentation = @min(indentation, raw.len - trimmed.len);
        }
        return .{ .lines = std.mem.splitScalar(u8, text, '\n'), .indentation = if (indentation == std.math.maxInt(usize)) 0 else indentation };
    }

    fn next(self: *Reading) ?Line {
        const raw = self.lines.next() orelse return null;
        const trimmed = std.mem.trimStart(u8, raw, " \t");
        const removed = if (self.line == 0) raw.len - trimmed.len else @min(self.indentation, raw.len - trimmed.len);
        self.line += 1;
        return .{ .text = std.mem.trimEnd(u8, raw[removed..], "\r"), .line = self.line };
    }
};

fn body(line: []const u8, marker: []const u8) ?[]const u8 {
    return if (std.mem.startsWith(u8, line, marker)) line[marker.len..] else null;
}

/// Count prompts without allocations, using the same indentation and grammar as parse.
pub fn count(text: []const u8) usize {
    var reading = Reading.init(text);
    var result: usize = 0;
    while (reading.next()) |line| {
        if (body(line.text, ">>> ") != null) result += 1;
    }
    return result;
}

/// Parse quote-stripped docstring text; first_line is the line of its first byte.
/// Expected lines include their newline, including a final line at end of text.
pub fn parse(allocator: std.mem.Allocator, text: []const u8, first_line: usize) std.mem.Allocator.Error![]const Example {
    var reading = Reading.init(text);
    var examples: std.ArrayList(Example) = .empty;
    errdefer {
        for (examples.items) |example| freeExample(allocator, example);
        examples.deinit(allocator);
    }
    var pending = reading.next();
    while (pending) |line| {
        const first = body(line.text, ">>> ") orelse {
            pending = reading.next();
            continue;
        };
        const example = try readExample(allocator, &reading, .{ .text = first, .line = line.line + first_line - 1 }, &pending, first_line);
        errdefer freeExample(allocator, example);
        try examples.append(allocator, example);
    }
    return examples.toOwnedSlice(allocator);
}

fn readExample(allocator: std.mem.Allocator, reading: *Reading, first: Line, pending: *?Line, first_line: usize) std.mem.Allocator.Error!Example {
    var lines: std.ArrayList(Line) = .empty;
    defer lines.deinit(allocator);
    try lines.append(allocator, first);
    pending.* = reading.next();
    while (pending.*) |line| {
        const continuation = body(line.text, "... ") orelse break;
        try lines.append(allocator, .{ .text = continuation, .line = line.line + first_line - 1 });
        pending.* = reading.next();
    }
    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(allocator);
    while (pending.*) |line| {
        if (std.mem.trim(u8, line.text, " \t").len == 0 or body(line.text, ">>> ") != null) break;
        if (!std.mem.eql(u8, line.text, "<BLANKLINE>")) try expected.appendSlice(allocator, line.text);
        try expected.append(allocator, '\n');
        pending.* = reading.next();
    }
    const owned_lines = try lines.toOwnedSlice(allocator);
    errdefer allocator.free(owned_lines);
    return .{ .lines = owned_lines, .expected = try expected.toOwnedSlice(allocator), .line = first.line };
}

fn freeExample(allocator: std.mem.Allocator, example: Example) void {
    allocator.free(example.lines);
    allocator.free(example.expected);
}

/// Release parsed storage; the original docstring remains owned by its caller.
pub fn release(allocator: std.mem.Allocator, examples: []const Example) void {
    for (examples) |example| freeExample(allocator, example);
    allocator.free(examples);
}
