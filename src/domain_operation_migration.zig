//! Replace structural operations and named bounds with explicit callback parameters.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const lex = @import("lexer.zig");
const requirements = @import("generic_requirements.zig");
const protocol = @import("domain_migration_protocol.zig");
const syntax = @import("domain_migration_spans.zig");
const naming = @import("domain_migration_names.zig");
const Names = @import("module_names.zig").Names;
const Span = source.Span;
const Edit = diagnostic.Edit;
const Slot = struct { function: ast.Function, parameter: usize, operation: ast.Operation, aliases: []const requirements.SubjectAlias };

/// Publish callback migrations only when operation providers can be resolved exactly.
pub fn reject(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, names: ?*Names, sink: *diagnostic.Sink, checked: ?*const typed.Program) diagnostic.Error!void {
    var pass: Pass = .{ .allocator = allocator, .src = src, .program = program, .names = names, .sink = sink, .checked = checked };
    try pass.run();
}
const Pass = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    names: ?*Names,
    sink: *diagnostic.Sink,
    checked: ?*const typed.Program,
    slots: []const Slot = &.{},

    fn report(self: Pass, at: Span, edits: []const Edit) !void {
        for (self.sink.items.items) |item| if (std.mem.eql(u8, item.code, protocol.removed_code) and std.meta.eql(item.span, at)) return;
        const item: diagnostic.Diagnostic = .{
            .code = protocol.removed_code,
            .span = at,
            .message = if (self.checked == null or edits.len == 0) protocol.deferred_message else "type-owned operations and named constraints were removed; pass each operation as a function value",
            .related = if (self.checked != null and edits.len == 0) .{
                .span = at,
                .message = "no certain automatic repair is available here; qualify the required types or rewrite the constraint manually before migrating dependent sites",
            } else null,
        };
        if (self.checked == null or edits.len == 0) return self.sink.items.append(self.allocator, item);
        try self.sink.appendFix(item, edits[0]);
        self.sink.items.items[self.sink.items.items.len - 1].provenance.fix.?.more = edits[1..];
    }

    fn run(self: *Pass) diagnostic.Error!void {
        var provider: @import("constraint_lookup.zig").Provider = .{ .program = self.program, .src = self.src, .names = self.names };
        var slots: std.ArrayList(Slot) = .empty;
        var blocked: std.ArrayList(Span) = .empty;
        const tokens = try lex.lex(self.allocator, self.src.bytes, self.sink);
        for (self.program.functions) |function| {
            const resolved = requirements.resolveBounds(self.allocator, self.src, function.signature.type_parameters, self.sink, provider.lookup()) catch |err| switch (err) {
                error.SourceError => continue,
                else => return err,
            };
            for (function.signature.type_parameters, resolved, 0..) |parameter, bound, index| {
                if (parameter.operation_requirements.len == 0 and parameter.named_requirements.len == 0) continue;
                if (!self.typesCertain(function, bound)) {
                    const lookup = provider.lookup();
                    for (parameter.named_requirements) |reference| {
                        const definition = try lookup.find(lookup.ctx, reference, self.sink);
                        try blocked.append(self.allocator, definition.name);
                    }
                    try self.report(parameter.name, &.{});
                    continue;
                }
                var edits: std.ArrayList(Edit) = .empty;
                const region = boundRegion(tokens, parameter.name) orelse {
                    try self.report(parameter.name, &.{});
                    continue;
                };
                try edits.append(self.allocator, .{ .span = region, .text = try self.boundText(parameter, bound) });
                for (bound.operation_requirements, 0..) |operation, operation_index| {
                    const duplicate = for (bound.operation_requirements[0..operation_index]) |previous| {
                        if (std.mem.eql(u8, self.src.text(previous.name), self.src.text(operation.name))) break true;
                    } else false;
                    if (duplicate) continue;
                    const slot: Slot = .{ .function = function, .parameter = index, .operation = operation, .aliases = requirements.subjectAliases(bound) };
                    try slots.append(self.allocator, slot);
                }
                try self.report(parameter.name, try edits.toOwnedSlice(self.allocator));
            }
        }
        self.slots = slots.items;
        for (self.program.types.constraints) |constraint| {
            const uncertain = for (blocked.items) |name| {
                if (std.meta.eql(name, constraint.name)) break true;
            } else false;
            try self.report(constraint.name, if (uncertain) &.{} else try self.allocator.dupe(Edit, &.{.{ .span = declarationLine(self.src.bytes, constraint.span), .text = "" }}));
        }
        try self.signatures(tokens);
        try self.calls(tokens);
    }

    fn signatures(self: Pass, tokens: []const lex.Token) diagnostic.Error!void {
        for (self.program.functions) |function| {
            const close = syntax.callClose(tokens, function.name.end) orelse continue;
            const trailing_comma = previousTag(tokens, close) == .comma;
            var additions: std.Io.Writer.Allocating = .init(self.allocator);
            for (self.slots) |slot| {
                if (!std.meta.eql(slot.function.name, function.name)) continue;
                if (additions.written().len != 0 or (function.signature.parameters.len != 0 and !trailing_comma)) additions.writer.writeAll(", ") catch return error.OutOfMemory;
                additions.writer.print("named {s}: func(", .{try self.callbackName(slot)}) catch return error.OutOfMemory;
                for (slot.operation.parameters, 0..) |parameter, index| {
                    if (index != 0) additions.writer.writeAll(", ") catch return error.OutOfMemory;
                    additions.writer.writeAll(try self.slotType(slot, parameter.ty)) catch return error.OutOfMemory;
                }
                additions.writer.print(") -> {s}", .{try self.slotType(slot, slot.operation.return_type)}) catch return error.OutOfMemory;
            }
            if (additions.written().len != 0) {
                const at = close;
                try self.report(.{ .start = at, .end = at }, try self.allocator.dupe(Edit, &.{.{ .span = .{ .start = at, .end = at }, .text = try additions.toOwnedSlice() }}));
            }
        }
    }
    fn calls(self: Pass, tokens: []const lex.Token) diagnostic.Error!void {
        for (self.program.nodes.items) |original_node| {
            if (original_node.data != .call) continue;
            var node = original_node;
            node.data.call = (try @import("call_type_arguments.zig").split(self.src, self.program, self.names, original_node.data.call, self.sink)) orelse original_node.data.call;
            const call = node.data.call;
            const close = syntax.callClose(tokens, call.name.end) orelse continue;
            if (call.owner) |owner| {
                var rewritten = false;
                if (self.enclosingFunction(node.span)) |enclosing| for (self.slots) |slot| {
                    if (!std.meta.eql(slot.function.name, enclosing.name)) continue;
                    if (!std.mem.eql(u8, self.src.text(enclosing.signature.type_parameters[slot.parameter].name), self.src.text(owner))) continue;
                    if (!std.mem.eql(u8, self.src.text(slot.operation.name), self.src.text(call.name))) continue;
                    try self.report(node.span, try self.allocator.dupe(Edit, &.{.{ .span = .{ .start = owner.start, .end = call.name.end }, .text = try self.callbackName(slot) }}));
                    rewritten = true;
                };
                if (rewritten) continue;
            }
            const spelling = self.src.text(call.name);
            const bare = if (std.mem.lastIndexOfScalar(u8, spelling, '.')) |dot| spelling[dot + 1 ..] else spelling;
            const relevant = for (self.slots) |slot| {
                if (std.mem.eql(u8, self.src.text(slot.function.name), bare)) break true;
            } else false;
            if (!relevant) continue;
            const callee = try self.calledFunction(node) orelse continue;
            var additions: std.Io.Writer.Allocating = .init(self.allocator);
            var certain = true;
            for (self.slots) |slot| {
                if (!std.meta.eql(slot.function.name, callee.name)) continue;
                const argument = try self.callbackArgument(node, slot, self.slots) orelse {
                    certain = false;
                    break;
                };
                if (additions.written().len != 0 or (call.arguments.len != 0 and previousTag(tokens, close) != .comma)) additions.writer.writeAll(", ") catch return error.OutOfMemory;
                additions.writer.print("{s}={s}", .{ try self.callbackName(slot), argument }) catch return error.OutOfMemory;
            }
            if (!certain) {
                try self.sink.items.append(self.allocator, .{
                    .code = protocol.removed_code,
                    .span = node.span,
                    .message = protocol.deferred_message,
                    .related = .{
                        .span = node.span,
                        .message = "no certain operation provider is available independently of specialization; pass explicit type arguments or rewrite this call manually",
                    },
                });
                continue;
            }
            if (additions.written().len != 0) {
                const at = close;
                try self.report(.{ .start = at, .end = at }, try self.allocator.dupe(Edit, &.{.{ .span = .{ .start = at, .end = at }, .text = try additions.toOwnedSlice() }}));
            }
        }
    }

    fn boundText(self: Pass, parameter: ast.TypeParameter, bound: requirements.Parameter) error{OutOfMemory}![]const u8 {
        var output: std.Io.Writer.Allocating = .init(self.allocator);
        var first = true;
        inline for (.{ .copy, .equality, .integer, .codec, .storable }) |requirement| {
            const redundant = switch (requirement) {
                .copy => bound.requirements.contains(.equality) or bound.requirements.contains(.integer),
                .equality => bound.requirements.contains(.integer),
                .storable => bound.requirements.contains(.copy) or bound.requirements.contains(.equality) or bound.requirements.contains(.integer),
                else => false,
            };
            if (bound.requirements.contains(requirement) and !redundant) {
                output.writer.writeAll(if (first) ": " else " + ") catch return error.OutOfMemory;
                first = false;
                output.writer.writeAll(@tagName(requirement)) catch return error.OutOfMemory;
            }
        }
        for (bound.field_requirements, 0..) |field, index| {
            const duplicate = for (bound.field_requirements[0..index]) |previous| {
                if (std.mem.eql(u8, self.src.text(previous.name), self.src.text(field.name))) break true;
            } else false;
            if (duplicate) continue;
            output.writer.writeAll(if (first) ": " else " + ") catch return error.OutOfMemory;
            first = false;
            const ty = try self.aliasedType(field.ty, requirements.subjectAliases(bound), parameter.name);
            output.writer.print("field({s}: {s})", .{ self.src.text(field.name), ty }) catch return error.OutOfMemory;
        }
        return output.toOwnedSlice();
    }

    fn callbackName(self: Pass, requested: Slot) ![]const u8 {
        var reserved: std.ArrayList([]const u8) = .empty;
        for (self.slots) |slot| {
            if (!std.meta.eql(slot.function.name, requested.function.name)) continue;
            const stem = try std.fmt.allocPrint(self.allocator, "domain_op_{s}_{s}", .{ self.src.text(slot.function.signature.type_parameters[slot.parameter].name), self.src.text(slot.operation.name) });
            var candidate = stem;
            var suffix: usize = 2;
            while (std.mem.indexOf(u8, naming.moduleBytes(self.src, slot.function.name), candidate) != null or nameReserved(reserved.items, candidate)) : (suffix += 1) {
                candidate = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ stem, suffix });
            }
            try reserved.append(self.allocator, candidate);
            if (slot.parameter == requested.parameter and std.meta.eql(slot.operation.name, requested.operation.name)) return candidate;
        }
        return error.InternalError;
    }
    fn slotType(self: Pass, slot: Slot, span: Span) ![]const u8 {
        return self.aliasedType(span, slot.aliases, slot.function.signature.type_parameters[slot.parameter].name);
    }
    fn typeBinder(self: Pass, span: Span) bool {
        for (self.program.types.expressions.callbacks) |callback| for (callback.parameter_names) |name| {
            if (name != null and std.meta.eql(name.?, span)) return true;
        };
        return false;
    }

    fn aliasedType(self: Pass, span: Span, aliases: []const requirements.SubjectAlias, name: Span) error{OutOfMemory}![]const u8 {
        var output: std.Io.Writer.Allocating = .init(self.allocator);
        const text = self.src.text(span);
        var at: usize = 0;
        while (at < text.len) {
            const start = at;
            if (!std.ascii.isAlphabetic(text[at]) and text[at] != '_') {
                at += 1;
                output.writer.writeAll(text[start..at]) catch return error.OutOfMemory;
                continue;
            }
            at += 1;
            while (at < text.len and (std.ascii.isAlphanumeric(text[at]) or text[at] == '_')) at += 1;
            var replacement = text[start..at];
            for (aliases) |alias| {
                if (span.start < alias.scope.start or span.end > alias.scope.end) continue;
                if (qualifiedWord(text, start) or self.typeBinder(.{ .start = span.start + start, .end = span.start + at })) continue;
                if (std.mem.eql(u8, replacement, self.src.text(alias.name))) replacement = self.src.text(name);
            }
            output.writer.writeAll(replacement) catch return error.OutOfMemory;
        }
        return output.toOwnedSlice();
    }
    fn typesCertain(self: Pass, function: ast.Function, bound: requirements.Parameter) bool {
        const aliases = requirements.subjectAliases(bound);
        for (bound.field_requirements) |field| if (!self.typeCertain(function.name, field.ty, aliases)) return false;
        for (bound.operation_requirements) |operation| {
            if (!self.typeCertain(function.name, operation.return_type, aliases)) return false;
            for (operation.parameters) |parameter| if (!self.typeCertain(function.name, parameter.ty, aliases)) return false;
        }
        return true;
    }
    fn typeCertain(self: Pass, consumer: Span, span: Span, aliases: []const requirements.SubjectAlias) bool {
        if (naming.sameModule(self.src, consumer, span)) return true;
        const text = self.src.text(span);
        var at: usize = 0;
        while (at < text.len) {
            if (!std.ascii.isAlphabetic(text[at]) and text[at] != '_') {
                at += 1;
                continue;
            }
            const start = at;
            at += 1;
            while (at < text.len and (std.ascii.isAlphanumeric(text[at]) or text[at] == '_')) at += 1;
            const word = text[start..at];
            if (typed.Type.fromName(word) != null) continue;
            const subject = for (aliases) |alias| {
                if (span.start >= alias.scope.start and span.end <= alias.scope.end and std.mem.eql(u8, word, self.src.text(alias.name))) break true;
            } else false;
            if (subject) continue;
            const builtin = for ([_][]const u8{ "dict", "set", "FixedArray", "func", "effects", "noio", "noalloc", "Unit", "mut", "named", "str", "bytes", "float" }) |name| {
                if (std.mem.eql(u8, word, name)) break true;
            } else false;
            if (!builtin) return false;
        }
        return true;
    }
    fn enclosingFunction(self: Pass, span: Span) ?ast.Function {
        for (self.program.functions) |function| {
            const body = self.program.statements.items[@backingInt(function.body)].span;
            if (body.start <= span.start and body.end >= span.end) return function;
        }
        return null;
    }
    fn calledFunction(self: Pass, node: ast.Node) diagnostic.Error!?ast.Function {
        const call = node.data.call;
        if (call.owner) |owner| if (!try naming.isDomainOwner(self.src, self.program, self.names, owner, self.sink)) return null;
        const identity = if (self.names) |names| if (call.owner) |owner|
            names.reference(owner, .function, call.name, self.src.text(owner), self.sink) catch |err| switch (err) {
                error.SourceError => return null,
                else => return err,
            }
        else
            names.reference(call.name, .function, null, null, self.sink) catch |err| switch (err) {
                error.SourceError => return null,
                else => return err,
            } else null;
        for (self.program.functions) |function| {
            if ((call.owner == null) != (function.policy.owner == null)) continue;
            if (identity) |resolved| {
                const declaration = try self.names.?.functionDeclaration(function.policy.owner, function.name);
                if (!std.mem.eql(u8, resolved, declaration)) continue;
            } else {
                if (!std.mem.eql(u8, self.src.text(function.name), self.src.text(call.name))) continue;
                if (call.owner) |owner| if (!std.mem.eql(u8, self.src.text(function.policy.owner.?), self.src.text(owner))) continue;
            }
            return function;
        }
        return null;
    }
    fn callbackArgument(self: Pass, node: ast.Node, slot: Slot, slots: []const Slot) diagnostic.Error!?[]const u8 {
        const target = try self.inferredTarget(node, slot);
        if (target == null) if (self.enclosingFunction(node.span)) |enclosing| {
            if (enclosing.signature.type_parameters.len != 0) return null;
        };
        if (target) |actual| if (self.enclosingFunction(node.span)) |enclosing| {
            for (slots) |provided| {
                if (!std.meta.eql(provided.function.name, enclosing.name)) continue;
                if (!std.mem.eql(u8, self.src.text(enclosing.signature.type_parameters[provided.parameter].name), self.src.text(actual))) continue;
                if (std.mem.eql(u8, self.src.text(slot.operation.name), self.src.text(provided.operation.name))) {
                    const callback = try self.callbackName(provided);
                    return callback;
                }
            }
        };
        const declaration = try self.providerDeclaration(node, slot, target);
        const owner = declaration orelse return null;
        for (self.program.functions) |function| {
            if (!std.meta.eql(function.policy.owner orelse continue, owner)) continue;
            if (!std.mem.eql(u8, self.src.text(function.name), self.src.text(slot.operation.name))) continue;
            const renamed = try naming.memberName(self.allocator, self.src, self.program, function);
            if (naming.sameModule(self.src, node.span, owner)) return renamed;
            const names = self.names orelse return null;
            const from = self.src.originalSpan(node.span) catch return null;
            const to = self.src.originalSpan(owner) catch return null;
            for (names.index.project.modules.items[from.input].imports) |imported| {
                if (imported.target == to.input) {
                    const qualified = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ imported.alias, renamed });
                    return qualified;
                }
            }
            return null;
        }
        return null;
    }
    fn genericTypeText(self: Pass, span: Span, subject: ?Span, replacement: ?Span) ![]const u8 {
        const text = if (subject) |formal|
            try self.aliasedType(span, &.{.{ .name = formal, .scope = span, .parameter = 0 }}, replacement.?)
        else
            self.src.text(span);
        var output: std.ArrayList(u8) = .empty;
        for (text) |byte| if (!std.ascii.isWhitespace(byte)) try output.append(self.allocator, byte);
        return output.toOwnedSlice(self.allocator);
    }

    fn forwardedType(self: Pass, enclosing: ast.Function, formal: Span, provided: Span, subject: Span) !?Span {
        if (std.mem.eql(u8, self.src.text(formal), self.src.text(subject))) return provided;
        const actual = try self.genericTypeText(provided, null, null);
        const original = try self.genericTypeText(formal, null, null);
        const removed = try self.genericTypeText(formal, subject, .{ .start = subject.start, .end = subject.start });
        if (std.mem.eql(u8, original, removed)) return null;
        for (enclosing.signature.type_parameters) |candidate| {
            const expected = try self.genericTypeText(formal, subject, candidate.name);
            if (std.mem.eql(u8, expected, actual)) return candidate.name;
        }
        return null;
    }

    fn inferredTarget(self: Pass, node: ast.Node, slot: Slot) !?Span {
        const call = @import("call_arguments.zig").bind(self.allocator, self.src, self.program.nodes.items, node.data.call, slot.function.signature, self.sink) catch |err| switch (err) {
            error.SourceError => return null,
            else => return err,
        };
        if (slot.parameter < call.type_arguments.len) return call.type_arguments[slot.parameter];
        const enclosing = self.enclosingFunction(node.span) orelse return null;
        const subject = slot.function.signature.type_parameters[slot.parameter].name;
        for (slot.function.signature.parameters, 0..) |parameter, index| {
            if (index >= call.arguments.len) continue;
            const argument = self.program.nodes.items[@backingInt(call.arguments[index])];
            if (argument.data != .name) continue;
            for (enclosing.signature.parameters) |provided| {
                if (!std.mem.eql(u8, self.src.text(provided.name), self.src.text(argument.data.name))) continue;
                if (try self.forwardedType(enclosing, parameter.ty, provided.ty, subject)) |target| return target;
            }
        }
        return null;
    }
    fn providerDeclaration(self: Pass, node: ast.Node, slot: Slot, target: ?Span) diagnostic.Error!?Span {
        var declaration: ?Span = null;
        if (self.checked) |checked| for (checked.nodes) |typed_node| {
            if (!std.meta.eql(typed_node.span, node.span) or typed_node.data != .call) continue;
            const function = checked.functions[@backingInt(typed_node.data.call.function)];
            if (slot.parameter >= function.type_arguments.len) continue;
            const ty = function.type_arguments[slot.parameter];
            if (ty.isAggregate()) declaration = checked.records[ty.recordIndex()].declaration;
            break;
        };
        if (declaration == null and target != null) {
            const identity = if (self.names) |names| names.reference(target.?, .type, null, null, self.sink) catch |err| switch (err) {
                error.SourceError => return null,
                else => return err,
            } else null;
            for (self.program.types.domains) |domain| {
                if (identity) |resolved| {
                    if (!std.mem.eql(u8, resolved, try self.names.?.declaration(domain.name))) continue;
                } else if (!std.mem.eql(u8, self.src.text(domain.name), self.src.text(target.?))) continue;
                declaration = domain.name;
                break;
            }
        }
        return declaration;
    }
};

