//! Collision-safe names shared by domain and operation retirement repairs.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Names = @import("module_names.zig").Names;
const Span = source.Span;
const Reserved = struct { name: []const u8 };

/// Exclude ordinary type constructors and resources before looking up owned functions.
pub fn isDomainOwner(src: source.Source, program: ast.Program, names: ?*Names, owner: Span, sink: *diagnostic.Sink) diagnostic.Error!bool {
    const identity = if (names) |module| blk: {
        if ((try module.symbolKind(owner)) != .type) return false;
        break :blk module.reference(owner, .type, null, null, sink) catch |err| switch (err) {
            error.SourceError => return false,
            else => return err,
        };
    } else null;
    for (program.types.domains) |domain| {
        if (identity) |resolved| {
            if (std.mem.eql(u8, resolved, try names.?.declaration(domain.name))) return true;
        } else if (std.mem.eql(u8, src.text(domain.name), src.text(owner))) return true;
    }
    return false;
}

/// Name a lifted member without capturing bindings, declarations or generated names.
pub fn memberName(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, function: ast.Function) error{OutOfMemory}![]const u8 {
    var reserved: std.ArrayList(Reserved) = .empty;
    for (program.functions) |member| {
        const owner = member.policy.owner orelse continue;
        if (!sameModule(src, member.name, function.name)) continue;
        const bare = src.text(member.name);
        const collision = captured(src, program, member) or reservedName(reserved.items, bare);
        const stem = if (collision) try std.fmt.allocPrint(allocator, "{s}_{s}", .{ src.text(owner), bare }) else bare;
        var candidate = stem;
        var suffix: usize = 2;
        if (collision) while (identifierPresent(moduleBytes(src, member.name), candidate) or reservedName(reserved.items, candidate)) : (suffix += 1) {
            candidate = try std.fmt.allocPrint(allocator, "{s}_{d}", .{ stem, suffix });
        };
        try reserved.append(allocator, .{ .name = candidate });
        if (std.meta.eql(member.name, function.name)) return candidate;
    }
    return src.text(function.name);
}
fn reservedName(reserved: []const Reserved, name: []const u8) bool {
    for (reserved) |entry| if (std.mem.eql(u8, entry.name, name)) return true;
    return false;
}
fn captured(src: source.Source, program: ast.Program, member: ast.Function) bool {
    if (declarationsCapture(src, program, member) or bindingsCapture(src, program, member)) return true;
    const bytes = moduleBytes(src, member.name);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "import ")) continue;
        const hash = std.mem.indexOfScalar(u8, line, '#') orelse line.len;
        const path = std.mem.trim(u8, line[7..hash], " \t\r");
        const alias = if (std.mem.lastIndexOf(u8, path, " as ")) |at| path[at + 4 ..] else if (std.mem.lastIndexOfScalar(u8, path, '.')) |at| path[at + 1 ..] else path;
        if (std.mem.eql(u8, alias, src.text(member.name))) return true;
    }
    return false;
}
fn declarationsCapture(src: source.Source, program: ast.Program, member: ast.Function) bool {
    for (program.functions) |function| {
        if (!sameModule(src, function.name, member.name)) continue;
        if (!std.meta.eql(function.name, member.name) and same(src, function.name, member.name)) return true;
        for (function.signature.parameters) |parameter| if (same(src, parameter.name, member.name)) return true;
        for (function.signature.type_parameters) |parameter| if (same(src, parameter.name, member.name)) return true;
    }
    inline for (.{ "domains", "records", "resources", "variants", "constraints" }) |field| {
        for (@field(program.types, field)) |declaration| {
            if (sameModule(src, declaration.name, member.name) and same(src, declaration.name, member.name)) return true;
        }
    }
    for (program.types.expressions.aliases) |declaration| {
        if (sameModule(src, declaration.name, member.name) and same(src, declaration.name, member.name)) return true;
    }
    return false;
}
fn bindingsCapture(src: source.Source, program: ast.Program, member: ast.Function) bool {
    for (program.statements.items) |statement| {
        if (!sameModule(src, statement.span, member.name)) continue;
        const collision = switch (statement.data) {
            .binding => |binding| same(src, binding.name, member.name),
            .for_each => |loop| same(src, loop.name, member.name) or (if (loop.index_name) |name| same(src, name, member.name) else false),
            .for_range => |loop| same(src, loop.name, member.name),
            .with_scope => |scope| if (scope.name) |name| same(src, name, member.name) else false,
            .match => |match| armNames(src, match.arms, member.name),
            else => false,
        };
        if (collision) return true;
    }
    for (program.lambdas) |lambda| {
        if (!sameModule(src, lambda.span, member.name)) continue;
        for (lambda.parameters) |parameter| if (same(src, parameter, member.name)) return true;
    }
    for (program.nodes.items) |node| {
        if (!sameModule(src, node.span, member.name)) continue;
        const collision = switch (node.data) {
            .length => std.mem.eql(u8, src.text(member.name), "len"),
            .replace => std.mem.eql(u8, src.text(member.name), "replace"),
            .name => |name| same(src, name, member.name),
            .call => |call| call.owner == null and same(src, call.name, member.name),
            .comprehension => |comprehension| same(src, comprehension.name, member.name),
            .gather => true,
            .field_assignment => |assignment| assignment.declaration != null,
            .match_expression => |match| armNames(src, match.arms, member.name),
            else => false,
        };
        if (collision) return true;
    }
    return false;
}
fn same(src: source.Source, left: Span, right: Span) bool {
    return std.mem.eql(u8, src.text(left), src.text(right));
}
fn armNames(src: source.Source, arms: []const ast.MatchArm, name: Span) bool {
    for (arms) |arm| {
        for (arm.bindings) |binding| if (binding) |span| if (same(src, span, name)) return true;
        if (patternNames(src, arm.payload_patterns, name)) return true;
    }
    return false;
}
fn patternNames(src: source.Source, fields: []const ast.PatternField, name: Span) bool {
    for (fields) |field| switch (field.pattern.data) {
        .binding => |binding| if (binding) |span| if (same(src, span, name)) return true,
        .variant => |variant| if (patternNames(src, variant.fields, name)) return true,
    };
    return false;
}
fn identifierPresent(bytes: []const u8, candidate: []const u8) bool {
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, offset, candidate)) |at| {
        const end = at + candidate.len;
        const starts_word = at == 0 or !identifierByte(bytes[at - 1]);
        const ends_word = end == bytes.len or !identifierByte(bytes[end]);
        if (starts_word and ends_word) return true;
        offset = end;
    }
    return false;
}
fn identifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}
/// Compare original module identities without depending on source spellings.
pub fn sameModule(src: source.Source, left: Span, right: Span) bool {
    const a = src.originalSpan(left) catch return src.origins.len == 0;
    const b = src.originalSpan(right) catch return false;
    return a.input == b.input;
}

/// Borrow only the stable original module containing a source declaration.
pub fn moduleBytes(src: source.Source, declaration: Span) []const u8 {
    const original = src.originalSpan(declaration) catch return src.bytes;
    return src.origins[original.input].original.bytes;
}
