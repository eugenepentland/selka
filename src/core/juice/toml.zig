//! Workload TOML reader: tables, table arrays, strings, numbers and arrays.
//! Reject unsupported TOML constructs explicitly; JSON manifests use the same schema.
const std = @import("std");
const d = @import("data.zig");
const V = d.Value;
const Parser = struct {
    c: *d.Context,
    text: []const u8,
    at: usize = 0,
    fn space(p: *Parser) void {
        while (p.at < p.text.len) {
            const ch = p.text[p.at];
            if (std.ascii.isWhitespace(ch)) {
                p.at += 1;
            } else if (ch == '#') {
                while (p.at < p.text.len and p.text[p.at] != '\n') p.at += 1;
            } else break;
        }
    }
    fn quoted(p: *Parser) !V {
        const quote = p.text[p.at];
        p.at += 1;
        const start = p.at;
        while (p.at < p.text.len) {
            const ch = p.text[p.at];
            p.at += 1;
            if (ch == quote) {
                if (quote == '\'') return d.string(try p.c.a.dupe(u8, p.text[start .. p.at - 1]));
                return p.c.parse(p.text[start - 1 .. p.at]);
            }
            if (ch == '\n' or ch == '\r') return p.c.fail("multiline TOML strings are unsupported; use escaped strings or JSON");
            if (ch == '\\' and quote == '"') {
                if (p.at == p.text.len) break;
                p.at += 1;
            }
        }
        return p.c.fail("unterminated TOML string");
    }
    fn value(p: *Parser) anyerror!V {
        p.space();
        if (p.at == p.text.len) return error.InvalidExperiment;
        switch (p.text[p.at]) {
            '"', '\'' => return p.quoted(),
            '[' => {
                p.at += 1;
                var result = d.array(p.c);
                p.space();
                while (p.at < p.text.len and p.text[p.at] != ']') {
                    try d.add(p.c, &result, try p.value());
                    p.space();
                    if (p.at == p.text.len) return error.InvalidExperiment;
                    if (p.text[p.at] == ']') break;
                    if (p.text[p.at] != ',') return error.InvalidExperiment;
                    p.at += 1;
                    p.space();
                }
                if (p.at == p.text.len) return error.InvalidExperiment;
                p.at += 1;
                return result;
            },
            else => {
                const start = p.at;
                while (p.at < p.text.len and !std.ascii.isWhitespace(p.text[p.at]) and std.mem.indexOfScalar(u8, ",]#", p.text[p.at]) == null) p.at += 1;
                const token = try std.mem.replaceOwned(u8, p.c.a, p.text[start..p.at], "_", "");
                if (std.mem.eql(u8, token, "true")) return .{ .bool = true };
                if (std.mem.eql(u8, token, "false")) return .{ .bool = false };
                if (std.fmt.parseInt(i64, token, 0)) |n| return .{ .integer = n } else |_| {}
                const number = std.fmt.parseFloat(f64, token) catch return p.c.fail("unsupported TOML value; use strings, arrays, finite numbers or booleans");
                if (!std.math.isFinite(number)) return error.InvalidExperiment;
                return .{ .float = number };
            },
        }
    }
};
/// Parse the manifest's table-oriented TOML syntax, rejecting duplicate keys/tables.
pub fn parse(c: *d.Context, text: []const u8) d.Error!V {
    return parseImpl(c, text) catch |err| d.failure(c, err);
}
fn parseImpl(c: *d.Context, text: []const u8) !V {
    var parser: Parser = .{ .c = c, .text = text };
    var result = d.object();
    var table: []const u8 = "";
    var array_index: ?usize = null;
    var declared = d.object();
    while (true) {
        parser.space();
        if (parser.at == text.len) break;
        if (text[parser.at] == '[') {
            parser.at += 1;
            const is_array = parser.at < text.len and text[parser.at] == '[';
            if (is_array) parser.at += 1;
            const start = parser.at;
            while (parser.at < text.len and text[parser.at] != ']') parser.at += 1;
            if (parser.at == text.len) return error.InvalidExperiment;
            table = std.mem.trim(u8, text[start..parser.at], " \t");
            if (!d.identifier(table)) return c.fail("manifest table must be a simple name");
            parser.at += 1;
            if (is_array) {
                if (parser.at == text.len or text[parser.at] != ']') return error.InvalidExperiment;
                parser.at += 1;
                var rows = d.get(result, table);
                if (rows == .null) rows = d.array(c);
                try d.add(c, &rows, d.object());
                array_index = rows.array.items.len - 1;
                try d.put(c, &result, table, rows);
            } else {
                if (declared.object.contains(table) or d.get(result, table) != .null) return c.fail("duplicate TOML table");
                try d.put(c, &declared, table, .{ .bool = true });
                try d.put(c, &result, table, d.object());
                array_index = null;
            }
        } else {
            const start = parser.at;
            while (parser.at < text.len and text[parser.at] != '=' and text[parser.at] != '\n') parser.at += 1;
            if (parser.at == text.len or text[parser.at] != '=') return error.InvalidExperiment;
            const key = std.mem.trim(u8, text[start..parser.at], " \t");
            if (!d.identifier(key)) return c.fail("manifest keys must be simple names");
            parser.at += 1;
            const value = try parser.value();
            if (table.len == 0) {
                if (result.object.contains(key)) return c.fail("duplicate manifest key");
                try d.put(c, &result, key, value);
            } else {
                var target = d.get(result, table);
                if (array_index) |index| {
                    var row = target.array.items[index];
                    if (row.object.contains(key)) return c.fail("duplicate workload key");
                    try d.put(c, &row, key, value);
                    target.array.items[index] = row;
                } else {
                    if (target.object.contains(key)) return c.fail("duplicate table key");
                    try d.put(c, &target, key, value);
                }
                try d.put(c, &result, table, target);
            }
        }
        while (parser.at < text.len and (text[parser.at] == ' ' or text[parser.at] == '\t' or text[parser.at] == '\r')) parser.at += 1;
        if (parser.at < text.len and text[parser.at] != '\n' and text[parser.at] != '#') return c.fail("unexpected text after TOML value");
    }
    return result;
}
