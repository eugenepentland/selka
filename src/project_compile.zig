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
    pub fn emitC(self: *Compilation, allocator: @import("std").mem.Allocator) ![]u8 {
        try self.emit();
        return @import("native.zig").generate(allocator, self.code.?, self.src, &self.diagnostics);
    }
    pub fn exportRoots(self: *Compilation, allocator: @import("std").mem.Allocator) ![]typed.FunctionId {
        try self.check();
        var roots: @import("std").ArrayList(typed.FunctionId) = .empty;
        errdefer roots.deinit(allocator);
        for (self.program.?.functions) |function| {
            if (self.exported(function)) try roots.append(allocator, function.id);
        }
        return roots.toOwnedSlice(allocator);
    }
    fn exported(self: *Compilation, function: typed.Function) bool {
        const original = self.src.originalSpan(function.declaration) catch unreachable;
        const unit = self.index.units[original.input];
        const prefix_len = self.index.project.modules.items[original.input].name.len + 2;
        return unit.symbols.items[unit.names.get(function.name[prefix_len..]).?].exported;
    }
    /// Select an explicitly exported nominal type, or a built-in type.
    pub fn publicValueType(self: *Compilation, name: []const u8) !typed.Type {
        try self.check();
        if (typed.Type.fromName(name)) |ty| return ty;
        for (self.program.?.records) |record| {
            if (!@import("std").mem.eql(u8, name, record.name) or record.array != null) continue;
            const original = self.src.originalSpan(record.declaration) catch return error.UnknownPublicValueType;
            const unit = self.index.units[original.input];
            const prefix_len = self.index.project.modules.items[original.input].name.len + 2;
            const symbol = unit.symbols.items[unit.names.get(record.name[prefix_len..]) orelse return error.UnknownPublicValueType];
            if (symbol.exported and symbol.kind == .type) return record.id;
        }
        return error.UnknownPublicValueType;
    }
    /// Only explicitly exported functions/public methods may be invoked by name.
    pub fn invokePublic(self: *Compilation, allocator: @import("std").mem.Allocator, name: []const u8, arguments: []const typed.Value, options: @import("vm.zig").InvokeOptions) !@import("vm.zig").ValueResult {
        if (options.steps_executed) |steps| steps.* = 0;
        try self.emit();
        for (self.program.?.functions) |function| {
            if (@import("std").mem.eql(u8, function.name, name) and self.exported(function)) {
                return @import("vm.zig").invoke(allocator, self.code.?, function.id, arguments, options);
            }
        }
        return error.UnknownPublicFunction;
    }
    pub fn emit(self: *Compilation) !void {
        try self.check();
        if (self.code == null) self.code = try @import("lower.zig").lower(self.index.project.arena.allocator(), self.program.?);
    }
};
