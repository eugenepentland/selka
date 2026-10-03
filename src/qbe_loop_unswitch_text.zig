//! Clone closed original QBE CFGs, folding only bytecode-certified dispatch.
const std = @import("std");
const proof = @import("qbe_loop_unswitch_model.zig");
/// Only allocation failure escapes an optional optimization.
pub const Error = error{OutOfMemory};
const max_text = 4 * 1024 * 1024;
const max_region = 256 * 1024;
const max_added = 256 * 1024;
const max_blocks = 8192;
const marker = " # QBE-LOOP-UNSWITCH-1 ";
const Block = struct { name: []const u8, start: usize, end: usize, last: []const u8 };
const Graph = struct { blocks: []const Block, labels: std.StringHashMapUnmanaged(usize) };
const Region = struct { start: usize, end: usize };
const Branch = union(enum) { none, stop, one: []const u8, two: [2][]const u8 };

/// Refusal returns an owned identical copy; no partial specialization is installed.
pub fn rewrite(a: std.mem.Allocator, input: []const u8, certificate: proof.Certificate) Error![]u8 {
    if (input.len > max_text or std.mem.indexOf(u8, input, marker) != null) return a.dupe(u8, input);
    const region = try findRegion(a, input, certificate) orelse return a.dupe(u8, input);
    if (region.end - region.start > max_region) return a.dupe(u8, input);
    const body = input[region.start..region.end];
    var graph = try parse(a, body) orelse return a.dupe(u8, input);
    defer {
        a.free(graph.blocks);
        graph.labels.deinit(a);
    }
    if (!closed(input, region, graph)) return a.dupe(u8, input);
    var copies: std.Io.Writer.Allocating = .init(a);
    defer copies.deinit();
    for (certificate.values.items[0..certificate.values.len], 0..) |value, ordinal| {
        const reachable = try reach(a, graph, certificate, value) orelse return a.dupe(u8, input);
        defer a.free(reachable);
        const prefix = try std.fmt.allocPrint(a, "us{d}_{d}_", .{ certificate.head, ordinal });
        defer a.free(prefix);
        for (graph.blocks, reachable) |block, live| {
            if (!live) continue;
            try copied(&copies.writer, body[block.start..block.end], graph, prefix, forced(block, certificate, value));
        }
        const function_room = @max(4096, input.len / 2);
        const allowed = @min(max_added, @min(function_room, body.len * 2));
        if (copies.writer.end > allowed) return a.dupe(u8, input);
    }
    var out: std.Io.Writer.Allocating = .init(a);
    errdefer out.deinit();
    out.writer.writeAll(input[0..region.start]) catch return error.OutOfMemory;
    out.writer.print("{s}{d} literals={d} copied-bytes={d}\n@i{d}\n", .{ marker, certificate.head, certificate.values.len, copies.writer.end, certificate.head }) catch return error.OutOfMemory;
    out.writer.print(" %usk{d} =l loadl %l{d}\n", .{ certificate.head, certificate.slot }) catch return error.OutOfMemory;
    for (certificate.values.items[0..certificate.values.len], 0..) |value, ordinal| {
        out.writer.print(" %usflag{d}_{d} =l ceql %usk{d}, {d}\n", .{ certificate.head, ordinal, certificate.head, value }) catch return error.OutOfMemory;
        out.writer.print(" jnz %usflag{d}_{d}, @us{d}_{d}_i{d}, @usguard{d}_{d}\n", .{ certificate.head, ordinal, certificate.head, ordinal, certificate.head, certificate.head, ordinal }) catch return error.OutOfMemory;
        out.writer.print("@usguard{d}_{d}\n", .{ certificate.head, ordinal }) catch return error.OutOfMemory;
    }
    out.writer.print(" jmp @us{d}_original_i{d}\n", .{ certificate.head, certificate.head }) catch return error.OutOfMemory;
    const original = try std.fmt.allocPrint(a, "us{d}_original_", .{certificate.head});
    defer a.free(original);
    try copied(&out.writer, body, graph, original, null);
    out.writer.writeAll(copies.written()) catch return error.OutOfMemory;
    out.writer.writeAll(input[region.end..]) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

fn findRegion(a: std.mem.Allocator, input: []const u8, certificate: proof.Certificate) Error!?Region {
    const first = try std.fmt.allocPrint(a, "\n@i{d}\n", .{certificate.head});
    defer a.free(first);
    const last = try std.fmt.allocPrint(a, "\n@i{d}\n", .{certificate.back + 1});
    defer a.free(last);
    const start = (std.mem.indexOf(u8, input, first) orelse return null) + 1;
    const end = (std.mem.indexOfPos(u8, input, start + first.len, last) orelse return null) + 1;
    if (std.mem.indexOfPos(u8, input, end, first) != null) return null;
    return .{ .start = start, .end = end };
}

fn parse(a: std.mem.Allocator, body: []const u8) Error!?Graph {
    var blocks: std.ArrayList(Block) = .empty;
    defer blocks.deinit(a);
    var labels: std.StringHashMapUnmanaged(usize) = .empty;
    var keep = false;
    defer if (!keep) labels.deinit(a);
    var lines = std.mem.splitScalar(u8, body, '\n');
    var offset: usize = 0;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "@")) {
            const name = trimmed[1..];
            if (name.len == 0 or blocks.items.len == max_blocks or labels.contains(name)) return null;
            for (name) |character| if (!nameCharacter(character)) return null;
            if (blocks.items.len != 0) blocks.items[blocks.items.len - 1].end = offset;
            try labels.put(a, name, blocks.items.len);
            try blocks.append(a, .{ .name = name, .start = offset, .end = body.len, .last = "" });
        } else if (trimmed.len != 0 and trimmed[0] != '#') {
            if (blocks.items.len == 0 or std.mem.indexOf(u8, trimmed, " phi ") != null) return null;
            blocks.items[blocks.items.len - 1].last = line;
        }
        offset += line.len + 1;
    }
    if (blocks.items.len == 0) return null;
    const result = try blocks.toOwnedSlice(a);
    keep = true;
    return .{ .blocks = result, .labels = labels };
}

