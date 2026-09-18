//! Stable incremental identities and exported-interface fingerprints.
//!
//! Identities are derived from canonical module/declaration names, checked
//! interface data, and emitted-fragment content, never from source byte offsets.
//! Source spans are only used to borrow diagnostic/body bytes and are replaced
//! by content hashes before anything becomes part of an identity.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const effect_set = @import("effect_set.zig");
const ids = @import("identity.zig");
const bytecode = @import("bytecode.zig");
const interface = @import("interfaces.zig");
const lexer = @import("lexer.zig");
const project_compile = @import("project_compile.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");

const full_name_format = "{s}::{s}";
const declaration_interface_domain = "mylang-declaration-interface-v1";
const function_kind = "function";

/// Identity allocation or schema derivation failed.
pub const Error = error{ OutOfMemory, SourceError, InternalError };
/// SHA-256 identity bytes.
pub const Hash = [32]u8;

/// One exported or private declaration identity and body fingerprint.
pub const Declaration = struct {
    name: []const u8,
    kind: []const u8,
    identity: []const u8,
    body_sha256: ?[]const u8 = null,
    /// Observable interface hash, or null when it cannot be derived without guessing.
    interface_sha256: ?[]const u8 = null,
    /// Stable identity of this declaration when it is an exported interface item.
    interface_identity: ?[]const u8 = null,
};

/// One module's stable identity and declaration table.
pub const Module = struct {
    name: []const u8,
    identity: []const u8,
    declarations: []const Declaration,
};

/// One checked nominal type or generic template.
pub const Nominal = struct {
    name: []const u8,
    kind: []const u8,
    identity: []const u8,
    interface_sha256: ?[]const u8 = null,
};

/// One concrete generic function specialization and its canonical key.
pub const Specialization = struct {
    name: []const u8,
    identity: []const u8,
    key_sha256: []const u8,
};

/// One emitted function or data fragment.
pub const Fragment = struct {
    name: []const u8,
    symbol_identity: []const u8,
    kind: []const u8,
    sha256: []const u8,
    identity: []const u8,
};

/// Build inputs a check-only manifest cannot derive from the checked program.
/// Specialization keys must distinguish target/runtime layout and compiler build,
/// so callers supply them explicitly instead of baking in placeholders.
pub const Contract = struct {
    compiler_sha256: []const u8,
    target_abi: []const u8,
};

/// Debug manifest for incremental identities; all strings are allocator-owned.
pub const Report = struct {
    /// False when built from a partial (rejected) check; fields are best-effort.
    complete: bool = true,
    version: []const u8,
    project_interface_sha256: []const u8,
    modules: []const Module,
    types: []const Nominal,
    specializations: []const Specialization,
    fragments: []const Fragment,
};

/// Derive a module identity from its canonical module name.
pub fn moduleIdentity(allocator: std.mem.Allocator, name: []const u8) Error![]const u8 {
    return ids.moduleIdentity(allocator, name) catch error.OutOfMemory;
}

/// Derive a declaration identity from module identity, kind, owner and local name.
pub fn declarationIdentity(allocator: std.mem.Allocator, module: []const u8, kind: []const u8, owner: ?[]const u8, name: []const u8) Error![]const u8 {
    return ids.declarationIdentity(allocator, module, kind, owner, name) catch error.OutOfMemory;
}

/// Derive a body identity from its declaration identity and exact body bytes.
pub fn bodyIdentity(allocator: std.mem.Allocator, declaration: []const u8, bytes: []const u8) Error![]const u8 {
    return ids.bodyIdentity(allocator, declaration, bytes) catch error.OutOfMemory;
}

/// Derive an exported-interface item identity from module, kind, owner and name.
pub fn interfaceItemIdentity(allocator: std.mem.Allocator, module: []const u8, kind: []const u8, owner: ?[]const u8, name: []const u8) Error![]const u8 {
    return ids.interfaceItemIdentity(allocator, module, kind, owner, name) catch error.OutOfMemory;
}

/// Derive a nominal type or generic-template identity; `kind` separates the two.
pub fn typeIdentity(allocator: std.mem.Allocator, module: []const u8, kind: []const u8, name: []const u8) Error![]const u8 {
    return ids.typeIdentity(allocator, module, kind, name) catch error.OutOfMemory;
}

/// Derive a generic specialization identity from its canonical cache key.
pub fn specializationIdentity(allocator: std.mem.Allocator, template_identity: []const u8, arguments_sha256: []const u8, provider_sha256: []const u8, target_abi: []const u8, compiler_sha256: []const u8) Error![]const u8 {
    return ids.specializationIdentity(allocator, template_identity, arguments_sha256, provider_sha256, target_abi, compiler_sha256) catch error.OutOfMemory;
}

/// Derive an emitted function/data fragment identity.
pub fn fragmentIdentity(allocator: std.mem.Allocator, symbol_identity: []const u8, kind: []const u8, normalized_bytes: []const u8) Error![]const u8 {
    return ids.fragmentIdentity(allocator, symbol_identity, kind, normalized_bytes) catch error.OutOfMemory;
}

const InterfaceComponent = struct { identity: []const u8, interface_sha256: []const u8 };

fn interfaceComponentLess(_: void, a: InterfaceComponent, b: InterfaceComponent) bool {
    if (!std.mem.eql(u8, a.identity, b.identity)) return std.mem.lessThan(u8, a.identity, b.identity);
    return std.mem.lessThan(u8, a.interface_sha256, b.interface_sha256);
}

/// Fingerprint the observable project interface: sorted exported-interface item
/// identities and their complete semantic interface fingerprints. Source
/// metadata, comments, formatting and private declarations are excluded.
pub fn projectInterfaceFingerprint(allocator: std.mem.Allocator, modules: []const Module) Error![]const u8 {
    var components: std.ArrayList(InterfaceComponent) = .empty;
    defer components.deinit(allocator);
    for (modules) |module| for (module.declarations) |declaration| {
        const interface_identity = declaration.interface_identity orelse continue;
        try components.append(allocator, .{
            .identity = interface_identity,
            .interface_sha256 = declaration.interface_sha256 orelse "",
        });
    };
    std.mem.sort(InterfaceComponent, components.items, {}, interfaceComponentLess);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("mylang-project-interface-v1");
    for (components.items) |component| {
        hash.update(&.{0});
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, component.identity.len, .little);
        hash.update(&length);
        hash.update(component.identity);
        std.mem.writeInt(u64, &length, component.interface_sha256.len, .little);
        hash.update(&length);
        hash.update(component.interface_sha256);
    }
    return allocator.dupe(u8, &std.fmt.bytesToHex(hash.finalResult(), .lower)) catch error.OutOfMemory;
}

/// Release a report allocated by `describe` with the same allocator.
pub fn deinit(self: Report, allocator: std.mem.Allocator) void {
    for (self.modules) |module| freeModule(allocator, module);
    allocator.free(self.modules);
    for (self.types) |item| freeNominal(allocator, item);
    allocator.free(self.types);
    for (self.specializations) |item| freeSpecialization(allocator, item);
    allocator.free(self.specializations);
    for (self.fragments) |item| freeFragment(allocator, item);
    allocator.free(self.fragments);
    allocator.free(self.version);
    allocator.free(self.project_interface_sha256);
}

