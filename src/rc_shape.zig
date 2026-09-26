//! Physical RC edges and unique-drop obligations (RC-OWNERSHIP-PLAN-1).
//! A COW-free immutable value can still own a managed pointer. Raw external
//! resources instead keep their existing unique-drop schedule and no RC prefix.
const std = @import("std");
const typed = @import("typed.zig");
const native = @import("native_types.zig");

/// Whether a value needs physical lifetime accounting or a unique drop.
pub const Shape = struct {
    /// At least one initialized variant can contain an owning pointer edge.
    counted: bool = false,
    /// The existing resource/drop plan must discharge a unique obligation.
    unique_drop: bool = false,
    /// Copying the whole value is permitted by its physical layout contract.
    copyable: bool = true,
};

/// Memoized shape facts over an already physically lowered native catalog.
pub const Catalog = struct {
    allocator: std.mem.Allocator,
    native: *native.Catalog,
    shapes: []?Shape,

    /// Allocate facts independently of the existing layout catalog.
    pub fn init(allocator: std.mem.Allocator, layouts: *native.Catalog) error{OutOfMemory}!Catalog {
        const shapes = try allocator.alloc(?Shape, layouts.records.len);
        @memset(shapes, null);
        return .{ .allocator = allocator, .native = layouts, .shapes = shapes };
    }

    /// Release only this catalog's memo table; the native catalog is borrowed.
    pub fn deinit(self: *Catalog) void {
        self.allocator.free(self.shapes);
        self.* = undefined;
    }

    /// Resolve owning edges without descending through managed pointers.
    pub fn get(self: *Catalog, ty: typed.Type) native.Error!Shape {
        if (!ty.isAggregate()) return self.ofLayout(try self.native.layout(ty));
        const index = ty.recordIndex();
        if (index >= self.shapes.len) return error.InvalidType;
        if (self.shapes[index]) |shape| return shape;
        const shape = try self.ofLayout(try self.native.layout(ty));
        self.shapes[index] = shape;
        return shape;
    }

    fn ofLayout(self: *Catalog, layout: native.Layout) native.Error!Shape {
        var result: Shape = .{ .unique_drop = layout.drop, .copyable = layout.copy != .prohibited };
        switch (layout.kind) {
            .managed => result.counted = true,
            .record, .domain, .variant, .niche => {
                for (layout.fields) |field| result.counted = result.counted or (try self.get(field.ty)).counted;
            },
            .array => if (layout.count != 0) {
                result.counted = layout.fields.len != 0 and (try self.get(layout.fields[0].ty)).counted;
            },
            // These kinds do not prove a managed allocation prefix. In
            // particular File/TextFile are raw provider-owned Resource blocks.
            .scalar, .handle, .pool_handle, .callable, .resource, .owned_buffer, .owned_pool => {},
        }
        return result;
    }
};
