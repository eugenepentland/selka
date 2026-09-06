//! Resolve generic requirements against the same value operations as concrete code.
const eRequirement = "E_GENERIC_REQUIREMENT";
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
/// Builtin requirements; integer implies equality and equality implies copy.
pub const Requirement = enum(u2) { copy, equality, integer };
/// Closed set of operations promised by an explicitly declared requirement list.
pub const Set = struct {
    bits: u3 = 0,
    /// Include a requirement and its implied prerequisites.
    pub fn include(self: *Set, requirement: Requirement) void {
        self.bits |= switch (requirement) {
            .copy => 1,
            .equality => 3,
            .integer => 7,
        };
    }
    /// Test whether this contract promises a particular operation.
    pub fn contains(self: Set, requirement: Requirement) bool {
        return self.bits & (@as(u3, 1) << @backingInt(requirement)) != 0;
    }
    /// Check implication when forwarding a type parameter to another generic.
    pub fn implies(self: Set, required: Set) bool {
        return self.bits & required.bits == required.bits;
    }
    /// Test a concrete checked type without erasing nominal or result obligations.
    pub fn accepts(self: Set, ty: typed.Type, records: []const typed.Record) bool {
        if (self.contains(.integer) and !ty.isInteger()) return false;
        if (self.contains(.equality) and !typed.supportsEquality(ty, records)) return false;
        if (self.contains(.copy) and (typed.moveOnly(ty, records) or typed.requiresHandling(ty, records))) return false;
        return true;
    }
};
/// Resolved local type-variable identity and its declared operation contract.
pub const Parameter = struct { name: source.Span, requirements: Set };
/// Resolve names and diagnose malformed declarations even in uncalled templates.
pub fn resolve(allocator: std.mem.Allocator, src: source.Source, parameters: []const ast.TypeParameter, sink: *diagnostic.Sink) diagnostic.Error![]const Parameter {
    if (parameters.len == 0) return &.{};
    if (parameters.len > 16) return sink.fail("E_GENERIC_LIMIT", parameters[16].name, "at most 16 type parameters are permitted");
    const resolved = try allocator.alloc(Parameter, parameters.len);
    errdefer allocator.free(resolved);
    for (parameters, resolved, 0..) |parameter, *out, index| {
        const name = src.text(parameter.name);
        if (typed.Type.fromName(name) != null) return sink.fail("E_GENERIC_PARAMETER", parameter.name, "type parameter cannot shadow a builtin type");
        for (parameters[0..index]) |previous| if (std.mem.eql(u8, name, src.text(previous.name))) return sink.fail("E_GENERIC_PARAMETER", parameter.name, "duplicate type parameter");
        out.* = .{ .name = parameter.name, .requirements = try resolveRequirements(src, parameter, sink) };
    }
    return resolved;
}
fn resolveRequirements(src: source.Source, parameter: ast.TypeParameter, sink: *diagnostic.Sink) diagnostic.Error!Set {
    if (parameter.requirements.len == 0) return sink.fail(eRequirement, parameter.name, "type parameter requires an explicit requirement");
    if (parameter.requirements.len > 16) return sink.fail("E_GENERIC_LIMIT", parameter.requirements[16], "at most 16 requirements are permitted");
    var result: Set = .{};
    var explicit: u3 = 0;
    for (parameter.requirements) |span| {
        const requirement = std.meta.stringToEnum(Requirement, src.text(span)) orelse return sink.fail(eRequirement, span, "unknown requirement; expected copy, equality, or integer");
        const bit = @as(u3, 1) << @backingInt(requirement);
        if (explicit & bit != 0) return sink.fail(eRequirement, span, "duplicate type requirement");
        explicit |= bit;
        result.include(requirement);
    }
    return result;
}