/// Build the stable-identity debug manifest for one checked project.
pub fn describe(allocator: std.mem.Allocator, compilation: *project_compile.Compilation, contract: Contract) Error!Report {
    try compilation.check();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const program = compilation.program.?;

    var modules: std.ArrayList(Module) = .empty;
    for (compilation.index.units, 0..) |unit, module_index| {
        const module_name = compilation.index.project.modules.items[module_index].name;
        const module_identity = try moduleIdentity(scratch, module_name);
        const module_src = compilation.index.project.modules.items[module_index].src;
        var declarations: std.ArrayList(Declaration) = .empty;
        for (unit.symbols.items) |symbol| {
            const kind = @tagName(symbol.kind);
            const decl_identity = try declarationIdentity(scratch, module_name, kind, symbol.owner, symbol.name);
            const body = declarationBody(unit.syntax, module_src, symbol);
            const body_sha = if (body) |bytes| try bodyIdentity(scratch, decl_identity, bytes) else null;
            const iface = try declarationInterface(scratch, module_name, unit, symbol, program, module_src);
            const item_identity = if (symbol.exported) try interfaceItemIdentity(scratch, module_name, kind, symbol.owner, symbol.name) else null;
            try declarations.append(scratch, .{
                .name = try scratch.dupe(u8, symbol.name),
                .kind = kind,
                .identity = decl_identity,
                .body_sha256 = body_sha,
                .interface_sha256 = iface,
                .interface_identity = item_identity,
            });
        }
        std.mem.sort(Declaration, declarations.items, {}, lessDeclaration);
        try modules.append(scratch, .{
            .name = try scratch.dupe(u8, module_name),
            .identity = module_identity,
            .declarations = try declarations.toOwnedSlice(scratch),
        });
    }
    std.mem.sort(Module, modules.items, {}, lessModule);
    // Compose the project interface from the sorted semantic fingerprints of the
    // exported interface items only. This excludes source paths, spans and
    // source hashes, and includes exported constants and declared effect ceilings
    // through each declaration's `interface_sha256`.
    const project_interface = try projectInterfaceFingerprint(scratch, modules.items);

    // Declaration lookup by canonical module-qualified name. Values borrow the
    // scratch report storage and only live for the duration of `describe`.
    var declarations_by_name: std.StringHashMapUnmanaged(DeclInfo) = .empty;
    for (modules.items) |module| for (module.declarations) |declaration| {
        const full_name = try std.fmt.allocPrint(scratch, full_name_format, .{ module.name, declaration.name });
        try declarations_by_name.put(scratch, full_name, .{
            .identity = declaration.identity,
            .interface_sha256 = declaration.interface_sha256,
        });
    };

    // Nominal types and generic templates are keyed by their declaration name;
    // concrete instances are handled as specializations/fragments instead.
    var types: std.ArrayList(Nominal) = .empty;
    for (compilation.index.units, 0..) |unit, module_index| {
        const module_name = compilation.index.project.modules.items[module_index].name;
        for (unit.symbols.items) |symbol| {
            if (symbol.kind != .type) continue;
            const declaration = findAstType(unit, symbol.span) orelse continue;
            const category = astTypeCategory(declaration);
            const is_template = astTypeIsTemplate(declaration);
            const identity_kind = if (is_template) try std.fmt.allocPrint(scratch, "{s}-template", .{category}) else category;
            const full_name = try std.fmt.allocPrint(scratch, full_name_format, .{ module_name, symbol.name });
            const info = declarations_by_name.get(full_name);
            try types.append(scratch, .{
                .name = full_name,
                .kind = identity_kind,
                .identity = try typeIdentity(scratch, module_name, identity_kind, symbol.name),
                .interface_sha256 = if (info) |entry| entry.interface_sha256 else null,
            });
        }
    }
    std.mem.sort(Nominal, types.items, {}, lessNominal);

    // Concrete specializations are the checked functions that carry type arguments.
    // The target and compiler identities are not plumbed into this check-only
    // manifest, so explicit placeholders keep cache keys deterministic and honest.
    var specializations: std.ArrayList(Specialization) = .empty;
    for (program.functions) |function| {
        if (function.type_arguments.len == 0) continue;
        const base_name = specializationBaseName(function.name);
        const info = declarations_by_name.get(base_name) orelse continue;
        const arguments_sha = try argumentsFingerprint(scratch, function, program.records);
        // The provider fingerprint is the concrete argument shape (record fields,
        // variants and layout flags), not the generic template's interface: a
        // field inserted before an accessed field changes generated offsets.
        const provider_sha = try providerFingerprint(scratch, function, program.records);
        const target_abi = contract.target_abi;
        const compiler_sha = contract.compiler_sha256;
        try specializations.append(scratch, .{
            .name = try scratch.dupe(u8, function.name),
            .identity = try specializationIdentity(scratch, info.identity, arguments_sha, provider_sha, target_abi, compiler_sha),
            .key_sha256 = try specializationKey(scratch, info.identity, arguments_sha, provider_sha, target_abi, compiler_sha),
        });
    }
    std.mem.sort(Specialization, specializations.items, {}, lessSpecialization);

    // Lowered fragments require bytecode. `describe` is the check-only
    // `project-dependencies` path, so when `compilation.emit()` has not run the
    // fragment table stays empty rather than forcing a lowering pass.
    var fragments: std.ArrayList(Fragment) = .empty;
    if (compilation.code) |code| try buildFragments(scratch, &fragments, code, &declarations_by_name, specializations.items);
    std.mem.sort(Fragment, fragments.items, {}, lessFragment);

    return materialize(allocator, .{
        .version = "incremental-identities-v2",
        .complete = true,
        .project_interface_sha256 = project_interface,
        .modules = modules.items,
        .types = types.items,
        .specializations = specializations.items,
        .fragments = fragments.items,
    });
}