/// Every native external entry must be the original loop header.
fn closed(input: []const u8, region: Region, graph: Graph) bool {
    for ([_][]const u8{ input[0..region.start], input[region.end..] }) |outside| {
        var lines = std.mem.splitScalar(u8, outside, '\n');
        while (lines.next()) |line| {
            var scan: Labels = .{ .line = line };
            while (scan.next()) |label| {
                const index = graph.labels.get(label.name) orelse continue;
                if (index != 0) return false;
            }
        }
    }
    return true;
}

fn reach(a: std.mem.Allocator, graph: Graph, certificate: proof.Certificate, value: i64) Error!?[]bool {
    const live = try a.alloc(bool, graph.blocks.len);
    var keep = false;
    defer if (!keep) a.free(live);
    @memset(live, false);
    const queue = try a.alloc(usize, graph.blocks.len);
    defer a.free(queue);
    var count: usize = 1;
    var cursor: usize = 0;
    queue[0] = 0;
    live[0] = true;
    while (cursor < count) : (cursor += 1) {
        const index = queue[cursor];
        const block = graph.blocks[index];
        const terminal = if (forced(block, certificate, value)) |target| Branch{ .one = target } else branch(block.last) orelse return null;
        switch (terminal) {
            .stop => {},
            .none => {
                if (index + 1 == graph.blocks.len) return null;
                add(index + 1, live, queue, &count);
            },
            .one => |target| if (graph.labels.get(target)) |next| add(next, live, queue, &count),
            .two => |pair| for (pair) |target| {
                if (graph.labels.get(target)) |next| add(next, live, queue, &count);
            },
        }
    }
    keep = true;
    return live;
}
fn add(index: usize, live: []bool, queue: []usize, count: *usize) void {
    if (live[index]) return;
    live[index] = true;
    queue[count.*] = index;
    count.* += 1;
}