fn boundRegion(tokens: []const lex.Token, name: Span) ?Span {
    var depth: usize = 0;
    for (tokens) |token| {
        if (token.span.start < name.end) continue;
        switch (token.tag) {
            .lparen, .lbracket => depth += 1,
            .rbracket => if (depth == 0) return .{ .start = name.end, .end = token.span.start } else {
                depth -= 1;
            },
            .rparen => if (depth != 0) {
                depth -= 1;
            },
            .comma => if (depth == 0) return .{ .start = name.end, .end = token.span.start },
            else => {},
        }
    }
    return null;
}

fn declarationLine(bytes: []const u8, span: Span) Span {
    const start = if (std.mem.lastIndexOfScalar(u8, bytes[0..span.start], '\n')) |at| at + 1 else 0;
    const end = if (std.mem.indexOfScalarPos(u8, bytes, span.end, '\n')) |at| at + 1 else bytes.len;
    return .{ .start = start, .end = end };
}

fn nameReserved(names: []const []const u8, candidate: []const u8) bool {
    for (names) |name| if (std.mem.eql(u8, name, candidate)) return true;
    return false;
}

fn previousTag(tokens: []const lex.Token, before: usize) ?lex.Tag {
    var previous: ?lex.Tag = null;
    for (tokens) |token| {
        if (token.span.start >= before) break;
        previous = token.tag;
    }
    return previous;
}

fn qualifiedWord(bytes: []const u8, start: usize) bool {
    var previous = start;
    while (previous != 0 and std.ascii.isWhitespace(bytes[previous - 1])) previous -= 1;
    return previous != 0 and bytes[previous - 1] == '.';
}