/// Build a best-effort manifest from a project whose bodies did not all check.
/// This never calls `check()`, publishes no verdict, and leaves typed-only tables
/// empty; callers use it to explain a rejection rather than to reuse work.
pub fn describePartial(allocator: std.mem.Allocator, compilation: *project_compile.Compilation) Error!Report {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    var modules: std.ArrayList(Module) = .empty;
    for (compilation.index.units, 0..) |unit, module_index| {
        const module_name = compilation.index.project.modules.items[module_index].name;
        const module_identity = try moduleIdentity(scratch, module_name);
        const module_src = compilation.index.project.modules.items[module_index].src;
        var declarations: std.ArrayList(Declaration) = .empty;
        for (unit.symbols.items) |symbol| {
            const kind = @tagName(symbol.kind);
            const decl_identity = try declarationIdentity(scratch, module_name, kind, symbol.owner, symbol.name);
            const body = declarationBody(unit.syntax, module_src, symbol);
            const body_sha = if (body) |bytes| try bodyIdentity(scratch, decl_identity, bytes) else null;
            const iface = try astDeclarationInterface(scratch, unit, symbol, module_src);
            const item_identity = if (symbol.exported) try interfaceItemIdentity(scratch, module_name, kind, symbol.owner, symbol.name) else null;
            try declarations.append(scratch, .{
                .name = try scratch.dupe(u8, symbol.name),
                .kind = kind,
                .identity = decl_identity,
                .body_sha256 = body_sha,
                .interface_sha256 = iface,
                .interface_identity = item_identity,
            });
        }
        std.mem.sort(Declaration, declarations.items, {}, lessDeclaration);
        try modules.append(scratch, .{
            .name = try scratch.dupe(u8, module_name),
            .identity = module_identity,
            .declarations = try declarations.toOwnedSlice(scratch),
        });
    }
    std.mem.sort(Module, modules.items, {}, lessModule);
    const project_interface = try projectInterfaceFingerprint(scratch, modules.items);
    return materialize(allocator, .{
        .version = "incremental-identities-v2",
        .complete = false,
        .project_interface_sha256 = project_interface,
        .modules = modules.items,
        .types = &.{},
        .specializations = &.{},
        .fragments = &.{},
    });
}

/// AST-only interface fallback for a rejected check, mirroring the typed paths in
/// `declarationInterface` without requiring a checked program.
fn astDeclarationInterface(scratch: std.mem.Allocator, unit: interface.Unit, symbol: interface.Symbol, src: source.Source) Error!?[]const u8 {
    switch (symbol.kind) {
        .function => {
            const function = findAstFunction(unit.syntax, symbol.span) orelse return null;
            if (function.policy.constant) {
                const span = unit.syntax.statements.items[@backingInt(function.body)].span;
                const value = try normalizedDeclarationHash(scratch, src, "constant", span);
                return value;
            }
            const value = try normalizedFunctionDeclarationHash(scratch, src, unit.syntax, function, function_kind);
            return value;
        },
        .type => {
            const declaration = findAstType(unit, symbol.span) orelse return null;
            const value = try normalizedDeclarationHash(scratch, src, astTypeCategory(declaration), astTypeSpan(declaration));
            return value;
        },
        .constraint => {
            const constraint = findAstConstraint(unit.syntax, symbol.span) orelse return null;
            const value = try normalizedDeclarationHash(scratch, src, "constraint", constraint.span);
            return value;
        },
    }
}

const DeclInfo = struct {
    identity: []const u8,
    interface_sha256: ?[]const u8,
};

fn declarationBody(syntax: ast.Program, src: source.Source, symbol: interface.Symbol) ?[]const u8 {
    for (syntax.functions) |function| {
        if (function.name.start != symbol.span.start or function.name.end != symbol.span.end) continue;
        if (function.policy.host != null or function.policy.c_abi) return null;
        const span = syntax.statements.items[@backingInt(function.body)].span;
        if (span.end < span.start or span.end > src.bytes.len) return null;
        return src.bytes[span.start..span.end];
    }
    return null;
}

/// Hash a declaration's observable interface. Function/record/alias interfaces
/// come from the checked `typed.Program`; generic templates, constants and
/// constraints, whose interface is the declaration itself, use a canonical
/// whitespace/comment-normalized spelling. Unknown shapes return null.
fn declarationInterface(scratch: std.mem.Allocator, module_name: []const u8, unit: interface.Unit, symbol: interface.Symbol, program: typed.Program, src: source.Source) Error!?[]const u8 {
    const full_name = try std.fmt.allocPrint(scratch, full_name_format, .{ module_name, symbol.name });
    switch (symbol.kind) {
        .function => {
            const ast_function = findAstFunction(unit.syntax, symbol.span);
            if (ast_function) |function| {
                if (function.policy.constant) {
                    const span = unit.syntax.statements.items[@backingInt(function.body)].span;
                    const hash = try normalizedDeclarationHash(scratch, src, "constant", span);
                    return hash;
                }
                if (function.signature.type_parameters.len != 0) {
                    const hash = try normalizedFunctionDeclarationHash(scratch, src, unit.syntax, function, "function-template");
                    return hash;
                }
            }
            if (findTypedFunction(program, full_name)) |function| {
                var out: std.Io.Writer.Allocating = .init(scratch);
                defer out.deinit();
                try writeTypedFunction(&out.writer, function, program.records);
                // The typed encoder cannot see AST-only default values, so append the
                // normalized declaration header (which includes defaults) as well.
                if (ast_function) |declared| {
                    try writerWrite(&out.writer, "\x00");
                    try writerWrite(&out.writer, try normalizedFunctionSpan(scratch, src, unit.syntax, declared));
                }
                const bytes = out.toOwnedSlice() catch return error.OutOfMemory;
                const hash = try hashFields(scratch, declaration_interface_domain, &.{ function_kind, bytes });
                return hash;
            }
            if (ast_function) |function| {
                const hash = try normalizedFunctionDeclarationHash(scratch, src, unit.syntax, function, function_kind);
                return hash;
            }
            return null;
        },
        .type => {
            const declaration = findAstType(unit, symbol.span) orelse return null;
            switch (declaration) {
                .alias => |alias| {
                    if (findTypedAlias(program, full_name)) |checked| {
                        var out: std.Io.Writer.Allocating = .init(scratch);
                        defer out.deinit();
                        try writeTypedAlias(&out.writer, checked, program.records);
                        const spelling = try normalizeSpan(scratch, src, aliasSpan(alias));
                        try writerWrite(&out.writer, "\x00");
                        try writerWrite(&out.writer, spelling);
                        const bytes = out.toOwnedSlice() catch return error.OutOfMemory;
                        const hash = try hashFields(scratch, declaration_interface_domain, &.{ "alias", bytes });
                        return hash;
                    }
                    const hash = try normalizedDeclarationHash(scratch, src, "alias", aliasSpan(alias));
                    return hash;
                },
                else => {
                    if (!astTypeIsTemplate(declaration)) if (findTypedRecord(program, full_name)) |record| {
                        var out: std.Io.Writer.Allocating = .init(scratch);
                        defer out.deinit();
                        try writeTypedRecord(&out.writer, record, program.records);
                        const bytes = out.toOwnedSlice() catch return error.OutOfMemory;
                        const hash = try hashFields(scratch, declaration_interface_domain, &.{ astTypeCategory(declaration), bytes });
                        return hash;
                    };
                    const hash = try normalizedDeclarationHash(scratch, src, astTypeCategory(declaration), astTypeSpan(declaration));
                    return hash;
                },
            }
        },
        .constraint => {
            const constraint = findAstConstraint(unit.syntax, symbol.span) orelse return null;
            const hash = try normalizedDeclarationHash(scratch, src, "constraint", constraint.span);
            return hash;
        },
    }
}

fn normalizedDeclarationHash(scratch: std.mem.Allocator, src: source.Source, kind: []const u8, span: source.Span) Error![]const u8 {
    const normalized = try normalizeSpan(scratch, src, span);
    return hashFields(scratch, declaration_interface_domain, &.{ kind, normalized });
}

