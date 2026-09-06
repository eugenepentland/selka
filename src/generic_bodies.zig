//! Symbolic checking of pure template bodies; no representative concrete type is substituted.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const requirements = @import("generic_requirements.zig");
const Error = diagnostic.Error;
const Names = @import("module_names.zig").Names;
const eShadowing = diagnostic.shadowing;
const eResultOperation = diagnostic.result_operation;
const eResultPath = diagnostic.result_path;
const eTryReturn = "E_TRY_RETURN";
const eUnsupported = "E_GENERIC_BODY_UNSUPPORTED";
const Catalog = @import("records.zig").Catalog;
const Symbolic = union(enum) { concrete: typed.Type, parameter: usize };
const Call = @FieldType(@FieldType(ast.Node, "data"), "call");
const FunctionMap = std.StringHashMapUnmanaged(usize);
const Return = struct { parameter: usize, mutable: bool, slice: bool };
const Pending = struct { available: bool, fields: []const bool };
const Local = struct {
    name: source.Span,
    ty: Symbolic,
    mutable: bool,
    available: bool = true,
    fields: []const bool = &.{},
    reference: ?bool = null,
    slice: bool = false,
    root: ?usize = null,
    children: usize = 0,
    shared: usize = 0,
    exclusive: usize = 0,
};
const Checker = struct {
    allocator: std.mem.Allocator,
    field_arena: std.heap.ArenaAllocator,
    src: source.Source,
    program: ast.Program,
    catalog: Catalog,
    concrete_checked: []bool,
    sink: *diagnostic.Sink,
    parameters: []const requirements.Parameter,
    result: Symbolic,
    return_reference: ?Return = null,
    functions: *const FunctionMap,
    pending: *std.ArrayList(usize),
    scheduled: []bool,
    owner: ?source.Span = null,
    module_names: ?*Names = null,
    locals: std.ArrayList(Local) = .empty,
    active: std.StringHashMapUnmanaged(usize) = .empty,
    depth: usize = 0,
    work: usize = 0,
    expression_depth: usize = 0,
    temporary_results: usize = 0,
    fn enter(self: *Checker, span: source.Span) Error!void {
        if (self.depth == 256 or self.work == 100000) return self.sink.fail("E_GENERIC_BODY_LIMIT", span, "generic body exceeds checking depth/work budget");
        self.depth += 1;
        self.work += 1;
    }
    fn ty(self: *Checker, span: source.Span) Error!Symbolic {
        const text = self.src.text(span);
        for (self.parameters, 0..) |parameter, index| if (std.mem.eql(u8, text, self.src.text(parameter.name))) return .{ .parameter = index };
        return self.concreteType(span);
    }
    fn concreteType(self: *Checker, span: source.Span) Error!Symbolic {
        const ty_value = try self.catalog.resolve(self.src, span, self.sink);
        if (ty_value.isAggregate() and !self.concrete_checked[ty_value.recordIndex()]) {
            @import("data_type.zig").check(self.allocator, self.catalog.records, ty_value, true) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return self.sink.fail(eUnsupported, span, "concrete generic values require complete copyable data graphs without runtime identities");
            };
            self.concrete_checked[ty_value.recordIndex()] = true;
        }
        return .{ .concrete = ty_value };
    }
    fn requiresHandling(self: *Checker, value: Symbolic) bool {
        return switch (value) {
            .concrete => |ty_value| typed.requiresHandling(ty_value, self.catalog.records),
            .parameter => false,
        };
    }
    fn pendingObligation(self: *Checker, binding: Local) bool {
        if (binding.reference != null or !binding.available) return false;
        if (!self.requiresHandling(binding.ty)) return false;
        if (binding.fields.len == 0) return true;
        const record = self.catalog.records[binding.ty.concrete.recordIndex()];
        for (record.fields, binding.fields) |field, moved| {
            if (!moved and self.requiresHandling(.{ .concrete = field.ty })) return true;
        }
        return false;
    }
    fn requireHandled(self: *Checker, first: usize, span: source.Span) Error!void {
        for (self.locals.items[first..]) |binding| {
            if (self.pendingObligation(binding))
                return self.sink.failRelated("E_RESULT_UNHANDLED", span, "result-bearing binding leaves scope without handling or transfer", .{ .span = binding.name, .message = "unhandled result-bearing binding" });
        }
    }
    fn pendingState(self: *Checker, count: usize) Error![]Pending {
        const state = try self.allocator.alloc(Pending, count);
        for (self.locals.items[0..count], state) |binding, *pending| pending.* = .{ .available = binding.available, .fields = binding.fields };
        return state;
    }
    fn restorePending(self: *Checker, state: []const Pending) void {
        for (self.locals.items[0..state.len], state) |*binding, pending| {
            binding.available = pending.available;
            binding.fields = pending.fields;
        }
    }
    fn samePending(self: *Checker, state: []const Pending, span: source.Span, code: []const u8) Error!void {
        for (self.locals.items[0..state.len], state) |binding, pending| {
            const fields_match = std.mem.eql(bool, binding.fields, pending.fields);
            if (binding.available != pending.available or !fields_match) return self.sink.failRelated(
                code,
                span,
                "result obligation must agree on every continuing path",
                .{ .span = binding.name, .message = "binding declared here" },
            );
        }
    }
    fn concreteValue(self: *Checker, value: Symbolic, span: source.Span) Error!typed.Type {
        return switch (value) {
            .concrete => |ty_value| ty_value,
            .parameter => self.sink.fail(eUnsupported, span, "structural operations require a concrete type; parameter shapes need declared constraints"),
        };
    }
    fn same(self: *Checker, actual: Symbolic, expected: Symbolic, span: source.Span) Error!void {
        if (!std.meta.eql(actual, expected)) return self.sink.fail("E_GENERIC_TYPE", span, "types differ; distinct type parameters remain distinct even with identical requirements");
    }
    fn supports(self: *Checker, ty_value: Symbolic, requirement: requirements.Requirement, span: source.Span) Error!void {
        const supported = switch (ty_value) {
            .parameter => |index| self.parameters[index].requirements.contains(requirement),
            .concrete => |builtin| result: {
                var required: requirements.Set = .{};
                required.include(requirement);
                break :result required.accepts(builtin, self.catalog.records);
            },
        };
        if (!supported) {
            const message = try std.fmt.allocPrint(self.sink.allocator, "operation requires declared {s} support", .{@tagName(requirement)});
            return self.sink.fail("E_GENERIC_OPERATION", span, message);
        }
    }
    fn local(self: *Checker, span: source.Span) Error!*Local {
        const index = self.active.get(self.src.text(span)) orelse return self.sink.fail("E_UNKNOWN_NAME", span, "name is not defined in this template scope");
        return &self.locals.items[index];
    }
    fn reference(self: *Checker, span: source.Span, mutable: bool, slice: bool) Error!*Local {
        const value = try self.local(span);
        const exclusive = value.reference orelse return self.sink.fail("E_REFERENCE_SCOPE", span, "operation requires an active reference");
        if (exclusive and value.children != 0) return self.sink.fail("E_BORROW_SUSPENDED", span, "exclusive reference is suspended while a child borrow is active");
        if (value.slice != slice) return self.sink.fail("E_REFERENCE_KIND", span, "whole-value references and slices are distinct");
        if (mutable and !exclusive) return self.sink.fail(diagnostic.reference_read_only, span, "write or exclusive forwarding requires an exclusive reference");
        return value;
    }
    fn namedValue(self: *Checker, span: source.Span) Error!Symbolic {
        const binding = try self.local(span);
        if (binding.reference != null) return self.sink.fail("E_REFERENCE_VALUE", span, "references require read_ref or an explicit reference parameter");
        try self.ownerAccess(binding.*, false, span);
        if (binding.fields.len != 0) return self.sink.fail("E_PARTIAL_MOVE", span, "record has missing fields; access remaining fields individually or replace it");
        if (self.requiresHandling(binding.ty)) {
            if (!binding.available) return self.sink.fail("E_RESULT_CONSUMED", span, "result-bearing binding was already transferred");
            binding.available = false;
        }
        return binding.ty;
    }
    fn ownerAccess(self: *Checker, binding: Local, write: bool, span: source.Span) Error!void {
        if (binding.exclusive != 0 or (write and binding.shared != 0)) return self.sink.fail("E_BORROW_CONFLICT", span, "owner access conflicts with an active borrow");
    }
    fn endScope(self: *Checker, before: usize) void {
        for (self.locals.items[before..]) |item| _ = self.active.remove(self.src.text(item.name));
        self.locals.shrinkRetainingCapacity(before);
    }
    fn borrowScope(self: *Checker, borrow: @FieldType(@FieldType(ast.Statement, "data"), "borrow")) Error!bool {
        if (borrow.range) |range| {
            try self.supports(try self.expression(range.start), .integer, borrow.owner);
            try self.supports(try self.expression(range.end), .integer, borrow.owner);
        }
        const binding = (try self.local(borrow.owner)).*;
        const owner_index = self.active.get(self.src.text(borrow.owner)).?;
        const parent: ?usize = if (binding.reference != null) owner_index else null;
        if (parent != null) {
            _ = try self.reference(borrow.owner, borrow.mutable, binding.slice);
        } else {
            if (borrow.mutable and !binding.mutable) return self.sink.fail("E_IMMUTABLE", borrow.owner, "exclusive borrowing requires a mutable owner");
            try self.ownerAccess(binding, borrow.mutable, borrow.owner);
        }
        if (borrow.range != null and !binding.slice) return self.sink.fail(eUnsupported, borrow.owner, "generic range borrowing requires a known slice input");
        if (self.requiresHandling(binding.ty)) return self.sink.fail("E_RESULT_BORROW", borrow.owner, "result-bearing values must transfer by value");
        try self.supports(binding.ty, .copy, borrow.owner);
        return self.loanScope(.{ .name = borrow.name, .ty = binding.ty, .mutable = false, .reference = borrow.mutable, .slice = binding.slice, .root = binding.root orelse owner_index }, parent, borrow.body);
    }
    fn loanScope(self: *Checker, child: Local, parent: ?usize, body: ast.StatementId) Error!bool {
        const root = child.root.?;
        const mutable = child.reference.?;
        const before = self.locals.items.len;
        try self.bind(child.name, child.ty, false);
        defer self.endScope(before);
        self.locals.items[before] = child;
        if (mutable) self.locals.items[root].exclusive += 1 else self.locals.items[root].shared += 1;
        if (parent) |id| self.locals.items[id].children += 1;
        defer {
            if (mutable) self.locals.items[root].exclusive -= 1 else self.locals.items[root].shared -= 1;
            if (parent) |id| self.locals.items[id].children -= 1;
        }
        return self.statement(body);
    }
    fn provenance(self: *Checker, function: ast.Function) Error!?Return {
        const contract = function.signature.return_reference orelse return null;
        for (function.signature.parameters, 0..) |parameter, index| {
            if (!std.mem.eql(u8, self.src.text(parameter.name), self.src.text(contract.source))) continue;
            const mutable = parameter.reference orelse return self.sink.fail(diagnostic.return_lifetime, contract.source, "reference result requires a reference input");
            if (contract.mutable and !mutable) return self.sink.fail(diagnostic.reference_read_only, contract.source, "shared input cannot supply an exclusive result");
            if (parameter.slice and !contract.slice) return self.sink.fail("E_REFERENCE_KIND", contract.source, "slice input cannot supply a whole-value reference result");
            if (contract.slice != parameter.slice) return self.sink.fail(eUnsupported, contract.source, "generic reference results must preserve the input reference kind");
            return .{ .parameter = index, .mutable = contract.mutable, .slice = contract.slice };
        }
        return self.sink.fail(diagnostic.return_lifetime, contract.source, "result lifetime names no input parameter");
    }
    fn borrowCall(self: *Checker, borrow: @FieldType(@FieldType(ast.Statement, "data"), "borrow_call")) Error!bool {
        const node = self.program.nodes.items[@backingInt(borrow.call)];
        if (node.data != .call) return self.sink.fail(diagnostic.reference_result, node.span, "borrow result requires a direct call");
        try self.enter(node.span);
        defer self.depth -= 1;
        const before_temporaries = self.temporary_results;
        self.expression_depth += 1;
        defer {
            self.expression_depth -= 1;
            self.temporary_results = before_temporaries;
        }
        const result = try self.call(node.data.call, node.span, true);
        const function = try self.callTarget(node.data.call);
        const contract = (try self.provenance(function)) orelse return self.sink.fail(diagnostic.reference_result, node.span, "borrow result requires a reference-returning function");
        if (borrow.mutable and !contract.mutable) return self.sink.fail(diagnostic.reference_read_only, borrow.name, "shared result cannot be borrowed exclusively");
        const argument = self.program.nodes.items[@backingInt(node.data.call.arguments[contract.parameter])].data.name;
        const parent = self.active.get(self.src.text(argument)).?;
        return self.loanScope(.{ .name = borrow.name, .ty = result, .mutable = false, .reference = borrow.mutable, .slice = contract.slice, .root = self.locals.items[parent].root }, parent, borrow.body);
    }
    fn returnValue(self: *Checker, value: ast.NodeId, span: source.Span) Error!void {
        if (self.return_reference) |contract| {
            const node = self.program.nodes.items[@backingInt(value)];
            if (node.data != .name) return self.sink.fail(diagnostic.reference_result, node.span, "reference return requires an active reference name");
            const ref = try self.reference(node.data.name, contract.mutable, contract.slice);
            if (ref.root != contract.parameter) return self.sink.fail(diagnostic.return_lifetime, node.span, "returned reference does not originate from the declared input");
            try self.same(ref.ty, self.result, span);
        } else try self.same(try self.expression(value), self.result, span);
        try self.requireHandled(0, span);
    }
    fn topLevel(self: *Checker, span: source.Span) Error!bool {
        if (self.module_names) |names| return names.topLevel(span);
        const name = self.src.text(span);
        if (self.functions.contains(name)) return true;
        inline for (.{ "records", "domains", "variants", "buffers", "resources", "pools" }) |field| {
            for (@field(self.program.types, field)) |declaration| if (std.mem.eql(u8, name, self.src.text(declaration.name))) return true;
        }
        for (self.program.types.pools) |pool| if (std.mem.eql(u8, name, self.src.text(pool.handle))) return true;
        return false;
    }
    fn bind(self: *Checker, name: source.Span, ty_value: Symbolic, mutable: bool) Error!void {
        const text = self.src.text(name);
        if (try self.topLevel(name)) return self.sink.fail(eShadowing, name, "binding shadows a top-level declaration or import");
        if (self.active.contains(text)) return self.sink.fail(eShadowing, name, "binding shadows an active template binding");
        for (self.parameters) |parameter| if (std.mem.eql(u8, text, self.src.text(parameter.name))) return self.sink.fail(eShadowing, name, "binding shadows a template type parameter");
        try self.active.put(self.allocator, text, self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = name, .ty = ty_value, .mutable = mutable });
    }
    fn callTarget(self: *Checker, invocation: Call) Error!ast.Function {
        if (@import("source_codec.zig").operation(self.src.text(invocation.name)) and invocation.owner == null)
            return self.sink.fail(eUnsupported, invocation.name, "generic codec operations require nominal codec constraints, which are not implemented");
        const key = if (self.module_names) |names|
            try names.reference(invocation.owner orelse invocation.name, .function, if (invocation.owner != null) invocation.name else null, if (self.owner) |owner| self.src.text(owner) else null, self.sink)
        else
            try @import("function_identity.zig").localName(self.sink.allocator, self.src, invocation.owner, invocation.name);
        const index = self.functions.get(key) orelse return self.sink.fail("E_UNKNOWN_FUNCTION", invocation.name, "no function has this qualified name");
        const function = self.program.functions[index];
        if (self.module_names == null and function.policy.restricted) {
            const allowed = if (self.owner) |owner| std.mem.eql(u8, self.src.text(owner), self.src.text(function.policy.owner.?)) else false;
            if (!allowed) return self.sink.failRelated("E_PRIVATE_FUNCTION", invocation.name, "private generic method requires the same declaring domain", .{ .span = function.name, .message = "private function declared here" });
        }
        if (!self.scheduled[index]) {
            self.pending.appendAssumeCapacity(index);
            self.scheduled[index] = true;
        }
        return function;
    }
    fn substituted(self: *Checker, span: source.Span, parameters: []const ast.TypeParameter, arguments: []const Symbolic) Error!Symbolic {
        const text = self.src.text(span);
        for (parameters, arguments) |parameter, argument| if (std.mem.eql(u8, text, self.src.text(parameter.name))) return argument;
        return self.concreteType(span);
    }
    fn call(self: *Checker, invocation: Call, span: source.Span, allow_reference: bool) Error!Symbolic {
        const function = try self.callTarget(invocation);
        const signature = function.signature;
        if (function.policy.conversion) return self.sink.fail(eUnsupported, span, "generic conversions still need abstract checking");
        if (signature.return_reference != null and !allow_reference) return self.sink.fail(diagnostic.reference_result, span, "reference-returning calls require a borrow scope");
        if (invocation.type_arguments.len != signature.type_parameters.len) return self.sink.fail("E_GENERIC_ARITY", span, "explicit type argument count does not match generic parameters");
        if (invocation.arguments.len != signature.parameters.len) return self.sink.fail("E_ARITY", span, "argument count does not match function parameters");
        const required = try requirements.resolve(self.allocator, self.src, signature.type_parameters, self.sink);
        defer self.allocator.free(required);
        const arguments = try self.allocator.alloc(Symbolic, required.len);
        defer self.allocator.free(arguments);
        for (invocation.type_arguments, required, arguments) |argument_span, parameter, *argument| {
            argument.* = try self.ty(argument_span);
            const satisfies = switch (argument.*) {
                .parameter => |index| self.parameters[index].requirements.implies(parameter.requirements),
                .concrete => |builtin| parameter.requirements.accepts(builtin, self.catalog.records),
            };
            if (!satisfies) return self.sink.failRelated(
                "E_GENERIC_ARGUMENT",
                argument_span,
                "type argument does not satisfy the callee's declared requirements",
                .{ .span = parameter.name, .message = "required type parameter declared here" },
            );
        }
        var loans: std.AutoHashMapUnmanaged(usize, bool) = .empty;
        defer loans.deinit(self.allocator);
        for (invocation.arguments, signature.parameters) |input, parameter| {
            const expected = try self.substituted(parameter.ty, signature.type_parameters, arguments);
            const node = self.program.nodes.items[@backingInt(input)];
            if (parameter.reference) |mutable| {
                if (node.data != .name) return self.sink.fail("E_REFERENCE_ARGUMENT", node.span, "reference parameter requires an active reference name");
                const ref = try self.reference(node.data.name, mutable, parameter.slice);
                try self.same(ref.ty, expected, node.span);
                try self.enter(node.span);
                self.depth -= 1;
                const loan = try loans.getOrPut(self.allocator, ref.root.?);
                if (loan.found_existing and (loan.value_ptr.* or ref.reference.?)) return self.sink.fail("E_BORROW_CONFLICT", node.span, "call cannot alias an exclusive reference argument");
                loan.value_ptr.* = ref.reference.?;
            } else try self.same(try self.expression(input), expected, node.span);
        }
        return self.substituted(signature.return_type, signature.type_parameters, arguments);
    }
    fn expression(self: *Checker, id: ast.NodeId) Error!Symbolic {
        const before = self.temporary_results;
        self.expression_depth += 1;
        defer self.expression_depth -= 1;
        errdefer self.temporary_results = before;
        const result = try self.expressionValue(id);
        self.temporary_results = before;
        if (self.expression_depth > 1 and self.requiresHandling(result)) self.temporary_results += 1;
        return result;
    }
    fn expressionValue(self: *Checker, id: ast.NodeId) Error!Symbolic {
        const node = self.program.nodes.items[@backingInt(id)];
        try self.enter(node.span);
        defer self.depth -= 1;
        return switch (node.data) {
            .name => |name| try self.namedValue(name),
            .read_field, .take_field => |access| try self.fieldValue(access, node.data == .take_field),
            .read_slice => |read| result: {
                const ref = try self.reference(read.name, false, true);
                try self.supports(try self.expression(read.index), .integer, node.span);
                try self.supports(ref.ty, .copy, read.name);
                break :result ref.ty;
            },
            .len_slice => |name| result: {
                _ = try self.reference(name, false, true);
                break :result .{ .concrete = .u64 };
            },
            .read_ref => |name| result: {
                const ref = try self.reference(name, false, false);
                try self.supports(ref.ty, .copy, name);
                break :result ref.ty;
            },
            .call => |invocation| try self.call(invocation, node.span, false),
            .propagate => |operand| try self.propagateValue(operand, node.span),
            .boolean => .{ .concrete = .bool },
            .integer => |span| .{ .concrete = (try @import("integer_literal.zig").parse(self.src, span, false, self.sink)).ty },
            .unary => |unary| result: {
                const child = self.program.nodes.items[@backingInt(unary.operand)];
                const operand: Symbolic = if (unary.op == .neg and child.data == .integer)
                    .{ .concrete = (try @import("integer_literal.zig").parse(self.src, child.data.integer, true, self.sink)).ty }
                else
                    try self.expression(unary.operand);
                if (unary.op == .neg) try self.supports(operand, .integer, unary.op_span) else try self.same(operand, .{ .concrete = .bool }, unary.op_span);
                break :result operand;
            },
            .binary => |operation| try self.binary(operation),
            .record => |record| try self.recordValue(record, node.span),
            .variant => |variant| try self.variantValue(variant, node.span),
            .array => |array| try self.arrayValue(array, node.span),
            .update => |update| result: {
                const base = try self.expression(update.base);
                try self.recordFields(try self.concreteValue(base, node.span), update.fields, false, node.span);
                break :result base;
            },
            .replace => |replacement| result: {
                const base = try self.expression(replacement.base);
                const shape = try self.arrayIndex(base, replacement.index, node.span);
                if (self.requiresHandling(.{ .concrete = shape.element })) return self.sink.fail(eResultOperation, node.span, "replacement would drop a result-bearing element");
                try self.same(try self.expression(replacement.value), .{ .concrete = shape.element }, node.span);
                break :result base;
            },
            .field => |field| result: {
                const base = try self.concreteValue(try self.expression(field.base), node.span);
                const index = try self.catalog.field(base, self.src, field.name, self.sink);
                for (self.catalog.records[base.recordIndex()].fields, 0..) |other, i| {
                    if (i != index and self.requiresHandling(.{ .concrete = other.ty })) return self.sink.fail(eResultOperation, node.span, "projection would drop another result-bearing field");
                }
                break :result .{ .concrete = self.catalog.records[base.recordIndex()].fields[index].ty };
            },
            .length => |input| result: {
                const base = try self.concreteValue(try self.expression(input), node.span);
                _ = try self.catalog.array(base, node.span, self.sink);
                if (self.requiresHandling(.{ .concrete = base })) return self.sink.fail(eResultOperation, node.span, "length would drop result-bearing elements");
                break :result .{ .concrete = .u64 };
            },
            .index => |access| result: {
                const shape = try self.arrayIndex(try self.expression(access.base), access.index, node.span);
                if (shape.length != 1 and self.requiresHandling(.{ .concrete = shape.element })) return self.sink.fail(eResultOperation, node.span, "indexing would drop other result-bearing elements");
                break :result .{ .concrete = shape.element };
            },
            .cast => |cast| result: {
                const operand = try self.expression(cast.value);
                const target = try self.ty(cast.ty);
                try self.supports(operand, .integer, node.span);
                try self.supports(target, .integer, cast.ty);
                break :result target;
            },
            else => self.sink.fail(eUnsupported, node.span, "this operation still needs abstract generic body checking"),
        };
    }
    fn fieldValue(self: *Checker, access: @FieldType(@FieldType(ast.Node, "data"), "read_field"), taking: bool) Error!Symbolic {
        const binding = try self.local(access.owner);
        if (binding.reference != null) return self.sink.fail("E_TYPE", access.owner, "field access requires a value binding, not a reference");
        const owner_type = try self.concreteValue(binding.ty, access.owner);
        const index = try self.catalog.field(owner_type, self.src, access.field, self.sink);
        const fields = self.catalog.records[owner_type.recordIndex()].fields;
        const result: Symbolic = .{ .concrete = fields[index].ty };
        if (!taking and self.requiresHandling(result)) return self.sink.fail("E_FIELD_COPY", access.field, "read_field cannot copy result obligations");
        if (self.requiresHandling(binding.ty) and !binding.available) return self.sink.fail("E_OWNED_CONSUMED", access.owner, "record has already been transferred");
        if (taking and !self.requiresHandling(binding.ty)) return self.sink.fail("E_FIELD_TAKE", access.owner, "take_field requires a result-bearing record; use read_field for copyable records");
        if (binding.fields.len != 0 and binding.fields[index]) return self.sink.fail("E_FIELD_MOVED", access.field, "field has already been transferred");
        try self.ownerAccess(binding.*, taking, access.owner);
        if (taking) {
            const moved = try self.field_arena.allocator().alloc(bool, fields.len);
            @memset(moved, false);
            if (binding.fields.len != 0) @memcpy(moved, binding.fields);
            moved[index] = true;
            binding.fields = moved;
        }
        return result;
    }
    fn propagateValue(self: *Checker, operand: ast.NodeId, span: source.Span) Error!Symbolic {
        const temporaries = self.temporary_results;
        const value = try self.concreteValue(try self.expression(operand), span);
        const input = typed.resultShape(value, self.catalog.records) orelse return self.sink.fail("E_TRY_TYPE", span, "try requires a declared result");
        const return_type = switch (self.result) {
            .concrete => |ty_value| ty_value,
            .parameter => return self.sink.fail(eTryReturn, span, "try requires a concrete declared result return type"),
        };
        const output = typed.resultShape(return_type, self.catalog.records) orelse return self.sink.fail(eTryReturn, span, "try requires a result return type");
        if (self.return_reference != null) return self.sink.fail(eTryReturn, span, "try cannot propagate through a reference return");
        try self.same(.{ .concrete = input.error_type }, .{ .concrete = output.error_type }, span);
        try self.requireHandled(0, span);
        if (temporaries != 0) return self.sink.fail("E_RESULT_PROPAGATION", span, "propagation could drop an already evaluated result temporary");
        return .{ .concrete = input.ok_type };
    }
    fn variantValue(self: *Checker, variant: @FieldType(@FieldType(ast.Node, "data"), "variant"), span: source.Span) Error!Symbolic {
        const result = try self.ty(variant.ty);
        const ty_value = try self.concreteValue(result, span);
        const tag = try self.catalog.variant(ty_value, self.src, variant.name, self.sink);
        const payload = (try self.catalog.variants(ty_value, span, self.sink)).cases[tag].payload;
        if ((payload != null) != (variant.value != null)) return self.sink.fail("E_VARIANT_PAYLOAD", span, "construction must supply exactly the declared payload");
        if (variant.value) |value| try self.same(try self.expression(value), .{ .concrete = payload.? }, span);
        return result;
    }
    fn matchValue(self: *Checker, match: @FieldType(@FieldType(ast.Statement, "data"), "match"), span: source.Span) Error!bool {
        const value = try self.expression(match.value);
        const ty_value = try self.concreteValue(value, span);
        const variants = try self.catalog.variants(ty_value, span, self.sink);
        const seen = try self.allocator.alloc(bool, variants.cases.len);
        defer self.allocator.free(seen);
        @memset(seen, false);
        const incoming = try self.pendingState(self.locals.items.len);
        defer self.allocator.free(incoming);
        var continuation: ?[]Pending = null;
        defer if (continuation) |state| self.allocator.free(state);
        var terminated = true;
        for (match.arms) |arm| {
            self.restorePending(incoming);
            try self.same(try self.ty(arm.ty), value, arm.ty);
            const tag = try self.catalog.variant(ty_value, self.src, arm.name, self.sink);
            if (seen[tag]) return self.sink.fail("E_DUPLICATE_ARM", arm.name, "variant has more than one match arm");
            seen[tag] = true;
            const payload = variants.cases[tag].payload;
            if (arm.discard_payload and payload != null and self.requiresHandling(.{ .concrete = payload.? })) return self.sink.fail("E_RESULT_DISCARD", arm.name, "nested result payload requires explicit handling");
            if ((payload != null) != (arm.binding != null or arm.discard_payload)) return self.sink.fail("E_PATTERN_PAYLOAD", arm.name, "payload cases require a binding or discard; empty cases take neither");
            const before = self.locals.items.len;
            defer self.endScope(before);
            if (arm.binding) |binding| try self.bind(binding, .{ .concrete = payload.? }, false);
            const returns = try self.statement(arm.body);
            if (!returns) {
                try self.requireHandled(before, arm.name);
                if (continuation) |state| try self.samePending(state, span, eResultPath) else continuation = try self.pendingState(incoming.len);
            }
            terminated = terminated and returns;
        }
        for (seen) |present| if (!present) return self.sink.fail("E_INCOMPLETE_MATCH", span, "match must cover every declared case");
        if (continuation) |state| self.restorePending(state);
        return terminated;
    }
    fn arrayIndex(self: *Checker, base: Symbolic, input: ast.NodeId, span: source.Span) Error!typed.Array {
        const shape = try self.catalog.array(try self.concreteValue(base, span), span, self.sink);
        const index = try self.expression(input);
        if (shape.key) |key| try self.same(index, .{ .concrete = key }, span) else try self.supports(index, .integer, span);
        return shape;
    }
    fn arrayValue(self: *Checker, array: @FieldType(@FieldType(ast.Node, "data"), "array"), span: source.Span) Error!Symbolic {
        const result = try self.ty(array.ty);
        const ty_value = try self.concreteValue(result, span);
        const shape = try self.catalog.array(ty_value, span, self.sink);
        if (shape.key != null) return self.sink.fail("E_TYPE", span, "enum-indexed tables require named construction");
        if (array.values.len != shape.length) return self.sink.fail("E_ARRAY_LENGTH", span, "array construction must supply its declared number of elements");
        for (array.values) |value| try self.same(try self.expression(value), .{ .concrete = shape.element }, span);
        return result;
    }
    fn recordValue(self: *Checker, record: @FieldType(@FieldType(ast.Node, "data"), "record"), span: source.Span) Error!Symbolic {
        const result = try self.ty(record.name);
        const ty_value = try self.concreteValue(result, span);
        try self.recordFields(ty_value, record.fields, true, span);
        return result;
    }
    fn recordFields(self: *Checker, ty_value: typed.Type, fields: []const ast.FieldInit, complete: bool, span: source.Span) Error!void {
        const shape = if (complete) try self.catalog.constructor(ty_value, span, self.sink) else try self.catalog.record(ty_value, span, self.sink);
        const table_key = shape.tableKey();
        const seen = try self.allocator.alloc(bool, shape.fields.len);
        defer self.allocator.free(seen);
        @memset(seen, false);
        for (fields) |field| {
            const index = if (table_key) |key| try self.catalog.variant(key, self.src, field.name, self.sink) else try self.catalog.field(ty_value, self.src, field.name, self.sink);
            if (seen[index]) return self.sink.fail(if (table_key != null) "E_DUPLICATE_KEY" else "E_DUPLICATE_FIELD", field.name, "named entry is initialized more than once");
            seen[index] = true;
            if (!complete and self.requiresHandling(.{ .concrete = shape.fields[index].ty })) return self.sink.fail(eResultOperation, field.name, "update would drop a result-bearing field");
            try self.same(try self.expression(field.value), .{ .concrete = shape.fields[index].ty }, field.name);
        }
        if (complete) for (seen) |present| {
            if (!present) return self.sink.fail(if (table_key != null) "E_INCOMPLETE_TABLE" else "E_MISSING_FIELD", span, "named construction must initialize every entry");
        };
    }
    fn binary(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), "binary")) Error!Symbolic {
        const left = try self.expression(operation.left);
        const short_circuit = operation.op == .logical_and or operation.op == .logical_or;
        const state = if (short_circuit) try self.pendingState(self.locals.items.len) else null;
        defer if (state) |snapshot| self.allocator.free(snapshot);
        const right = try self.expression(operation.right);
        if (state) |snapshot| try self.samePending(snapshot, operation.op_span, eResultPath);
        try self.same(right, left, operation.op_span);
        switch (operation.op) {
            .logical_and, .logical_or => try self.same(left, .{ .concrete = .bool }, operation.op_span),
            .eq, .ne => try self.supports(left, .equality, operation.op_span),
            else => try self.supports(left, .integer, operation.op_span),
        }
        return switch (operation.op) {
            .add, .sub, .mul, .div, .rem => left,
            else => .{ .concrete = .bool },
        };
    }
    fn block(self: *Checker, statements: []const ast.StatementId) Error!bool {
        const before = self.locals.items.len;
        defer self.endScope(before);
        var terminated = false;
        for (statements) |id| {
            if (terminated) return self.sink.fail("E_UNREACHABLE", self.program.statements.items[@backingInt(id)].span, "statement follows an unconditional return");
            terminated = try self.statement(id);
        }
        if (!terminated and statements.len != 0) try self.requireHandled(before, self.program.statements.items[@backingInt(statements[statements.len - 1])].span);
        return terminated;
    }
    fn branchValue(self: *Checker, branch: @FieldType(@FieldType(ast.Statement, "data"), "branch"), span: source.Span) Error!bool {
        try self.same(try self.expression(branch.condition), .{ .concrete = .bool }, span);
        const before = try self.pendingState(self.locals.items.len);
        defer self.allocator.free(before);
        const left = try self.statement(branch.then_body);
        const after = try self.pendingState(before.len);
        defer self.allocator.free(after);
        self.restorePending(before);
        const right = if (branch.else_body) |other| try self.statement(other) else false;
        if (!left) {
            if (!right) try self.samePending(after, span, eResultPath);
            self.restorePending(after);
        }
        return left and right;
    }
    fn statement(self: *Checker, id: ast.StatementId) Error!bool {
        const statement_value = self.program.statements.items[@backingInt(id)];
        try self.enter(statement_value.span);
        defer self.depth -= 1;
        switch (statement_value.data) {
            .block => |statements| return self.block(statements),
            .match => |match| return self.matchValue(match, statement_value.span),
            .borrow => |borrow| return self.borrowScope(borrow),
            .borrow_call => |borrow| return self.borrowCall(borrow),
            .ret => |value| {
                try self.returnValue(value, statement_value.span);
                return true;
            },
            .binding => |binding| {
                const value = try self.expression(binding.value);
                if (binding.annotation) |annotation| try self.same(value, try self.ty(annotation), annotation);
                try self.bind(binding.name, value, binding.mutable);
            },
            .assignment => |assignment| {
                const target = try self.local(assignment.name);
                if (!target.mutable) return self.sink.fail("E_IMMUTABLE", assignment.name, "assignment requires a mutable binding");
                try self.ownerAccess(target.*, true, assignment.name);
                const value = try self.expression(assignment.value);
                try self.same(value, target.ty, assignment.op_span);
                if (assignment.op != .set) try self.supports(target.ty, .integer, assignment.op_span);
                if (self.requiresHandling(target.ty)) {
                    if (self.pendingObligation(target.*)) return self.sink.fail("E_RESULT_OVERWRITE", assignment.name, "assignment would overwrite an unhandled result");
                    target.available = true;
                    target.fields = &.{};
                }
            },
            .write_slice => |write| {
                const ref = try self.reference(write.name, true, true);
                try self.supports(try self.expression(write.index), .integer, statement_value.span);
                try self.same(try self.expression(write.value), ref.ty, statement_value.span);
            },
            .write_ref => |write| {
                const ref = try self.reference(write.name, true, false);
                try self.same(try self.expression(write.value), ref.ty, statement_value.span);
            },
            .acknowledge => |value| {
                if (!self.requiresHandling(try self.expression(value))) return self.sink.fail("E_ACKNOWLEDGE_TYPE", statement_value.span, "acknowledge requires a result-bearing value");
            },
            .discard => |value| {
                const ty_value = try self.expression(value);
                if (self.requiresHandling(ty_value)) return self.sink.fail("E_RESULT_DISCARD", statement_value.span, "discard cannot erase a result obligation");
                try self.supports(ty_value, .copy, statement_value.span);
            },
            .branch => |branch| return self.branchValue(branch, statement_value.span),
            .loop => |loop| {
                const before = try self.pendingState(self.locals.items.len);
                defer self.allocator.free(before);
                try self.same(try self.expression(loop.condition), .{ .concrete = .bool }, statement_value.span);
                try self.samePending(before, statement_value.span, "E_RESULT_LOOP");
                if (!try self.statement(loop.body)) try self.samePending(before, statement_value.span, "E_RESULT_LOOP");
                self.restorePending(before);
            },
            else => return self.sink.fail(eUnsupported, statement_value.span, "this statement still needs abstract generic body checking"),
        }
        return false;
    }
};
/// Validate supported template bodies symbolically; unsupported forms remain explicit errors.
pub fn check(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink) Error!void {
    return checkWithNames(allocator, src, program, sink, null);
}
/// Validate bodies while preserving the declaring module's names and import aliases.
pub fn checkWithNames(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, module_names: ?*Names) Error!void {
    const catalog = try @import("records.zig").collectWithNames(sink.allocator, src, program, sink, module_names);
    return checkWithCatalog(allocator, src, program, sink, catalog);
}
/// Check symbolic bodies against the same concrete type catalog used by specialization.
pub fn checkWithCatalog(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, catalog: Catalog) Error!void {
    const module_names = catalog.module_names;
    var has_generic = false;
    for (program.functions) |function| if (function.signature.type_parameters.len != 0) {
        has_generic = true;
        break;
    };
    if (!has_generic) return;
    const concrete_checked = try allocator.alloc(bool, catalog.records.len);
    defer allocator.free(concrete_checked);
    @memset(concrete_checked, false);
    var functions: FunctionMap = .empty;
    defer functions.deinit(allocator);
    for (program.functions, 0..) |function, index| {
        const key = if (module_names) |names| try names.functionDeclaration(function.policy.owner, function.name) else try @import("function_identity.zig").localName(sink.allocator, src, function.policy.owner, function.name);
        const entry = try functions.getOrPut(allocator, key);
        if (entry.found_existing) return sink.fail("E_DUPLICATE_FUNCTION", function.name, "duplicate function declaration");
        entry.value_ptr.* = index;
    }
    const scheduled = try allocator.alloc(bool, program.functions.len);
    defer allocator.free(scheduled);
    @memset(scheduled, false);
    var pending = try std.ArrayList(usize).initCapacity(allocator, program.functions.len);
    defer pending.deinit(allocator);
    for (program.functions, 0..) |function, index| {
        if (function.signature.type_parameters.len == 0) continue;
        scheduled[index] = true;
        pending.appendAssumeCapacity(index);
    }
    var cursor: usize = 0;
    while (cursor < pending.items.len) : (cursor += 1) {
        const function = program.functions[pending.items[cursor]];
        const parameters = try requirements.resolve(allocator, src, function.signature.type_parameters, sink);
        defer allocator.free(parameters);
        var checker: Checker = .{
            .allocator = allocator,
            .field_arena = std.heap.ArenaAllocator.init(allocator),
            .src = src,
            .program = program,
            .catalog = catalog,
            .concrete_checked = concrete_checked,
            .sink = sink,
            .parameters = parameters,
            .result = undefined,
            .module_names = module_names,
            .functions = &functions,
            .pending = &pending,
            .scheduled = scheduled,
            .owner = function.policy.owner,
        };
        defer checker.field_arena.deinit();
        defer checker.locals.deinit(allocator);
        defer checker.active.deinit(allocator);
        if (function.policy.conversion) return sink.fail(eUnsupported, function.name, "generic conversions still need abstract checking");
        for (parameters) |parameter| if (try checker.topLevel(parameter.name)) return sink.fail(eShadowing, parameter.name, "type parameter shadows a top-level declaration or import");
        checker.result = try checker.ty(function.signature.return_type);
        for (function.signature.parameters) |parameter| {
            const parameter_type = try checker.ty(parameter.ty);
            if (parameter.reference != null and checker.requiresHandling(parameter_type)) return sink.fail("E_RESULT_BORROW", parameter.ty, "result-bearing parameters must transfer by value");
            try checker.bind(parameter.name, parameter_type, false);
            checker.locals.items[checker.locals.items.len - 1].reference = parameter.reference;
            checker.locals.items[checker.locals.items.len - 1].slice = parameter.slice;
            if (parameter.reference != null) checker.locals.items[checker.locals.items.len - 1].root = checker.locals.items.len - 1;
        }
        checker.return_reference = try checker.provenance(function);
        if (checker.return_reference) |contract| try checker.same(checker.locals.items[contract.parameter].ty, checker.result, function.signature.return_type);
        if (!try checker.statement(function.body)) return sink.fail("E_MISSING_RETURN", function.name, "template may fall through without returning its declared type");
    }
}
