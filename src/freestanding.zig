//! `@freestanding` functions (MCU-NOC2): code that needs nothing from the runtime, because it runs before the runtime is up
//! (reset), while the runtime cannot be entered (a fault, an interrupt, a signal) or while the flash it lives in cannot be
//! read. The attribute is a promise the check verifies over the whole body, the way `@noalloc` is verified over a call
//! graph (`core/allocation_contract.zig`); nothing switches a check off. A failed check inside such a function calls
//! nothing either: Core lowers it to a fault that carries its code and place (`core/emit_llvm.zig`, `freestandingFault`),
//! and the emitted text of the function is verified to name no runtime symbol (`core/freestanding_emitted.zig`).
//!
//! The rules, each refused with `E_FREESTANDING` at the place that breaks it:
//! - unmanaged data only, in the parameters, the result, every local and every expression: integers, floats, `bool`,
//!   enums, records, unions, options and fixed arrays made only of those, `extern type` handles, and the capabilities
//!   `Registers` and `Host` (`unmanaged`);
//! - calls only of other `@freestanding` functions, of `extern func`s (trusted native code that keeps the same promise),
//!   and of the built-ins in `inline_builtins`, which become inline code with no runtime call;
//! - no function value, no output, no text, no task, no resource and no other operation of the runtime (`refusedNode`);
//! - an `assert` takes no message: no text is built when it fails;
//! - a `@freestanding(ram)` function (MCU-NOC2B), whose code runs from RAM while the flash cannot be read, calls only other
//!   `ram` functions, `extern func`s (C placed in RAM by its author, who makes the same promise) and the inline built-ins.
//!   What the code generator adds (a library routine, a table in read-only data) is found on the linked image
//!   (`core/ram_image.zig`).
const std = @import("std");
const product = @import("product.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const origins = @import("origins.zig");

/// The one code every refusal of the promise carries; the message names the rule.
pub const code = "E_FREESTANDING";

/// One standard-library function a freestanding function may call: it becomes inline code with no runtime call on a
/// device (`registers` reads and writes are one volatile load or store, and each `cpu` function that acts on the machine
/// is one instruction or two: `core/emit_registers.zig`). On Linux they reach the simulated bank, a test's stand-in for
/// the hardware, which the emitted-text check allows by name (`core/freestanding_emitted.zig`). `ordinary` is a function
/// the library writes in Selka over private built-ins of this kind (`cpu.interrupts_off` makes the linear state from the
/// built-in that reads PRIMASK); every other row is a `builtin func` itself.
pub const Builtin = struct { module: []const u8, name: []const u8, ordinary: bool = false };

/// The built-ins a freestanding function may call, by embedded module and name. The `cpu` functions that only a simulated
/// bank has (`event_count`, `interrupts_are_off` and the rest of its log) are not here: they are refused by name, as a
/// device build refuses them (`E_TARGET_SIMULATED_REGISTERS`).
pub const inline_builtins = [_]Builtin{
    .{ .module = "registers", .name = "read8" },
    .{ .module = "registers", .name = "read16" },
    .{ .module = "registers", .name = "read32" },
    .{ .module = "registers", .name = "write8" },
    .{ .module = "registers", .name = "write16" },
    .{ .module = "registers", .name = "write32" },
    .{ .module = "cpu", .name = "wait_for_event" },
    .{ .module = "cpu", .name = "wait_for_interrupt" },
    .{ .module = "cpu", .name = "send_event" },
    .{ .module = "cpu", .name = "barrier" },
    .{ .module = "cpu", .name = "breakpoint" },
    .{ .module = "cpu", .name = "interrupts_off", .ordinary = true },
    .{ .module = "cpu", .name = "interrupts_restore", .ordinary = true },
};

/// Refuse the first broken rule of every checked `@freestanding` function body.
pub fn checkProgram(allocator: std.mem.Allocator, program: typed.Program, src: source.Source, sink: *diagnostic.Sink, stubs: []const ?origins.Fact) diagnostic.Error!void {
    for (program.functions, 0..) |function, index| {
        const promise = function.policy.freestanding orelse continue;
        if (origins.standIn(stubs, index) != null or !function.scope.body_complete) continue;
        var walk: Walk = .{ .allocator = allocator, .program = program, .src = src, .sink = sink, .promise = promise, .ram = function.policy.ram };
        try walk.function(function);
    }
}

/// Whether a value of `ty` needs nothing from the runtime: no block, no count, no handle the runtime keeps.
pub fn unmanaged(ty: typed.Type, records: []const typed.Record) bool {
    return unmanagedDepth(ty, records, 0);
}

fn unmanagedDepth(ty: typed.Type, records: []const typed.Record, depth: usize) bool {
    if (depth > 64) return false;
    if (ty.isInteger() or ty == .bool or ty == .unit or ty == .registers_cap or ty == .host_cap) return true;
    if (!ty.isAggregate()) return false;
    if (ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (record.managed or record.shape.resource != null or record.shape.buffer != null) return false;
    if (record.contract.callback != null) return false;
    switch (record.shape.builtin) {
        .foreign_handle => return true,
        .cell, .live_view => return false,
        .none => {},
    }
    if (record.shape.domain) |base| if (!unmanagedDepth(base, records, depth + 1)) return false;
    for (record.fields) |field| if (field.boxed or !unmanagedDepth(field.ty, records, depth + 1)) return false;
    if (record.shape.array) |array| if (array.length != 0 and !unmanagedDepth(array.element, records, depth + 1)) return false;
    if (record.shape.variants) |variants| for (variants.cases) |case| {
        const payload = case.payload orelse continue;
        if (case.boxed or !unmanagedDepth(payload, records, depth + 1)) return false;
    };
    return true;
}

/// Whether `function` is one of `inline_builtins`.
pub fn inlineBuiltin(src: source.Source, function: typed.Function) bool {
    const path = src.locate(function.declaration.start).path;
    const name = src.text(function.declaration);
    for (inline_builtins) |entry| {
        if (function.policy.builtin == entry.ordinary or !std.mem.eql(u8, name, entry.name)) continue;
        if (path.len == "@stdlib/".len + entry.module.len + product.source_suffix.len and std.mem.startsWith(u8, path, "@stdlib/") and
            std.mem.eql(u8, path["@stdlib/".len..][0..entry.module.len], entry.module) and product.isSource(path)) return true;
    }
    return false;
}

/// What a node of each refused kind is, for the message; null for a kind the rules allow.
fn refusedNode(data: @FieldType(typed.Node, "data")) ?[]const u8 {
    return switch (data) {
        .function_value => "a function value: its type cannot carry the freestanding promise, so a call through it could reach the runtime",
        .invoke => "a call through a function value: its type cannot carry the freestanding promise",
        .print, .stream_write, .stream_flush => "output: printing and writing a stream are runtime calls",
        .format => "a format string: it builds text",
        .borrow_selection, .blob => "text or bytes, which the runtime manages",
        .buffer_operation, .acquire_buffer, .byte_load => "a collection or buffer operation, which the runtime performs",
        .acquire_resource, .complete_resource, .resource_io, .restrict_resource, .dir_resource, .host_resource, .accept_resource, .file_access, .file_method => "a resource operation, which the runtime performs",
        .environment_get, .environment_only, .environment_names, .external_read, .stand_in => "a capability operation, which the runtime performs",
        .task_group_open, .task_submit, .task_result => "`parallel` tasks, which the runtime runs",
        .arena_escape => "an arena copy, which the runtime makes",
        else => null,
    };
}

const Walk = struct {
    allocator: std.mem.Allocator,
    program: typed.Program,
    src: source.Source,
    sink: *diagnostic.Sink,
    promise: source.Span,
    /// The function is `@freestanding(ram)`: it calls only RAM code.
    ram: bool = false,

    fn refuse(self: *Walk, span: source.Span, comptime format: []const u8, arguments: anytype) diagnostic.Error {
        const text = try std.fmt.allocPrint(self.allocator, "a @freestanding function needs nothing from the runtime: " ++ format, arguments);
        return self.sink.fail(code, span, text);
    }

    fn requireUnmanaged(self: *Walk, ty: typed.Type, span: source.Span, what: []const u8) diagnostic.Error!void {
        if (unmanaged(ty, self.program.records)) return;
        const name = try typed.surfaceTypeName(self.allocator, ty, self.program.records);
        return self.refuse(span, "{s} has type `{s}`, which the runtime manages (rule: unmanaged data only)", .{ what, name });
    }

    fn function(self: *Walk, checked: typed.Function) diagnostic.Error!void {
        try self.requireUnmanaged(checked.signature.return_type, checked.declaration, "the result");
        for (checked.scope.locals, 0..) |local, index| {
            const what = if (index < checked.signature.parameter_count) "a parameter" else "a local";
            try self.requireUnmanaged(local.ty, local.declaration, what);
        }
        try self.statement(checked.scope.body);
    }

    fn statement(self: *Walk, id: typed.StatementId) diagnostic.Error!void {
        const stmt = self.program.statements[@backingInt(id)];
        if (stmt.data == .assertion) try self.assertion(stmt);
        try self.visit(@TypeOf(stmt.data), stmt.data);
    }

    /// An `assert` with no message keeps its condition's text as the message, which a fault never shows; a message the
    /// source wrote, a literal or a computed one, is refused, as a failed check builds no text.
    fn assertion(self: *Walk, stmt: typed.Statement) diagnostic.Error!void {
        const claim = stmt.data.assertion;
        if (claim.kind != .statement) return;
        const condition = self.program.nodes[@backingInt(claim.condition)].span;
        if (claim.message_value == null and std.mem.eql(u8, claim.message, self.src.text(condition))) return;
        return self.refuse(stmt.span, "an `assert` takes no message, so a failed one builds no text (rule: no runtime operations)", .{});
    }

    fn node(self: *Walk, id: typed.NodeId) diagnostic.Error!void {
        const checked = self.program.nodes[@backingInt(id)];
        if (refusedNode(checked.data)) |what| return self.refuse(checked.span, "{s} (rule: no runtime operations)", .{what});
        try self.requireUnmanaged(checked.ty, checked.span, "this expression");
        if (checked.data == .call) try self.call(checked.span, self.program.functions[@backingInt(checked.data.call.function)]);
        try self.visit(@TypeOf(checked.data), checked.data);
    }

    fn call(self: *Walk, span: source.Span, callee: typed.Function) diagnostic.Error!void {
        if (callee.policy.c_abi or inlineBuiltin(self.src, callee)) return;
        if (self.ram) {
            if (callee.policy.freestanding != null and callee.policy.ram) return;
            const kind = if (callee.policy.freestanding != null) "@freestanding but not placed in RAM, so its code is in flash" else if (callee.policy.host != null) "a `host` function" else if (callee.policy.builtin) "a built-in that calls the runtime" else "a function not marked @freestanding(ram)";
            return self.refuse(span, "`{s}` is {s} (rule: a @freestanding(ram) function calls only @freestanding(ram) functions, `extern func`s and inline built-ins)", .{ callee.name, kind });
        }
        if (callee.policy.freestanding != null) return;
        const kind = if (callee.policy.host != null) "a `host` function" else if (callee.policy.builtin) "a built-in that calls the runtime" else "a function not marked @freestanding";
        return self.refuse(span, "`{s}` is {s} (rule: calls only of @freestanding functions, `extern func`s and inline built-ins)", .{ callee.name, kind });
    }

    /// Visit every node and statement `value` names, whatever its shape: a node or statement id, an optional, a slice, a
    /// struct or a tagged union of them. Every other field (a type, a local, a span) holds none.
    fn visit(self: *Walk, comptime T: type, value: T) diagnostic.Error!void {
        if (T == typed.NodeId) return self.node(value);
        if (T == typed.StatementId) return self.statement(value);
        switch (@typeInfo(T)) {
            .optional => |info| if (value) |present| try self.visit(info.child, present),
            .pointer => |info| if (info.size == .slice and comptime holdsIds(info.child)) for (value) |item| try self.visit(info.child, item),
            .@"struct" => |info| inline for (info.field_names, info.field_types) |name, Field| {
                if (comptime holdsIds(Field)) try self.visit(Field, @field(value, name));
            },
            .@"union" => |info| if (info.tag_type != null) switch (value) {
                inline else => |payload| if (comptime holdsIds(@TypeOf(payload))) try self.visit(@TypeOf(payload), payload),
            },
            else => {},
        }
    }
};

/// Whether a value of `T` can hold a node or statement id, so the walk visits it.
fn holdsIds(comptime T: type) bool {
    return comptime holdsIdsDepth(T, 0);
}

fn holdsIdsDepth(comptime T: type, comptime depth: usize) bool {
    if (depth > 6) return false;
    if (T == typed.NodeId or T == typed.StatementId) return true;
    return switch (@typeInfo(T)) {
        .optional => |info| holdsIdsDepth(info.child, depth + 1),
        .pointer => |info| info.size == .slice and holdsIdsDepth(info.child, depth + 1),
        .@"struct" => |info| for (info.field_types) |Field| {
            if (holdsIdsDepth(Field, depth + 1)) break true;
        } else false,
        .@"union" => |info| info.tag_type != null and for (info.field_types) |Field| {
            if (holdsIdsDepth(Field, depth + 1)) break true;
        } else false,
        else => false,
    };
}
