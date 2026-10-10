//! Standalone projection of the unchanged production parser AST.
const std = @import("std");
const parser = @import("src/parser.zig");
const lexer = @import("src/lexer.zig");
const ast = @import("src/ast.zig");
const source = @import("src/source.zig");
const diagnostic = @import("src/diagnostic.zig");
extern "c" fn getenv([*:0]const u8) ?[*:0]const u8;
extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;
extern "c" fn fread([*]u8, usize, usize, *anyopaque) usize;
extern "c" fn fclose(*anyopaque) c_int;
extern "c" fn printf([*:0]const u8, ...) c_int;
var next_id: usize = 0;
fn emit(kind: []const u8, start: usize, end: usize, children: []const usize) usize {
    const id = next_id;
    next_id += 1;
    _ = printf("%.*s %zu %zu", @as(c_int, @intCast(kind.len)), kind.ptr, start, end);
    for (children) |child| _ = printf(" %zu", child);
    _ = printf("\n");
    return id;
}
fn expr(p: ast.Program, id: ast.NodeId) usize {
    const n = p.nodes.items[@backingInt(id)];
    return switch (n.data) {
        .integer => emit("integer", n.span.start, n.span.end, &.{}),
        .name => emit("name", n.span.start, n.span.end, &.{}),
        .boolean => |b| emit(if (b) "true" else "false", n.span.start, n.span.end, &.{}),
        .binary => |b| blk: {
            const left = expr(p, b.left);
            const right = expr(p, b.right);
            break :blk emit(@tagName(b.op), n.span.start, n.span.end, &.{ left, right });
        },
        .unary => |u| blk: {
            const child = expr(p, u.operand);
            break :blk emit(@tagName(u.op), n.span.start, n.span.end, &.{child});
        },
        .call => |c| blk: {
            var children: [4096]usize = undefined;
            children[0] = emit("name", c.name.start, c.name.end, &.{});
            for (c.arguments, 1..) |arg, i| children[i] = expr(p, arg);
            break :blk emit("call", n.span.start, n.span.end, children[0 .. c.arguments.len + 1]);
        },
        else => @panic("unsupported oracle expression"),
    };
}
fn stmt(p: ast.Program, id: ast.StatementId) usize {
    const s = p.statements.items[@backingInt(id)];
    return switch (s.data) {
        .ret => |r| blk: {
            const child = expr(p, r);
            break :blk emit("return", s.span.start, s.span.end, &.{child});
        },
        .binding => |b| blk: {
            var children: [3]usize = undefined;
            children[0] = emit("name", b.name.start, b.name.end, &.{});
            var count: usize = 1;
            if (b.annotation) |a| {
                children[count] = emit("type", a.start, a.end, &.{});
                count += 1;
            }
            children[count] = expr(p, b.value);
            count += 1;
            break :blk emit(if (b.mutable) "mut" else "const", s.span.start, s.span.end, children[0..count]);
        },
        .block => |body| blk: {
            var children: [4096]usize = undefined;
            for (body, 0..) |child, i| children[i] = stmt(p, child);
            const first = p.statements.items[@backingInt(body[0])];
            const last = p.statements.items[@backingInt(body[body.len - 1])];
            break :blk emit("block", first.span.start, last.span.end, children[0..body.len]);
        },
        else => @panic("unsupported oracle statement"),
    };
}
pub fn main() !void {
    const path = getenv("PILOT_SOURCE") orelse return error.NoSource;
    const file = fopen(path, "rb") orelse return error.Open;
    defer _ = fclose(file);
    var buffer: [1048577]u8 = undefined;
    const size = fread(&buffer, 1, buffer.len, file);
    if (size > 1048576) return error.SourceLimit;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "fixture.my", buffer[0..size]);
    var sink = diagnostic.Sink{ .allocator = a };
    const tokens = lexer.lex(a, src.bytes, &sink) catch return error.Lexical;
    if (getenv("PILOT_TOKENS") != null) {
        _ = printf("%zu\n", size);
        for (tokens) |t| _ = printf("%s %zu %zu\n", @tagName(t.tag).ptr, t.span.start, t.span.end);
        return;
    }
    var reader = parser.Parser{ .src = src, .storage = a, .tokens = tokens, .sink = &sink };
    const program = reader.parse() catch {
        for (sink.items.items) |d| _ = printf("error %.*s %zu %zu\n", @as(c_int, @intCast(d.code.len)), d.code.ptr, d.span.start, d.span.end);
        return;
    };
    var functions: [4096]usize = undefined;
    for (program.functions, 0..) |f, i| {
        const name = emit("name", f.name.start, f.name.end, &.{});
        const ty = emit("type", f.signature.return_type.start, f.signature.return_type.end, &.{});
        const body = stmt(program, f.body);
        const block = program.statements.items[@backingInt(f.body)].data.block;
        const last = program.statements.items[@backingInt(block[block.len - 1])];
        functions[i] = emit("function", f.name.start, last.span.end, &.{ name, ty, body });
    }
    _ = emit("program", 0, size, functions[0..program.functions.len]);
}
