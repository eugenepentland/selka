//! Stage host I/O through checked byte slices without exposing guest storage.
const std = @import("std");
const memory = @import("memory.zig");
const typed = @import("typed.zig");
pub const View = struct { lease: memory.Borrow, start: usize, length: usize, direct: bool };
pub const Prepared = struct {
    allocator: std.mem.Allocator,
    store: *memory.Store,
    view: View,
    bytes: []u8,
    replacement: ?typed.Value = null,
    mutable: bool,
    pub fn init(allocator: std.mem.Allocator, store: *memory.Store, view: View, mutable: bool, records: []const typed.Record) !Prepared {
        const lease = try store.describe(view.lease);
        if (mutable and lease.kind != .exclusive) return error.ReadOnly;
        var prepared: Prepared = .{ .allocator = allocator, .store = store, .view = view, .bytes = try allocator.alloc(u8, view.length), .mutable = mutable };
        errdefer prepared.deinit();
        if (view.direct) {
            if (lease.element_type != .u8 or view.start > lease.length or view.length > lease.length - view.start) return error.Bounds;
            if (!mutable) for (prepared.bytes, 0..) |*byte, index| {
                const value = try store.read(view.lease, view.start + index);
                defer value.release(allocator);
                if (value.typeOf() != .u8) return error.TypeMismatch;
                byte.* = std.math.cast(u8, try value.asInteger()) orelse return error.TypeMismatch;
            };
        } else {
            if (lease.length != 1) return error.Bounds;
            const array = try store.read(view.lease, 0);
            defer array.release(allocator);
            if (!typed.byteRequest(array.typeOf(), records) or array != .aggregate) return error.TypeMismatch;
            const length = array.aggregate.fields.len;
            if (view.start > length or view.length > length - view.start) return error.Bounds;
            if (mutable and view.length != 0) prepared.replacement = try typed.Value.create(allocator, array.typeOf(), array.aggregate.fields);
            if (!mutable) for (prepared.bytes, array.aggregate.fields[view.start..][0..view.length]) |*byte, value| {
                if (value.typeOf() != .u8) return error.TypeMismatch;
                byte.* = std.math.cast(u8, try value.asInteger()) orelse return error.TypeMismatch;
            };
        }
        return prepared;
    }
    /// Replace only the successfully read prefix. Metadata/backing preparation
    /// was done before the provider call; byte stores allocate no memory here.
    pub fn commit(self: *Prepared, length: usize) !void {
        if (!self.mutable) return error.ReadOnly;
        if (length > self.bytes.len) return error.Bounds;
        if (length == 0) return;
        if (self.view.direct) {
            for (self.bytes[0..length], 0..) |byte, index| try self.store.write(self.view.lease, self.view.start + index, typed.Value.number(.u8, byte));
        } else {
            const array = self.replacement orelse return error.InternalError;
            const fields = @constCast(array.aggregate.fields);
            for (self.bytes[0..length], 0..) |byte, index| {
                fields[self.view.start + index].release(self.allocator);
                fields[self.view.start + index] = typed.Value.number(.u8, byte);
            }
            try self.store.write(self.view.lease, 0, array);
        }
    }
    pub fn deinit(self: *Prepared) void {
        if (self.replacement) |array| array.release(self.allocator);
        self.allocator.free(self.bytes);
    }
};
