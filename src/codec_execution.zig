//! Per-operation codec calls: no authority injection or implicit domain wrapping.
const std = @import("std");
const typed = @import("typed.zig");
const vm = @import("vm.zig");
pub const Failure = struct {
    domain: ?typed.Type = null,
    rejection: ?typed.Value = null,
    trap: ?@import("diagnostic.zig").Diagnostic = null,
    pub fn deinit(self: *Failure, allocator: std.mem.Allocator) void {
        if (self.rejection) |value| value.release(allocator);
        self.* = .{};
    }
};
pub const Execution = struct {
    program: @import("bytecode.zig").Program,
    max_steps: u64,
    max_frames: u64,
    max_calls: usize,
    arguments: @import("value_copy.zig").Limits,
    failure: *Failure,
    steps: u64 = 0,
    calls: usize = 0,
    fn call(self: *Execution, allocator: std.mem.Allocator, domain: typed.Type, id: typed.FunctionId, input: typed.Value) !typed.Value {
        if (self.calls == self.max_calls) return error.CodecCallLimit;
        if (self.steps == self.max_steps) return error.CodecStepLimit;
        self.calls += 1;
        var executed: u64 = 0;
        defer self.steps += executed;
        const result = try vm.invoke(allocator, self.program, id, &.{input}, .{ .max_steps = self.max_steps - self.steps, .max_frames = self.max_frames, .arguments = self.arguments, .steps_executed = &executed });
        return switch (result) {
            .value => |value| value,
            .trap => |trap| {
                self.failure.domain = domain;
                self.failure.trap = trap;
                return error.DomainCodecTrap;
            },
        };
    }
    pub fn decode(self: *Execution, allocator: std.mem.Allocator, domain: typed.Type, input: typed.Value) !typed.Value {
        const codec = self.program.records[domain.recordIndex()].codec orelse return error.NoImplicitCodec;
        const result = try self.call(allocator, domain, codec.decode, input);
        defer result.release(allocator);
        const shape = typed.resultShape(result.typeOf(), self.program.records) orelse return error.InvalidCodecContract;
        if (shape.ok_type != domain or result != .aggregate or result.aggregate.fields.len != 1) return error.InvalidCodecContract;
        const tag = try result.variantTag();
        if (tag == shape.ok_tag) return result.aggregate.fields[0].retain();
        if (tag != shape.error_tag) return error.InvalidCodecContract;
        self.failure.domain = domain;
        self.failure.rejection = result.aggregate.fields[0].retain();
        return error.DomainCodecRejected;
    }
    pub fn encode(self: *Execution, allocator: std.mem.Allocator, domain: typed.Type, input: typed.Value) !typed.Value {
        const codec = self.program.records[domain.recordIndex()].codec orelse return error.NoImplicitCodec;
        const result = try self.call(allocator, domain, codec.encode, input);
        errdefer result.release(allocator);
        if (result.typeOf() != codec.wire) return error.InvalidCodecContract;
        return result;
    }
};
