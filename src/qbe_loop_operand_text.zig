//! Whole-function, all-or-nothing isolation into existing write-only word slots.
const std = @import("std");
/// The source proof admits at most this many normalized operand positions.
pub const max_words = 8;
const max_slots = 4096;
/// Only this many existing planned loops may ask for optional isolation.
pub const max_regions = 32;
const max_text = 4 * 1024 * 1024;
const begin_marker = " # RC-LOOP-OPERANDS-BEGIN ";
const end_marker = " # RC-LOOP-OPERANDS-END ";
/// Optional refusal is unchanged text; only allocation failure propagates.
pub const Error = error{OutOfMemory};
const Region = struct { head: usize, back: usize, start: usize, end: usize };
const Regions = struct { items: [max_regions]Region = undefined, len: usize = 0 };
const Role = enum { definition, read, write, other };
const Slot = struct { definitions: usize = 0, refused: bool = false };
const Inventory = struct {
    slots: [max_slots]Slot = @splat(.{}),
    sources: [max_words]bool = @splat(false),
};
const Token = struct { start: usize, end: usize, quoted: bool = false, comment: bool = false };

/// Refusal preserves complete original text; no partial map is ever installed.
pub fn rewrite(a: std.mem.Allocator, input: []const u8) Error![]u8 {
    if (input.len > max_text) return a.dupe(u8, input);
    const regions = findRegions(input) orelse return a.dupe(u8, input);
    if (regions.len == 0) return a.dupe(u8, input);
    var inventory: Inventory = .{};
    if (!inspect(input, regions, &inventory)) return a.dupe(u8, input);
    const bank = choose(inventory) orelse return a.dupe(u8, input);
    var out: std.Io.Writer.Allocating = .init(a);
    errdefer out.deinit();
    var cursor: usize = 0;
    for (regions.items[0..regions.len]) |region| {
        out.writer.writeAll(input[cursor..region.start]) catch return error.OutOfMemory;
        out.writer.print(" # RC-LOOP-OPERANDS-ISOLATED {d}", .{region.head}) catch return error.OutOfMemory;
        for (bank, 0..) |target, source| if (target) |destination| {
            out.writer.print(" s{d}=s{d}", .{ source, destination }) catch return error.OutOfMemory;
        };
        out.writer.writeAll("\n") catch return error.OutOfMemory;
        try mapped(&out.writer, input[region.start..region.end], bank);
        cursor = region.end;
    }
    out.writer.writeAll(input[cursor..]) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

fn findRegions(input: []const u8) ?Regions {
    var result: Regions = .{};
    var active: ?Region = null;
    var lines = std.mem.splitScalar(u8, input, '\n');
    var offset: usize = 0;
    while (lines.next()) |line| {
        const next = offset + line.len + 1;
        if (std.mem.startsWith(u8, line, begin_marker)) {
            const pair = marker(line[begin_marker.len..]) orelse return null;
            if (active != null or result.len == max_regions or pair[0] > pair[1]) return null;
            if (!label(lineAt(input, next), "fi", pair[0])) return null;
            active = .{ .head = pair[0], .back = pair[1], .start = next, .end = 0 };
        } else if (std.mem.startsWith(u8, line, end_marker)) {
            const pair = marker(line[end_marker.len..]) orelse return null;
            var region = active orelse return null;
            if (pair[0] != region.head or pair[1] != region.back) return null;
            if (!label(lineAt(input, next), "oi", region.head)) return null;
            region.end = offset;
            result.items[result.len] = region;
            result.len += 1;
            active = null;
        }
        offset = next;
    }
    return if (active == null) result else null;
}
fn marker(value: []const u8) ?[2]usize {
    const space = std.mem.indexOfScalar(u8, value, ' ') orelse return null;
    return .{ number(value[0..space]) orelse return null, number(value[space + 1 ..]) orelse return null };
}
fn lineAt(input: []const u8, at: usize) []const u8 {
    if (at >= input.len) return "";
    return input[at .. std.mem.indexOfScalarPos(u8, input, at, '\n') orelse input.len];
}
fn label(line: []const u8, prefix: []const u8, pc: usize) bool {
    if (line.len < prefix.len + 2 or line[0] != '@' or !std.mem.startsWith(u8, line[1..], prefix)) return false;
    return (number(line[prefix.len + 1 ..]) orelse return false) == pc;
}

fn inspect(input: []const u8, regions: Regions, inventory: *Inventory) bool {
    var lines = std.mem.splitScalar(u8, input, '\n');
    var offset: usize = 0;
    while (lines.next()) |line| {
        const body = inside(regions, offset);
        if (body and !wordStores(line)) return false;
        var scan: Lexer = .{ .text = line };
        while (scan.next()) |token| {
            if (token.quoted) continue;
            const name = line[token.start + 1 .. token.end];
            if (line[token.start] == '@') {
                if (!token.comment and !entryAllowed(name, body, regions)) return false;
                continue;
            }
            if (body and privateStorage(name)) return false;
            const index = slot(name) orelse {
                if (name.len > 1 and name[0] == 's' and std.ascii.isDigit(name[1])) return false;
                continue;
            };
            if (index >= max_slots) return false;
            const role = if (token.comment) .other else use(line, token);
            switch (role) {
                .definition => inventory.slots[index].definitions += 1,
                .write => {},
                .read, .other => inventory.slots[index].refused = true,
            }
            if (body) {
                if (index >= max_words or (role != .read and role != .write)) return false;
                inventory.sources[index] = true;
            }
        }
        offset += line.len + 1;
    }
    return true;
}
fn inside(regions: Regions, offset: usize) bool {
    for (regions.items[0..regions.len]) |region| if (offset >= region.start and offset < region.end) return true;
    return false;
}
fn entryAllowed(name: []const u8, body: bool, regions: Regions) bool {
    if (body or !std.mem.startsWith(u8, name, "fi")) return true;
    const pc = number(name[2..]) orelse return true;
    for (regions.items[0..regions.len]) |region| if (pc > region.head and pc <= region.back) return false;
    return true;
}
fn privateStorage(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "rc") or std.mem.startsWith(u8, name, "cowscope") or
        std.mem.startsWith(u8, name, "root") or std.mem.startsWith(u8, name, "agg") or
        std.mem.startsWith(u8, name, "aux") or std.mem.startsWith(u8, name, "rs") or
        std.mem.eql(u8, name, "arguments") or std.mem.eql(u8, name, "scratch");
}
fn wordStores(line: []const u8) bool {
    const value = std.mem.trim(u8, line, " \t");
    if (std.mem.startsWith(u8, value, "blit ")) return false;
    if (!std.mem.startsWith(u8, value, "store")) return true;
    if (!std.mem.startsWith(u8, value, "storel ")) return false;
    const comma = std.mem.indexOf(u8, value, ", ") orelse return false;
    const destination = value[comma + 2 ..];
    if (std.mem.eql(u8, destination, "%position")) return true;
    if (destination.len < 3 or destination[0] != '%') return false;
    if (destination[1] != 's' and destination[1] != 'l') return false;
    return number(destination[2..]) != null;
}
fn use(line: []const u8, token: Token) Role {
    const before = std.mem.trim(u8, line[0..token.start], " \t");
    const after = std.mem.trim(u8, line[token.end..], " \t");
    if (before.len == 0 and std.mem.eql(u8, after, "=l alloc8 8")) return .definition;
    if (after.len != 0) return .other;
    if (std.mem.startsWith(u8, before, "%v") and std.mem.endsWith(u8, before, " =l loadl")) return .read;
    if (std.mem.startsWith(u8, before, "storel ") and std.mem.endsWith(u8, before, ",")) return .write;
    return .other;
}
fn choose(inventory: Inventory) ?[max_words]?usize {
    var bank: [max_words]?usize = @splat(null);
    var next: usize = 0;
    var used = false;
    for (inventory.sources, 0..) |needed, source| {
        if (!needed) continue;
        used = true;
        while (next < max_slots) : (next += 1) {
            if (next < max_words and inventory.sources[next]) continue;
            const candidate = inventory.slots[next];
            if (candidate.definitions != 1 or candidate.refused) continue;
            bank[source] = next;
            next += 1;
            break;
        }
        if (bank[source] == null) return null;
    }
    return if (used) bank else null;
}

