//! The names of type descriptors: a type's stable identity, never its position (G4a step 2a).
//!
//! The descriptor of a type (`@myl.value.<id>`, `@myl.copy.<id>`) used to be named by the type's ordinal in `Module.compounds`, so
//! one type added earlier in discovery order renamed every descriptor after it and a catalog keyed by those names changed for every
//! unit. The id is now the first 128 bits of the type's digest in the by-name canon (`canonical_ir.Canon.named`): a nominal record or
//! union by its module and name, any other compound by its structure over its children's ids. Two builds that discover the same
//! types in another order, or with unrelated types added, give a type the same id and the same descriptor text. A unit's text
//! renumbers its descriptors locally (`emit_constants.Catalog.finish`), so the id never reaches an object.
const std = @import("std");
const ir = @import("ir.zig");
const identity = @import("canonical_ir.zig");
const source_location = @import("source_location.zig");

/// Allocation failure, or a type the canonical form does not know.
pub const Error = identity.Error;

/// A type id as it is spelled in a symbol: 32 lower-case hexadecimal digits.
pub const Text = [32]u8;

const unlocated: u8 = 0;

fn nowhere(_: *const anyopaque, _: u32) source_location.Location {
    return .{ .line = 0, .column = 0 };
}

/// The ids of the compound types of one module, by compound ordinal; a builtin type's id is a function of the type alone.
pub const Table = struct {
    compounds: []const [16]u8 = &.{},

    /// Digest every compound type of `module` by name and keep the first 128 bits of each. Scratch and the table live in `a`.
    pub fn build(a: std.mem.Allocator, module: *const ir.Module) Error!Table {
        // The canon's memo types are private to it; the fields give their names without a second constructor.
        const Memo = @FieldType(identity.Canon, "memo");
        const types = try a.alloc(@typeInfo(@FieldType(Memo, "types")).pointer.child, module.compounds.items.len);
        @memset(types, null);
        const callees = try a.alloc(@typeInfo(@FieldType(Memo, "callees")).pointer.child, 0);
        var canon: identity.Canon = .{ .a = a, .module = module, .locator = .{ .context = &unlocated, .locate = nowhere }, .memo = .{ .types = types, .callees = callees }, .by_name = true };
        const ids = try a.alloc([16]u8, types.len);
        for (ids, 0..) |*id, ordinal| {
            const ty: ir.Type = @fromBackingInt(@intCast(ir.Type.first_compound + ordinal));
            id.* = (try canon.typeDigest(ty))[0..16].*;
        }
        return .{ .compounds = ids };
    }

    /// The id of `ty` spelled for a symbol. A compound outside the table (a type that does not exist) is spelled from its ordinal,
    /// which no valid descriptor reference reaches.
    pub fn text(self: Table, ty: ir.Type) Text {
        var hash = std.crypto.hash.Blake3.init(.{});
        var id: [16]u8 = undefined;
        if (ty.isCompound()) {
            const ordinal = @backingInt(ty) - ir.Type.first_compound;
            if (ordinal < self.compounds.len) return std.fmt.bytesToHex(self.compounds[ordinal], .lower);
            hash.update("missing");
        } else hash.update("builtin");
        hash.update(std.mem.asBytes(&@backingInt(ty)));
        var full: [32]u8 = undefined;
        hash.final(&full);
        id = full[0..16].*;
        return std.fmt.bytesToHex(id, .lower);
    }
};