/// Tokenize a source range and join token spellings with NUL separators. This
/// removes comments/formatting while preserving identifiers, literals and names.
fn normalizeSpan(scratch: std.mem.Allocator, src: source.Source, span: source.Span) Error![]const u8 {
    if (span.start > span.end or span.end > src.bytes.len) return error.InternalError;
    var sink: diagnostic.Sink = .{ .allocator = scratch };
    const tokens = lexer.lexRangeWithMarkers(scratch, src.bytes, span, src.mutation_markers, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InternalError,
    };
    var out: std.Io.Writer.Allocating = .init(scratch);
    defer out.deinit();
    var first = true;
    for (tokens) |token| {
        if (token.tag == .eof) continue;
        if (!first) try writerWrite(&out.writer, "\x00");
        first = false;
        if (token.span.start > token.span.end or token.span.end > src.bytes.len) return error.InternalError;
        try writerWrite(&out.writer, src.bytes[token.span.start..token.span.end]);
    }
    return out.toOwnedSlice() catch return error.OutOfMemory;
}

/// Hash the function declaration header after normalizing its optional
/// `mutates(...)` clause to the contract's sorted, duplicate-free parameter
/// positions. The clause region therefore changes with the declared contract
/// without making binder spelling or argument order part of the type identity.
fn normalizedFunctionDeclarationHash(scratch: std.mem.Allocator, src: source.Source, syntax: ast.Program, function: ast.Function, kind: []const u8) Error![]const u8 {
    const normalized = try normalizedFunctionSpan(scratch, src, syntax, function);
    // Generic templates and AST-only fallbacks have no checked `typed.Function`
    // serializer, so append the same declared contract fields here. The
    // return-origin bound is the conservative exported default: no source
    // syntax publishes a narrower one.
    var out: std.Io.Writer.Allocating = .init(scratch);
    defer out.deinit();
    try writerWrite(&out.writer, normalized);
    try writerWrite(&out.writer, "\x00public-mutates=");
    if (function.signature.mutates.len == 0) try writerWrite(&out.writer, "none") else try writePositions(&out.writer, function.signature.mutates);
    try writerWrite(&out.writer, "\x00public-return-origin=");
    try writeReturnOrigin(&out.writer, .unknown);
    const bytes = out.toOwnedSlice() catch return error.OutOfMemory;
    return hashFields(scratch, declaration_interface_domain, &.{ kind, bytes });
}

fn normalizedFunctionSpan(scratch: std.mem.Allocator, src: source.Source, syntax: ast.Program, function: ast.Function) Error![]const u8 {
    const span = try functionSpan(scratch, src, syntax, function);
    if (span.start > span.end or span.end > src.bytes.len) return error.InternalError;
    var sink: diagnostic.Sink = .{ .allocator = scratch };
    const tokens = lexer.lexRangeWithMarkers(scratch, src.bytes, span, src.mutation_markers, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InternalError,
    };
    const clause = try mutatesClauseSpan(scratch, src, syntax, function);
    var out: std.Io.Writer.Allocating = .init(scratch);
    defer out.deinit();
    var first = true;
    var index: usize = 0;
    while (tokens[index].tag != .eof) {
        if (clause) |region| {
            if (tokens[index].span.start == region.start) {
                if (!first) try writerWrite(&out.writer, "\x00");
                first = false;
                try writeCanonicalMutates(&out.writer, function.signature.mutates);
                while (tokens[index].tag != .eof and tokens[index].span.end <= region.end) index += 1;
                continue;
            }
        }
        const token = tokens[index];
        if (token.span.start > token.span.end or token.span.end > src.bytes.len) return error.InternalError;
        if (!first) try writerWrite(&out.writer, "\x00");
        first = false;
        try writerWrite(&out.writer, src.bytes[token.span.start..token.span.end]);
        index += 1;
    }
    return out.toOwnedSlice() catch return error.OutOfMemory;
}

fn writeCanonicalMutates(writer: *std.Io.Writer, positions: []const u16) Error!void {
    try writerWrite(writer, "mutates(");
    try writePositions(writer, positions);
    try writerWrite(writer, ")");
}

fn writePositions(writer: *std.Io.Writer, positions: []const u16) Error!void {
    for (positions, 0..) |position, index| {
        if (index != 0) try writerWrite(writer, ",");
        try writerPrint(writer, "{d}", .{position});
    }
}

fn writeReturnOrigin(writer: *std.Io.Writer, origin: typed.ReturnOrigin) Error!void {
    switch (origin) {
        .fresh => try writerWrite(writer, "fresh"),
        .unknown => try writerWrite(writer, "unknown"),
        .params => |positions| {
            try writerWrite(writer, "params(");
            try writePositions(writer, positions);
            try writerWrite(writer, ")");
        },
    }
}

fn writeTypedFunction(writer: *std.Io.Writer, function: typed.Function, records: []const typed.Record) Error!void {
    try writerWrite(writer, "function\nname=");
    try writerWrite(writer, function.name);
    try writerWrite(writer, "\nowner=");
    if (function.policy.owner) |owner| try writerWrite(writer, typed.typeName(owner, records)) else try writerWrite(writer, "-");
    try writerWrite(writer, "\nreturn=");
    try writerWrite(writer, typed.typeName(function.signature.return_type, records));
    try writerWrite(writer, "\nrestricted=");
    try writerWrite(writer, if (function.policy.restricted) "true" else "false");
    try writerWrite(writer, "\nc-abi=");
    try writerWrite(writer, if (function.policy.c_abi) "true" else "false");
    try writerWrite(writer, "\nhost=");
    try writerWrite(writer, if (function.policy.host != null) "true" else "false");
    try writerWrite(writer, "\nconversion=");
    try writerWrite(writer, if (function.policy.conversion) "true" else "false");
    try writerWrite(writer, "\nparameters=");
    for (function.scope.locals[0..@min(function.signature.parameter_count, function.scope.locals.len)]) |parameter| {
        try writerWrite(writer, parameter.name);
        try writerWrite(writer, ":");
        try writerWrite(writer, typed.typeName(parameter.ty, records));
        try writerWrite(writer, "\x00");
    }
    try writerWrite(writer, "\nconstant-arguments=");
    for (function.signature.constant_arguments) |value| {
        if (value) |length| try writerPrint(writer, "{d}", .{length}) else try writerWrite(writer, "-");
        try writerWrite(writer, "\x00");
    }
    // E2: the public interface fingerprint carries only the declared ceiling.
    // Inferred implementation effects stay in the checked program for
    // diagnostics and in `body_sha256` for runtime-test cacheability, so an
    // implementation edit that stays inside the published bound cannot change
    // the API fingerprint or invalidate callers' type checking.
    try writerWrite(writer, "\npublic-ceiling=");
    if (function.policy.effect_bound) |bound| try writeEffectMask(writer, bound.allowed) else try writerWrite(writer, "unbounded");

    // M1/M2: the declared ceiling also includes the normalized mutation
    // footprint and the return-origin bound. Exported declarations publish the
    // conservative `unknown` return-origin default because there is no source
    // syntax for a narrower bound. Private inferred summaries remain separate:
    // they stay in the checked program and in `body_sha256`/C2 context, and are
    // deliberately not mixed into this declaration interface fingerprint. This
    // is the public API fingerprint, so inferred implementation effect sets are
    // also excluded above.
    const declared_mutates = function.signature.declared_mutates;
    const declared_return_origin: typed.ReturnOrigin = .unknown;
    try writerWrite(writer, "\npublic-mutates=");
    if (declared_mutates.len == 0) try writerWrite(writer, "none") else try writePositions(writer, declared_mutates);
    try writerWrite(writer, "\npublic-return-origin=");
    try writeReturnOrigin(writer, declared_return_origin);
}

