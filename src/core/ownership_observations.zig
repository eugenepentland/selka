//! Opt-in observations from the ownership checker, for migration and layer audits.
const std = @import("std");
const language = @import("selka");

/// An audit writes JSON lines alongside diagnostics; it never changes a checking decision.
pub const Observer = struct {
    source: language.source.Source,
    sink: struct { allocator: std.mem.Allocator, output: *std.ArrayList(u8) },
    returned: ?struct { span: language.source.Span, field: bool } = null,
    argument: ?language.source.Span = null,

    /// The named root of a direct place, without treating constructor payloads as that place.
    pub fn bindingSpan(program: language.typed.Program, value: language.typed.NodeId) ?language.source.Span {
        var current = sourceValue(program, value);
        while (true) switch (program.nodes[@backingInt(current)].data) {
            .local => return program.nodes[@backingInt(current)].span,
            .field => |field| current = field.base,
            else => return null,
        };
    }

    /// Discard optional injections that retain exactly their source operand's span.
    pub fn sourceValue(program: language.typed.Program, value: language.typed.NodeId) language.typed.NodeId {
        var current = value;
        while (true) {
            const node = program.nodes[@backingInt(current)];
            if (node.data != .variant) return current;
            const child = node.data.variant.value orelse return current;
            if (!sameSpan(node.span, program.nodes[@backingInt(child)].span)) return current;
            current = child;
        }
    }

    /// Recover a return's source expression through implicit success and optional injections.
    pub fn returnedValue(self: Observer, program: language.typed.Program, value: language.typed.NodeId) language.typed.NodeId {
        var current = value;
        const outer = program.nodes[@backingInt(current)];
        const text = std.mem.trimStart(u8, self.source.text(outer.span), " \t\r\n");
        if (outer.data == .variant and startsToken(text, "return")) current = outer.data.variant.value orelse current;
        return sourceValue(program, current);
    }

    /// Retain direct returned fields separately; unwrap only the compiler's implicit success injection.
    pub fn returnedBinding(self: Observer, program: language.typed.Program, value: language.typed.NodeId) @FieldType(Observer, "returned") {
        const current = self.returnedValue(program, value);
        const span = bindingSpan(program, current) orelse return null;
        return .{ .span = span, .field = program.nodes[@backingInt(current)].data == .field };
    }

    /// Classify only a direct argument or return place; nested construction still stores its operands.
    pub fn moveKind(self: Observer, span: language.source.Span) []const u8 {
        if (self.argument) |argument| if (sameSpan(argument, span)) return "argument_move";
        if (self.returned) |returned| if (sameSpan(returned.span, span)) return if (returned.field) "return_field_move" else "return_move";
        return "move";
    }

    /// Recognize an existing marker on the moved node or immediately before its root binding.
    pub fn spellsOwn(self: Observer, span: language.source.Span) bool {
        const text = std.mem.trimStart(u8, self.source.text(span), " \t\r\n");
        if (startsToken(text, "own")) return true;
        var end = span.start;
        while (end != 0 and (std.ascii.isWhitespace(self.source.bytes[end - 1]) or self.source.bytes[end - 1] == '(')) end -= 1;
        if (end < 3 or !std.mem.eql(u8, self.source.bytes[end - 3 .. end], "own")) return false;
        return end == 3 or (!std.ascii.isAlphanumeric(self.source.bytes[end - 4]) and self.source.bytes[end - 4] != '_');
    }

    /// Distinguish a spelled collection call from the append/write nodes constructing literals or stores.
    pub fn sourceCall(self: Observer, span: language.source.Span) bool {
        const text = std.mem.trimStart(u8, self.source.text(span), " \t\r\n");
        var index: usize = 0;
        while (index < text.len) {
            if (!std.ascii.isAlphabetic(text[index]) and text[index] != '_') return false;
            index += 1;
            while (index < text.len and (std.ascii.isAlphanumeric(text[index]) or text[index] == '_')) index += 1;
            while (index < text.len and std.ascii.isWhitespace(text[index])) index += 1;
            while (index < text.len and text[index] == '[') {
                index = afterIndex(text, index) orelse return false;
                while (index < text.len and std.ascii.isWhitespace(text[index])) index += 1;
            }
            if (index == text.len) return false;
            if (text[index] == '(') return true;
            if (text[index] != '.') return false;
            index += 1;
            while (index < text.len and std.ascii.isWhitespace(text[index])) index += 1;
        }
        return false;
    }

    /// Locate a compiler-observed fact in its original module, including imported functions.
    pub fn record(self: *Observer, kind: []const u8, span: language.source.Span, detail: anytype) error{OutOfMemory}!void {
        const location = self.source.locate(span.start);
        const text = try std.json.Stringify.valueAlloc(self.sink.allocator, .{
            .version = "ownership-audit-v1",
            .kind = kind,
            .path = location.path,
            .line = location.line,
            .column = location.column,
            .detail = detail,
        }, .{});
        defer self.sink.allocator.free(text);
        try self.sink.output.appendSlice(self.sink.allocator, text);
        try self.sink.output.append(self.sink.allocator, '\n');
    }
};

fn sameSpan(left: language.source.Span, right: language.source.Span) bool {
    return left.start == right.start and left.end == right.end;
}

fn startsToken(text: []const u8, token: []const u8) bool {
    return std.mem.startsWith(u8, text, token) and text.len > token.len and
        !std.ascii.isAlphanumeric(text[token.len]) and text[token.len] != '_';
}

fn afterIndex(text: []const u8, start: usize) ?usize {
    var depth: usize = 0;
    var quote: u8 = 0;
    var escaped = false;
    var comment = false;
    for (text[start..], start..) |byte, index| {
        if (comment) {
            if (byte == '\n') comment = false;
            continue;
        }
        if (quote != 0) {
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == quote) {
                quote = 0;
            }
            continue;
        }
        switch (byte) {
            '"', '\'' => quote = byte,
            '#' => comment = true,
            '[' => depth += 1,
            ']' => {
                depth -= 1;
                if (depth == 0) return index + 1;
            },
            else => {},
        }
    }
    return null;
}