fn branch(line: []const u8) ?Branch {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (std.mem.startsWith(u8, trimmed, "ret ") or std.mem.eql(u8, trimmed, "ret") or std.mem.eql(u8, trimmed, "hlt")) return .stop;
    if (std.mem.startsWith(u8, trimmed, "jmp ")) {
        const target = std.mem.trim(u8, trimmed[4..], " \t");
        return if (target.len > 1 and target[0] == '@') .{ .one = target[1..] } else null;
    }
    if (std.mem.startsWith(u8, trimmed, "jnz ")) {
        var pieces = std.mem.splitScalar(u8, trimmed[4..], ',');
        _ = pieces.next() orelse return null;
        const first = std.mem.trim(u8, pieces.next() orelse return null, " \t");
        const second = std.mem.trim(u8, pieces.next() orelse return null, " \t");
        if (pieces.next() != null or first.len < 2 or second.len < 2) return null;
        if (first[0] != '@' or second[0] != '@') return null;
        return .{ .two = .{ first[1..], second[1..] } };
    }
    return .none;
}

fn forced(block: Block, certificate: proof.Certificate, value: i64) ?[]const u8 {
    const pc = instructionPc(block.name) orelse return null;
    for (certificate.conditions.items[0..certificate.conditions.len]) |condition| {
        if (condition.pc != pc) continue;
        const terminal = branch(block.last) orelse return null;
        if (terminal != .two or instructionPc(terminal.two[1]) != condition.target) return null;
        const yes = switch (condition.predicate) {
            .eq => value == condition.value,
            .ne => value != condition.value,
            .lt => value < condition.value,
            .le => value <= condition.value,
            .gt => value > condition.value,
            .ge => value >= condition.value,
        };
        return terminal.two[if (yes) 0 else 1];
    }
    return null;
}
fn instructionPc(name: []const u8) ?usize {
    const prefix: usize = if (std.mem.startsWith(u8, name, "fi")) 2 else if (std.mem.startsWith(u8, name, "ce")) 2 else if (std.mem.startsWith(u8, name, "i")) 1 else return null;
    if (name.len == prefix) return null;
    return std.fmt.parseInt(usize, name[prefix..], 10) catch null;
}

fn copied(out: *std.Io.Writer, body: []const u8, graph: Graph, prefix: []const u8, force: ?[]const u8) Error!void {
    var lines = std.mem.splitScalar(u8, body, '\n');
    var last: ?[]const u8 = null;
    if (force != null) {
        var scan = lines;
        while (scan.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len != 0 and trimmed[0] != '#') last = line;
        }
    }
    while (lines.next()) |line| {
        if (line.len == 0 and lines.index == null) break;
        if (force != null and last != null and line.ptr == last.?.ptr) {
            out.writeAll(" jmp @") catch return error.OutOfMemory;
            if (graph.labels.contains(force.?)) out.writeAll(prefix) catch return error.OutOfMemory;
            out.print("{s}\n", .{force.?}) catch return error.OutOfMemory;
            continue;
        }
        var cursor: usize = 0;
        var labels: Labels = .{ .line = line };
        while (labels.next()) |label| {
            if (!graph.labels.contains(label.name)) continue;
            out.writeAll(line[cursor .. label.start + 1]) catch return error.OutOfMemory;
            out.writeAll(prefix) catch return error.OutOfMemory;
            cursor = label.start + 1;
        }
        out.print("{s}\n", .{line[cursor..]}) catch return error.OutOfMemory;
    }
}

const Label = struct { name: []const u8, start: usize };
const Labels = struct {
    line: []const u8,
    cursor: usize = 0,
    fn next(self: *Labels) ?Label {
        while (self.cursor < self.line.len) {
            const start = self.cursor;
            const character = self.line[self.cursor];
            self.cursor += 1;
            if (character == '#') return null;
            if (character == '"') {
                while (self.cursor < self.line.len) {
                    const quoted = self.line[self.cursor];
                    self.cursor += 1;
                    if (quoted == '\\' and self.cursor < self.line.len) self.cursor += 1 else if (quoted == '"') break;
                }
            } else if (character == '@') {
                const name = self.cursor;
                while (self.cursor < self.line.len and nameCharacter(self.line[self.cursor])) self.cursor += 1;
                return .{ .name = self.line[name..self.cursor], .start = start };
            }
        }
        return null;
    }
};
fn nameCharacter(character: u8) bool {
    return std.ascii.isAlphanumeric(character) or character == '_' or character == '.';
}
