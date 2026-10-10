//! Native bounded archive extraction; links are created only after regular files.
const std = @import("std");
const Link = struct { name: []const u8, target: []const u8 };

fn validateName(name: []const u8) !void {
    if (name.len == 0 or std.fs.path.isAbsolute(name)) return error.UnsafeSeedArchive;
    const normalized = std.mem.trimEnd(u8, name, "/");
    if (normalized.len == 0) return error.UnsafeSeedArchive;
    var segments = std.mem.splitScalar(u8, normalized, '/');
    while (segments.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return error.UnsafeSeedArchive;
    }
}

// Only leading parent steps are supported. A parent step after an ordinary
// target component could escape through another archive symlink despite lexical
// normalization (for example d -> ".", followed by d/../outside).
fn validateTarget(target: []const u8) !void {
    if (target.len == 0 or std.fs.path.isAbsolute(target)) return error.UnsafeSeedArchive;
    var ordinary = false;
    var segments = std.mem.splitScalar(u8, target, '/');
    while (segments.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) return error.UnsafeSeedArchive;
        if (std.mem.eql(u8, part, "..")) {
            if (ordinary) return error.UnsafeSeedArchive;
        } else ordinary = true;
    }
}

/// Stream regular files first; no tar entry can write through an archive symlink.
pub fn extract(io: std.Io, archive: []const u8, destination: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const dir = try std.Io.Dir.cwd().openDir(io, destination, .{});
    defer dir.close(io);
    const file = try std.Io.Dir.cwd().openFile(io, archive, .{});
    defer file.close(io);
    var read_buffer: [65536]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    var name_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var link_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var iterator = std.tar.Iterator.init(&reader.interface, .{ .file_name_buffer = &name_buffer, .link_name_buffer = &link_buffer });
    var links: std.ArrayList(Link) = .empty;
    while (try iterator.next()) |entry| {
        try validateName(entry.name);
        switch (entry.kind) {
            .directory => try dir.createDirPath(io, entry.name),
            .file => {
                if (std.fs.path.dirname(entry.name)) |parent| try dir.createDirPath(io, parent);
                const output = try dir.createFile(io, entry.name, .{ .exclusive = true, .permissions = .fromMode(if ((entry.mode & 0o100) != 0) 0o755 else 0o644) });
                defer output.close(io);
                var write_buffer: [65536]u8 = undefined;
                var writer = output.writer(io, &write_buffer);
                try iterator.streamRemaining(entry, &writer.interface);
                try writer.interface.flush();
            },
            .sym_link => {
                try validateTarget(entry.link_name);
                const parent = std.fs.path.dirname(entry.name) orelse "";
                const resolved = try std.fs.path.resolve(a, &.{ destination, parent, entry.link_name });
                if (!std.mem.startsWith(u8, resolved, destination) or resolved.len <= destination.len or resolved[destination.len] != '/') return error.UnsafeSeedArchive;
                try links.append(a, .{ .name = try a.dupe(u8, entry.name), .target = try a.dupe(u8, entry.link_name) });
            },
        }
    }
    for (links.items) |link| {
        // A later link cannot traverse a link created earlier in this loop.
        for (links.items) |other| {
            if (std.mem.startsWith(u8, link.name, other.name) and link.name.len > other.name.len and link.name[other.name.len] == '/') return error.UnsafeSeedArchive;
        }
        if (std.fs.path.dirname(link.name)) |parent| try dir.createDirPath(io, parent);
        try dir.symLink(io, link.target, link.name, .{});
    }
}
