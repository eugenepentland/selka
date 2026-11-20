const std = @import("std");
const gpa = std.heap.c_allocator;
const modulus: i64 = 1_000_000_007;
const Timespec = extern struct { sec: c_long, nsec: c_long };
extern "c" fn clock_gettime(clock: c_int, time: *Timespec) c_int;
extern "c" fn printf(format: [*:0]const u8, ...) c_int;
fn now() i64 {
    var t: Timespec = undefined;
    if (clock_gettime(1, &t) != 0) @panic("clock failed");
    return t.sec * 1_000_000_000 + t.nsec;
}
fn score(text: []const u8) i64 {
    var result: i64 = @intCast(text.len);
    for (text) |v| result += v;
    return result;
}
fn rowName(j: usize) []u8 {
    return std.fmt.allocPrint(gpa, "{s}{d}", .{ if (j % 2 == 0) "café,\"item\"" else "naïve,item", j }) catch @panic("allocation failed");
}
fn repeat(text: []const u8, count: usize) []u8 {
    const output = gpa.alloc(u8, text.len * count) catch @panic("allocation failed");
    for (0..count) |j| @memcpy(output[j * text.len ..][0..text.len], text);
    return output;
}
fn join(parts: []const []const u8, sep: []const u8) []u8 {
    return std.mem.join(gpa, sep, parts) catch @panic("allocation failed");
}
const Inputs = struct {
    raw: []u8 = &.{},
    texts: std.ArrayList([]const u8) = .empty,
    other: std.ArrayList([]const u8) = .empty,
    numbers: []i64 = &.{},
    fragments: []const []const u8 = &.{},
    fn deinit(self: *Inputs) void {
        gpa.free(self.raw);
        for (self.texts.items) |text| gpa.free(text);
        self.texts.deinit(gpa);
        for (self.other.items) |text| gpa.free(text);
        self.other.deinit(gpa);
        gpa.free(self.numbers);
        gpa.free(self.fragments);
    }
};
fn add(list: *std.ArrayList([]const u8), text: []const u8) void {
    list.append(gpa, text) catch @panic("allocation failed");
}
fn fixtures(kind: []const u8, size: usize, seed: i64) Inputs {
    var d: Inputs = .{};
    const s: usize = @intCast(seed);
    if (std.mem.eql(u8, kind, "bytes_scan")) {
        d.raw = gpa.alloc(u8, size) catch @panic("allocation failed");
        for (d.raw, 0..) |*v, j| v.* = @intCast(@mod(seed + @as(i64, @intCast(j)) * 37, 256));
    } else if (std.mem.eql(u8, kind, "string_equal")) {
        add(&d.texts, repeat("a", size));
        add(&d.texts, repeat("é", size));
        add(&d.texts, repeat("a", size));
        add(&d.texts, std.fmt.allocPrint(gpa, "café{d}", .{seed}) catch @panic("allocation failed"));
        add(&d.other, repeat("a", size));
        const u = repeat("é", size - 1);
        defer gpa.free(u);
        add(&d.other, std.fmt.allocPrint(gpa, "{s}ê", .{u}) catch @panic("allocation failed"));
        const a = repeat("a", size - 1);
        defer gpa.free(a);
        add(&d.other, std.fmt.allocPrint(gpa, "b{s}", .{a}) catch @panic("allocation failed"));
        add(&d.other, std.fmt.allocPrint(gpa, "café{d}", .{seed}) catch @panic("allocation failed"));
    } else if (std.mem.eql(u8, kind, "string_search")) {
        const a = repeat("a", size);
        defer gpa.free(a);
        add(&d.texts, std.fmt.allocPrint(gpa, "{s};café;needle;{d}", .{ a, seed }) catch @panic("allocation failed"));
        for ([_][]const u8{ "a", "needle", "absentΩ", "é" }) |text| add(&d.other, gpa.dupe(u8, text) catch @panic("allocation failed"));
    } else if (std.mem.eql(u8, kind, "string_split") or std.mem.eql(u8, kind, "string_join")) {
        const options = [_][]const u8{ "", "alpha", "café", "x", "naïve" };
        const parts = gpa.alloc([]const u8, size) catch @panic("allocation failed");
        for (parts, 0..) |*part, j| part.* = options[(s + j) % 5];
        d.fragments = parts;
        add(&d.texts, join(parts, "|"));
        add(&d.texts, join(parts, "::"));
    } else if (std.mem.eql(u8, kind, "int_parse")) {
        for (0..size) |j| {
            const n = @mod(seed + @as(i64, @intCast(j)) * 137, 1_000_003);
            const text = switch (j % 6) {
                0 => std.fmt.allocPrint(gpa, "{d}", .{n}),
                1 => std.fmt.allocPrint(gpa, "-{d}", .{n}),
                2 => std.fmt.allocPrint(gpa, "00{d}", .{n}),
                3 => std.fmt.allocPrint(gpa, "{d}x", .{n}),
                4 => gpa.dupe(u8, "oops"),
                else => gpa.dupe(u8, ""),
            };
            add(&d.texts, text catch @panic("allocation failed"));
        }
    } else if (std.mem.eql(u8, kind, "int_format")) {
        d.numbers = gpa.alloc(i64, size) catch @panic("allocation failed");
        for (d.numbers, 0..) |*v, j| {
            const n = @mod(seed + @as(i64, @intCast(j)) * 137, 1_000_003);
            v.* = if (j % 3 == 0) -n else n;
        }
    } else if (std.mem.eql(u8, kind, "word_count")) {
        const vocabulary = [_][]const u8{ "red", "blue", "café", "red", "green", "blue", "naïve", "red" };
        const separators = [_][]const u8{ " ", "\t", "\n", "  " };
        var document: std.ArrayList(u8) = .empty;
        defer document.deinit(gpa);
        for (0..size) |j| {
            document.appendSlice(gpa, vocabulary[(s + j) % 8]) catch @panic("allocation failed");
            document.appendSlice(gpa, separators[j % 4]) catch @panic("allocation failed");
        }
        add(&d.texts, std.fmt.allocPrint(gpa, "{s}red", .{document.items}) catch @panic("allocation failed"));
        add(&d.texts, std.fmt.allocPrint(gpa, "{s}blue", .{document.items}) catch @panic("allocation failed"));
    } else if (std.mem.eql(u8, kind, "csv_aggregate")) {
        const regions = [_][]const u8{ "east", "west", "north" };
        var document: std.ArrayList(u8) = .empty;
        for (0..size) |j| {
            const name = rowName(j);
            defer gpa.free(name);
            const escaped = std.mem.replaceOwned(u8, gpa, name, "\"", "\"\"") catch @panic("allocation failed");
            defer gpa.free(escaped);
            const amount = if (j % 11 == 0) gpa.dupe(u8, "oops") else std.fmt.allocPrint(gpa, "{d}", .{@mod(seed + @as(i64, @intCast(j)) * 19, 100_003)});
            const digits = amount catch @panic("allocation failed");
            defer gpa.free(digits);
            const row = std.fmt.allocPrint(gpa, "{d},\"{s}\",{s},{s},{s}\n", .{ seed + @as(i64, @intCast(j)), escaped, regions[(s + j) % 3], digits, if ((s + j) % 3 != 0) "1" else "0" }) catch @panic("allocation failed");
            defer gpa.free(row);
            document.appendSlice(gpa, row) catch @panic("allocation failed");
        }
        add(&d.texts, document.toOwnedSlice(gpa) catch @panic("allocation failed"));
    } else if (std.mem.eql(u8, kind, "json_transform")) {
        const Row = struct { id: i64, name: []const u8, amount: i64, active: bool };
        const rows = gpa.alloc(Row, size) catch @panic("allocation failed");
        defer gpa.free(rows);
        for (rows, 0..) |*row, j| row.* = .{ .id = seed + @as(i64, @intCast(j)), .name = rowName(j), .amount = @mod(seed + @as(i64, @intCast(j)) * 19, 100_003), .active = (s + j) % 3 != 0 };
        defer for (rows) |row| gpa.free(row.name);
        add(&d.texts, std.json.Stringify.valueAlloc(gpa, rows, .{}) catch @panic("serialize failed"));
    } else @panic("unknown case");
    return d;
}
fn wordJob(text: []const u8) i64 {
    var counts = std.StringHashMap(i64).init(gpa);
    defer counts.deinit();
    var iter = std.mem.tokenizeAny(u8, text, " \t\n\r");
    while (iter.next()) |word| {
        const entry = counts.getOrPut(word) catch @panic("allocation failed");
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;
    }
    var result: i64 = 0;
    var entries = counts.iterator();
    while (entries.next()) |entry| result += score(entry.key_ptr.*) * entry.value_ptr.* * entry.value_ptr.*;
    return result;
}
// Quote-aware fixture subset parser; arbitrary UTF-8 bytes are preserved.
fn csvRows(text: []const u8) [][]const []const u8 {
    var rows: std.ArrayList([]const []const u8) = .empty;
    var fields: std.ArrayList([]const u8) = .empty;
    var field: std.ArrayList(u8) = .empty;
    var quoted = false;
    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        const ch = text[index];
        if (quoted) {
            if (ch == '"') {
                if (index + 1 < text.len and text[index + 1] == '"') {
                    field.append(gpa, '"') catch @panic("allocation failed");
                    index += 1;
                } else {
                    quoted = false;
                }
            } else {
                field.append(gpa, ch) catch @panic("allocation failed");
            }
        } else {
            switch (ch) {
                '"' => quoted = true,
                ',' => fields.append(gpa, field.toOwnedSlice(gpa) catch @panic("allocation failed")) catch @panic("allocation failed"),
                '\n' => {
                    fields.append(gpa, field.toOwnedSlice(gpa) catch @panic("allocation failed")) catch @panic("allocation failed");
                    rows.append(gpa, fields.toOwnedSlice(gpa) catch @panic("allocation failed")) catch @panic("allocation failed");
                },
                else => field.append(gpa, ch) catch @panic("allocation failed"),
            }
        }
    }
    if (quoted or field.items.len != 0 or fields.items.len != 0) @panic("malformed CSV fixture");
    field.deinit(gpa);
    fields.deinit(gpa);
    return rows.toOwnedSlice(gpa) catch @panic("allocation failed");
}
fn csvJob(text: []const u8) i64 {
    const rows = csvRows(text);
    defer {
        for (rows) |row| {
            for (row) |field| gpa.free(field);
            gpa.free(row);
        }
        gpa.free(rows);
    }
    var groups = std.StringHashMap(i64).init(gpa);
    defer groups.deinit();
    groups.put("east", 0) catch @panic("allocation failed");
    groups.put("west", 0) catch @panic("allocation failed");
    groups.put("north", 0) catch @panic("allocation failed");
    var accepted: i64 = 0;
    var rejected: i64 = 0;
    var names: i64 = 0;
    for (rows) |row| {
        const amount = std.fmt.parseInt(i64, row[3], 10) catch {
            rejected += 1;
            continue;
        };
        if (std.mem.eql(u8, row[4], "1")) {
            groups.getPtr(row[2]).?.* += amount;
            accepted += 1;
            names += score(row[1]);
        }
    }
    return groups.get("east").? + groups.get("west").? * 2 + groups.get("north").? * 3 + accepted * 17 + rejected * 101 + names;
}
fn jsonJob(text: []const u8, bump: i64) i64 {
    const parsed = std.json.parseFromSlice(std.json.Value, gpa, text, .{}) catch @panic("parse failed");
    defer parsed.deinit();
    var output = std.json.Array.init(gpa);
    defer output.deinit();
    defer for (output.items) |*row| row.object.deinit(gpa);
    for (parsed.value.array.items) |row| {
        if (row.object.get("active").?.bool) {
            var fields: std.json.ObjectMap = .{};
            fields.put(gpa, "id", row.object.get("id").?) catch @panic("allocation failed");
            fields.put(gpa, "name", row.object.get("name").?) catch @panic("allocation failed");
            fields.put(gpa, "amount", .{ .integer = row.object.get("amount").?.integer + bump }) catch @panic("allocation failed");
            output.append(.{ .object = fields }) catch @panic("allocation failed");
        }
    }
    const encoded = std.json.Stringify.valueAlloc(gpa, std.json.Value{ .array = output }, .{}) catch @panic("serialize failed");
    defer gpa.free(encoded);
    return score(encoded);
}

