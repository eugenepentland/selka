//! One request owns source, syntax, semantic nodes, and lowered instructions.
const std = @import("std");
pub const source = @import("source.zig");
pub const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const sema = @import("sema.zig");
const lower = @import("lower.zig");
pub const bytecode = @import("bytecode.zig");
pub const duplicates = @import("duplicates.zig");
pub const vm = @import("vm.zig");
const disassemble = @import("disassemble.zig");

pub const Compilation = struct {
    arena: std.heap.ArenaAllocator,
    src: source.Source,
    diagnostics: std.ArrayList(diagnostic.Diagnostic) = .empty,
    syntax: ?ast.Program = null,
    program: ?typed.Program = null,
    code: ?bytecode.Program = null,

    pub fn init(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !Compilation {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const src = try source.Source.init(arena.allocator(), path, bytes);
        return .{ .arena = arena, .src = src };
    }

    pub fn deinit(self: *Compilation) void {
        self.arena.deinit();
    }

    pub fn check(self: *Compilation) diagnostic.Error!void {
        if (self.program != null) return;
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        const tokens = try lexer.lex(sink.allocator, self.src.bytes, &sink);
        var p: parser.Parser = .{ .allocator = sink.allocator, .tokens = tokens, .sink = &sink };
        self.syntax = try p.parse();
        self.program = try sema.check(sink.allocator, self.src, self.syntax.?, &sink);
    }

    pub fn emit(self: *Compilation) !void {
        try self.check();
        if (self.code == null) self.code = try lower.lower(self.arena.allocator(), self.program.?);
    }

    pub fn execute(self: *Compilation, allocator: std.mem.Allocator) !vm.Result {
        return self.executeWithOptions(allocator, .{});
    }

    pub fn executeWithOptions(self: *Compilation, allocator: std.mem.Allocator, options: vm.Options) !vm.Result {
        try self.emit();
        return vm.runWithOptions(allocator, self.code.?, options);
    }

    pub fn dump(self: *Compilation, allocator: std.mem.Allocator) ![]u8 {
        try self.emit();
        return disassemble.dump(allocator, self.code.?, self.src);
    }
};

test {
    _ = @import("compiler_test.zig");
    _ = @import("duplicates_test.zig");
    _ = @import("value_test.zig");
}
