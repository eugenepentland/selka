//! Full semantic checking over relocated module syntax and explicit namespaces.
const interfaces = @import("interfaces.zig");
const syntax = @import("project_syntax.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const Names = @import("module_names.zig").Names;
pub const Compilation = struct {
    index: *interfaces.Index,
    src: source.Source,
    syntax: @import("ast.zig").Program,
    diagnostics: diagnostic.Sink,
    program: ?typed.Program = null,
    code: ?@import("bytecode.zig").Program = null,
    pub fn init(index: *interfaces.Index) !Compilation {
        const merged = try syntax.build(index);
        return .{ .index = index, .src = merged.src, .syntax = merged.syntax, .diagnostics = .{ .allocator = index.project.arena.allocator() } };
    }
    pub fn check(self: *Compilation) !void {
        if (self.program != null) return;
        var names: Names = .{ .index = self.index, .src = self.src };
        self.program = try @import("sema.zig").checkWithNames(self.index.project.arena.allocator(), self.src, self.syntax, &self.diagnostics, &names);
    }
    pub fn exportRoots(self: *Compilation, allocator: @import("std").mem.Allocator) ![]typed.FunctionId {
        try self.check();
        var roots: @import("std").ArrayList(typed.FunctionId) = .empty;
        errdefer roots.deinit(allocator);
        for (self.program.?.functions) |function| {
            const original = self.src.originalSpan(function.declaration) catch unreachable;
            const unit = self.index.units[original.input];
            const prefix_len = self.index.project.modules.items[original.input].name.len + 2;
            const symbol = unit.symbols.items[unit.names.get(function.name[prefix_len..]).?];
            if (symbol.exported) try roots.append(allocator, function.id);
        }
        return roots.toOwnedSlice(allocator);
    }
    pub fn emit(self: *Compilation) !void {
        try self.check();
        if (self.code == null) self.code = try @import("lower.zig").lower(self.index.project.arena.allocator(), self.program.?);
    }
};