fn writeTypedRecord(writer: *std.Io.Writer, record: typed.Record, records: []const typed.Record) Error!void {
    try writerWrite(writer, "type\nname=");
    try writerWrite(writer, record.name);
    try writerWrite(writer, "\nmanaged=");
    try writerWrite(writer, if (record.managed) "true" else "false");
    try writerWrite(writer, "\nmove-only=");
    try writerWrite(writer, if (record.contract.move_only) "true" else "false");
    try writerWrite(writer, "\nrequires-handling=");
    try writerWrite(writer, if (record.contract.requires_handling) "true" else "false");
    try writerWrite(writer, "\nstorable=");
    try writerWrite(writer, if (record.contract.storable) "true" else "false");
    try writerWrite(writer, "\npublic-arguments=");
    try writerWrite(writer, if (record.contract.public_arguments) "true" else "false");
    try writerWrite(writer, "\nfields=");
    for (record.fields) |field| {
        try writerWrite(writer, field.name);
        try writerWrite(writer, ":");
        try writerWrite(writer, typed.typeName(field.ty, records));
        try writerWrite(writer, "\x00");
    }
    if (record.shape.variants) |variants| {
        try writerWrite(writer, "\nvariants=");
        try writerWrite(writer, if (variants.fallible) "result" else if (variants.is_union) "union" else "enum");
        for (variants.cases) |case| {
            try writerWrite(writer, "\x00");
            try writerWrite(writer, case.name);
            if (case.payload) |payload| {
                try writerWrite(writer, ":");
                try writerWrite(writer, typed.typeName(payload, records));
            }
        }
    }
    if (record.shape.array) |array| {
        try writerWrite(writer, "\narray=");
        try writerWrite(writer, typed.typeName(array.element, records));
        try writerPrint(writer, ",{d},", .{array.length});
        if (array.key) |key| try writerWrite(writer, typed.typeName(key, records)) else try writerWrite(writer, "-");
    }
    if (record.shape.domain) |backing| {
        try writerWrite(writer, "\ndomain=");
        try writerWrite(writer, typed.typeName(backing, records));
    }
    if (record.shape.buffer) |element| {
        try writerWrite(writer, "\nbuffer=");
        try writerWrite(writer, typed.typeName(element, records));
    }
    if (record.shape.resource) |kind| {
        try writerWrite(writer, "\nresource=");
        try writerWrite(writer, @tagName(kind));
    }
    if (record.contract.callback) |callback| {
        try writerWrite(writer, "\ncallback=");
        for (callback.parameters) |parameter| {
            try writerWrite(writer, typed.typeName(parameter, records));
            try writerWrite(writer, ",");
        }
        try writerWrite(writer, "->");
        try writerWrite(writer, typed.typeName(callback.return_type, records));
        try writerWrite(writer, " effects=");
        try writeEffectMask(writer, callback.effects);
    }
}

fn writeTypedAlias(writer: *std.Io.Writer, alias: typed.TypeAlias, records: []const typed.Record) Error!void {
    try writerWrite(writer, "alias\nname=");
    try writerWrite(writer, alias.name);
    try writerWrite(writer, "\ntarget=");
    try writerWrite(writer, typed.typeName(alias.target, records));
}

// twin-drift-ok: canonical fingerprint spelling is a brace-set over effect tags;
// src/interfaces.zig renders schema text for a different consumer, so the shared
// shape is intentional while the emitted bytes are not interchangeable.
fn writeEffectMask(writer: *std.Io.Writer, mask: effect_set.Mask) Error!void {
    try writerWrite(writer, "{");
    var separator = false;
    inline for (std.meta.tags(effect_set.Effect)) |effect| {
        if (mask & effect_set.bit(effect) != 0) {
            if (separator) try writerWrite(writer, ",");
            try writerWrite(writer, @tagName(effect));
            separator = true;
        }
    }
    try writerWrite(writer, "}");
}

fn argumentsFingerprint(scratch: std.mem.Allocator, function: typed.Function, records: []const typed.Record) Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(scratch);
    defer out.deinit();
    for (function.type_arguments) |argument| {
        try writerWrite(&out.writer, typed.typeName(argument, records));
        try writerWrite(&out.writer, "\x00");
    }
    for (function.signature.constant_arguments) |value| {
        if (value) |length| try writerPrint(&out.writer, "{d}", .{length}) else try writerWrite(&out.writer, "-");
        try writerWrite(&out.writer, "\x00");
    }
    const bytes = out.toOwnedSlice() catch return error.OutOfMemory;
    return hashFields(scratch, "mylang-specialization-arguments-v1", &.{bytes});
}

fn providerFingerprint(scratch: std.mem.Allocator, function: typed.Function, records: []const typed.Record) Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(scratch);
    defer out.deinit();
    for (function.type_arguments) |argument| {
        try writerWrite(&out.writer, typed.typeName(argument, records));
        try writerWrite(&out.writer, "\x00");
        if (argument.isAggregate() and argument.recordIndex() < records.len) {
            try writeTypedRecord(&out.writer, records[argument.recordIndex()], records);
        }
        try writerWrite(&out.writer, "\x01");
    }
    const bytes = out.toOwnedSlice() catch return error.OutOfMemory;
    return hashFields(scratch, "mylang-specialization-provider-v1", &.{bytes});
}

fn specializationKey(scratch: std.mem.Allocator, template_identity: []const u8, arguments_sha256: []const u8, provider_sha256: []const u8, target_abi: []const u8, compiler_sha256: []const u8) Error![]const u8 {
    return hashFields(scratch, "mylang-specialization-key-v1", &.{ template_identity, arguments_sha256, provider_sha256, target_abi, compiler_sha256 });
}

/// `describe` is check-only, so fragments are built only when the caller has
/// already lowered the project (`compilation.code != null`).
fn buildFragments(scratch: std.mem.Allocator, fragments: *std.ArrayList(Fragment), code: bytecode.Program, declarations: *const std.StringHashMapUnmanaged(DeclInfo), specializations: []const Specialization) Error!void {
    for (code.functions) |function| {
        const symbol_identity = try fragmentSymbolIdentity(scratch, function.name, declarations, specializations);
        var normalized: std.Io.Writer.Allocating = .init(scratch);
        defer normalized.deinit();
        try writeLoweredFunction(&normalized.writer, code, function);
        const bytes = normalized.toOwnedSlice() catch return error.OutOfMemory;
        try fragments.append(scratch, .{
            .name = try scratch.dupe(u8, function.name),
            .symbol_identity = symbol_identity,
            .kind = function_kind,
            .sha256 = try hashFields(scratch, "mylang-fragment-content-v1", &.{bytes}),
            .identity = try fragmentIdentity(scratch, symbol_identity, function_kind, bytes),
        });
    }
}

