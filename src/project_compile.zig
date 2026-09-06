//! Full semantic checking over relocated module syntax and explicit namespaces.
/// Failures returned by init; callers must handle these boundary errors.
pub const InitError = error{
    EmptySourceMap,
    IncompleteProject,
    InvalidNodeId,
    InvalidSourceIndex,
    InvalidSourceSpan,
    InvalidStatementId,
    NestedSourceMap,
    OutOfMemory,
    Overflow,
};
/// Failures returned by check; callers must handle these boundary errors.
pub const CheckError = error{
    OutOfMemory,
    SourceError,
    InternalError,
};
/// Failures returned by emitC; callers must handle these boundary errors.
pub const EmitCError = error{
    InternalError,
    OutOfMemory,
    SourceError,
    WriteFailed,
};
/// Failures returned by publicValueType; callers must handle these boundary errors.
pub const PublicValueTypeError = error{
    OutOfMemory,
    SourceError,
    UnknownPublicValueType,
    InternalError,
};
/// Failures returned by publicFunction; callers must handle these boundary errors.
pub const PublicFunctionError = error{
    OutOfMemory,
    SourceError,
    UnknownPublicFunction,
    InternalError,
};
/// Failures returned by emit; callers must handle these boundary errors.
pub const EmitError = error{
    InternalError,
    OutOfMemory,
    SourceError,
};

/// Failures returned by invokePublic; callers must handle these boundary errors.
pub const InvokePublicError = PublicFunctionError || error{
    BorrowConflict,
    BorrowSuspended,
    Bounds,
    CapabilityUnavailable,
    CapacityLimit,
    ChildrenActive,
    Closed,
    Denied,
    ExpiredBorrow,
    Failed,
    ForeignMemory,
    IdentityExhausted,
    InternalError,
    InvalidAggregateType,
    InvalidAllocation,
    InvalidBudget,
    InvalidCapability,
    InvalidDataType,
    InvalidDataValue,
    InvalidOwner,
    InvalidProvider,
    InvalidValueLimits,
    InvocationArity,
    InvocationEffects,
    InvocationReference,
    MemoryClosed,
    NoCapacity,
    NotDataType,
    PrivateInvocationFunction,
    ReadOnly,
    RegionInUse,
    ResourceLimit,
    TypeMismatch,
    Unavailable,
    UnknownInvocationFunction,
    ValueCountLimit,
    ValueDepthLimit,
    ValueTypeMismatch,
};

const interfaces = @import("interfaces.zig");
const syntax = @import("project_syntax.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const Names = @import("module_names.zig").Names;
/// Project-level checked and lowered state borrowing the interface index and its arena.
pub const Compilation = struct {
    index: *interfaces.Index,
    src: source.Source,
    syntax: @import("ast.zig").Program,
    diagnostics: diagnostic.Sink,
    program: ?typed.Program = null,
    code: ?@import("bytecode.zig").Program = null,
    /// Merge indexed modules into a compilation whose storage belongs to the project arena.
    pub fn init(index: *interfaces.Index) InitError!Compilation {
        const merged = try syntax.build(index);
        return .{ .index = index, .src = merged.src, .syntax = merged.syntax, .diagnostics = .{ .allocator = index.project.arena.allocator() } };
    }
    /// Type-check merged module bodies and enforce exported signature boundaries.
    pub fn check(self: *Compilation) CheckError!void {
        if (self.program != null) return;
        var names: Names = .{ .index = self.index, .src = self.src };
        self.program = try @import("sema.zig").checkWithNames(self.index.project.arena.allocator(), self.src, self.syntax, &self.diagnostics, &names);
    }
    /// Allocate native C output after checking and lowering the complete project.
    pub fn emitC(self: *Compilation, allocator: @import("std").mem.Allocator) EmitCError![]u8 {
        try self.emit();
        return @import("native.zig").generate(allocator, self.code.?, self.src, &self.diagnostics);
    }
    /// Allocate the function identities exposed by the checked public interface.
    pub fn exportRoots(self: *Compilation, allocator: @import("std").mem.Allocator) CheckError![]typed.FunctionId {
        try self.check();
        var roots: @import("std").ArrayList(typed.FunctionId) = .empty;
        errdefer roots.deinit(allocator);
        for (self.program.?.functions) |function| {
            if (try self.exported(function)) try roots.append(allocator, function.id);
        }
        return roots.toOwnedSlice(allocator);
    }
    fn exported(self: *Compilation, function: typed.Function) error{InternalError}!bool {
        // Concrete instances are implementation details reachable through ordinary exports.
        if (@import("std").mem.indexOfScalar(u8, function.name, '$') != null) return false;
        const original = self.src.originalSpan(function.declaration) catch return error.InternalError;
        if (original.input >= self.index.units.len or original.input >= self.index.project.modules.items.len) return error.InternalError;
        const unit = self.index.units[original.input];
        const prefix_len = self.index.project.modules.items[original.input].name.len + 2;
        if (prefix_len > function.name.len) return error.InternalError;
        return unit.symbols.items[unit.names.get(function.name[prefix_len..]) orelse return error.InternalError].exported;
    }
    /// Select an explicitly exported nominal type, or a built-in type.
    pub fn publicValueType(self: *Compilation, name: []const u8) PublicValueTypeError!typed.Type {
        try self.check();
        if (typed.Type.fromName(name)) |ty| return ty;
        for (self.program.?.records) |record| {
            if (!@import("std").mem.eql(u8, name, record.name) or record.shape.array != null) continue;
            const original = self.src.originalSpan(record.declaration) catch return error.InternalError;
            if (original.input >= self.index.units.len or original.input >= self.index.project.modules.items.len) return error.InternalError;
            const unit = self.index.units[original.input];
            const prefix_len = self.index.project.modules.items[original.input].name.len + 2;
            if (prefix_len > record.name.len) return error.InternalError;
            const symbol = unit.symbols.items[unit.names.get(record.name[prefix_len..]) orelse return error.InternalError];
            if (symbol.exported and symbol.kind == .type) return record.id;
        }
        return error.UnknownPublicValueType;
    }
    /// Only explicitly exported functions/public methods may be invoked by name.
    pub fn invokePublic(self: *Compilation, allocator: @import("std").mem.Allocator, name: []const u8, arguments: []const typed.Value, options: @import("vm.zig").InvokeOptions) InvokePublicError!@import("vm.zig").ValueResult {
        if (options.steps_executed) |steps| steps.* = 0;
        try self.emit();
        return @import("vm.zig").invoke(allocator, self.code.?, try self.publicFunction(name), arguments, options);
    }
    /// Resolve a public callable name, rejecting hidden or unknown functions.
    pub fn publicFunction(self: *Compilation, name: []const u8) PublicFunctionError!typed.FunctionId {
        try self.check();
        for (self.program.?.functions) |function| {
            if (@import("std").mem.eql(u8, function.name, name) and try self.exported(function)) return function.id;
        }
        return error.UnknownPublicFunction;
    }
    /// Lazily lower the checked project into its retained bytecode representation.
    pub fn emit(self: *Compilation) EmitError!void {
        try self.check();
        if (self.code == null) self.code = try @import("lower.zig").lower(self.index.project.arena.allocator(), self.program.?);
    }
};