fn bytesJob(raw: []const u8, mask: u8) i64 {
    var total: i64 = 0;
    for (raw) |value| total += value ^ mask;
    return total;
}
fn searchJob(text: []const u8, needle: []const u8) i64 {
    const index = std.mem.indexOf(u8, text, needle) orelse return 0;
    const count = std.unicode.utf8CountCodepoints(text[0..index]) catch @panic("invalid UTF-8");
    return @as(i64, @intCast(count)) + 1;
}
fn splitJob(text: []const u8, separator: []const u8) i64 {
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(gpa);
    var iter = std.mem.splitSequence(u8, text, separator);
    while (iter.next()) |part| parts.append(gpa, part) catch @panic("allocation failed");
    var result: i64 = @as(i64, @intCast(parts.items.len)) * 7;
    for (parts.items) |part| result += score(part);
    return result;
}
fn joinJob(parts: []const []const u8, separator: []const u8) i64 {
    const text = join(parts, separator);
    defer gpa.free(text);
    return score(text);
}
fn formatJob(n: i64) i64 {
    const text = std.fmt.allocPrint(gpa, "{d}", .{n}) catch @panic("allocation failed");
    defer gpa.free(text);
    return score(text);
}
fn kernel(kind: []const u8, d: *const Inputs, iterations: usize, seed: usize) i64 {
    var checksum: i64 = 0;
    if (std.mem.eql(u8, kind, "bytes_scan")) {
        for (0..iterations) |step| {
            const cursor = seed + step;
            const value = bytesJob(d.raw, @intCast(cursor % 256));
            checksum = @mod(checksum + value, modulus);
        }
    } else if (std.mem.eql(u8, kind, "string_equal")) {
        for (0..iterations) |step| {
            const cursor = seed + step;
            const value = @as(i64, @intFromBool(std.mem.eql(u8, d.texts.items[cursor % 4], d.other.items[cursor % 4])));
            checksum = @mod(checksum + value, modulus);
        }
    } else if (std.mem.eql(u8, kind, "string_search")) {
        for (0..iterations) |step| {
            const cursor = seed + step;
            const value = searchJob(d.texts.items[0], d.other.items[cursor % 4]);
            checksum = @mod(checksum + value, modulus);
        }
    } else if (std.mem.eql(u8, kind, "string_split")) {
        for (0..iterations) |step| {
            const cursor = seed + step;
            const value = splitJob(d.texts.items[cursor % 2], if (cursor % 2 == 0) "|" else "::");
            checksum = @mod(checksum + value, modulus);
        }
    } else if (std.mem.eql(u8, kind, "string_join")) {
        for (0..iterations) |step| {
            const cursor = seed + step;
            const value = joinJob(d.fragments, if (cursor % 2 == 0) "|" else "::");
            checksum = @mod(checksum + value, modulus);
        }
    } else if (std.mem.eql(u8, kind, "int_parse")) {
        for (0..iterations) |step| {
            const cursor = seed + step;
            const value = std.fmt.parseInt(i64, d.texts.items[cursor % d.texts.items.len], 10) catch 97;
            checksum = @mod(checksum + value, modulus);
        }
    } else if (std.mem.eql(u8, kind, "int_format")) {
        for (0..iterations) |step| {
            const cursor = seed + step;
            const value = formatJob(d.numbers[cursor % d.numbers.len]);
            checksum = @mod(checksum + value, modulus);
        }
    } else if (std.mem.eql(u8, kind, "word_count")) {
        for (0..iterations) |step| {
            const cursor = seed + step;
            const value = wordJob(d.texts.items[cursor % 2]);
            checksum = @mod(checksum + value, modulus);
        }
    } else if (std.mem.eql(u8, kind, "csv_aggregate")) {
        for (0..iterations) |_| {
            const value = csvJob(d.texts.items[0]);
            checksum = @mod(checksum + value, modulus);
        }
    } else if (std.mem.eql(u8, kind, "json_transform")) {
        for (0..iterations) |step| {
            const cursor = seed + step;
            const value = jsonJob(d.texts.items[0], @intCast(cursor % 17));
            checksum = @mod(checksum + value, modulus);
        }
    } else @panic("unknown case");
    return checksum;
}