fn fragmentSymbolIdentity(scratch: std.mem.Allocator, name: []const u8, declarations: *const std.StringHashMapUnmanaged(DeclInfo), specializations: []const Specialization) Error![]const u8 {
    for (specializations) |item| if (std.mem.eql(u8, item.name, name)) return item.identity;
    if (declarations.get(name)) |info| return info.identity;
    const separator = std.mem.indexOf(u8, name, "::") orelse return declarationIdentity(scratch, "", function_kind, null, name);
    return declarationIdentity(scratch, name[0..separator], function_kind, null, name[separator + 2 ..]);
}

fn writeLoweredFunction(writer: *std.Io.Writer, code: bytecode.Program, function: bytecode.Function) Error!void {
    try writerWrite(writer, "function\nname=");
    try writerWrite(writer, function.name);
    try writerWrite(writer, "\nreturn=");
    try writerWrite(writer, typed.typeName(function.signature.return_type, code.records));
    try writerWrite(writer, "\nparameters=");
    for (function.scope.locals[0..@min(function.signature.parameter_count, function.scope.locals.len)]) |parameter| {
        try writerWrite(writer, typed.typeName(parameter.ty, code.records));
        try writerWrite(writer, "\x00");
    }
    try writerWrite(writer, "\ninstructions\n");
    for (function.scope.instructions) |instruction| {
        switch (instruction.op) {
            inline else => |payload| {
                try writerWrite(writer, @tagName(instruction.op));
                try writerWrite(writer, "=");
                try writePayload(writer, code, payload);
                try writerWrite(writer, "\n");
            },
        }
    }
}

/// Structural payload writer: maps types and function ids to stable names, keeps
/// local/jump ordinals (they are function-local, not source offsets), and never
/// emits spans.
fn writePayload(writer: *std.Io.Writer, code: bytecode.Program, payload: anytype) Error!void {
    const P = @TypeOf(payload);
    if (P == typed.Type) return writerWrite(writer, typed.typeName(payload, code.records));
    if (P == typed.FunctionId) {
        if (@backingInt(payload) < code.functions.len) return writerWrite(writer, code.functions[@backingInt(payload)].name);
        return writerWrite(writer, "<invalid-function>");
    }
    if (P == typed.LocalId) return writerPrint(writer, "{d}", .{@backingInt(payload)});
    switch (@typeInfo(P)) {
        .bool => return writerWrite(writer, if (payload) "true" else "false"),
        .int => return writerPrint(writer, "{d}", .{payload}),
        .float => return writerPrint(writer, "{d}", .{payload}),
        .@"enum" => return writerWrite(writer, @tagName(payload)),
        .optional => {
            if (payload) |value| return writePayload(writer, code, value);
            return writerWrite(writer, "null");
        },
        .pointer => |pointer| {
            if (pointer.size != .slice) return writerWrite(writer, "<pointer>");
            try writerWrite(writer, "[");
            for (payload, 0..) |item, index| {
                if (index != 0) try writerWrite(writer, ",");
                try writePayload(writer, code, item);
            }
            return writerWrite(writer, "]");
        },
        .array => {
            try writerWrite(writer, "[");
            for (payload, 0..) |item, index| {
                if (index != 0) try writerWrite(writer, ",");
                try writePayload(writer, code, item);
            }
            return writerWrite(writer, "]");
        },
        .@"struct" => {
            try writerWrite(writer, "{");
            inline for (@typeInfo(P).@"struct".field_names, @typeInfo(P).@"struct".field_types, 0..) |field_name, Field, index| {
                _ = Field;
                if (index != 0) try writerWrite(writer, ",");
                try writerWrite(writer, field_name);
                try writerWrite(writer, ":");
                try writePayload(writer, code, @field(payload, field_name));
            }
            return writerWrite(writer, "}");
        },
        .void => return,
        else => return writerWrite(writer, "<value>"),
    }
}

fn classify(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.SourceError => error.SourceError,
        else => error.InternalError,
    };
}

fn lessDeclaration(_: void, a: Declaration, b: Declaration) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
fn lessModule(_: void, a: Module, b: Module) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
fn lessNominal(_: void, a: Nominal, b: Nominal) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
fn lessSpecialization(_: void, a: Specialization, b: Specialization) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
fn lessFragment(_: void, a: Fragment, b: Fragment) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn findAstFunction(syntax: ast.Program, span: source.Span) ?ast.Function {
    for (syntax.functions) |function| if (sameSpan(function.name, span)) return function;
    return null;
}

fn findTypedFunction(program: typed.Program, full_name: []const u8) ?typed.Function {
    for (program.functions) |function| {
        if (function.type_arguments.len != 0) continue;
        if (std.mem.eql(u8, function.name, full_name)) return function;
    }
    return null;
}

fn findTypedRecord(program: typed.Program, full_name: []const u8) ?typed.Record {
    for (program.records) |record| if (std.mem.eql(u8, record.name, full_name)) return record;
    return null;
}

fn findTypedAlias(program: typed.Program, full_name: []const u8) ?typed.TypeAlias {
    for (program.aliases) |alias| if (std.mem.eql(u8, alias.name, full_name)) return alias;
    return null;
}

fn findAstConstraint(syntax: ast.Program, span: source.Span) ?ast.Constraint {
    for (syntax.types.constraints) |constraint| if (sameSpan(constraint.name, span)) return constraint;
    return null;
}

const AstType = union(enum) {
    record: ast.Record,
    variant: ast.Variants,
    domain: ast.Domain,
    resource: ast.Domain,
    alias: ast.TypeAlias,
};

fn findAstType(unit: interface.Unit, span: source.Span) ?AstType {
    for (unit.syntax.types.records) |record| if (sameSpan(record.name, span)) return .{ .record = record };
    for (unit.syntax.types.variants) |variant| if (sameSpan(variant.name, span)) return .{ .variant = variant };
    for (unit.syntax.types.domains) |domain| if (sameSpan(domain.name, span)) return .{ .domain = domain };
    for (unit.syntax.types.resources) |resource| if (sameSpan(resource.name, span)) return .{ .resource = resource };
    for (unit.syntax.types.expressions.aliases) |alias| if (sameSpan(alias.name, span)) return .{ .alias = alias };
    return null;
}

fn astTypeCategory(declaration: AstType) []const u8 {
    return switch (declaration) {
        .record => "record",
        .variant => |variant| if (variant.fallible) "result" else if (variant.is_union) "tagged_union" else "enumeration",
        .domain => "domain",
        .resource => "resource",
        .alias => "alias",
    };
}

fn astTypeIsTemplate(declaration: AstType) bool {
    return switch (declaration) {
        .record => |record| record.type_parameters.len != 0,
        .variant => |variant| variant.type_parameters.len != 0,
        .domain => |domain| domain.type_parameters.len != 0,
        .resource => |resource| resource.type_parameters.len != 0,
        .alias => false,
    };
}

