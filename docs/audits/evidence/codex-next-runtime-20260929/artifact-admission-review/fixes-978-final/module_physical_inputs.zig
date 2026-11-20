//! Restore real imported physical bodies without parsing or checking their source.
//! All names are reserved before decoding; missing authority remains an explicit
//! bodyless physical stand-in and cannot yield a readonly, borrow or pin proof.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const physical = @import("module_physical.zig");
const iface = @import("module_interface.zig");
const native_interface = @import("native_interface.zig");

/// Corrupt or inconsistent artifacts refuse compilation and request fresh inputs.
pub const Error = error{ OutOfMemory, InternalError };
/// The complete native input table and matching module selection/fact tables.
pub const Restored = struct {
    code: bytecode.Program,
    emit: []const bool,
    imported: []const ?native_interface.Imported,
};

/// Enrich one lowered program with imported real bodies and conservative signatures.
pub fn restore(a: std.mem.Allocator, code: bytecode.Program, emit: []const bool, imported: []const ?native_interface.Imported, interfaces: []const iface.Interface) Error!Restored {
    var state = try State.of(a, code);
    for (interfaces) |interface| try state.reserve(interface.emission.physical);
    for (interfaces) |interface| try state.recordsFrom(interface.emission.physical);
    for (interfaces) |interface| try state.dependenciesFrom(interface.emission.physical);
    for (interfaces) |interface| try state.functionsFrom(interface, emit);
    try state.markStandins(emit);
    const chosen = try a.alloc(bool, state.functions.items.len);
    @memset(chosen, false);
    @memcpy(chosen[0..emit.len], emit);
    const facts = try a.alloc(?native_interface.Imported, chosen.len);
    @memset(facts, null);
    @memcpy(facts[0..imported.len], imported);
    for (state.functions.items, facts) |function, *entry| {
        const supplied = function.physical orelse continue;
        if (!supplied.unknown) continue;
        const writes = try a.alloc(bool, function.signature.parameter_count);
        @memset(writes, true);
        entry.* = .{ .allocates = true, .writes = writes };
    }
    for (interfaces) |interface| for (interface.emission.functions) |function| {
        const id = state.ids.functions.get(function.name) orelse continue;
        if (state.functions.items[@backingInt(id)].physical) |supplied| if (supplied.unknown) continue;
        facts[@backingInt(id)] = .{ .allocates = function.allocates, .writes = function.writes };
    };
    return .{ .code = .{ .functions = state.functions.items, .records = state.records.items, .main = code.main }, .emit = chosen, .imported = facts };
}

