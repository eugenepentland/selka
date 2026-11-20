//! A function stored by what it names (G3o, stage 1). `ir_snapshot` keeps function and type ordinals in a stored body and guards them
//! with the digest of the whole declaration table, so one added function invalidates every record. Here a body names each callee
//! by the canonical digest of its reference (`canonical_ir.Canon.callee`: name and signature, an equality or rendering adapter by
//! the type its id stands for), each compound type by its stable name (a nominal record by module and name, `ir.Module.nominal`; any
//! other compound by its structure over its children's names) and each source file by its key path, in tables local to the record.
//! Restoring resolves the tables against the module being built. A name that is missing, that two entries of the module share, or
//! whose type has another structure than the record saw, refuses the record: the build then computes what it would have computed.
const std = @import("std");
const ir = @import("ir.zig");
const identity = @import("canonical_ir.zig");
const snapshot = @import("ir_snapshot.zig");

/// A canonical digest: a callee's reference or a type's name or structure.
pub const Digest = [32]u8;

/// A compound type as a stored record names it: by name to find it, and by structure to check what was found.
pub const TypeName = struct { name: Digest, structure: Digest };

/// The names a stored function refers to, in the order its local indexes number them.
pub const Names = struct {
    callees: []const Digest = &.{},
    types: []const TypeName = &.{},
    origins: []const []const u8 = &.{},
    /// The key path of the one source a location without an origin counts its lines in; null when no location does.
    plain: ?[]const u8 = null,
};

/// A function whose ordinals are local indexes into `names`, with the strings and locations of `snapshot.Wire`.
pub const Portable = struct { wire: snapshot.Wire, names: Names };

/// The two forms of the canon a build uses: by structure, which keys and checks, and by name, which finds.
pub const Canons = struct { structure: *identity.Canon, named: *identity.Canon };

/// Marks a name that two entries of the module share; a record that uses it is refused.
const ambiguous: u32 = std.math.maxInt(u32);

/// The module being built, indexed by name: what a stored name resolves to. Built once per build, after the passes that declare
/// the helpers a body may call; a function or type declared later is not found, which refuses the record.
pub const Index = struct {
    callees: std.AutoHashMapUnmanaged(Digest, u32) = .empty,
    types: std.AutoHashMapUnmanaged(Digest, u32) = .empty,
    origins: std.StringHashMapUnmanaged(u32) = .empty,

    /// Index every function, compound type and source file of `module` and `source` by name.
    pub fn build(canons: Canons, module: *const ir.Module, source: snapshot.Context) std.mem.Allocator.Error!Index {
        const a = canons.named.a;
        var index: Index = .{};
        for (0..module.functions.items.len) |ordinal| {
            const digest = canons.named.callee(@intCast(ordinal)) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnknownMetadata => continue,
            };
            const slot = try index.callees.getOrPut(a, digest);
            slot.value_ptr.* = if (slot.found_existing) ambiguous else @intCast(ordinal);
        }
        for (0..module.compounds.items.len) |ordinal| {
            const ty: ir.Type = @fromBackingInt(@intCast(ir.Type.first_compound + ordinal));
            const digest = canons.named.typeDigest(ty) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnknownMetadata => continue,
            };
            const slot = try index.types.getOrPut(a, digest);
            slot.value_ptr.* = if (slot.found_existing) ambiguous else @intCast(ir.Type.first_compound + ordinal);
        }
        if (source.source) |merged| for (merged.origins, 0..) |entry, ordinal| {
            const slot = try index.origins.getOrPut(a, entry.original.keyPath());
            slot.value_ptr.* = if (slot.found_existing) ambiguous else @intCast(ordinal);
        };
        return index;
    }

    /// The function a stored callee name stands for here, or null when it is absent or shared.
    pub fn callee(self: *const Index, name: Digest) ?u32 {
        const found = self.callees.get(name) orelse return null;
        return if (found == ambiguous) null else found;
    }

    /// The compound type a stored name stands for here, or null when it is absent or shared.
    pub fn compound(self: *const Index, name: Digest) ?ir.Type {
        const found = self.types.get(name) orelse return null;
        return if (found == ambiguous) null else @fromBackingInt(found);
    }

    /// The position of the source file a stored key path names, or null when it is absent or shared.
    pub fn origin(self: *const Index, path: []const u8) ?u32 {
        const found = self.origins.get(path) orelse return null;
        return if (found == ambiguous) null else found;
    }
};