fn astTypeSpan(declaration: AstType) source.Span {
    return switch (declaration) {
        .record => |record| .{ .start = record.name.start, .end = @max(record.name.end, @max(typeParametersEnd(record.type_parameters), fieldsEnd(record.fields))) },
        .variant => |variant| .{ .start = variant.name.start, .end = @max(variant.name.end, @max(typeParametersEnd(variant.type_parameters), casesEnd(variant.cases))) },
        .domain => |domain| .{ .start = domain.name.start, .end = @max(domain.name.end, @max(typeParametersEnd(domain.type_parameters), @max(domain.backing.end, codecEnd(domain.codec)))) },
        .resource => |resource| .{ .start = resource.name.start, .end = resource.backing.end },
        .alias => |alias| aliasSpan(alias),
    };
}

fn aliasSpan(alias: ast.TypeAlias) source.Span {
    return .{ .start = alias.name.start, .end = alias.target.end };
}

fn baseFunctionSpan(syntax: ast.Program, function: ast.Function) source.Span {
    var start = function.name.start;
    // Attributes are part of the declaration header: adding, removing or editing
    // one changes the interface fingerprint through this span.
    for (ast.attributesOf(syntax, function.name)) |attribute| start = @min(start, attribute.span.start);
    var end = @max(function.name.end, typeParametersEnd(function.signature.type_parameters));
    end = @max(end, function.signature.return_type.end);
    for (function.signature.parameters) |parameter| {
        end = @max(end, @max(parameter.name.end, parameter.ty.end));
        // A default value is part of the callable contract: two declarations with
        // different defaults accept the same calls with different behavior.
        if (parameter.default_value) |value| end = @max(end, syntax.nodes.items[@backingInt(value)].span.end);
    }
    if (function.policy.effect_bound) |bound| end = @max(end, bound.span.end);
    return .{ .start = start, .end = end };
}

/// The declaration region hashed into the public interface. For a nonempty
/// `mutates(...)` clause this extends the header span through the closing
/// parenthesis; the normalizer replaces those tokens with the contract's sorted
/// parameter positions, so `mutates()`/omitted remain the same and binder
/// spelling or argument order cannot leak into the fingerprint.
fn functionSpan(scratch: std.mem.Allocator, src: source.Source, syntax: ast.Program, function: ast.Function) Error!source.Span {
    var span = baseFunctionSpan(syntax, function);
    if (try mutatesClauseSpan(scratch, src, syntax, function)) |clause| span.end = @max(span.end, clause.end);
    return span;
}

fn mutatesClauseSpan(scratch: std.mem.Allocator, src: source.Source, syntax: ast.Program, function: ast.Function) Error!?source.Span {
    if (function.signature.mutates.len == 0) return null;
    const bound = function.policy.effect_bound orelse return null;
    var limit = src.bytes.len;
    const body_span = syntax.statements.items[@backingInt(function.body)].span;
    if (body_span.start >= bound.span.end and body_span.start <= src.bytes.len) limit = body_span.start;
    if (bound.span.end > limit or limit > src.bytes.len) return error.InternalError;
    var sink: diagnostic.Sink = .{ .allocator = scratch };
    const tokens = lexer.lexRangeWithMarkers(scratch, src.bytes, .{ .start = bound.span.end, .end = limit }, src.mutation_markers, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InternalError,
    };
    var index: usize = 0;
    while (tokens[index].tag != .eof) : (index += 1) {
        if (tokens[index].tag != .ident) continue;
        if (!std.mem.eql(u8, src.bytes[tokens[index].span.start..tokens[index].span.end], "mutates")) continue;
        if (index + 1 >= tokens.len or tokens[index + 1].tag != .lparen) continue;
        var depth: usize = 0;
        var close = index + 1;
        while (close < tokens.len) : (close += 1) {
            switch (tokens[close].tag) {
                .lparen => depth += 1,
                .rparen => {
                    depth -|= 1;
                    if (depth == 0) return .{ .start = tokens[index].span.start, .end = tokens[close].span.end };
                },
                else => {},
            }
        }
        return error.InternalError;
    }
    return error.InternalError;
}

fn typeParametersEnd(parameters: []const ast.TypeParameter) usize {
    var end: usize = 0;
    for (parameters) |parameter| {
        end = @max(end, parameter.name.end);
        for (parameter.requirements) |span| end = @max(end, span.end);
        for (parameter.named_requirements) |reference| {
            if (reference.alias) |alias| end = @max(end, alias.end);
            end = @max(end, reference.name.end);
        }
        for (parameter.field_requirements) |field| end = @max(end, @max(field.name.end, field.ty.end));
        for (parameter.operation_requirements) |operation| {
            end = @max(end, operation.name.end);
            for (operation.parameters) |input| end = @max(end, @max(input.name.end, input.ty.end));
            end = @max(end, operation.return_type.end);
            end = @max(end, operation.effect_bound.span.end);
        }
    }
    return end;
}

fn fieldsEnd(fields: []const ast.Parameter) usize {
    var end: usize = 0;
    for (fields) |field| end = @max(end, @max(field.name.end, field.ty.end));
    return end;
}

fn casesEnd(cases: []const ast.Variant) usize {
    var end: usize = 0;
    for (cases) |case| {
        end = @max(end, case.name.end);
        if (case.payload) |payload| end = @max(end, payload.end);
    }
    return end;
}

fn codecEnd(codec: ?ast.Codec) usize {
    const value = codec orelse return 0;
    return @max(value.decode.end, value.encode.end);
}

fn specializationBaseName(name: []const u8) []const u8 {
    const bracket = std.mem.indexOfScalar(u8, name, '[') orelse return name;
    return name[0..bracket];
}

fn sameSpan(a: source.Span, b: source.Span) bool {
    return a.start == b.start and a.end == b.end;
}

fn writerWrite(writer: *std.Io.Writer, bytes: []const u8) Error!void {
    writer.writeAll(bytes) catch return error.OutOfMemory;
}

fn writerPrint(writer: *std.Io.Writer, comptime format: []const u8, args: anytype) Error!void {
    writer.print(format, args) catch return error.OutOfMemory;
}

fn hashFields(allocator: std.mem.Allocator, domain: []const u8, fields: []const []const u8) Error![]const u8 {
    return ids.hashFields(allocator, domain, fields) catch error.OutOfMemory;
}

fn freeModule(allocator: std.mem.Allocator, module: Module) void {
    allocator.free(module.name);
    allocator.free(module.identity);
    for (module.declarations) |declaration| freeDeclaration(allocator, declaration);
    allocator.free(module.declarations);
}

fn freeDeclaration(allocator: std.mem.Allocator, declaration: Declaration) void {
    allocator.free(declaration.name);
    allocator.free(declaration.kind);
    allocator.free(declaration.identity);
    if (declaration.body_sha256) |hash| allocator.free(hash);
    if (declaration.interface_sha256) |hash| allocator.free(hash);
    if (declaration.interface_identity) |identity| allocator.free(identity);
}