const State = struct {
    a: std.mem.Allocator,
    ids: physical.Ids = .{},
    records: std.ArrayList(typed.Record) = .empty,
    functions: std.ArrayList(bytecode.Function) = .empty,
    original: usize,
    record_count: usize,
    restored: Stored = .{},

    fn of(a: std.mem.Allocator, code: bytecode.Program) Error!State {
        var out: State = .{ .a = a, .original = code.functions.len, .record_count = code.records.len };
        try out.functions.appendSlice(a, code.functions);
        try out.records.appendSlice(a, code.records);
        for (code.functions, 0..) |function, index| try out.ids.functions.put(a, function.name, @fromBackingInt(index));
        for (code.records, 0..) |record, index| try out.ids.records.put(a, record.name, @fromBackingInt(typed.Type.record_base + index));
        return out;
    }

    fn markStandins(self: *State, emit: []const bool) Error!void {
        for (self.functions.items, 0..) |*function, index| {
            if (index < emit.len and emit[index]) continue;
            if (function.scope.instructions.len != 0) continue;
            const unknown = try self.a.create(bytecode.Physical);
            unknown.* = .{ .unknown = true };
            function.physical = unknown;
        }
    }

    fn reserve(self: *State, archive: physical.Archive) Error!void {
        for (archive.records) |data| {
            if (self.ids.records.contains(data.name)) continue;
            try self.ids.records.put(self.a, data.name, @fromBackingInt(typed.Type.record_base + self.records.items.len));
            try self.records.append(self.a, .{ .id = self.ids.records.get(data.name).?, .name = data.name, .declaration = .{ .start = 0, .end = 0 }, .fields = &.{} });
        }
        for ([_][]const physical.Data{ archive.functions, archive.dependencies }) |list| for (list) |data| {
            if (self.ids.functions.contains(data.name)) continue;
            const index = self.functions.items.len;
            try self.ids.functions.put(self.a, data.name, @fromBackingInt(index));
            try self.functions.append(self.a, .{ .id = @fromBackingInt(index), .name = data.name, .scope = .{ .instructions = &.{} } });
        };
    }

    fn recordsFrom(self: *State, archive: physical.Archive) Error!void {
        for (archive.records) |data| {
            const ty = self.ids.records.get(data.name) orelse return error.InternalError;
            const record = physical.read(self.a, &self.ids, typed.Record, data) catch |err| return failed(err);
            if (record.id != ty) return error.InternalError;
            const normalized = try physical.write(self.a, .{ .functions = self.functions.items, .records = self.records.items }, record);
            const known = try self.restored.records.getOrPut(self.a, data.name);
            if (known.found_existing) {
                if (!std.mem.eql(u8, known.value_ptr.*, normalized.bytes)) return error.InternalError;
                continue;
            }
            known.value_ptr.* = normalized.bytes;
            if (ty.recordIndex() < self.record_count) {
                const existing = try physical.write(self.a, .{ .functions = self.functions.items, .records = self.records.items }, self.records.items[ty.recordIndex()]);
                if (!std.mem.eql(u8, existing.bytes, normalized.bytes)) return error.InternalError;
                continue;
            }
            self.records.items[ty.recordIndex()] = record;
        }
    }

    fn dependenciesFrom(self: *State, archive: physical.Archive) Error!void {
        for (archive.dependencies) |data| {
            const id = self.ids.functions.get(data.name) orelse return error.InternalError;
            var function = physical.read(self.a, &self.ids, bytecode.Function, data) catch |err| return failed(err);
            if (function.scope.instructions.len != 0) return error.InternalError;
            try self.signatureFrom(function);
            if (@backingInt(id) < self.original or self.functions.items[@backingInt(id)].physical != null) continue;
            const unknown = try self.a.create(bytecode.Physical);
            unknown.* = .{ .unknown = true };
            function.physical = unknown;
            self.functions.items[@backingInt(id)] = function;
        }
    }

    fn functionsFrom(self: *State, interface: iface.Interface, emit: []const bool) Error!void {
        for (interface.emission.physical.functions) |data| {
            const id = self.ids.functions.get(data.name) orelse return error.InternalError;
            const index = @backingInt(id);
            const decoded = physical.read(self.a, &self.ids, bytecode.Function, data) catch |err| return failed(err);
            try self.signatureFrom(decoded);
            if (index < emit.len and emit[index]) continue;
            const known = try self.restored.functions.getOrPut(self.a, data.name);
            if (known.found_existing) {
                if (!std.mem.eql(u8, known.value_ptr.*, data.bytes)) return error.InternalError;
                continue;
            }
            known.value_ptr.* = data.bytes;
            var function = if (index < self.original and self.functions.items[index].scope.instructions.len != 0)
                self.functions.items[index]
            else
                decoded;
            for (interface.emission.functions) |stated| if (std.mem.eql(u8, stated.name, data.name)) {
                const facts = try self.a.create(bytecode.Physical);
                facts.* = .{ .stable = stated.stable };
                function.physical = facts;
                break;
            };
            self.functions.items[index] = function;
        }
    }

    fn signatureFrom(self: *State, function: bytecode.Function) Error!void {
        const data = try self.signatureData(function);
        const index = @backingInt(function.id);
        if (index < self.original) {
            const existing = try self.signatureData(self.functions.items[index]);
            if (!std.mem.eql(u8, existing.bytes, data.bytes)) return error.InternalError;
        }
        const known = try self.restored.signatures.getOrPut(self.a, function.name);
        if (known.found_existing and !std.mem.eql(u8, known.value_ptr.*, data.bytes)) return error.InternalError;
        known.value_ptr.* = data.bytes;
    }

    fn signatureData(self: *State, function: bytecode.Function) Error!physical.Data {
        var plain = function;
        const count = plain.signature.parameter_count;
        if (count > plain.scope.locals.len) return error.InternalError;
        const parameters = try self.a.dupe(typed.Local, plain.scope.locals[0..count]);
        for (parameters) |*parameter| {
            parameter.ownership = .{};
            parameter.usage = .{};
            parameter.mutable = false;
            parameter.origin = .local;
        }
        plain.physical = null;
        plain.policy.effects = 0;
        plain.policy.effect_bound = null;
        plain.signature = .{
            .return_type = plain.signature.return_type,
            .parameter_count = count,
            .constant_arguments = plain.signature.constant_arguments,
            .declared_mutates = plain.signature.declared_mutates,
        };
        plain.scope = .{ .locals = parameters, .instructions = &.{} };
        return physical.write(self.a, .{ .functions = self.functions.items, .records = self.records.items }, plain);
    }
};

const Stored = struct {
    records: std.StringHashMapUnmanaged([]const u8) = .empty,
    functions: std.StringHashMapUnmanaged([]const u8) = .empty,
    signatures: std.StringHashMapUnmanaged([]const u8) = .empty,
};

fn failed(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}