/// Capture side: numbers the names a function uses as they are met, so its tables hold each once.
pub const Interner = struct {
    a: std.mem.Allocator,
    canons: Canons,
    source: snapshot.Context,
    callees: std.ArrayList(Digest) = .empty,
    types: std.ArrayList(TypeName) = .empty,
    origins: std.ArrayList([]const u8) = .empty,
    plain: ?[]const u8 = null,

    /// The local index of the callee at module `ordinal`.
    pub fn callee(self: *Interner, ordinal: u32) snapshot.Error!u32 {
        const digest = self.canons.named.callee(ordinal) catch return error.InvalidSnapshot;
        for (self.callees.items, 0..) |known, position| if (std.mem.eql(u8, &known, &digest)) return @intCast(position);
        try self.callees.append(self.a, digest);
        return @intCast(self.callees.items.len - 1);
    }

    /// `ty` with a compound replaced by `first_compound` plus its local index; a builtin stays as it is.
    pub fn typeRef(self: *Interner, ty: ir.Type) snapshot.Error!ir.Type {
        if (!ty.isCompound()) return ty;
        const name: TypeName = .{
            .name = self.canons.named.typeDigest(ty) catch return error.InvalidSnapshot,
            .structure = self.canons.structure.typeDigest(ty) catch return error.InvalidSnapshot,
        };
        for (self.types.items, 0..) |known, position| if (std.meta.eql(known, name)) return @fromBackingInt(@intCast(ir.Type.first_compound + position));
        try self.types.append(self.a, name);
        return @fromBackingInt(@intCast(ir.Type.first_compound + self.types.items.len - 1));
    }

    /// Replace the origin position of `location` by the local index of its key path.
    pub fn location(self: *Interner, at: *snapshot.Location) snapshot.Error!void {
        const merged = self.source.source orelse return;
        const origin = at.origin orelse {
            if (at.point != null) self.plain = merged.keyPath();
            return;
        };
        if (origin >= merged.origins.len) return error.InvalidSnapshot;
        const path = merged.origins[origin].original.keyPath();
        for (self.origins.items, 0..) |known, position| if (std.mem.eql(u8, known, path)) {
            at.origin = @intCast(position);
            return;
        };
        try self.origins.append(self.a, try self.a.dupe(u8, path));
        at.origin = @intCast(self.origins.items.len - 1);
    }

    /// The tables numbered so far.
    pub fn names(self: *const Interner) Names {
        return .{ .callees = self.callees.items, .types = self.types.items, .origins = self.origins.items, .plain = self.plain };
    }

    /// Rewrite the body, the signature and the locations of a captured wire to local names.
    pub fn wire(self: *Interner, captured: *snapshot.Wire) snapshot.Error!void {
        const f = &captured.function;
        for (f.insts) |*inst| {
            switch (inst.op) {
                .call => inst.a = @fromBackingInt(try self.callee(@intCast(inst.a.index()))),
                .func_ref => inst.data = try self.callee(@intCast(inst.data)),
                else => {},
            }
            inst.ty = try self.typeRef(inst.ty);
        }
        f.signature.ret = try self.typeRef(f.signature.ret);
        for (@constCast(f.signature.params)) |*param| param.* = try self.typeRef(param.*);
        for (captured.locations) |*at| try self.location(at);
    }
};

/// Restore side: resolves local indexes against the module being built.
pub const Resolver = struct {
    index: *const Index,
    canons: Canons,
    source: snapshot.Context,
    names: Names,
    /// Whether a type found by name must also have the structure the record saw. A record whose key holds the structure of every
    /// type it uses has no need to check it again.
    verify: bool = true,

    /// The module function a local callee index stands for.
    pub fn callee(self: Resolver, local: u32) ?u32 {
        if (local >= self.names.callees.len) return null;
        return self.index.callee(self.names.callees[local]);
    }

    /// The module type a local type reference stands for, found by its name and kept only if it has the structure the record saw;
    /// a builtin stays as it is.
    pub fn typeRef(self: Resolver, ty: ir.Type) ?ir.Type {
        if (!ty.isCompound()) return ty;
        const local = @backingInt(ty) - ir.Type.first_compound;
        if (local >= self.names.types.len) return null;
        const wanted = self.names.types[local];
        const found = self.index.compound(wanted.name) orelse return null;
        if (!self.verify) return found;
        const structure = self.canons.structure.typeDigest(found) catch return null;
        return if (std.mem.eql(u8, &structure, &wanted.structure)) found else null;
    }

    /// Replace the local origin index of `location` by this module's.
    pub fn location(self: Resolver, at: *snapshot.Location) bool {
        const local = at.origin orelse {
            if (at.point == null) return true;
            const merged = self.source.source orelse return false;
            const stored = self.names.plain orelse return false;
            return merged.origins.len == 0 and std.mem.eql(u8, stored, merged.keyPath());
        };
        if (local >= self.names.origins.len) return false;
        at.origin = self.index.origin(self.names.origins[local]) orelse return false;
        return true;
    }

    /// Rewrite a decoded wire to this module's ordinals in place; false when any name does not resolve.
    pub fn wire(self: Resolver, decoded: *snapshot.Wire) bool {
        const f = &decoded.function;
        for (f.insts) |*inst| {
            switch (inst.op) {
                .call => inst.a = @fromBackingInt(self.callee(@intCast(inst.a.index())) orelse return false),
                .func_ref => inst.data = self.callee(@intCast(inst.data)) orelse return false,
                else => {},
            }
            inst.ty = self.typeRef(inst.ty) orelse return false;
        }
        f.signature.ret = self.typeRef(f.signature.ret) orelse return false;
        for (@constCast(f.signature.params)) |*param| param.* = self.typeRef(param.*) orelse return false;
        for (decoded.locations) |*at| if (!self.location(at)) return false;
        return true;
    }
};
