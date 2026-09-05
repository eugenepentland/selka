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
pub const quality = @import("quality.zig");
pub const duplicates = @import("duplicates.zig");
pub const vm = @import("vm.zig");
const disassemble = @import("disassemble.zig");

pub const Compilation = struct {
    arena: std.heap.ArenaAllocator,
    src: source.Source,
    diagnostics: std.ArrayList(diagnostic.Diagnostic) = .empty,
    tokens: ?[]const lexer.Token = null,
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

    pub fn parse(self: *Compilation) diagnostic.Error!void {
        if (self.syntax != null) return;
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        self.tokens = try lexer.lex(sink.allocator, self.src.bytes, &sink);
        var p: parser.Parser = .{ .src = self.src, .allocator = sink.allocator, .tokens = self.tokens.?, .sink = &sink };
        self.syntax = try p.parse();
    }

    pub fn format(self: *Compilation, allocator: std.mem.Allocator) ![]u8 {
        try self.parse();
        return @import("formatter.zig").format(allocator, self.src.bytes, self.tokens.?);
    }

    pub fn check(self: *Compilation) diagnostic.Error!void {
        if (self.program != null) return;
        try self.parse();
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
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

    pub fn emitC(self: *Compilation, allocator: std.mem.Allocator) ![]u8 {
        try self.emit();
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        return @import("native.zig").generate(allocator, self.code.?, self.src, &sink);
    }

    pub fn dump(self: *Compilation, allocator: std.mem.Allocator) ![]u8 {
        try self.emit();
        return disassemble.dump(allocator, self.code.?, self.src);
    }
};

test {
    _ = @import("compiler_test.zig");
    _ = @import("duplicates_test.zig");
    _ = @import("near_duplicates_test.zig");
    _ = @import("quality_test.zig");
    _ = @import("formatter_test.zig");
    _ = @import("native_test.zig");
    _ = @import("partial_fields_test.zig");
    _ = @import("value_test.zig");
    _ = @import("records_test.zig");
    _ = @import("integers_test.zig");
    _ = @import("arrays_test.zig");
    _ = @import("domains_test.zig");
    _ = @import("variants_test.zig");
    _ = @import("tables_test.zig");
    _ = @import("memory_test.zig");
    _ = @import("owned_scope_test.zig");
    _ = @import("buffers_test.zig");
    _ = @import("pools_test.zig");
    _ = @import("regions_test.zig");
    _ = @import("arena_source_test.zig");
    _ = @import("effects_test.zig");
    _ = @import("allocator_capabilities_test.zig");
    _ = @import("external_capabilities_test.zig");
    _ = @import("external_resources_test.zig");
    _ = @import("resource_source_test.zig");
    _ = @import("field_reads_test.zig");
    _ = @import("environment_test.zig");
    _ = @import("resource_io_test.zig");
    _ = @import("attenuation_test.zig");
    _ = @import("resource_slice_test.zig");
    _ = @import("typed_pool_test.zig");
    _ = @import("arena_test.zig");
    _ = @import("arena_execution_test.zig");
    _ = @import("references_test.zig");
    _ = @import("slices_test.zig");
    _ = @import("returned_references_test.zig");
    _ = @import("results_test.zig");
    _ = @import("propagation_test.zig");
}
