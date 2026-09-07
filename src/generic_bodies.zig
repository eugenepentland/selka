//! Symbolic template checking preserves types, ownership and effects without representative substitution.
const eResultDiscard = diagnostic.result_discard;
const std = @import("std");
const source_json = @import("source_json.zig");
const eReferenceArgument = diagnostic.reference_argument;
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const field_moves = @import("field_moves.zig");
const requirements = @import("generic_requirements.zig");
const Error = diagnostic.Error;
const effects = @import("effects.zig");
const effect_set = @import("effect_set.zig");
const Names = @import("module_names.zig").Names;
const eShadowing = diagnostic.shadowing;
const eResultOperation = diagnostic.result_operation;
const eResultPath = diagnostic.result_path;
const eTryReturn = "E_TRY_RETURN";
const eArgument = diagnostic.generic_argument;
const eBorrowConflict = "E_BORROW_CONFLICT";
const eUnsupported = "E_GENERIC_BODY_UNSUPPORTED";
const region_check = @import("region_check.zig");
const Regions = @import("generic_regions.zig");
const Catalog = @import("records.zig").Catalog;
const symbolic = @import("symbolic_types.zig");
const provider_shapes = @import("symbolic_providers.zig");
const Symbolic = symbolic.Value;
const Call = @FieldType(@FieldType(ast.Node, "data"), "call");
const FunctionMap = std.StringHashMapUnmanaged(usize);
const Return = struct { parameter: usize, mutable: bool, slice: bool };
const Pending = struct { available: bool, fields: field_moves.State, transfer_span: ?source.Span };
const Local = struct {
    split_sibling: ?usize = null,
    name: source.Span,
    ty: Symbolic,
    mutable: bool,
    origin: usize = 0,
    arena_depth: usize = 0,
    transfer_span: ?source.Span = null,
    parent: ?usize = null,
    available: bool = true,
    fields: field_moves.State = &.{},
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
    regions: Regions.Graph,
    region_types: []const bool,
    region_inputs: ?usize = null,
    last_origin: usize = 0,
    arena_depth: usize = 0,
    src: source.Source,
    program: ast.Program,
    catalog: Catalog,
    cleanup_masks: []const effect_set.Mask,
    effect_masks: []effect_set.Mask,
    effect_calls: *std.ArrayList(effects.AbstractCall),
    function_index: usize,
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
    loop_pending: ?[]const Pending = null,
    fn checkFunction(self: *Checker, function: ast.Function) Error!void {
        const sink = self.sink;
        if (function.policy.conversion) return sink.fail(eUnsupported, function.name, "generic conversions still need abstract checking");
        for (self.parameters) |parameter| if (try self.topLevel(parameter.name)) return sink.fail(eShadowing, parameter.name, "type parameter shadows a top-level declaration or import");
        try self.validateStructural();
        self.result = try self.ty(function.signature.return_type);
        if (function.signature.return_reference == null) try self.seedCleanup(self.result);
        for (function.signature.parameters) |parameter| {
            const parameter_type = try self.ty(parameter.ty);
            if (parameter.reference != null and (try self.properties(parameter_type)).requires_handling) return sink.fail(diagnostic.result_borrow, parameter.ty, "result-bearing parameters must transfer by value");
            try self.bindMode(parameter.name, parameter_type, false, parameter.reference == false);
            self.locals.items[self.locals.items.len - 1].reference = parameter.reference;
            self.locals.items[self.locals.items.len - 1].slice = parameter.slice;
            if (parameter.reference != null) self.locals.items[self.locals.items.len - 1].root = self.locals.items.len - 1;
        }
        self.return_reference = try self.provenance(function);
        if (self.return_reference) |contract| {
            const input = self.locals.items[contract.parameter];
            const returned = if (contract.slice and !input.slice) try self.sliceType(input.ty, function.signature.return_type) else input.ty;
            try self.same(returned, self.result, function.signature.return_type);
        }
        if (!try self.statement(function.body)) return sink.fail("E_MISSING_RETURN", function.name, "template may fall through without returning its declared type");
        try self.regions.check(sink);
    }
    fn shapes(self: *Checker) @import("symbolic_shapes.zig").Context {
        return .{
            .arena = &self.field_arena,
            .catalog = self.catalog,
            .src = self.src,
            .sink = self.sink,
            .parameters = self.parameters,
            .contracts = .{ .regions = self.region_types, .cleanup = self.cleanup_masks },
            .work = &self.work,
        };
    }
    fn properties(self: *Checker, value: Symbolic) Error!symbolic.Properties {
        return self.shapes().properties(value, self.program.functions[self.function_index].name);
    }
    fn carriesRegion(self: *Checker, value: Symbolic) Error!bool {
        return (try self.properties(value)).region;
    }
    fn regionRead(self: *Checker, binding: Local) Error!void {
        if (!(try self.carriesRegion(binding.ty))) return;
        const origin = if (binding.root) |root| self.locals.items[root].origin else binding.origin;
        try self.regions.flow(origin, self.region_inputs.?);
    }
    fn referenceLimit(self: *Checker, binding: Local) Regions.Limit {
        const owner = self.locals.items[binding.root.?];
        if (binding.slice and self.shapes().kind(owner.ty) == .buffer) return .{ .node = owner.origin };
        return .{ .depth = owner.arena_depth };
    }
    fn regionWrite(self: *Checker, binding: Local, value: usize, span: source.Span) Error!void {
        if (!(try self.carriesRegion(binding.ty))) return;
        const limit = self.referenceLimit(binding);
        try self.regions.require(value, limit, span);
        if (limit == .depth) try self.regions.flow(value, self.locals.items[binding.root.?].origin);
    }
    fn enter(self: *Checker, span: source.Span) Error!void {
        if (self.depth == 256 or self.work == 100000) return self.sink.fail("E_GENERIC_BODY_LIMIT", span, "generic body exceeds checking depth/work budget");
        self.depth += 1;
        self.work += 1;
    }
    fn ty(self: *Checker, span: source.Span) Error!Symbolic {
        if (self.catalog.templates.applications.get(span.start)) |template| {
            try self.enter(span);
            defer self.depth -= 1;
            var arguments: [16]Symbolic = undefined;
            for (template.syntax.arguments, 0..) |argument, i| arguments[i] = try self.ty(argument);
            return self.shapes().nominal(template.declaration, arguments[0..template.arguments.len]);
        }
        if (self.catalog.arrays.templates.get(span.start)) |template| {
            try self.enter(span);
            defer self.depth -= 1;
            return self.arrayType(template.length, try self.ty(template.syntax.element));
        }
        const text = self.src.text(span);
        for (self.parameters, 0..) |parameter, index| if (std.mem.eql(u8, text, self.src.text(parameter.name))) return .{ .parameter = index };
        return self.concreteType(span);
    }
    fn arrayType(self: *Checker, length: usize, element: Symbolic) Error!Symbolic {
        const shape = try self.field_arena.allocator().create(symbolic.Array);
        shape.* = .{ .length = length, .element = element };
        return .{ .array = shape };
    }
    fn arrayShape(self: *Checker, value: Symbolic, span: source.Span) Error!symbolic.Array {
        return symbolic.array(value, self.catalog.records) orelse self.sink.fail("E_TYPE", span, "operation requires a fixed array value");
    }
    fn concreteType(self: *Checker, span: source.Span) Error!Symbolic {
        return .{ .concrete = try self.catalog.resolve(self.src, span, self.sink) };
    }
    fn moveOnly(self: *Checker, value: Symbolic) Error!bool {
        return (try self.properties(value)).move_only;
    }
    fn transfers(self: *Checker, value: Symbolic) Error!bool {
        const flags = try self.properties(value);
        return flags.move_only or flags.requires_handling;
    }
    fn seedCleanup(self: *Checker, value: Symbolic) Error!void {
        self.effect_masks[self.function_index] |= (try self.properties(value)).cleanup;
    }
    fn definiteHandling(self: *Checker, value: Symbolic, span: source.Span) Error!bool {
        try self.enter(span);
        defer self.depth -= 1;
        return switch (value) {
            .parameter => false,
            .concrete => |ty_value| typed.requiresHandling(ty_value, self.catalog.records),
            .array => |array| array.length != 0 and try self.definiteHandling(array.element, span),
            .nominal => result: {
                const shape = try self.shapes().schema(value, span);
                if (shape.kind == .result) break :result true;
                for (shape.fields) |field| if (field.ty) |field_type| if (try self.definiteHandling(field_type, span)) break :result true;
                break :result false;
            },
        };
    }
    fn requiresHandling(self: *Checker, value: Symbolic) Error!bool {
        return (try self.properties(value)).requires_handling;
    }
    fn seedEffect(self: *Checker, effect: effect_set.Effect) void {
        self.effect_masks[self.function_index] |= effect_set.bit(effect);
    }
    fn pendingObligation(self: *Checker, binding: Local) Error!bool {
        if (binding.reference != null or !binding.available) return false;
        if (!(try self.requiresHandling(binding.ty))) return false;
        if (binding.fields.len == 0) return true;
        const record = try self.shapes().requireRecord(binding.ty, binding.name, false);
        for (record.fields, binding.fields) |field, moved| {
            if (moved == null and (try self.requiresHandling(field.ty.?))) return true;
        }
        return false;
    }
    fn requireHandled(self: *Checker, first: usize, span: source.Span) Error!void {
        for (self.locals.items[first..]) |binding| {
            if ((try self.pendingObligation(binding)))
                return self.sink.failRelated("E_RESULT_UNHANDLED", span, "result-bearing binding leaves scope without handling or transfer", .{ .span = binding.name, .message = "unhandled result-bearing binding" });
        }
    }
    fn pendingState(self: *Checker, count: usize) Error![]Pending {
        const state = try self.allocator.alloc(Pending, count);
        for (self.locals.items[0..count], state) |binding, *pending| pending.* = .{ .available = binding.available, .fields = binding.fields, .transfer_span = binding.transfer_span };
        return state;
    }
    fn restorePending(self: *Checker, state: []const Pending) void {
        for (self.locals.items[0..state.len], state) |*binding, pending| {
            binding.available = pending.available;
            binding.fields = pending.fields;
            binding.transfer_span = pending.transfer_span;
        }
    }
    fn samePending(self: *Checker, state: []const Pending, span: source.Span, code: []const u8) Error!void {
        for (self.locals.items[0..state.len], state) |binding, pending| {
            const fields_match = field_moves.same(binding.fields, pending.fields);
            const owned = (try self.moveOnly(binding.ty)) and !(try self.requiresHandling(binding.ty));
            const mismatch_code = if (owned) (if (std.mem.eql(u8, code, diagnostic.result_loop)) "E_OWNED_LOOP" else "E_OWNED_PATH") else code;
            if (binding.available != pending.available or !fields_match) return self.sink.failRelated(
                mismatch_code,
                span,
                "result obligation must agree on every continuing path",
                .{ .span = binding.name, .message = "binding declared here" },
            );
        }
    }
    fn concreteValue(self: *Checker, value: Symbolic, span: source.Span) Error!typed.Type {
        return switch (value) {
            .concrete => |ty_value| ty_value,
            .parameter, .array, .nominal => self.sink.fail(eUnsupported, span, "structural operations require a concrete type; parameter shapes need declared constraints"),
        };
    }
    fn same(self: *Checker, actual: Symbolic, expected: Symbolic, span: source.Span) Error!void {
        if (!symbolic.same(actual, expected, self.catalog)) return self.sink.fail("E_GENERIC_TYPE", span, "types differ; distinct type parameters remain distinct even with identical requirements");
    }
    fn supports(self: *Checker, ty_value: Symbolic, requirement: requirements.Requirement, span: source.Span) Error!void {
        const supported = symbolic.supports(ty_value, requirement, self.parameters, self.catalog);
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
        if (exclusive and value.children != 0) {
            const parent = self.active.get(self.src.text(span)).?;
            for (self.locals.items) |child| if (child.parent == parent) return self.sink.failProvenance(
                "E_BORROW_SUSPENDED",
                span,
                "exclusive reference is suspended by an active child borrow",
                .{ .span = child.name, .message = "child borrow starts here" },
                self.locals.items[value.root.?].name,
            );
            return error.InternalError;
        }
        if (value.slice != slice) return self.sink.fail("E_REFERENCE_KIND", span, "whole-value references and slices are distinct");
        if (mutable and !exclusive) return self.sink.fail(diagnostic.reference_read_only, span, "write or exclusive forwarding requires an exclusive reference");
        return value;
    }
    fn namedValue(self: *Checker, span: source.Span) Error!Symbolic {
        if (!self.active.contains(self.src.text(span))) {
            const constants: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.program, .names = self.module_names, .sink = self.sink, .catalog = self.catalog };
            if (try constants.lookup(span)) |index| return .{ .concrete = (try constants.evaluate(index)).typeOf() };
        }
        const binding = try self.local(span);
        if (binding.reference != null) return self.sink.fail("E_REFERENCE_VALUE", span, "references require read_ref or an explicit reference parameter");
        try self.ownerAccess(binding.*, (try self.transfers(binding.ty)), span);
        if (field_moves.first(binding.fields)) |at| return self.sink.failPartialMove(span, binding.name, at);
        if ((try self.transfers(binding.ty))) {
            if (!binding.available) return self.sink.failTransfer(if ((try self.moveOnly(binding.ty))) diagnostic.owned_consumed else "E_RESULT_CONSUMED", span, binding.name, binding.transfer_span);
            binding.available = false;
            binding.transfer_span = span;
        }
        try self.regionRead(binding.*);
        return binding.ty;
    }
    fn ownerAccess(self: *Checker, binding: Local, write: bool, span: source.Span) Error!void {
        if (binding.exclusive == 0 and (!write or binding.shared == 0)) return;
        const root = self.active.get(self.src.text(binding.name)).?;
        for (self.locals.items) |loan| {
            if (loan.root == root and loan.parent == null and (write or loan.reference == true)) return self.sink.failProvenance(
                eBorrowConflict,
                span,
                "owner access conflicts with an active borrow",
                .{ .span = loan.name, .message = "conflicting borrow starts here" },
                binding.name,
            );
        }
        return error.InternalError;
    }
    fn endScope(self: *Checker, before: usize) void {
        for (self.locals.items[before..]) |item| _ = self.active.remove(self.src.text(item.name));
        self.locals.shrinkRetainingCapacity(before);
    }
    fn sliceType(self: *Checker, value: Symbolic, span: source.Span) Error!Symbolic {
        if (value == .array) return value.array.element;
        if (try self.shapes().container(value, span, false)) |shape| return shape.element;
        const owner_type = try self.concreteValue(value, span);
        const element = typed.sliceElement(owner_type, self.catalog.records) orelse return self.sink.fail("E_SLICE_TYPE", span, "slicing requires a fixed numeric array, buffer, or existing slice");
        return .{ .concrete = element };
    }
    fn splitScope(self: *Checker, borrow: @FieldType(@FieldType(ast.Statement, "data"), "borrow")) Error!bool {
        const split = borrow.split.?;
        try self.supports(try self.expression(split.middle), .integer, borrow.owner);
        const source_ref = (try self.reference(borrow.owner, true, true)).*;
        const parent = self.active.get(self.src.text(borrow.owner)).?;
        const root = source_ref.root.?;
        const before = self.locals.items.len;
        defer self.endScope(before);
        for ([_]source.Span{ borrow.name, split.right }, [_]usize{ before + 1, before }) |name, sibling| {
            try self.bindMode(name, source_ref.ty, false, false);
            const child = &self.locals.items[self.locals.items.len - 1];
            child.reference = true;
            child.slice = true;
            child.root = root;
            child.parent = parent;
            child.split_sibling = sibling;
        }
        self.locals.items[root].exclusive += 2;
        self.locals.items[parent].children += 2;
        defer {
            self.locals.items[root].exclusive -= 2;
            self.locals.items[parent].children -= 2;
        }
        return self.statement(borrow.body);
    }
    fn disjointLoans(self: *Checker, left: usize, right: usize) bool {
        var a: ?usize = left;
        while (a) |first| : (a = self.locals.items[first].parent) {
            var b: ?usize = right;
            while (b) |second| : (b = self.locals.items[second].parent) {
                if (self.locals.items[first].split_sibling == second) return true;
            }
        }
        return false;
    }
    fn claimLoan(self: *Checker, loans: *std.ArrayList(usize), name: source.Span) Error!void {
        const index = self.active.get(self.src.text(name)).?;
        const ref = self.locals.items[index];
        for (loans.items) |previous| {
            const old = self.locals.items[previous];
            const exclusive = old.reference.? or ref.reference.?;
            if (old.root == ref.root and exclusive and !self.disjointLoans(previous, index))
                return self.sink.fail(eBorrowConflict, name, "call cannot alias an exclusive reference argument");
        }
        try loans.append(self.allocator, index);
    }
    fn borrowScope(self: *Checker, borrow: @FieldType(@FieldType(ast.Statement, "data"), "borrow")) Error!bool {
        if (borrow.split != null) return self.splitScope(borrow);
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
            if (borrow.mutable and !binding.mutable) return self.sink.fail(diagnostic.immutable, borrow.owner, "exclusive borrowing requires a mutable owner");
            try self.ownerAccess(binding, borrow.mutable, borrow.owner);
        }
        const buffer_owner = self.shapes().kind(binding.ty) == .buffer;
        if ((try self.transfers(binding.ty)) and !binding.available) return self.sink.failTransfer(diagnostic.owned_consumed, borrow.owner, binding.name, binding.transfer_span);
        if ((try self.properties(binding.ty)).requires_handling) return self.sink.fail(diagnostic.result_borrow, borrow.owner, "result-bearing values must transfer their handling obligation by value");
        if (field_moves.first(binding.fields) != null) return self.sink.fail(diagnostic.result_borrow, borrow.owner, "a partially moved owner cannot be borrowed whole");
        if (buffer_owner and borrow.range != null) {
            if (binding.reference != null and !binding.slice) return self.sink.fail("E_SLICE_TYPE", borrow.owner, "borrow buffer elements directly from the owner in a separate lexical scope");
        }
        const element = if (borrow.range != null and !binding.slice) try self.sliceType(binding.ty, borrow.owner) else binding.ty;
        if ((try self.properties(element)).requires_handling) return self.sink.fail(diagnostic.result_borrow, borrow.owner, "result obligations cannot be exposed through references");
        if (borrow.range != null or binding.slice) try self.supports(element, .copy, borrow.owner);
        return self.loanScope(.{ .name = borrow.name, .ty = element, .mutable = false, .reference = borrow.mutable, .slice = borrow.range != null or binding.slice, .root = binding.root orelse owner_index }, parent, borrow.body);
    }

    fn loanScope(self: *Checker, child: Local, parent: ?usize, body: ast.StatementId) Error!bool {
        const root = child.root.?;
        const mutable = child.reference.?;
        const before = self.locals.items.len;
        try self.bindMode(child.name, child.ty, false, !child.reference.?);
        defer self.endScope(before);
        self.locals.items[before] = child;
        self.locals.items[before].parent = parent;
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
        const previous_inputs = self.region_inputs;
        self.region_inputs = try self.regions.add(.{});
        defer self.region_inputs = previous_inputs;
        const result = try self.call(node.data.call, node.span, true);
        self.region_inputs = previous_inputs;
        const function = try self.callTarget(try self.resolveCall(node.data.call), node.data.call.name);
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
            if (ref.root != contract.parameter) return self.sink.failReturnLifetime(
                node.span,
                ref.name,
                self.locals.items[ref.root.?].name,
                self.locals.items[contract.parameter].name,
            );
            try self.same(ref.ty, self.result, span);
            try self.regions.require(self.locals.items[ref.root.?].origin, .{ .depth = 0 }, span);
        } else {
            try self.same(try self.expression(value), self.result, span);
            try self.regions.require(self.last_origin, .{ .depth = 0 }, span);
        }
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
        return self.bindMode(name, ty_value, mutable, false);
    }
    fn bindMode(self: *Checker, name: source.Span, ty_value: Symbolic, mutable: bool, readonly_reference: bool) Error!void {
        const text = self.src.text(name);
        if (try self.topLevel(name)) return self.sink.fail(eShadowing, name, "binding shadows a top-level declaration or import");
        if (self.active.contains(text)) return self.sink.fail(eShadowing, name, "binding shadows an active template binding");
        for (self.parameters) |parameter| if (std.mem.eql(u8, text, self.src.text(parameter.name))) return self.sink.fail(eShadowing, name, "binding shadows a template type parameter");
        try self.active.put(self.allocator, text, self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = name, .ty = ty_value, .mutable = mutable, .origin = try self.regions.add(.{}), .arena_depth = self.arena_depth });
        if (!readonly_reference) try self.seedCleanup(ty_value);
    }
    fn callTarget(self: *Checker, invocation: Call, call_span: source.Span) Error!ast.Function {
        const key = if (self.module_names) |names|
            try names.reference(invocation.owner orelse invocation.name, .function, if (invocation.owner != null) invocation.name else null, if (self.owner) |owner| self.src.text(owner) else null, self.sink)
        else
            try @import("function_identity.zig").localName(self.sink.allocator, self.src, invocation.owner, invocation.name);
        const index = self.functions.get(key) orelse return self.sink.fail("E_UNKNOWN_FUNCTION", invocation.name, "no function has this qualified name");
        const function = self.program.functions[index];
        try self.effect_calls.append(self.allocator, .{ .caller = self.function_index, .callee = index, .span = call_span });
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
        if (self.catalog.templates.applications.get(span.start)) |template| {
            try self.enter(span);
            defer self.depth -= 1;
            var values: [16]Symbolic = undefined;
            for (template.syntax.arguments, 0..) |argument, i| values[i] = try self.substituted(argument, parameters, arguments);
            return self.shapes().nominal(template.declaration, values[0..template.arguments.len]);
        }
        if (self.catalog.arrays.templates.get(span.start)) |template| {
            try self.enter(span);
            defer self.depth -= 1;
            return self.arrayType(template.length, try self.substituted(template.syntax.element, parameters, arguments));
        }
        const text = self.src.text(span);
        for (parameters, arguments) |parameter, argument| if (std.mem.eql(u8, text, self.src.text(parameter.name))) return argument;
        return self.concreteType(span);
    }
    fn resolveCall(self: *Checker, invocation: Call) Error!Call {
        const codec = @import("source_codec.zig");
        if (!codec.operation(self.src.text(invocation.name)) or invocation.owner != null) return invocation;
        if (invocation.type_arguments.len != 1 or invocation.arguments.len != 1) return self.sink.fail("E_CODEC_ARITY", invocation.name, "codec operation requires one explicit domain type and one value argument");
        const target = try self.ty(invocation.type_arguments[0]);
        if (target != .concrete) return self.sink.fail(eUnsupported, invocation.type_arguments[0], "codec operations on type parameters require declared codec constraints");
        return codec.resolve(self.src, self.program, self.catalog, invocation, self.sink);
    }
    fn call(self: *Checker, input_call: Call, span: source.Span, allow_reference: bool) Error!Symbolic {
        if (std.mem.eql(u8, self.src.text(input_call.name), "todo") and input_call.owner == null) {
            _ = try self.ty(input_call.type_arguments[0]);
            return self.sink.typedHole(input_call.name, input_call.type_arguments[0]);
        }
        if (input_call.owner == null) if (source_json.operation(self.src.text(input_call.name))) |decode| return self.jsonCall(input_call, decode);
        if (try self.operationCall(input_call)) |result| return result;
        const invocation = try self.resolveCall(input_call);
        const function = try self.callTarget(invocation, input_call.name);
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
                .array, .nominal => supportsSet(argument.*, parameter.requirements, self.parameters, self.catalog),
            };
            if (!satisfies) return self.sink.failRelated(
                eArgument,
                argument_span,
                "type argument does not satisfy the callee's declared requirements",
                .{ .span = parameter.name, .message = "required type parameter declared here" },
            );
        }
        for (required, arguments) |parameter, argument| try self.structural(argument, parameter, signature.type_parameters, arguments);
        var loans: std.ArrayList(usize) = .empty;
        defer loans.deinit(self.allocator);
        for (invocation.arguments, signature.parameters) |input, parameter| {
            const expected = try self.substituted(parameter.ty, signature.type_parameters, arguments);
            const node = self.program.nodes.items[@backingInt(input)];
            if (parameter.reference) |mutable| {
                if (node.data == .bytes) {
                    const valid_slice = !mutable and parameter.slice and expected == .concrete;
                    if (!valid_slice or expected.concrete != .u8 or signature.return_reference != null)
                        return self.sink.fail(eReferenceArgument, node.span, "byte literals require readonly u8 slice parameters and a value return");
                    _ = try self.expression(input);
                    continue;
                }
                if (node.data != .name) return self.sink.fail(eReferenceArgument, node.span, "reference parameter requires an active reference name");
                const ref = try self.reference(node.data.name, mutable, parameter.slice);
                try self.same(ref.ty, expected, node.span);
                try self.regionRead(ref.*);
                try self.enter(node.span);
                self.depth -= 1;
                try self.claimLoan(&loans, node.data.name);
            } else try self.same(try self.expression(input), expected, node.span);
        }
        for (invocation.arguments, signature.parameters) |input, parameter| {
            if (parameter.reference == true) {
                const ref = try self.local(self.program.nodes.items[@backingInt(input)].data.name);
                try self.regionWrite(ref.*, self.region_inputs.?, span);
            }
        }
        return self.substituted(signature.return_type, signature.type_parameters, arguments);
    }
    fn jsonCall(self: *Checker, invocation: Call, decode: bool) Error!Symbolic {
        if (invocation.type_arguments.len != 1 or invocation.arguments.len != 3) return self.sink.fail("E_JSON_ARITY", invocation.name, "JSON operation requires one result type and allocator, value, byte-limit arguments");
        const result = try self.ty(invocation.type_arguments[0]);
        const shape = try self.resultShape(result, invocation.name, "E_JSON_RESULT");
        try self.same(shape.error_type, .{ .concrete = .i64 }, invocation.name);
        try self.same(try self.expression(invocation.arguments[0]), .{ .concrete = .allocator }, invocation.name);
        const input = try self.expression(invocation.arguments[1]);
        try self.supports(try self.expression(invocation.arguments[2]), .integer, invocation.name);
        const wire = if (decode) input else shape.ok_type;
        if (wire != .concrete or !source_json.byteBuffer(wire.concrete, self.catalog.records)) return self.sink.fail("E_JSON_BYTES", invocation.name, "JSON wire bytes require an owned u8 buffer");
        const value = if (decode) shape.ok_type else input;
        const document = source_json.isDocument(self.src.text(invocation.name));
        if (document and (value != .concrete or !source_json.wordBuffer(value.concrete, self.catalog.records)))
            return self.sink.fail("E_JSON_DOCUMENT", invocation.name, "plain JSON parsing requires an owned i64 document buffer success");
        if (!document and !symbolic.supports(value, .codec, self.parameters, self.catalog)) return self.sink.fail("E_JSON_CODEC", invocation.name, "generic JSON values require a codec contract or a concrete codec-safe type");
        self.seedEffect(.allocation);
        return result;
    }
    fn operationCall(self: *Checker, invocation: Call) Error!?Symbolic {
        const owner = invocation.owner orelse return null;
        var contract: ?ast.Operation = null;
        var symbolic_owner = false;
        for (self.parameters) |parameter| if (std.mem.eql(u8, self.src.text(parameter.name), self.src.text(owner))) {
            symbolic_owner = true;
            for (parameter.operation_requirements) |operation| if (std.mem.eql(u8, self.src.text(operation.name), self.src.text(invocation.name))) {
                contract = operation;
                break;
            };
        };
        if (!symbolic_owner) return null;
        const operation = contract orelse return self.sink.fail("E_GENERIC_REQUIREMENT", invocation.name, "type parameter does not declare this operation");
        if (invocation.type_arguments.len != 0 or invocation.arguments.len != operation.parameters.len)
            return self.sink.fail("E_ARITY", invocation.name, "structural operation requires its declared value/reference arguments and no type arguments");
        var loans: std.ArrayList(usize) = .empty;
        defer loans.deinit(self.allocator);
        for (invocation.arguments, operation.parameters) |input, parameter| {
            const expected = try self.ty(parameter.ty);
            const node = self.program.nodes.items[@backingInt(input)];
            if (parameter.reference) |mutable| {
                if (node.data != .name) return self.sink.fail(eReferenceArgument, node.span, "operation reference argument must name an active borrow");
                const ref = try self.reference(node.data.name, mutable, parameter.slice);
                try self.same(ref.ty, expected, node.span);
                try self.regionRead(ref.*);
                try self.claimLoan(&loans, node.data.name);
            } else try self.same(try self.expression(input), expected, node.span);
        }
        for (invocation.arguments, operation.parameters) |input, parameter| if (parameter.reference == true) {
            const ref = try self.local(self.program.nodes.items[@backingInt(input)].data.name);
            try self.regionWrite(ref.*, self.region_inputs.?, invocation.name);
        };
        self.effect_masks[self.function_index] |= operation.effect_bound.allowed;
        const result = try self.ty(operation.return_type);
        return result;
    }
    fn structural(self: *Checker, argument: Symbolic, required: requirements.Parameter, parameters: []const ast.TypeParameter, arguments: []const Symbolic) Error!void {
        if (required.field_requirements.len != 0) {
            const shape = try self.shapes().requireRecord(argument, required.name, false);
            for (required.field_requirements) |field| {
                const index = try self.shapes().memberIndex(shape, field.name);
                try self.same(shape.fields[index].ty.?, try self.substituted(field.ty, parameters, arguments), field.name);
            }
        }
        for (required.operation_requirements) |operation| {
            var actual: ?ast.Operation = null;
            var concrete = false;
            switch (argument) {
                .parameter => |index| for (self.parameters[index].operation_requirements) |provided| {
                    if (std.mem.eql(u8, self.src.text(provided.name), self.src.text(operation.name))) {
                        actual = provided;
                        break;
                    }
                },
                .concrete => |target| {
                    const function = try (@import("structural_constraints.zig").Context{ .src = self.src, .catalog = &self.catalog, .program = self.program, .sink = self.sink }).method(target, operation.name);
                    actual = .{ .name = function.name, .parameters = function.signature.parameters, .return_type = function.signature.return_type, .effect_bound = function.policy.effect_bound.? };
                    concrete = true;
                },
                else => {},
            }
            const provided = actual orelse return self.sink.fail(eArgument, operation.name, "forwarded type does not promise the required operation");
            if (provided.effect_bound.allowed & ~operation.effect_bound.allowed != 0 or provided.parameters.len != operation.parameters.len)
                return self.sink.fail(eArgument, operation.name, "forwarded operation arity or effects do not imply the contract");
            for (provided.parameters, operation.parameters) |input, expected| {
                if (input.reference != expected.reference or input.slice != expected.slice) return self.sink.fail(eArgument, operation.name, "forwarded operation reference permission differs");
                const actual_type = if (concrete) try self.concreteType(input.ty) else try self.ty(input.ty);
                try self.same(actual_type, try self.substituted(expected.ty, parameters, arguments), expected.name);
            }
            const result = if (concrete) try self.concreteType(provided.return_type) else try self.ty(provided.return_type);
            try self.same(result, try self.substituted(operation.return_type, parameters, arguments), operation.name);
        }
    }
    fn validateStructural(self: *Checker) Error!void {
        for (self.parameters) |parameter| {
            for (parameter.field_requirements) |field| {
                if (try self.transfers(try self.ty(field.ty))) return self.sink.fail("E_GENERIC_REQUIREMENT", field.ty, "structural fields require a copyable field type without result obligations");
            }
            for (parameter.operation_requirements) |operation| {
                _ = try self.ty(operation.return_type);
                for (operation.parameters) |input| {
                    const value = try self.ty(input.ty);
                    if (input.reference != null and try self.requiresHandling(value)) return self.sink.fail(diagnostic.result_borrow, input.ty, "structural operation cannot borrow result-bearing values");
                }
            }
        }
    }
    fn expression(self: *Checker, id: ast.NodeId) Error!Symbolic {
        const before = self.temporary_results;
        self.expression_depth += 1;
        defer self.expression_depth -= 1;
        errdefer self.temporary_results = before;
        const previous_inputs = self.region_inputs;
        const inputs = try self.regions.add(.{});
        self.region_inputs = inputs;
        defer self.region_inputs = previous_inputs;
        const result = try self.expressionValue(id);
        const output = try self.regions.add(.{});
        if ((try self.carriesRegion(result))) try self.regions.flow(inputs, output);
        if (previous_inputs) |parent| try self.regions.flow(output, parent);
        self.last_origin = output;
        self.temporary_results = before;
        if (self.expression_depth > 1 and (try self.requiresHandling(result))) self.temporary_results += 1;
        return result;
    }
    fn domainBacking(self: *Checker, value: Symbolic, span: source.Span) Error!Symbolic {
        const domain_type = try self.concreteValue(value, span);
        const backing = try self.catalog.domain(domain_type, span, self.sink);
        const owner = if (self.owner) |name| try self.concreteType(name) else null;
        if (owner == null or !symbolic.same(owner.?, value, self.catalog)) return self.sink.failRelated(
            "E_PRIVATE_DOMAIN",
            span,
            "only functions declared inside this domain can access its representation; use its factories and accessors",
            .{ .span = self.catalog.records[domain_type.recordIndex()].declaration, .message = "domain representation is private here" },
        );
        return .{ .concrete = backing };
    }
    fn expressionValue(self: *Checker, id: ast.NodeId) Error!Symbolic {
        const node = self.program.nodes.items[@backingInt(id)];
        try self.enter(node.span);
        defer self.depth -= 1;
        return switch (node.data) {
            .name => |name| try self.namedValue(name),
            .match_expression => |match| try self.matchExpression(match, node.span),
            .wrap => |wrap| result: {
                const operand = try self.expression(wrap.value);
                const target = try self.ty(wrap.ty);
                try self.same(operand, try self.domainBacking(target, node.span), node.span);
                break :result target;
            },
            .unwrap => |input| try self.domainBacking(try self.expression(input), node.span),
            .reset_arena => |reset| result: {
                const output = try self.operationResult(reset.ty, .bool, "E_ARENA_RESULT");
                try self.same(try self.expression(reset.value), .{ .concrete = .allocator }, node.span);
                break :result output;
            },
            .read_field, .take_field => |access| try self.fieldValue(access, node.data == .take_field),
            .acquire_buffer, .acquire_pool => |acquire| try self.acquireValue(acquire, node.data == .acquire_pool, node.span),
            .buffer_operation => |operation| try self.bufferValue(operation),
            .pool_operation => |operation| try self.poolValue(operation),
            .external_read => |read| try self.externalValue(read),
            .environment_get => |get| try self.environmentValue(get),
            .acquire_resource => |acquire| try self.acquireResource(acquire),
            .complete_resource => |complete| try self.completeResource(complete),
            .resource_io => |io| try self.resourceIo(io),
            .restrict_resource => |restrict| result: {
                const value = try self.expression(restrict.value);
                const value_type = try self.concreteValue(value, node.span);
                if (value_type.resourceKind() == null) return self.sink.fail("E_TYPE", node.span, "restriction requires filesystem or network capability authority");
                break :result value;
            },
            .read_slice => |read| result: {
                const ref = try self.reference(read.name, false, true);
                try self.supports(try self.expression(read.index), .integer, node.span);
                try self.supports(ref.ty, .copy, read.name);
                try self.regionRead(ref.*);
                break :result ref.ty;
            },
            .len_slice => |name| result: {
                _ = try self.reference(name, false, true);
                break :result .{ .concrete = .u64 };
            },
            .read_ref => |name| result: {
                const ref = try self.reference(name, false, false);
                if (try self.transfers(ref.ty)) return self.sink.fail("E_REFERENCE_VALUE", name, "read_ref cannot copy an owned value");
                try self.supports(ref.ty, .copy, name);
                try self.regionRead(ref.*);
                break :result ref.ty;
            },
            .call => |invocation| try self.call(invocation, node.span, false),
            .propagate => |operand| try self.propagateValue(operand, node.span),
            .bytes => try self.concreteType(node.span),
            .boolean => .{ .concrete = .bool },
            .integer => |span| .{ .concrete = (try @import("integer_literal.zig").parse(self.src, span, false, self.sink)).ty },
            .unary => |unary| result: {
                const child = self.program.nodes.items[@backingInt(unary.operand)];
                const operand: Symbolic = if (unary.op == .neg and child.data == .integer)
                    .{ .concrete = (try @import("integer_literal.zig").parse(self.src, child.data.integer, true, self.sink)).ty }
                else
                    try self.expression(unary.operand);
                if (unary.op == .neg) try self.supports(operand, .integer, unary.op_span) else try self.same(operand, .{ .concrete = if (unary.op == .not) .bool else .u64 }, unary.op_span);
                break :result operand;
            },
            .binary => |operation| try self.binary(operation),
            .record => |record| try self.recordValue(record, node.span),
            .variant => |variant| try self.variantValue(variant, node.span),
            .array => |array| try self.arrayValue(array, node.span),
            .update => |update| result: {
                const base = try self.expression(update.base);
                try self.recordFields(base, update.fields, false, node.span);
                break :result base;
            },
            .replace => |replacement| result: {
                const base = try self.expression(replacement.base);
                const shape = try self.arrayIndex(base, replacement.index, node.span);
                if ((try self.requiresHandling(shape.element))) return self.sink.fail(eResultOperation, node.span, "replacement would drop a result-bearing element");
                try self.same(try self.expression(replacement.value), shape.element, node.span);
                break :result base;
            },
            .field => |field| result: {
                const base = try self.expression(field.base);
                const shape = try self.shapes().requireRecord(base, node.span, false);
                const index = try self.shapes().memberIndex(shape, field.name);
                for (shape.fields, 0..) |other, i| {
                    if (i != index and (try self.requiresHandling(other.ty.?))) return self.sink.fail(eResultOperation, node.span, "projection would drop another result-bearing field");
                }
                break :result shape.fields[index].ty.?;
            },
            .length => |input| result: {
                const base = try self.expression(input);
                _ = try self.arrayShape(base, node.span);
                if ((try self.requiresHandling(base))) return self.sink.fail(eResultOperation, node.span, "length would drop result-bearing elements");
                break :result .{ .concrete = .u64 };
            },
            .index => |access| result: {
                const shape = try self.arrayIndex(try self.expression(access.base), access.index, node.span);
                if (shape.length != 1 and (try self.requiresHandling(shape.element))) return self.sink.fail(eResultOperation, node.span, "indexing would drop other result-bearing elements");
                break :result shape.element;
            },
            .cast => |cast| result: {
                const operand = try self.expression(cast.value);
                const target = try self.ty(cast.ty);
                try self.supports(operand, .integer, node.span);
                try self.supports(target, .integer, cast.ty);
                break :result target;
            },
        };
    }
    fn externalValue(self: *Checker, read: @FieldType(@FieldType(ast.Node, "data"), "external_read")) Error!Symbolic {
        const success: typed.Type = if (read.kind == .clock) .i64 else .u64;
        const result = try self.operationResult(read.ty, success, "E_EXTERNAL_RESULT");
        const authority: typed.Type = if (read.kind == .clock) .clock_cap else .random_cap;
        try self.same(try self.expression(read.capability), .{ .concrete = authority }, self.program.nodes.items[@backingInt(read.capability)].span);
        self.seedEffect(read.kind.effect());
        return result;
    }
    fn byteInput(self: *Checker, input: ast.NodeId, code: []const u8) Error!void {
        const span = self.program.nodes.items[@backingInt(input)].span;
        const value_type = try self.expression(input);
        if (!provider_shapes.bytes(value_type, self.catalog.records)) return self.sink.fail(code, span, "input requires a fixed u8 array");
    }
    fn environmentValue(self: *Checker, get: @FieldType(@FieldType(ast.Node, "data"), "environment_get")) Error!Symbolic {
        const result = try self.ty(get.ty);
        if (try provider_shapes.payload(self.shapes(), result, .environment, get.ty) == null) return self.sink.fail("E_ENVIRONMENT_RESULT", get.ty, "environment result requires bytes, length and present success fields with i64 error");
        try self.same(try self.expression(get.capability), .{ .concrete = .environment_cap }, self.program.nodes.items[@backingInt(get.capability)].span);
        try self.byteInput(get.name, "E_ENVIRONMENT_NAME");
        self.seedEffect(.environment);
        return result;
    }
    fn acquireResource(self: *Checker, acquire: @FieldType(@FieldType(ast.Node, "data"), "acquire_resource")) Error!Symbolic {
        const result = try self.ty(acquire.ty);
        const shape = try self.resultShape(result, acquire.ty, diagnostic.resource_result);
        const kind = provider_shapes.resource(shape.ok_type, self.catalog.records) orelse return self.sink.fail(diagnostic.resource_result, acquire.ty, "acquisition success must be a resource");
        if (!symbolic.same(shape.error_type, .{ .concrete = .i64 }, self.catalog)) return self.sink.fail(diagnostic.resource_result, acquire.ty, "acquisition error must be i64");
        const authority: typed.Type = if (kind == .filesystem) .filesystem_cap else .network_cap;
        try self.same(try self.expression(acquire.capability), .{ .concrete = authority }, self.program.nodes.items[@backingInt(acquire.capability)].span);
        try self.byteInput(acquire.request, "E_RESOURCE_REQUEST");
        self.seedEffect(kind.effect());
        return result;
    }
    fn completeResource(self: *Checker, complete: @FieldType(@FieldType(ast.Node, "data"), "complete_resource")) Error!Symbolic {
        const result = try self.ty(complete.ty);
        const fields = (try provider_shapes.payload(self.shapes(), result, .completion, complete.ty)) orelse return self.sink.fail(
            "E_COMPLETION_RESULT",
            complete.ty,
            "completion requires bool success and an error record containing the resource and i64 code",
        );
        try self.same(try self.expression(complete.value), fields[0].?, self.program.nodes.items[@backingInt(complete.value)].span);
        self.seedEffect(provider_shapes.resource(fields[0].?, self.catalog.records).?.effect());
        return result;
    }
    fn resourceIo(self: *Checker, io: @FieldType(@FieldType(ast.Node, "data"), "resource_io")) Error!Symbolic {
        if (io.value) |input| try self.byteInput(input, "E_RESOURCE_BYTES");
        const owner = try self.local(io.owner);
        const owner_type = try self.concreteValue(owner.ty, io.owner);
        if (owner.reference != null) return self.sink.fail("E_RESOURCE_TYPE", io.owner, "I/O requires an owned resource value binding");
        const kind = typed.resourceKind(owner_type, self.catalog.records) orelse return self.sink.fail("E_RESOURCE_TYPE", io.owner, "I/O requires an owned resource value binding");
        try self.runtimeOwner(io.owner, true);
        if (io.reference) |name| {
            const ref = try self.reference(name, io.kind == .read, true);
            try self.same(ref.ty, .{ .concrete = .u8 }, name);
        }
        const result = try self.ty(io.ty);
        if (io.kind == .write) {
            _ = try self.operationResult(io.ty, .u64, "E_RESOURCE_IO_RESULT");
        } else {
            const valid = try provider_shapes.payload(self.shapes(), result, if (io.reference != null) .slice_read else .read, io.ty) != null;
            if (!valid) return self.sink.fail("E_RESOURCE_IO_RESULT", io.ty, "read result must contain the required bytes/length/eof fields and i64 error");
        }
        self.seedEffect(kind.effect());
        return result;
    }
    fn runtimeOwner(self: *Checker, span: source.Span, mutates: bool) Error!void {
        const binding = try self.local(span);
        if (binding.reference != null) {
            _ = try self.reference(span, mutates, false);
            return;
        }
        if (!binding.available) return self.sink.failTransfer(diagnostic.owned_consumed, span, binding.name, binding.transfer_span);
        if (mutates and !binding.mutable) return self.sink.fail(diagnostic.immutable, span, "mutation requires a let mut binding");
        try self.ownerAccess(binding.*, mutates, span);
    }
    fn operationResult(self: *Checker, span: ?source.Span, success: typed.Type, code: []const u8) Error!Symbolic {
        return self.symbolicOperationResult(span, .{ .concrete = success }, code);
    }
    fn symbolicOperationResult(self: *Checker, span: ?source.Span, success: Symbolic, code: []const u8) Error!Symbolic {
        const result_span = span orelse return success;
        const result = try self.ty(result_span);
        const shape = try self.resultShape(result, result_span, code);
        const success_matches = symbolic.same(shape.ok_type, success, self.catalog);
        if (!success_matches or !symbolic.same(shape.error_type, .{ .concrete = .i64 }, self.catalog)) return self.sink.fail(code, result_span, "operation result payloads do not match its contract");
        return result;
    }
    fn bufferValue(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), "buffer_operation")) Error!Symbolic {
        const owner = try self.local(operation.owner);
        try self.regionRead(owner.*);
        const shape = (try self.shapes().container(owner.ty, operation.owner, false)) orelse return self.sink.fail("E_BUFFER_TYPE", operation.owner, "operation requires a buffer value binding");
        const element = shape.element;
        for (operation.arguments, 0..) |input, index| {
            const value = try self.expression(input);
            const at = self.program.nodes.items[@backingInt(input)].span;
            const writes_element = index == 1 and (operation.kind == .write or operation.kind == .resize);
            if (operation.kind == .reserve and index == 0) {
                try self.same(value, .{ .concrete = .allocator }, at);
            } else if (operation.kind == .append or writes_element) {
                try self.same(value, element, at);
                try self.regions.require(self.last_origin, .{ .node = self.locals.items[owner.root orelse self.active.get(self.src.text(operation.owner)).?].origin }, at);
            } else try self.supports(value, .integer, at);
        }
        try self.runtimeOwner(operation.owner, operation.kind.mutates());
        if (operation.kind.allocates()) self.seedEffect(.allocation);
        const success: Symbolic = if (operation.result != null) .{ .concrete = .bool } else if (operation.kind == .read) element else .{ .concrete = .u64 };
        return self.symbolicOperationResult(operation.result, success, "E_BUFFER_RESULT");
    }
    fn poolValue(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), "pool_operation")) Error!Symbolic {
        const owner = try self.local(operation.owner);
        try self.regionRead(owner.*);
        const pool = (try self.shapes().container(owner.ty, operation.owner, true)) orelse return self.sink.fail("E_POOL_TYPE", operation.owner, "operation requires a pool value binding");
        for (operation.arguments, 0..) |input, index| {
            const expected = if (operation.kind == .insert or index == 1) pool.element else pool.handle;
            const at = self.program.nodes.items[@backingInt(input)].span;
            try self.same(try self.expression(input), expected, at);
            if (operation.kind == .insert or index == 1) try self.regions.require(self.last_origin, .{ .node = self.locals.items[owner.root orelse self.active.get(self.src.text(operation.owner)).?].origin }, at);
        }
        try self.runtimeOwner(operation.owner, operation.kind.mutates());
        const success: Symbolic = switch (operation.kind) {
            .length, .capacity => .{ .concrete = .u64 },
            .insert => pool.handle,
            .read => pool.element,
            .replace, .remove, .clear => .{ .concrete = .bool },
        };
        return self.symbolicOperationResult(operation.result, success, "E_POOL_RESULT");
    }
    fn acquireValue(self: *Checker, acquire: @FieldType(@FieldType(ast.Node, "data"), "acquire_buffer"), pool: bool, span: source.Span) Error!Symbolic {
        const result = try self.ty(acquire.ty);
        const code = if (pool) "E_POOL_RESULT" else "E_BUFFER_RESULT";
        const shape = try self.resultShape(result, acquire.ty, code);
        const kind_matches = try self.shapes().container(shape.ok_type, acquire.ty, pool) != null;
        if (!kind_matches or !symbolic.same(shape.error_type, .{ .concrete = .i64 }, self.catalog)) return self.sink.fail(code, acquire.ty, "acquisition requires matching owner success and i64 error payloads");
        try self.same(try self.expression(acquire.allocator), .{ .concrete = .allocator }, self.program.nodes.items[@backingInt(acquire.allocator)].span);
        try self.supports(try self.expression(acquire.value), .integer, span);
        self.seedEffect(.allocation);
        return result;
    }
    fn fieldValue(self: *Checker, access: @FieldType(@FieldType(ast.Node, "data"), "read_field"), taking: bool) Error!Symbolic {
        const binding = try self.local(access.owner);
        if (binding.reference != null) {
            if (taking) return self.sink.fail("E_FIELD_TAKE", access.owner, "cannot move a field out of a borrowed owner");
            _ = try self.reference(access.owner, false, false);
        }
        try self.regionRead(binding.*);
        const shape = try self.shapes().requireRecord(binding.ty, access.owner, false);
        const index = try self.shapes().memberIndex(shape, access.field);
        const fields = shape.fields;
        const result = fields[index].ty.?;
        if (!taking and (try self.transfers(result))) return self.sink.fail("E_FIELD_COPY", access.field, "read_field cannot copy owned values or result obligations");
        if ((try self.transfers(binding.ty)) and !binding.available) return self.sink.failTransfer(diagnostic.owned_consumed, access.owner, binding.name, binding.transfer_span);
        if (taking and !(try self.transfers(binding.ty))) return self.sink.fail("E_FIELD_TAKE", access.owner, "take_field requires an owned or result-bearing record; use read_field for copyable records");
        if (binding.fields.len != 0) {
            if (binding.fields[index]) |at| return self.sink.failMovedField(access.field, binding.name, at);
        }
        if (binding.reference == null) try self.ownerAccess(binding.*, taking, access.owner);
        if (taking) binding.fields = try field_moves.take(self.field_arena.allocator(), binding.fields, fields.len, index, access.field);
        return result;
    }
    fn resultShape(self: *Checker, value: Symbolic, span: source.Span, code: []const u8) Error!symbolic.ResultShape {
        return (try self.shapes().matchResult(value, span)) orelse self.sink.fail(code, span, "operation requires a declared result type");
    }
    fn propagateValue(self: *Checker, operand: ast.NodeId, span: source.Span) Error!Symbolic {
        const temporaries = self.temporary_results;
        const value = try self.expression(operand);
        const input = try self.resultShape(value, span, "E_TRY_TYPE");
        if ((try self.carriesRegion(input.error_type))) try self.regions.require(self.last_origin, .{ .depth = 0 }, span);
        const output = try self.resultShape(self.result, span, eTryReturn);
        if (self.return_reference != null) return self.sink.fail(eTryReturn, span, "try cannot propagate through a reference return");
        try self.same(input.error_type, output.error_type, span);
        try self.requireHandled(0, span);
        if (temporaries != 0) return self.sink.fail("E_RESULT_PROPAGATION", span, "propagation could drop an already evaluated result temporary");
        return input.ok_type;
    }
    fn variantValue(self: *Checker, variant: @FieldType(@FieldType(ast.Node, "data"), "variant"), span: source.Span) Error!Symbolic {
        const result = try self.ty(variant.ty);
        const shape = try self.shapes().requireVariants(result, span);
        const tag = try self.shapes().memberIndex(shape, variant.name);
        const payload = shape.fields[tag].ty;
        if ((payload != null) != (variant.value != null)) return self.sink.fail("E_VARIANT_PAYLOAD", span, "construction must supply exactly the declared payload");
        if (variant.value) |value| try self.same(try self.expression(value), payload.?, span);
        return result;
    }
    fn matchValue(self: *Checker, match: @FieldType(@FieldType(ast.Statement, "data"), "match"), span: source.Span) Error!bool {
        const value = try self.expression(match.value);
        const origin = self.last_origin;
        const variants = try self.shapes().requireVariants(value, span);
        const seen = try self.allocator.alloc(bool, variants.fields.len);
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
            const tag = try self.shapes().memberIndex(variants, arm.name);
            if (seen[tag]) return self.sink.fail("E_DUPLICATE_ARM", arm.name, "variant has more than one match arm");
            seen[tag] = true;
            const payload = variants.fields[tag].ty;
            if (arm.discard_payload and payload != null and (try self.requiresHandling(payload.?))) return self.sink.fail(eResultDiscard, arm.name, "nested result payload requires explicit handling");
            if ((payload != null) != (arm.binding != null or arm.discard_payload)) return self.sink.fail("E_PATTERN_PAYLOAD", arm.name, "payload cases require a binding or discard; empty cases take neither");
            const before = self.locals.items.len;
            defer self.endScope(before);
            if (arm.binding) |binding| {
                try self.bind(binding, payload.?, false);
                if ((try self.carriesRegion(payload.?))) try self.regions.flow(origin, self.locals.items[before].origin);
            }
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
    fn matchExpression(self: *Checker, match: @FieldType(@FieldType(ast.Node, "data"), "match_expression"), span: source.Span) Error!Symbolic {
        const outer_temporaries = self.temporary_results;
        const value = try self.expression(match.value);
        const origin = self.last_origin;
        const variants = try self.shapes().requireVariants(value, span);
        const seen = try self.allocator.alloc(bool, variants.fields.len);
        defer self.allocator.free(seen);
        @memset(seen, false);
        const incoming = try self.pendingState(self.locals.items.len);
        defer self.allocator.free(incoming);
        var continuation: ?[]Pending = null;
        defer if (continuation) |state| self.allocator.free(state);
        var result: ?Symbolic = null;
        for (match.arms) |arm| {
            self.restorePending(incoming);
            self.temporary_results = outer_temporaries;
            try self.same(try self.ty(arm.ty), value, arm.ty);
            const tag = try self.shapes().memberIndex(variants, arm.name);
            if (seen[tag]) return self.sink.fail("E_DUPLICATE_ARM", arm.name, "variant has more than one match arm");
            seen[tag] = true;
            const payload = variants.fields[tag].ty;
            if (arm.discard_payload and payload != null and (try self.requiresHandling(payload.?))) return self.sink.fail(eResultDiscard, arm.name, "nested result payload requires explicit handling");
            if ((payload != null) != (arm.binding != null or arm.discard_payload)) return self.sink.fail("E_PATTERN_PAYLOAD", arm.name, "payload cases require a binding or discard; empty cases take neither");
            const before = self.locals.items.len;
            defer self.endScope(before);
            if (arm.binding) |binding| {
                try self.bind(binding, payload.?, false);
                if ((try self.carriesRegion(payload.?))) try self.regions.flow(origin, self.locals.items[before].origin);
            }
            const arm_type = try self.expression(arm.value);
            if (result) |expected| try self.same(arm_type, expected, span) else result = arm_type;
            try self.requireHandled(before, span);
            if (continuation) |state| try self.samePending(state, span, eResultPath) else continuation = try self.pendingState(incoming.len);
        }
        for (seen) |present| if (!present) return self.sink.fail("E_INCOMPLETE_MATCH", span, "match must cover every declared case");
        if (continuation) |state| self.restorePending(state);
        self.temporary_results = outer_temporaries;
        return result orelse self.sink.fail("E_EMPTY_MATCH", span, "a value-producing match requires at least one case");
    }
    fn arrayIndex(self: *Checker, base: Symbolic, input: ast.NodeId, span: source.Span) Error!symbolic.Array {
        const shape = try self.arrayShape(base, span);
        const index = try self.expression(input);
        if (shape.key) |key| try self.same(index, .{ .concrete = key }, span) else try self.supports(index, .integer, span);
        return shape;
    }
    fn arrayValue(self: *Checker, array: @FieldType(@FieldType(ast.Node, "data"), "array"), span: source.Span) Error!Symbolic {
        const result = try self.ty(array.ty);
        const shape = try self.arrayShape(result, span);
        if (shape.key != null) return self.sink.fail("E_TYPE", span, "enum-indexed tables require named construction");
        if (array.values.len != shape.length) return self.sink.fail("E_ARRAY_LENGTH", span, "array construction must supply its declared number of elements");
        for (array.values) |value| try self.same(try self.expression(value), shape.element, span);
        return result;
    }
    fn recordValue(self: *Checker, record: @FieldType(@FieldType(ast.Node, "data"), "record"), span: source.Span) Error!Symbolic {
        const result = try self.ty(record.name);
        try self.recordFields(result, record.fields, true, span);
        return result;
    }
    fn recordFields(self: *Checker, ty_value: Symbolic, fields: []const ast.FieldInit, complete: bool, span: source.Span) Error!void {
        const shape = try self.shapes().requireRecord(ty_value, span, complete);
        const table_key = shape.key;
        const seen = try self.allocator.alloc(bool, shape.fields.len);
        defer self.allocator.free(seen);
        @memset(seen, false);
        for (fields) |field| {
            const index = try self.shapes().memberIndex(shape, field.name);
            if (seen[index]) return self.sink.fail(if (table_key != null) "E_DUPLICATE_KEY" else "E_DUPLICATE_FIELD", field.name, "named entry is initialized more than once");
            seen[index] = true;
            if (!complete and (try self.requiresHandling(shape.fields[index].ty.?))) return self.sink.fail(eResultOperation, field.name, "update would drop a result-bearing field");
            try self.same(try self.expression(field.value), shape.fields[index].ty.?, field.name);
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
            .f64_add, .f64_sub, .f64_mul, .f64_div, .f64_eq, .f64_lt, .f64_le => try self.same(left, .{ .concrete = .u64 }, operation.op_span),
            .logical_and, .logical_or => try self.same(left, .{ .concrete = .bool }, operation.op_span),
            .eq, .ne => try self.supports(left, .equality, operation.op_span),
            else => try self.supports(left, .integer, operation.op_span),
        }
        return switch (operation.op) {
            .f64_add,
            .f64_sub,
            .f64_mul,
            .f64_div,
            .add,
            .sub,
            .mul,
            .div,
            .rem,
            .bit_and,
            .bit_or,
            .bit_xor,
            .shift_left,
            .shift_right,
            .wrapping_add,
            .wrapping_sub,
            .wrapping_mul,
            .saturating_add,
            .saturating_sub,
            .saturating_mul,
            => left,
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
            .arena_scope => |scope| {
                try self.same(try self.expression(scope.parent), .{ .concrete = .allocator }, statement_value.span);
                const before = self.locals.items.len;
                self.arena_depth += 1;
                defer self.arena_depth -= 1;
                try self.bind(scope.name, .{ .concrete = .allocator }, false);
                defer self.endScope(before);
                try self.regions.flow(try self.regions.add(.{ .depth = self.arena_depth, .scope = scope.name }), self.locals.items[before].origin);
                self.seedEffect(.allocation);
                return self.statement(scope.body);
            },
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
                const local_value = self.locals.items[self.locals.items.len - 1];
                try self.regions.flow(self.last_origin, local_value.origin);
                try self.regions.require(self.last_origin, .{ .depth = local_value.arena_depth }, binding.name);
            },
            .assignment => |assignment| {
                const target = try self.local(assignment.name);
                if (!target.mutable) return self.sink.fail(diagnostic.immutable, assignment.name, "assignment requires a mutable binding");
                try self.ownerAccess(target.*, true, assignment.name);
                const value = try self.expression(assignment.value);
                try self.same(value, target.ty, assignment.op_span);
                try self.regions.flow(self.last_origin, target.origin);
                try self.regions.require(self.last_origin, .{ .depth = target.arena_depth }, assignment.name);
                if (assignment.op != .set) try self.supports(target.ty, .integer, assignment.op_span);
                if ((try self.transfers(target.ty))) {
                    if ((try self.pendingObligation(target.*))) return self.sink.fail("E_RESULT_OVERWRITE", assignment.name, "assignment would overwrite an unhandled result");
                    target.available = true;
                    target.transfer_span = null;
                    target.fields = &.{};
                }
            },
            .write_slice => |write| {
                const ref = try self.reference(write.name, true, true);
                try self.supports(try self.expression(write.index), .integer, statement_value.span);
                try self.same(try self.expression(write.value), ref.ty, statement_value.span);
                try self.regionWrite(ref.*, self.last_origin, statement_value.span);
            },
            .write_ref => |write| {
                const ref = try self.reference(write.name, true, false);
                try self.same(try self.expression(write.value), ref.ty, statement_value.span);
                try self.regionWrite(ref.*, self.last_origin, statement_value.span);
            },
            .acknowledge => |value| {
                const acknowledged = try self.expression(value);
                if (acknowledged == .parameter and self.parameters[acknowledged.parameter].requirements.contains(.codec) and !self.parameters[acknowledged.parameter].requirements.contains(.copy))
                    return self.sink.fail("E_GENERIC_BODY_UNSUPPORTED", statement_value.span, "a codec contract does not promise that every value is a result obligation");
                if (!(try self.definiteHandling(acknowledged, statement_value.span))) return self.sink.fail("E_ACKNOWLEDGE_TYPE", statement_value.span, "acknowledge requires a result-bearing value");
            },
            .discard => |value| {
                const ty_value = try self.expression(value);
                if ((try self.requiresHandling(ty_value))) return self.sink.fail(eResultDiscard, statement_value.span, "discard cannot erase a result obligation");
                if (ty_value == .parameter) try self.supports(ty_value, .copy, statement_value.span);
            },
            .branch => |branch| return self.branchValue(branch, statement_value.span),
            .for_range => |range| {
                const element = try self.expression(range.start);
                try self.supports(element, .integer, range.name);
                try self.same(try self.expression(range.end), element, range.name);
                const first = self.locals.items.len;
                try self.bind(range.name, element, false);
                defer self.endScope(first);
                const before = try self.pendingState(self.locals.items.len);
                defer self.allocator.free(before);
                const previous = self.loop_pending;
                self.loop_pending = before;
                defer self.loop_pending = previous;
                if (!try self.statement(range.body)) try self.samePending(before, statement_value.span, diagnostic.result_loop);
                self.restorePending(before);
            },
            .loop_exit => {
                const before = self.loop_pending orelse return self.sink.fail("E_LOOP_EXIT", statement_value.span, "break and continue require an enclosing loop");
                try self.requireHandled(before.len, statement_value.span);
                try self.samePending(before, statement_value.span, diagnostic.result_loop);
                return true;
            },
            .loop => |loop| {
                const before = try self.pendingState(self.locals.items.len);
                defer self.allocator.free(before);
                try self.same(try self.expression(loop.condition), .{ .concrete = .bool }, statement_value.span);
                try self.samePending(before, statement_value.span, diagnostic.result_loop);
                const previous = self.loop_pending;
                self.loop_pending = before;
                defer self.loop_pending = previous;
                if (!try self.statement(loop.body)) try self.samePending(before, statement_value.span, diagnostic.result_loop);
                self.restorePending(before);
            },
        }
        return false;
    }
};
fn supportsSet(value: Symbolic, required: requirements.Set, parameters: []const requirements.Parameter, catalog: Catalog) bool {
    inline for (std.meta.tags(requirements.Requirement)) |requirement| {
        if (required.contains(requirement) and !symbolic.supports(value, requirement, parameters, catalog)) return false;
    }
    return true;
}
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
    const region_types = try region_check.typeDependencies(allocator, catalog.records);
    defer allocator.free(region_types);
    const cleanup_masks = try effects.cleanupMasks(allocator, catalog.records);
    defer allocator.free(cleanup_masks);
    const effect_masks = try allocator.alloc(effect_set.Mask, program.functions.len);
    defer allocator.free(effect_masks);
    @memset(effect_masks, 0);
    var effect_calls: std.ArrayList(effects.AbstractCall) = .empty;
    defer effect_calls.deinit(allocator);
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
    var failed = false;
    var cursor: usize = 0;
    while (cursor < pending.items.len) : (cursor += 1) {
        const function = program.functions[pending.items[cursor]];
        if (function.policy.host != null) continue;
        const parameters = requirements.resolve(allocator, src, function.signature.type_parameters, sink) catch |err| switch (err) {
            error.SourceError => {
                failed = true;
                continue;
            },
            else => return err,
        };
        defer allocator.free(parameters);
        var checker: Checker = .{
            .allocator = allocator,
            .field_arena = std.heap.ArenaAllocator.init(allocator),
            .regions = .{ .allocator = allocator },
            .region_types = region_types,
            .src = src,
            .program = program,
            .catalog = catalog,
            .cleanup_masks = cleanup_masks,
            .effect_masks = effect_masks,
            .effect_calls = &effect_calls,
            .function_index = pending.items[cursor],
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
        defer checker.regions.deinit();
        defer checker.locals.deinit(allocator);
        defer checker.active.deinit(allocator);
        checker.checkFunction(function) catch |err| switch (err) {
            error.SourceError => failed = true,
            else => return err,
        };
    }
    if (failed) return error.SourceError;
    try effects.checkAbstract(allocator, program.functions, effect_masks, effect_calls.items, sink);
}
