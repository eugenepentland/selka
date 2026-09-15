//! Declaration-aware named-constraint lookup over merged or single-file syntax.
//! Keeps the requirement resolver free of the project index and its import cycle.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const requirements = @import("generic_requirements.zig");
const Names = @import("module_names.zig").Names;

/// Owns the syntax context a `Lookup` borrows; the provider must outlive it.
pub const Provider = struct {
    program: ast.Program,
    src: source.Source,
    names: ?*Names = null,

    /// Borrow this provider as a resolution seam for one check.
    pub fn lookup(self: *Provider) requirements.Lookup {
        return .{ .ctx = @ptrCast(self), .find = find };
    }

    fn find(ctx: *anyopaque, reference: ast.BoundReference, sink: *diagnostic.Sink) diagnostic.Error!requirements.Definition {
        const self: *Provider = @ptrCast(@alignCast(ctx));
        if (self.names) |names| return self.findIndexed(names, reference, sink);
        return self.findLocal(reference, sink);
    }

    fn findIndexed(self: *Provider, names: *Names, reference: ast.BoundReference, sink: *diagnostic.Sink) diagnostic.Error!requirements.Definition {
        const identity = try names.constraintIdentity(reference, sink);
        const symbol = names.index.units[identity.module].symbols.items[identity.symbol];
        for (self.program.types.constraints) |*constraint| {
            const original = self.src.originalSpan(constraint.name) catch return error.InternalError;
            if (original.input != identity.module) continue;
            if (original.span.start != symbol.span.start or original.span.end != symbol.span.end) continue;
            return self.definition(identity.module, constraint);
        }
        return sink.fail(diagnostic.generic_requirement, reference.name, "named constraint is not present in the checked syntax");
    }

    fn findLocal(self: *Provider, reference: ast.BoundReference, sink: *diagnostic.Sink) diagnostic.Error!requirements.Definition {
        if (reference.alias != null) return sink.fail(diagnostic.generic_requirement, reference.name, "a qualified constraint name requires module syntax");
        const name = self.src.text(reference.name);
        for (self.program.types.constraints) |*constraint| {
            if (!std.mem.eql(u8, name, self.src.text(constraint.name))) continue;
            return self.definition(null, constraint);
        }
        return sink.fail(diagnostic.generic_requirement, reference.name, "unknown constraint name");
    }

    fn definition(self: *Provider, module: ?usize, constraint: *const ast.Constraint) requirements.Definition {
        return .{
            .module = module,
            .name = constraint.name,
            .subject = constraint.subject.name,
            .scope = constraint.span,
            .body = &constraint.subject,
            .copyable = requirements.explicitCopyable(self.src, constraint.subject.requirements),
        };
    }
};
