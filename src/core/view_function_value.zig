//! Core owns the refusal of borrowing functions used as owned function values.
//! Source syntax is parsed only after a refusal, to preserve the copying wrapper.
const std = @import("std");
const language = @import("selka");
const ast = language.ast;
const diagnostic = language.diagnostic;
const source = language.source;
const typed = language.typed;

/// Stable code for borrowing function values.
pub const code = "E_VIEW_FUNCTION_VALUE";

/// The same signature predicate used by frontend representation probes.
pub const borrowsResult = language.view_function_value.borrowsResult;

const Parsed = struct { src: source.Source, program: ast.Program, module: Module };

/// Build one Core refusal and its source repair, including imported declarations.
/// Parsing uses a scratch arena; every retained message and edit uses `allocator`.
pub fn diagnosticForUse(allocator: std.mem.Allocator, src: source.Source, records: []const typed.Record, function: typed.Function, use: source.Span) error{OutOfMemory}!diagnostic.Diagnostic {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const module = moduleOf(src, function.declaration) catch return fallback(allocator, src, records, function, use);
    const original = if (src.origins.len == 0) src else src.origins[module.input].original;
    var sink: diagnostic.Sink = .{ .allocator = scratch.allocator() };
    const tokens = language.lexer.lex(scratch.allocator(), original.bytes, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return fallback(allocator, src, records, function, use),
    };
    var parser: language.parser.Parser = .{ .src = original, .storage = scratch.allocator(), .tokens = tokens, .sink = &sink };
    const program = parser.parseModule() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return fallback(allocator, src, records, function, use),
    };
    const name_span: source.Span = .{ .start = function.declaration.start - module.start, .end = function.declaration.end - module.start };
    const declared = astFunction(program, name_span) orelse return fallback(allocator, src, records, function, use);
    const parsed: Parsed = .{ .src = original, .program = program, .module = module };
    const name = simpleName(function.name);
    const words = resultWords(records, function.signature);
    const functype = try functionType(allocator, original, declared);
    const wrapper = try std.fmt.allocPrint(allocator, "{s}_copy", .{name});
    var item = diagnostic.ownership(.{ .code = code, .rule = .V4 }, use, "");
    if (try wrapperFix(allocator, src, parsed, declared, use, wrapper)) |fix| {
        item.message = try std.fmt.allocPrint(allocator, "`{s}` returns {s}, and a `{s}` value must return {s}; pass a function that copies, such as `{s}`", .{ name, words.what, functype, words.owned, wrapper });
        item.provenance.fix = fix;
    } else {
        item.message = try std.fmt.allocPrint(allocator, "`{s}` returns {s}, and a `{s}` value must return {s}; pass a function that copies its result under a name this module does not use", .{ name, words.what, functype, words.owned });
    }
    return item;
}

fn fallback(allocator: std.mem.Allocator, src: source.Source, records: []const typed.Record, function: typed.Function, use: source.Span) error{OutOfMemory}!diagnostic.Diagnostic {
    const name = simpleName(function.name);
    const words = resultWords(records, function.signature);
    const message = try std.fmt.allocPrint(allocator, "`{s}` returns {s}, and a function value must return {s}; pass a function that returns `copy({s}(...))`", .{ name, words.what, words.owned, src.text(use) });
    return diagnostic.ownership(.{ .code = code, .rule = .V4 }, use, message);
}

const ResultWords = struct { what: []const u8, owned: []const u8 };

fn resultWords(records: []const typed.Record, signature: typed.FunctionSignature) ResultWords {
    const kind = language.return_borrow.shape(records, signature).kind;
    return .{
        .what = if (kind == .value) "a borrow of its parameters" else "a view of its parameters",
        .owned = switch (kind) {
            .text => "owned text",
            .bytes => "owned bytes",
            .list => "an owned list",
            else => "owned storage",
        },
    };
}

/// The repair: the copying wrapper inserted in the use's module, and the use
/// renamed to it. Null when the name is taken there or the header is not plain.
fn wrapperFix(allocator: std.mem.Allocator, src: source.Source, parsed: Parsed, declared: ast.Function, use: source.Span, wrapper: []const u8) error{OutOfMemory}!?diagnostic.Fix {
    if (!plainHeader(declared)) return null;
    const use_module = moduleOf(src, use) catch return null;
    if (spelledIn(use_module.bytes, wrapper)) return null;
    const declaration = parsed.module;
    // The declaration's body ends the declaration; an imported function's wrapper
    // goes after the importing module's text instead.
    const insert_at = if (declaration.input == use_module.input)
        parsed.module.start + parsed.program.statements.items[@backingInt(declared.body)].span.end
    else
        use_module.start + use_module.bytes.len;
    // After the declaration the original line break and blank lines follow the
    // wrapper; at the end of a module the wrapper ends the file's last line.
    const trailing: []const u8 = if (declaration.input == use_module.input) "" else "\n";
    const text = try wrapperText(allocator, parsed.src, declared, src.text(use), wrapper, trailing);
    const insert: diagnostic.Edit = .{ .span = .{ .start = insert_at, .end = insert_at }, .text = text };
    const rename: diagnostic.Edit = .{ .span = use, .text = wrapper };
    return .{ .edit = insert, .more = try allocator.dupe(diagnostic.Edit, &.{rename}) };
}