fn mapped(writer: *std.Io.Writer, input: []const u8, bank: [max_words]?usize) Error!void {
    var cursor: usize = 0;
    var lines = std.mem.splitScalar(u8, input, '\n');
    var offset: usize = 0;
    while (lines.next()) |line| {
        var scan: Lexer = .{ .text = line };
        while (scan.next()) |token| {
            if (token.quoted or token.comment or line[token.start] != '%') continue;
            const index = slot(line[token.start + 1 .. token.end]) orelse continue;
            const target = bank[index].?;
            writer.writeAll(input[cursor .. offset + token.start]) catch return error.OutOfMemory;
            writer.print("%s{d}", .{target}) catch return error.OutOfMemory;
            cursor = offset + token.end;
        }
        offset += line.len + 1;
    }
    writer.writeAll(input[cursor..]) catch return error.OutOfMemory;
}
fn slot(name: []const u8) ?usize {
    if (name.len < 2 or name[0] != 's') return null;
    return number(name[1..]);
}
fn number(value: []const u8) ?usize {
    if (value.len == 0) return null;
    if (value.len > 1 and value[0] == '0') return null;
    for (value) |byte| if (!std.ascii.isDigit(byte)) return null;
    return std.fmt.parseInt(usize, value, 10) catch null;
}
const Lexer = struct {
    text: []const u8,
    cursor: usize = 0,
    quoted: bool = false,
    comment: bool = false,

    fn next(self: *Lexer) ?Token {
        while (self.cursor < self.text.len) {
            const at = self.cursor;
            const byte = self.text[at];
            self.cursor += 1;
            if (self.quoted and byte == '\\' and self.cursor < self.text.len) {
                self.cursor += 1;
                continue;
            }
            if (!self.comment and byte == '"') self.quoted = !self.quoted;
            if (!self.quoted and byte == '#') self.comment = true;
            if (byte != '%' and byte != '@') continue;
            while (self.cursor < self.text.len and nameByte(self.text[self.cursor])) self.cursor += 1;
            return .{ .start = at, .end = self.cursor, .quoted = self.quoted, .comment = self.comment };
        }
        return null;
    }
};
fn nameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '.' or byte == '$';
}
