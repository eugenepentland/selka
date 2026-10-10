//! Exact production AST oracle and independent validator for SLKAST01 replies.
const std = @import("std");
const parser = @import("src/parser.zig");
const lexer = @import("src/lexer.zig");
const source = @import("src/source.zig");
const diagnostic = @import("src/diagnostic.zig");
const wire = @import("src/parser_value.zig");
extern "c" fn getenv([*:0]const u8) ?[*:0]const u8;
extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;
extern "c" fn fread([*]u8, usize, usize, *anyopaque) usize;
extern "c" fn fwrite([*]const u8, usize, usize, *anyopaque) usize;
extern "c" fn fclose(*anyopaque) c_int;
extern "c" fn printf([*:0]const u8, ...) c_int;
extern "c" var stdout: *anyopaque;

fn read(a: std.mem.Allocator, path: [*:0]const u8, limit: usize) ![]const u8 {
    const file = fopen(path, "rb") orelse return error.Open;
    defer _ = fclose(file);
    const data = try a.alloc(u8, limit + 1);
    const size = fread(data.ptr, 1, data.len, file);
    if (size > limit) return error.SizeLimit;
    return data[0..size];
}

/// PILOT_SOURCE selects source; PILOT_REPLY selects validation instead of parsing.
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = getenv("PILOT_SOURCE") orelse return error.NoSource;
    const bytes = try read(a, path, 1048576);
    if (getenv("PILOT_REPLY")) |reply_path| {
        const reply = try read(a, reply_path, wire.value_wire_limit);
        const encoded = if (std.mem.startsWith(u8, reply, "SLKERR01")) errors: {
            var decoded = try wire.decodeErrors(a, reply, bytes.len);
            defer decoded.deinit();
            break :errors try wire.encodeReport(a, decoded.report);
        } else syntax: {
            var decoded = try wire.decode(a, reply, bytes.len);
            defer decoded.deinit();
            break :syntax try wire.encode(a, decoded.program);
        };
        if (fwrite(encoded.ptr, 1, encoded.len, stdout) != encoded.len) return error.Write;
        return;
    }
    var src = try source.Source.init(a, std.mem.span(path), bytes);
    src.trusted_intrinsics = getenv("PILOT_TRUSTED") != null;
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    if (getenv("PILOT_TOKENS") != null) {
        _ = printf("%zu\n", bytes.len);
        for (tokens) |token| _ = printf("%s %zu %zu\n", @tagName(token.tag).ptr, token.span.start, token.span.end);
        return;
    }
    var p: parser.Parser = .{ .src = src, .storage = a, .tokens = tokens, .sink = &sink };
    const result = if (getenv("PILOT_MODULE") != null) p.parseModule() else p.parse();
    const program = result catch {
        const encoded = try wire.encodeErrors(a, sink.items.items);
        if (fwrite(encoded.ptr, 1, encoded.len, stdout) != encoded.len) return error.Write;
        return;
    };
    const encoded = try wire.encode(a, program);
    if (fwrite(encoded.ptr, 1, encoded.len, stdout) != encoded.len) return error.Write;
}