/// Runs one text/bytes microbenchmark or native-library text application.
pub export fn main(argc: c_int, argv: [*][*:0]const u8) c_int {
    if (argc != 5) return 2;
    const kind = std.mem.span(argv[1]);
    var valid = false;
    for ([_][]const u8{ "bytes_scan", "string_equal", "string_search", "string_split", "string_join", "int_parse", "int_format", "word_count", "csv_aggregate", "json_transform" }) |entry| {
        if (std.mem.eql(u8, kind, entry)) valid = true;
    }
    if (!valid) return 2;
    const size = std.fmt.parseInt(usize, std.mem.span(argv[2]), 10) catch return 2;
    const iterations = std.fmt.parseInt(usize, std.mem.span(argv[3]), 10) catch return 2;
    const seed = std.fmt.parseInt(i64, std.mem.span(argv[4]), 10) catch return 2;
    if (size < 2 or iterations < 1 or seed < 1 or seed > 1_000_000) return 2;
    var d = fixtures(kind, size, seed);
    defer d.deinit();
    var checksum: i64 = 0;
    const start = now();
    checksum = kernel(kind, &d, iterations, @intCast(seed));
    const elapsed = now() - start;
    _ = printf("%lld %lld\n", @as(c_longlong, checksum), @as(c_longlong, elapsed));
    return 0;
}