/// The wrapper's declaration and body, set off by one blank line before it.
fn wrapperText(allocator: std.mem.Allocator, src: source.Source, declared: ast.Function, callee: []const u8, wrapper: []const u8, trailing: []const u8) error{OutOfMemory}![]const u8 {
    var parameters: std.ArrayList(u8) = .empty;
    var arguments: std.ArrayList(u8) = .empty;
    for (declared.signature.parameters, 0..) |parameter, index| {
        if (index != 0) {
            try parameters.appendSlice(allocator, ", ");
            try arguments.appendSlice(allocator, ", ");
        }
        try parameters.appendSlice(allocator, src.text(.{ .start = parameter.name.start, .end = parameter.ty.end }));
        try arguments.appendSlice(allocator, src.text(parameter.name));
    }
    return std.fmt.allocPrint(allocator, "\n\nfunc {s}({s}) -> {s}:\n    return copy({s}({s})){s}", .{
        wrapper, parameters.items, src.text(declared.signature.return_type), callee, arguments.items, trailing,
    });
}

/// The `func(...) -> ...` type a function value of this declaration would have.
fn functionType(allocator: std.mem.Allocator, src: source.Source, declared: ast.Function) error{OutOfMemory}![]const u8 {
    var types: std.ArrayList(u8) = .empty;
    for (declared.signature.parameters, 0..) |parameter, index| {
        if (index != 0) try types.appendSlice(allocator, ", ");
        try types.appendSlice(allocator, src.text(parameter.ty));
    }
    return std.fmt.allocPrint(allocator, "func({s}) -> {s}", .{ types.items, src.text(declared.signature.return_type) });
}

/// Whether the wrapper can copy this header: plain positional parameters, with no
/// `mut`, `own`, default or keyword-only marker, and no type parameters or failure.
fn plainHeader(declared: ast.Function) bool {
    if (declared.signature.type_parameters.len != 0 or declared.signature.failure_type != null) return false;
    if (declared.signature.mut_positions.len != 0) return false;
    for (declared.signature.parameters) |parameter| {
        if (parameter.mut or parameter.own or parameter.named or parameter.default_value != null) return false;
    }
    return true;
}

/// Whether `word` is spelled in `text` as a whole identifier. A comment counts,
/// so a name the module mentions anywhere is never taken by the wrapper.
fn spelledIn(text: []const u8, word: []const u8) bool {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, text, from, word)) |at| {
        const end = at + word.len;
        const before_ok = at == 0 or !isIdentifierByte(text[at - 1]);
        const after_ok = end == text.len or !isIdentifierByte(text[end]);
        if (before_ok and after_ok) return true;
        from = at + 1;
    }
    return false;
}

fn isIdentifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

/// The checked declaration of a function, found by its name span.
fn astFunction(program: ast.Program, name: source.Span) ?ast.Function {
    for (program.functions) |declared| {
        if (declared.name.start == name.start and declared.name.end == name.end) return declared;
    }
    return null;
}

/// The declared name of a qualified checked name: `texts::head` is `head`.
fn simpleName(qualified: []const u8) []const u8 {
    if (std.mem.lastIndexOf(u8, qualified, "::")) |at| return qualified[at + 2 ..];
    return qualified;
}

/// The module a merged span belongs to: its input index, its bytes, and the
/// offset those bytes start at in the merged text. A single unmapped source is
/// one module at offset zero.
const Module = struct { input: usize, bytes: []const u8, start: usize };

/// The module of a merged span.
fn moduleOf(src: source.Source, span: source.Span) diagnostic.Error!Module {
    if (src.origins.len == 0) return .{ .input = 0, .bytes = src.bytes, .start = 0 };
    const found = src.originalSpan(span) catch return error.InternalError;
    const origin = src.origins[found.input];
    return .{ .input = found.input, .bytes = origin.original.bytes, .start = origin.start };
}