fn freeNominal(allocator: std.mem.Allocator, item: Nominal) void {
    allocator.free(item.name);
    allocator.free(item.kind);
    allocator.free(item.identity);
    if (item.interface_sha256) |hash| allocator.free(hash);
}

fn freeSpecialization(allocator: std.mem.Allocator, item: Specialization) void {
    allocator.free(item.name);
    allocator.free(item.identity);
    allocator.free(item.key_sha256);
}

fn freeFragment(allocator: std.mem.Allocator, item: Fragment) void {
    allocator.free(item.name);
    allocator.free(item.symbol_identity);
    allocator.free(item.kind);
    allocator.free(item.sha256);
    allocator.free(item.identity);
}

/// Deep-copy the scratch report into the caller allocator so `deinit` owns
/// every returned string. Partial copies are released on allocation failure.
fn materialize(allocator: std.mem.Allocator, src: Report) Error!Report {
    const version = allocator.dupe(u8, src.version) catch return error.OutOfMemory;
    errdefer allocator.free(version);
    const project_interface = allocator.dupe(u8, src.project_interface_sha256) catch return error.OutOfMemory;
    errdefer allocator.free(project_interface);
    const modules = allocator.alloc(Module, src.modules.len) catch return error.OutOfMemory;
    var module_count: usize = 0;
    errdefer {
        for (modules[0..module_count]) |module| freeModule(allocator, module);
        allocator.free(modules);
    }
    for (src.modules, 0..) |module, index| {
        modules[index] = try dupModule(allocator, module);
        module_count = index + 1;
    }
    const types = allocator.alloc(Nominal, src.types.len) catch return error.OutOfMemory;
    var type_count: usize = 0;
    errdefer {
        for (types[0..type_count]) |item| freeNominal(allocator, item);
        allocator.free(types);
    }
    for (src.types, 0..) |item, index| {
        types[index] = try dupNominal(allocator, item);
        type_count = index + 1;
    }
    const specializations = allocator.alloc(Specialization, src.specializations.len) catch return error.OutOfMemory;
    var specialization_count: usize = 0;
    errdefer {
        for (specializations[0..specialization_count]) |item| freeSpecialization(allocator, item);
        allocator.free(specializations);
    }
    for (src.specializations, 0..) |item, index| {
        specializations[index] = try dupSpecialization(allocator, item);
        specialization_count = index + 1;
    }
    const fragments = allocator.alloc(Fragment, src.fragments.len) catch return error.OutOfMemory;
    var fragment_count: usize = 0;
    errdefer {
        for (fragments[0..fragment_count]) |item| freeFragment(allocator, item);
        allocator.free(fragments);
    }
    for (src.fragments, 0..) |item, index| {
        fragments[index] = try dupFragment(allocator, item);
        fragment_count = index + 1;
    }
    return .{
        .version = version,
        .complete = src.complete,
        .project_interface_sha256 = project_interface,
        .modules = modules,
        .types = types,
        .specializations = specializations,
        .fragments = fragments,
    };
}

fn dupModule(allocator: std.mem.Allocator, module: Module) Error!Module {
    const name = allocator.dupe(u8, module.name) catch return error.OutOfMemory;
    errdefer allocator.free(name);
    const identity = allocator.dupe(u8, module.identity) catch return error.OutOfMemory;
    errdefer allocator.free(identity);
    const declarations = allocator.alloc(Declaration, module.declarations.len) catch return error.OutOfMemory;
    var count: usize = 0;
    errdefer {
        for (declarations[0..count]) |declaration| freeDeclaration(allocator, declaration);
        allocator.free(declarations);
    }
    for (module.declarations, 0..) |declaration, index| {
        declarations[index] = try dupDeclaration(allocator, declaration);
        count = index + 1;
    }
    return .{ .name = name, .identity = identity, .declarations = declarations };
}

fn dupDeclaration(allocator: std.mem.Allocator, declaration: Declaration) Error!Declaration {
    const name = allocator.dupe(u8, declaration.name) catch return error.OutOfMemory;
    errdefer allocator.free(name);
    const kind = allocator.dupe(u8, declaration.kind) catch return error.OutOfMemory;
    errdefer allocator.free(kind);
    const identity = allocator.dupe(u8, declaration.identity) catch return error.OutOfMemory;
    errdefer allocator.free(identity);
    const body = if (declaration.body_sha256) |hash| allocator.dupe(u8, hash) catch return error.OutOfMemory else null;
    errdefer if (body) |hash| allocator.free(hash);
    const iface = if (declaration.interface_sha256) |hash| allocator.dupe(u8, hash) catch return error.OutOfMemory else null;
    errdefer if (iface) |hash| allocator.free(hash);
    const item = if (declaration.interface_identity) |value| allocator.dupe(u8, value) catch return error.OutOfMemory else null;
    errdefer if (item) |value| allocator.free(value);
    return .{ .name = name, .kind = kind, .identity = identity, .body_sha256 = body, .interface_sha256 = iface, .interface_identity = item };
}

fn dupNominal(allocator: std.mem.Allocator, item: Nominal) Error!Nominal {
    const name = allocator.dupe(u8, item.name) catch return error.OutOfMemory;
    errdefer allocator.free(name);
    const kind = allocator.dupe(u8, item.kind) catch return error.OutOfMemory;
    errdefer allocator.free(kind);
    const identity = allocator.dupe(u8, item.identity) catch return error.OutOfMemory;
    errdefer allocator.free(identity);
    const iface = if (item.interface_sha256) |hash| allocator.dupe(u8, hash) catch return error.OutOfMemory else null;
    errdefer if (iface) |hash| allocator.free(hash);
    return .{ .name = name, .kind = kind, .identity = identity, .interface_sha256 = iface };
}

fn dupSpecialization(allocator: std.mem.Allocator, item: Specialization) Error!Specialization {
    const name = allocator.dupe(u8, item.name) catch return error.OutOfMemory;
    errdefer allocator.free(name);
    const identity = allocator.dupe(u8, item.identity) catch return error.OutOfMemory;
    errdefer allocator.free(identity);
    const key = allocator.dupe(u8, item.key_sha256) catch return error.OutOfMemory;
    errdefer allocator.free(key);
    return .{ .name = name, .identity = identity, .key_sha256 = key };
}

fn dupFragment(allocator: std.mem.Allocator, item: Fragment) Error!Fragment {
    const name = allocator.dupe(u8, item.name) catch return error.OutOfMemory;
    errdefer allocator.free(name);
    const symbol = allocator.dupe(u8, item.symbol_identity) catch return error.OutOfMemory;
    errdefer allocator.free(symbol);
    const kind = allocator.dupe(u8, item.kind) catch return error.OutOfMemory;
    errdefer allocator.free(kind);
    const sha = allocator.dupe(u8, item.sha256) catch return error.OutOfMemory;
    errdefer allocator.free(sha);
    const identity = allocator.dupe(u8, item.identity) catch return error.OutOfMemory;
    errdefer allocator.free(identity);
    return .{ .name = name, .symbol_identity = symbol, .kind = kind, .sha256 = sha, .identity = identity };
}
