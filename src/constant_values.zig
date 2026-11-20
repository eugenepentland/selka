//! Literal-only managed constants and bounded scalar evaluation with checked dependencies.
const call_arguments = @import("call_arguments.zig");
const std = @import("std");
const compile_mode = @import("builtin").mode;
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Names = @import("module_names.zig").Names;
const Error = diagnostic.Error;
const integers = @import("integers.zig");
const integer_literal = @import("integer_literal.zig");
const embed = @import("embed.zig");
const floats = @import("floats.zig");
const float_intrinsics = @import("float_intrinsics.zig");
const float_syntax = @import("float_syntax.zig");
const number_literal = @import("number_literal.zig");
const numeric_surface = @import("numeric_surface.zig");
const byte_constants = @import("byte_constants.zig");
const standard_library = @import("standard_library.zig");
const eLimit = "E_CONSTANT_LIMIT";
const eType = "E_CONSTANT_TYPE";
const eEffect = "E_CONSTANT_EFFECT";
const eExpression = "E_CONSTANT_EXPRESSION";
const eName = "E_CONSTANT_NAME";
const Call = @FieldType(@FieldType(ast.Node, "data"), "call");
const Assignment = @FieldType(@FieldType(ast.Statement, "data"), "assignment");
const Range = @FieldType(@FieldType(ast.Statement, "data"), "for_range");
/// Source context for immutable declarations; no guest authority is available.
pub const Context = struct {
    src: source.Source,
    program: ast.Program,
    names: ?*Names,
    sink: *diagnostic.Sink,
    catalog: ?@import("type_catalog.zig").Catalog = null,
    fn resolveType(self: Context, span: source.Span) Error!typed.Type {
        if (self.catalog) |catalog| return catalog.resolve(self.src, span, self.sink);
        return typed.Type.fromName(self.src.text(span)) orelse self.sink.fail(eType, span, "constant type requires a known scalar type");
    }
    /// Resolve a visible constant or leave an ordinary local/function name unchanged.
    pub fn lookup(self: Context, name: source.Span) Error!?usize {
        var any_constants = false;
        for (self.program.functions) |function| if (function.policy.constant) {
            any_constants = true;
            break;
        };
        if (!any_constants) return null;
        const target = if (self.names) |names| resolved: {
            if (!try names.topLevel(name) and std.mem.indexOf(u8, self.src.text(name), "::") == null) return null;
            break :resolved try names.reference(name, .function, null, null, self.sink);
        } else self.src.text(name);
        if (self.names) |names| return names.constantIndex(self.program.functions, target);
        for (self.program.functions, 0..) |function, index| {
            if (!function.policy.constant) continue;
            if (std.mem.eql(u8, self.src.text(function.name), target)) return index;
        }
        return null;
    }
    /// The declared type of the constant at `index`, resolved without evaluating it.
    pub fn declaredType(self: Context, index: usize) Error!typed.Type {
        return self.resolveType(self.program.functions[index].signature.return_type);
    }
    /// The embed a constant's initializer is (`EMBED-1`), or null for any other expression.
    pub fn embedKind(self: Context, node: ast.Node) ?embed.Kind {
        if (node.data != .call or node.data.call.owner != null) return null;
        return embed.kindOf(self.src.text(node.data.call.name));
    }
    /// The initializer expression of the constant at `index`: the value its getter returns.
    pub fn initializerNode(self: Context, index: usize) ast.NodeId {
        const function = self.program.functions[index];
        const body = self.program.statements.items[@backingInt(function.body)].data.block[0];
        return self.program.statements.items[@backingInt(body)].data.ret;
    }
    /// Validate a str/bytes literal getter, leaving scalar declarations to evaluation.
    pub fn literalType(self: Context, index: usize) Error!?typed.Type {
        const function = self.program.functions[index];
        const ty = try self.resolveType(function.signature.return_type);
        const catalog = self.catalog orelse return null;
        if (!ty.isAggregate()) return null;
        const kind = catalog.records[ty.recordIndex()].collection.kind;
        if (kind != .string and kind != .bytes) return null;
        const initializer = self.initializerNode(index);
        const node = self.program.nodes.items[@backingInt(initializer)];
        if (self.embedKind(node)) |embedded| {
            // The checker reads the file itself; here only the declared type must agree.
            if ((kind == .string) != (embedded == .str))
                return self.sink.fail("E_TYPE", node.span, "constant embed type differs from its declared str or bytes type");
            return ty;
        }
        if (node.data == .binary or node.data == .name) {
            // A join of literals and constants (F-54): folding it once here refuses what it may not hold.
            const folded = try self.foldedText(index) orelse return error.InternalError;
            self.sink.allocator.free(folded);
            return ty;
        }
        // A bytes constant may be a call of the source function that builds its octets; `foldedText` runs it.
        if (node.data == .call and kind == .bytes) return ty;
        if (node.data != .text and node.data != .bytes) return self.sink.fail(eExpression, node.span, text_constant_forms);
        if ((kind == .string) != (node.data == .text))
            return self.sink.fail("E_TYPE", node.span, "constant literal type differs from its declared str or bytes type");
        return ty;
    }
    /// The octets a `str` or `bytes` constant holds when its initializer joins literals and other constants of its
    /// type with `+` (F-54), folded when the program is checked; null for a literal or an embed, which are read as
    /// written. The caller owns the slice (`sink.allocator`).
    pub fn foldedText(self: Context, index: usize) Error!?[]const u8 {
        const node = self.program.nodes.items[@backingInt(self.initializerNode(index))];
        const declared = try self.resolveType(self.program.functions[index].signature.return_type);
        if (node.data == .call) return if (self.isText(declared) or self.embedKind(node) != null) null else try self.tableOctets(index);
        if (node.data != .binary and node.data != .name) return null;
        var folder: TextFolder = .{ .context = self, .declared = declared, .text = self.isText(declared) };
        defer folder.chain.deinit(self.sink.allocator);
        // `toOwnedSlice` empties the list, so this frees only what a refused fold left behind.
        defer folder.out.deinit(self.sink.allocator);
        try folder.declaration(index);
        const octets = try folder.out.toOwnedSlice(self.sink.allocator);
        return octets;
    }
    fn isText(self: Context, ty: typed.Type) bool {
        const catalog = self.catalog orelse return false;
        return ty.isAggregate() and catalog.records[ty.recordIndex()].collection.kind == .string;
    }
    /// The octets a `bytes` constant holds when its initializer is a call of a source function that builds them
    /// (`docs/source-evaluation.md`, "Constants that are tables"), run while the program is checked. The caller owns the
    /// slice (`sink.allocator`).
    pub fn tableOctets(self: Context, index: usize) Error![]const u8 {
        const allocator = self.sink.allocator;
        const values = try allocator.alloc(?typed.Value, self.program.functions.len);
        defer allocator.free(values);
        @memset(values, null);
        const visiting = try allocator.alloc(bool, self.program.functions.len);
        defer allocator.free(visiting);
        @memset(visiting, false);
        var evaluator: Evaluator = .{ .context = self, .values = values, .visiting = visiting, .work_limit = table_work_limit };
        defer evaluator.frame.locals.deinit(allocator);
        defer evaluator.tables.deinit(allocator);
        defer evaluator.buffers.deinit(allocator);
        defer for (evaluator.buffers.items) |*buffer| buffer.deinit(allocator);
        defer if (evaluator.octets) |octets| allocator.free(octets);
        try evaluator.table(index);
        const octets = evaluator.octets.?;
        evaluator.octets = null;
        return octets;
    }
    /// Evaluate one constant including forward references within a bounded dependency graph.
    pub fn evaluate(self: Context, index: usize) Error!typed.Value {
        const allocator = self.sink.allocator;
        const values = try allocator.alloc(?typed.Value, self.program.functions.len);
        defer allocator.free(values);
        @memset(values, null);
        const visiting = try allocator.alloc(bool, self.program.functions.len);
        defer allocator.free(visiting);
        @memset(visiting, false);
        var evaluator: Evaluator = .{ .context = self, .values = values, .visiting = visiting };
        defer evaluator.frame.locals.deinit(allocator);
        defer evaluator.tables.deinit(allocator);
        try evaluator.validateDeclaration(index, 0);
        return evaluator.declaration(index, 0);
    }
};
/// What a `str` or `bytes` constant's initializer may be, said where it is something else (F-54).
const text_constant_forms = "a str or bytes constant is a literal, an embed_str/embed_bytes call, or literals and other " ++
    "constants of its type joined with `+` (`\"#\" + NAME`), or for bytes a call of a source function that builds its octets; " ++
    "other calls, format strings, other operators, indexes and casts are excluded";
/// The most octets one joined constant may hold, and the most operands its fold may visit: the work budget of a scalar
/// constant (`docs/source-evaluation.md`). A literal text becomes one checked node per scalar, so the size is bounded well
/// below what doubling joins could reach.
const text_constant_limit = 1 << 20;
/// What a join over `text_constant_limit` says: the limit, and the way to hold a larger text (`docs/bytes.md`).
const joined_over = "a joined constant holds more than 1 MiB; put text that large in a file and read it with embed_str " ++
    "(embed_bytes for bytes), which has no limit";
const text_constant_work = 1 << 16;
/// The work units one table constant may use (`docs/source-evaluation.md`, "Constants that are tables"): a scalar constant has
/// `scalar_work_limit`, and a `bytes` constant built by a source function has `table_work_limit` for the whole evaluation.
const table_work_limit = 1 << 25;
const scalar_work_limit = 1 << 16;
/// The octets all the byte buffers of one table constant may hold together: four octets for each of the 65,536 values of a
/// 16-bit index.
const table_size_limit = 1 << 18;
/// What a table constant's size over `table_size_limit` says: the limit, and the way to hold more (`docs/bytes.md`).
const table_over = "a table constant builds more than its size limit of 262,144 octets; put data that large in a file and read it with embed_bytes, which has no limit";
/// What a table constant's work over `table_work_limit` says.
const table_work_over = "a table constant's evaluation exceeds its work limit of 33,554,432 units (a scalar constant has 65,536)";
/// What a module constant may be, said where its type is something else.
const constant_types = "a module constant is an integer, `bool`, `float`, `f32`, `str` or `bytes`; a table of numbers is a `bytes` constant, " ++
    "read with `bytes.read_u16_le`, `bytes.read_u32_le` and the other fixed-width reads; lists, records, options and unions are not constants yet " ++
    "(docs/source-evaluation.md, \"Constants that are tables\")";
/// What the function of a table constant may build its octets with.
const table_forms = "a table function builds its octets with `mut table = buffers.empty()`, `_ = buffers.append_byte(mut table, value)` and a final " ++
    "`return bytes(table)`; other forms are excluded (docs/source-evaluation.md, \"Constants that are tables\")";
/// Folds a join of `str` or `bytes` literals and constants into the octets it holds (F-54), following the constants it
/// names through `chain`, which also finds a cycle and names it.
const TextFolder = struct {
    context: Context,
    declared: typed.Type,
    text: bool,
    out: std.ArrayList(u8) = .empty,
    chain: std.ArrayList(usize) = .empty,
    work: usize = 0,
    fn declaration(self: *TextFolder, index: usize) Error!void {
        const context = self.context;
        if (std.mem.indexOfScalar(usize, self.chain.items, index)) |first| return self.cycle(first, index);
        if (self.chain.items.len >= 256) return context.sink.fail(eLimit, context.program.functions[index].name, "constant dependency nesting exceeds 256");
        try self.chain.append(context.sink.allocator, index);
        defer _ = self.chain.pop();
        try self.expression(context.initializerNode(index));
    }
    fn cycle(self: *TextFolder, first: usize, index: usize) Error {
        const context = self.context;
        var names: std.ArrayList(u8) = .empty;
        defer names.deinit(context.sink.allocator);
        for (self.chain.items[first..]) |member| {
            try names.print(context.sink.allocator, "`{s}` -> ", .{context.src.text(context.program.functions[member].name)});
        }
        try names.print(context.sink.allocator, "`{s}`", .{context.src.text(context.program.functions[index].name)});
        const message = if (first + 1 == self.chain.items.len)
            try std.fmt.allocPrint(context.sink.allocator, "`{s}` is built from itself; write it as a literal or join other constants", .{context.src.text(context.program.functions[index].name)})
        else
            try std.fmt.allocPrint(context.sink.allocator, "these constants are built from each other in a cycle: {s}; write one of them as a literal", .{names.items});
        return context.sink.fail("E_CONSTANT_CYCLE", context.program.functions[index].name, message);
    }
    fn expression(self: *TextFolder, id: ast.NodeId) Error!void {
        const context = self.context;
        const node = context.program.nodes.items[@backingInt(id)];
        self.work += 1;
        if (self.work > text_constant_work) return context.sink.fail(eLimit, node.span, "a joined constant names more than 65,536 literals and constants");
        switch (node.data) {
            .text, .bytes => |octets| {
                if (self.text != (node.data == .text)) return context.sink.fail("E_TYPE", node.span, if (self.text)
                    "a str constant joins str literals and str constants; this literal is bytes"
                else
                    "a bytes constant joins bytes literals and bytes constants; this literal is a str");
                try self.out.appendSlice(context.sink.allocator, octets);
                if (self.out.items.len > text_constant_limit) return context.sink.fail(eLimit, node.span, joined_over);
            },
            .binary => |binary| {
                if (binary.op != .add) return context.sink.fail(eExpression, node.span, text_constant_forms);
                try self.expression(binary.left);
                try self.expression(binary.right);
            },
            .name => |name| {
                const index = try context.lookup(name) orelse return context.sink.fail(eName, name, "a str or bytes constant joins only literals and other constants of its type");
                const ty = try context.declaredType(index);
                if (ty != self.declared) {
                    const kind = if (self.text) "str" else "bytes";
                    const message = try std.fmt.allocPrint(context.sink.allocator, "`{s}` is not a {s} constant; a {s} constant joins only literals and constants of its type", .{ context.src.text(name), kind, kind });
                    return context.sink.fail("E_TYPE", name, message);
                }
                if (context.embedKind(context.program.nodes.items[@backingInt(context.initializerNode(index))]) != null) {
                    const message = try std.fmt.allocPrint(context.sink.allocator, "`{s}` reads its file where it is used, so a constant cannot join it; join literals and constants that hold literals", .{context.src.text(name)});
                    return context.sink.fail(eExpression, name, message);
                }
                try self.declaration(index);
            },
            else => return context.sink.fail(eExpression, node.span, text_constant_forms),
        }
    }
};
/// A builtin call a constant initializer may use: a conversion or a float intrinsic.
const Builtin = union(enum) { float, f32, int, intrinsic: typed.UnaryOp };
const Evaluator = struct {
    context: Context,
    values: []?typed.Value,
    visiting: []bool,
    work: usize = 0,
    work_limit: usize = scalar_work_limit,
    /// The byte buffers a table function has made (`buffers.empty()`), each named by a local's `buffer`, and the octets
    /// they hold together; `octets` is the result a `return bytes(table)` took.
    buffers: std.ArrayList(std.ArrayList(u8)) = .empty,
    held: usize = 0,
    octets: ?[]u8 = null,
    /// The answer of `tableFunction` for each call site, by the start of the call's name.
    tables: std.AutoHashMapUnmanaged(usize, ?Table) = .empty,
    frame: struct { locals: std.ArrayList(Local) = .empty, base: usize = 0, result: ?typed.Type = null, bytes: bool = false } = .{},
    /// A local's `buffer` is set for a byte buffer: its index in `buffers` when running, 0 when only validating.
    const Local = struct { name: source.Span, value: ?typed.Value, mutable: bool, buffer: ?usize = null };
    const Flow = union(enum) { next, returned: typed.Value, break_loop, continue_loop };
    /// The `buffers` functions a table function may call.
    const Table = enum { empty, append_byte };
    fn take(self: *Evaluator, span: source.Span, depth: usize) Error!void {
        self.work += 1;
        if (depth >= 256 or self.work > self.work_limit) return self.context.sink.fail(eLimit, span, if (self.work_limit == table_work_limit and depth < 256) table_work_over else "constant evaluation exceeds nesting or work budget");
    }
    fn local(self: *Evaluator, name: source.Span) Error!?usize {
        var index = self.frame.locals.items.len;
        while (index > self.frame.base) {
            index -= 1;
            try self.take(name, 0);
            if (std.mem.eql(u8, self.context.src.text(name), self.context.src.text(self.frame.locals.items[index].name))) return index;
        }
        return null;
    }
    fn bind(self: *Evaluator, name: source.Span, value: ?typed.Value, mutable: bool) Error!void {
        try self.frame.locals.append(self.context.sink.allocator, .{ .name = name, .value = value, .mutable = mutable });
    }
    /// A local that names a byte buffer: `buffer` is its index in `buffers`, or 0 while only validating.
    fn bindBuffer(self: *Evaluator, name: source.Span, buffer: usize, mutable: bool) Error!void {
        try self.frame.locals.append(self.context.sink.allocator, .{ .name = name, .value = null, .mutable = mutable, .buffer = buffer });
    }
    /// Run the function a `bytes` constant calls: validate all of its syntax, then execute it and keep what it returns.
    fn table(self: *Evaluator, index: usize) Error!void {
        const node = self.context.program.nodes.items[@backingInt(self.context.initializerNode(index))];
        if (node.data != .call) return self.context.sink.fail(eExpression, node.span, text_constant_forms);
        try self.validateCall(node.data.call, node.span, 0, true);
        _ = try self.executeCall(node.data.call, node.span, 0, true);
        if (self.octets == null) return self.context.sink.fail("E_CONSTANT_RETURN", node.span, table_forms);
    }
    /// The `buffers` function a call names, when it is one a table function may call: the call resolves to the standard
    /// library's `buffers.empty` or `buffers.append_byte`. A name the program declares itself is an ordinary call.
    fn tableFunction(self: *Evaluator, call: Call) Error!?Table {
        if (call.owner != null or call.type_arguments.len != 0) return null;
        if (self.tables.get(call.name.start)) |known| return known;
        const text = self.context.src.text(call.name);
        const which: Table = if (std.mem.endsWith(u8, text, "append_byte")) .append_byte else if (std.mem.endsWith(u8, text, "empty")) .empty else return null;
        const names = self.context.names orelse return null;
        const target = try names.reference(call.name, .function, null, null, self.context.sink);
        const answer: ?Table = found: {
            if (!std.mem.eql(u8, target, if (which == .empty) "buffers::empty" else "buffers::append_byte")) break :found null;
            for (self.context.program.functions) |function| {
                if (function.policy.owner != null) continue;
                if (!std.mem.eql(u8, try names.functionDeclaration(null, function.name), target)) continue;
                break :found if (self.standardModule(function.name)) which else null;
            }
            break :found null;
        };
        try self.tables.put(self.context.sink.allocator, call.name.start, answer);
        return answer;
    }
    /// Whether the module that declares `name` is the compiler's own standard library: the embedded copy, or a copy read from
    /// source beside the entry (`--local-stdlib`, or `check` of a standard-named file) whose bytes are exactly the embedded
    /// text. A module of the user's own that is called `buffers` has other bytes, so it is an ordinary module.
    fn standardModule(self: *Evaluator, name: source.Span) bool {
        const src = self.context.src;
        if (src.origins.len == 0) return standard_library.trusted(src.path, src.bytes, src.trusted_intrinsics);
        const original = src.originalSpan(name) catch return false;
        const unit = src.origins[original.input].original;
        return standard_library.trusted(unit.path, unit.bytes, unit.trusted_intrinsics);
    }
    /// Whether an initializer is `buffers.empty()`: the one way a table function makes a byte buffer.
    fn bufferCreation(self: *Evaluator, id: ast.NodeId) Error!bool {
        const node = self.context.program.nodes.items[@backingInt(id)];
        if (node.data != .call or !self.frame.bytes) return false;
        if (try self.tableFunction(node.data.call) != .empty) return false;
        if (node.data.call.arguments.len != 0) return self.context.sink.fail(eExpression, node.span, table_forms);
        return true;
    }
    /// The local a `mut table` argument or the `table` of `bytes(table)` names, which must hold a byte buffer.
    fn bufferLocal(self: *Evaluator, id: ast.NodeId, marked: bool) Error!usize {
        const node = self.context.program.nodes.items[@backingInt(id)];
        const inner = if (marked and node.data == .mut_argument) self.context.program.nodes.items[@backingInt(node.data.mut_argument)] else node;
        if (inner.data != .name or (marked and node.data != .mut_argument)) return self.context.sink.fail(eExpression, node.span, table_forms);
        const index = try self.local(inner.data.name) orelse return self.context.sink.fail(eName, inner.data.name, "a table function names only the buffers it made with `buffers.empty()`");
        if (self.frame.locals.items[index].buffer == null) return self.context.sink.fail(eExpression, node.span, table_forms);
        return index;
    }
    /// The `bytes(table)` that ends a table function, as the local holding `table`.
    fn octetsLocal(self: *Evaluator, id: ast.NodeId) Error!usize {
        const node = self.context.program.nodes.items[@backingInt(id)];
        if (node.data == .call) {
            const call = node.data.call;
            const plain = call.owner == null and call.type_arguments.len == 0 and call.argument_names.len == 0 and call.arguments.len == 1;
            if (plain and std.mem.eql(u8, self.context.src.text(call.name), "bytes")) return self.bufferLocal(call.arguments[0], false);
        }
        return self.context.sink.fail(eExpression, node.span, table_forms);
    }
    /// `return bytes(table)` of a table function: the octets of the buffer are the result.
    fn returnOctets(self: *Evaluator, id: ast.NodeId) Error!typed.Value {
        const allocator = self.context.sink.allocator;
        const slot = self.frame.locals.items[try self.octetsLocal(id)].buffer.?;
        const octets = try allocator.dupe(u8, self.buffers.items[slot].items);
        if (self.octets) |earlier| allocator.free(earlier);
        self.octets = octets;
        return .{ .bool = true };
    }
    /// Check one `buffers` call of a table function without running it.
    fn validateTableOperation(self: *Evaluator, which: Table, call: Call, span: source.Span, depth: usize) Error!void {
        if (call.argument_names.len != 0 or which == .empty or call.arguments.len != 2) return self.context.sink.fail(eExpression, span, table_forms);
        _ = try self.bufferLocal(call.arguments[0], true);
        try self.validateExpression(call.arguments[1], depth + 1);
    }
    /// `buffers.append_byte(mut table, value)`: append the octet when it is 0 to 255, and answer whether it did.
    fn tableOperation(self: *Evaluator, which: Table, call: Call, span: source.Span, depth: usize) Error!typed.Value {
        try self.validateTableOperation(which, call, span, depth);
        const slot = self.frame.locals.items[try self.bufferLocal(call.arguments[0], true)].buffer.?;
        const value = try self.expressionAs(call.arguments[1], .i64, depth + 1);
        if (!value.typeOf().isInteger()) return self.context.sink.fail("E_TYPE", span, "a byte appended to a buffer is an integer");
        const octet = integer(value);
        if (octet < 0 or octet > 255) return .{ .bool = false };
        if (self.held >= table_size_limit) return self.context.sink.fail(eLimit, span, table_over);
        self.held += 1;
        try self.buffers.items[slot].append(self.context.sink.allocator, @intCast(octet));
        return .{ .bool = true };
    }
    fn scalar(self: *Evaluator, span: source.Span) Error!typed.Type {
        const ty = try self.context.resolveType(span);
        if (!ty.isInteger() and ty != .bool) return self.context.sink.fail(eType, span, "compile-time function values require scalar integer or bool types");
        return ty;
    }
    /// The type a table function returns must be `bytes`.
    fn requireBytes(self: *Evaluator, span: source.Span) Error!void {
        // The dependency keys run a table before any catalog exists (CONSTSTALE, `semantic_key.constantValue`): there the
        // spelling `bytes` is the type, and any other spelling is refused, so the key stands for the table by its bodies.
        const catalog = self.context.catalog orelse return if (std.mem.eql(u8, self.context.src.text(span), "bytes")) {} else error.InternalError;
        const ty = try self.context.resolveType(span);
        if (!ty.isAggregate() or catalog.records[ty.recordIndex()].collection.kind != .bytes) return self.context.sink.fail(eType, span, "the function of a bytes constant returns bytes");
    }
    /// The function a compile-time call names; `bytes_result` is the one call that builds a table, which returns `bytes`.
    fn callIndex(self: *Evaluator, call: Call, span: source.Span, bytes_result: bool) Error!usize {
        if (call.owner != null or call.type_arguments.len != 0) return self.context.sink.fail(eExpression, span, "compile-time calls require nongeneric free functions");
        const target = if (self.context.names) |names| try names.reference(call.name, .function, null, null, self.context.sink) else self.context.src.text(call.name);
        for (self.context.program.functions, 0..) |function, index| {
            try self.take(span, 0);
            if (function.policy.owner != null) continue;
            const name = if (self.context.names) |names| try names.functionDeclaration(null, function.name) else self.context.src.text(function.name);
            if (!std.mem.eql(u8, name, target)) continue;
            if (function.policy.host != null or function.signature.type_parameters.len != 0)
                return self.context.sink.fail(eEffect, span, "compile-time calls cannot use host functions or generics");
            if (bytes_result and function.policy.builtin) return self.context.sink.fail(eExpression, span, text_constant_forms);
            const bound = try call_arguments.bind(self.context.sink.allocator, self.context.src, self.context.program.nodes.items, call, function.signature, self.context.sink);
            call_arguments.release(self.context.sink.allocator, call, bound);
            if (bytes_result) try self.requireBytes(function.signature.return_type) else _ = try self.scalar(function.signature.return_type);
            for (function.signature.parameters) |parameter| {
                _ = try self.scalar(parameter.ty);
            }
            return index;
        }
        return self.context.sink.fail(eName, call.name, "compile-time call requires a visible source function");
    }
    fn validateCall(self: *Evaluator, call: Call, span: source.Span, depth: usize, bytes_result: bool) Error!void {
        for (call.arguments) |argument| try self.validateExpression(argument, depth + 1);
        const index = try self.callIndex(call, span, bytes_result);
        if (self.visiting[index]) return;
        self.visiting[index] = true;
        defer self.visiting[index] = false;
        const before = self.frame.locals.items.len;
        const base = self.frame.base;
        const outer_bytes = self.frame.bytes;
        self.frame.base = before;
        self.frame.bytes = bytes_result;
        defer {
            self.frame.locals.shrinkRetainingCapacity(before);
            self.frame.base = base;
            self.frame.bytes = outer_bytes;
        }
        const function = self.context.program.functions[index];
        for (function.signature.parameters) |parameter| try self.bind(parameter.name, null, false);
        try ast.ensureBody(self.context.program, function.body);
        try self.validateStatement(function.body, depth + 1);
    }
    fn validateStatement(self: *Evaluator, id: ast.StatementId, depth: usize) Error!void {
        const stmt = self.context.program.statements.items[@backingInt(id)];
        try self.take(stmt.span, depth);
        switch (stmt.data) {
            .ret => |value| if (self.frame.bytes) {
                _ = try self.octetsLocal(value);
            } else try self.validateExpression(value, depth + 1),
            .discard => |value| try self.validateExpression(value, depth + 1),
            .loop_exit => {},
            .block => |children| {
                const before = self.frame.locals.items.len;
                defer self.frame.locals.shrinkRetainingCapacity(before);
                for (children) |child| try self.validateStatement(child, depth + 1);
            },
            .binding => |binding| {
                if (try self.bufferCreation(binding.value)) return self.bindBuffer(binding.name, 0, binding.mutable);
                try self.validateExpression(binding.value, depth + 1);
                if (binding.annotation) |annotation| _ = try self.scalar(annotation);
                try self.bind(binding.name, null, binding.mutable);
            },
            .assignment => |assignment| {
                try self.validateExpression(assignment.value, depth + 1);
                if (assignment.op == .set and try self.local(assignment.name) == null) try self.bind(assignment.name, null, true);
            },
            .branch => |branch| {
                try self.validateExpression(branch.condition, depth + 1);
                try self.validateStatement(branch.then_body, depth + 1);
                if (branch.else_body) |body| try self.validateStatement(body, depth + 1);
            },
            .loop => |loop| {
                try self.validateExpression(loop.condition, depth + 1);
                try self.validateStatement(loop.body, depth + 1);
            },
            .for_range => |range| {
                if (self.context.program.nodes.items[@backingInt(range.start)].data != .unit) try self.validateExpression(range.start, depth + 1);
                try self.validateExpression(range.end, depth + 1);
                if (range.step) |step| try self.validateExpression(step, depth + 1);
                const before = self.frame.locals.items.len;
                defer self.frame.locals.shrinkRetainingCapacity(before);
                try self.bind(range.name, null, true);
                try self.validateStatement(range.body, depth + 1);
            },
            else => return self.context.sink.fail(eEffect, stmt.span, "compile-time function bodies permit scalar locals, branches and loops; runtime memory and effects are excluded"),
        }
    }
    fn executeCall(self: *Evaluator, input: Call, span: source.Span, depth: usize, bytes_result: bool) Error!typed.Value {
        const index = try self.callIndex(input, span, bytes_result);
        const function = self.context.program.functions[index];
        const invocation = try call_arguments.bind(self.context.sink.allocator, self.context.src, self.context.program.nodes.items, input, function.signature, self.context.sink);
        defer call_arguments.release(self.context.sink.allocator, input, invocation);
        const arguments = try self.context.sink.allocator.alloc(typed.Value, invocation.arguments.len);
        defer self.context.sink.allocator.free(arguments);
        for (0..invocation.arguments.len) |source_index| {
            const position = call_arguments.parameterPosition(invocation, source_index);
            const argument = invocation.arguments[position];
            const parameter = function.signature.parameters[position];
            const value = &arguments[position];
            const parameter_type = try self.scalar(parameter.ty);
            value.* = try self.expressionAs(argument, parameter_type, depth + 1);
            if (value.typeOf() != parameter_type) return self.context.sink.fail("E_TYPE", parameter.ty, "compile-time argument type differs from parameter");
        }
        const before = self.frame.locals.items.len;
        const base = self.frame.base;
        const outer_result = self.frame.result;
        const outer_bytes = self.frame.bytes;
        self.frame.base = before;
        self.frame.bytes = bytes_result;
        self.frame.result = if (bytes_result) null else try self.scalar(function.signature.return_type);
        defer {
            self.frame.locals.shrinkRetainingCapacity(before);
            self.frame.base = base;
            self.frame.result = outer_result;
            self.frame.bytes = outer_bytes;
        }
        for (function.signature.parameters, arguments) |parameter, value| try self.bind(parameter.name, value, false);
        try ast.ensureBody(self.context.program, function.body);
        const result = try self.statement(function.body, depth + 1);
        if (result != .returned) return self.context.sink.fail("E_CONSTANT_RETURN", span, if (bytes_result) "a table function must end every path with `return bytes(table)`" else "compile-time function must return a scalar value");
        if (!bytes_result and result.returned.typeOf() != try self.scalar(function.signature.return_type)) return self.context.sink.fail("E_TYPE", function.signature.return_type, "compile-time return type differs from signature");
        return result.returned;
    }
    fn condition(self: *Evaluator, id: ast.NodeId, depth: usize) Error!bool {
        const value = try self.expression(id, depth + 1);
        if (value != .bool) return self.context.sink.fail("E_TYPE", self.context.program.nodes.items[@backingInt(id)].span, "compile-time condition requires bool");
        return value.bool;
    }
    fn statement(self: *Evaluator, id: ast.StatementId, depth: usize) Error!Flow {
        const stmt = self.context.program.statements.items[@backingInt(id)];
        try self.take(stmt.span, depth);
        switch (stmt.data) {
            .ret => |value| {
                if (self.frame.bytes) return .{ .returned = try self.returnOctets(value) };
                return .{ .returned = try self.expressionAs(value, self.frame.result, depth + 1) };
            },
            .discard => |value| {
                _ = try self.expression(value, depth + 1);
            },
            .loop_exit => |is_continue| return if (is_continue) .continue_loop else .break_loop,
            .block => |children| {
                const before = self.frame.locals.items.len;
                defer self.frame.locals.shrinkRetainingCapacity(before);
                for (children) |child| {
                    const flow = try self.statement(child, depth + 1);
                    if (flow != .next) return flow;
                }
            },
            .binding => |binding| {
                if (try self.bufferCreation(binding.value)) {
                    try self.buffers.append(self.context.sink.allocator, .empty);
                    try self.bindBuffer(binding.name, self.buffers.items.len - 1, binding.mutable);
                    return .next;
                }
                const declared: ?typed.Type = if (binding.annotation) |annotation| try self.scalar(annotation) else null;
                if (!binding.initialized) {
                    try self.bind(binding.name, null, binding.mutable);
                    return .next;
                }
                const value = try self.expressionAs(binding.value, declared, depth + 1);
                if (binding.annotation) |annotation| {
                    if (value.typeOf() != declared.?) return self.context.sink.fail("E_TYPE", annotation, "compile-time binding annotation differs from initializer");
                }
                try self.bind(binding.name, value, binding.mutable);
            },
            .assignment => |assignment| try self.assign(assignment, depth + 1),
            .branch => |branch| {
                if (try self.condition(branch.condition, depth + 1)) return self.statement(branch.then_body, depth + 1);
                if (branch.else_body) |body| return self.statement(body, depth + 1);
            },
            .loop => |loop| {
                while (try self.condition(loop.condition, depth + 1)) {
                    const flow = try self.statement(loop.body, depth + 1);
                    if (flow == .returned) return flow;
                    if (flow == .break_loop) break;
                }
            },
            .for_range => |range| return self.rangeLoop(range, depth + 1),
            else => return self.context.sink.fail(eEffect, stmt.span, "unsupported compile-time statement"),
        }
        return .next;
    }
    fn uninitializedType(self: *Evaluator, name: source.Span) Error!typed.Type {
        // The binding lies in the module that holds its name, so only that module's statements are read.
        const found = Evaluator.annotationOf(ast.statementsAt(self.context.program, name.start), name);
        if (compile_mode == .debug and self.context.program.facts.loader == null) std.debug.assert(std.meta.eql(found, Evaluator.annotationOf(self.context.program.statements.items, name)));
        return self.scalar((found orelse return error.InternalError) orelse return error.InternalError);
    }
    /// The annotation of the binding statement of `statements` whose name is `name`: null when none binds it, and its own null when it has
    /// no annotation.
    fn annotationOf(statements: []const ast.Statement, name: source.Span) ??source.Span {
        for (statements) |statement_value| {
            if (statement_value.data != .binding) continue;
            const bound = statement_value.data.binding;
            if (bound.name.start != name.start or bound.name.end != name.end) continue;
            return bound.annotation;
        }
        return null;
    }
    fn assign(self: *Evaluator, assignment: Assignment, depth: usize) Error!void {
        const existing = try self.local(assignment.name);
        if (existing == null and assignment.op == .set) {
            const bound = try self.expression(assignment.value, depth + 1);
            return self.bind(assignment.name, bound, true);
        }
        const index = existing orelse return self.context.sink.fail(eName, assignment.name, "compile-time compound assignment requires an existing local");
        const previous = self.frame.locals.items[index];
        const previous_type = if (previous.value) |value| value.typeOf() else try self.uninitializedType(previous.name);
        if (assignment.op != .set and previous.value == null) return self.context.sink.fail("E_UNBOUND", assignment.name, "compile-time compound assignment reads an uninitialized binding");
        var value = try self.expressionAs(assignment.value, previous_type, depth + 1);
        if (value.typeOf() != previous_type) return self.context.sink.fail("E_TYPE", assignment.op_span, "compile-time assignment types differ");
        if (assignment.op != .set) {
            if (!value.typeOf().isInteger()) return self.context.sink.fail("E_TYPE", assignment.op_span, "compound assignment requires integers");
            value = integers.binary(value.typeOf(), if (assignment.op == .add) .add else .sub, integer(previous.value.?), integer(value)) catch |err| return self.failure(assignment.op_span, err);
        }
        self.frame.locals.items[index].value = value;
    }
    fn rangeLoop(self: *Evaluator, range: Range, depth: usize) Error!Flow {
        var start: typed.Value = if (self.context.program.nodes.items[@backingInt(range.start)].data == .unit) .{ .i64 = 0 } else try self.expression(range.start, depth + 1);
        const end = try self.expression(range.end, depth + 1);
        if (!start.typeOf().isInteger() or start.typeOf() != end.typeOf()) return self.context.sink.fail("E_TYPE", range.name, "compile-time range requires matching integers");
        // PY-RANGE-STEP-1: a stepped range counts in its step's direction and
        // ends where the next value would leave the counter's type.
        const step: i128 = if (range.step) |syntax| integer(try self.expression(syntax, depth + 1)) else 1;
        if (step == 0) return self.context.sink.fail(@import("range_step.zig").zero_code, range.name, @import("range_step.zig").zero_message);
        const before = self.frame.locals.items.len;
        defer self.frame.locals.shrinkRetainingCapacity(before);
        try self.bind(range.name, start, true);
        while (if (step > 0) integer(start) < integer(end) else integer(start) > integer(end)) {
            self.frame.locals.items[before].value = start;
            const flow = try self.statement(range.body, depth + 1);
            if (flow == .returned) return flow;
            if (flow == .break_loop) break;
            start = integers.cast(start.typeOf(), integer(start) + step) catch break;
        }
        return .next;
    }

    fn validateDeclaration(self: *Evaluator, index: usize, depth: usize) Error!void {
        const before = self.frame.locals.items.len;
        const base = self.frame.base;
        self.frame.base = before;
        defer {
            self.frame.locals.shrinkRetainingCapacity(before);
            self.frame.base = base;
        }
        const function = self.context.program.functions[index];
        if (depth >= 256) return self.context.sink.fail(eLimit, function.name, "constant dependency nesting exceeds 256");
        if (self.visiting[index]) return self.context.sink.fail("E_CONSTANT_CYCLE", function.name, "constant initializers must have acyclic dependencies");
        self.visiting[index] = true;
        defer self.visiting[index] = false;
        const declared = try self.context.resolveType(function.signature.return_type);
        if (!self.mayBeConstant(declared)) return self.context.sink.fail(eType, function.signature.return_type, constant_types);
        const body = self.context.program.statements.items[@backingInt(function.body)].data.block[0];
        try self.validateExpression(self.context.program.statements.items[@backingInt(body)].data.ret, depth + 1);
    }
    /// Whether a module constant may have the type: an integer, `bool`, `float`, `f32`, `str` or `bytes`.
    fn mayBeConstant(self: *Evaluator, ty: typed.Type) bool {
        if (ty.isInteger() or ty == .bool) return true;
        return self.isFloat(ty) or self.isTextual(ty);
    }
    /// Whether a type is `str` or `bytes`, which a constant may be though a scalar initializer cannot name one.
    fn isTextual(self: *Evaluator, ty: typed.Type) bool {
        const catalog = self.context.catalog orelse return false;
        if (!ty.isAggregate()) return false;
        const kind = catalog.records[ty.recordIndex()].collection.kind;
        return kind == .string or kind == .bytes;
    }
    fn validateExpression(self: *Evaluator, id: ast.NodeId, depth: usize) Error!void {
        const node = self.context.program.nodes.items[@backingInt(id)];
        try self.take(node.span, depth);
        switch (node.data) {
            .unit, .integer, .boolean => {},
            .call => |invocation| if (try self.foldedByte(id) != null) {
                // `ord("=")`: a one-byte literal, folded where the position needs a value.
            } else if (try self.builtinName(invocation) != null) {
                try self.validateBuiltin(invocation, node.span, depth + 1);
            } else if (try self.tableFunction(invocation)) |which| {
                try self.validateTableOperation(which, invocation, node.span, depth + 1);
            } else try self.validateCall(invocation, node.span, depth + 1, false),
            .index => if (try self.foldedByte(id) == null) return self.context.sink.fail(eExpression, node.span, "an index in a constant must select a byte of a literal: `b\"=\"[0]`"),
            .name => |name| {
                if (try self.local(name)) |slot| {
                    if (self.frame.locals.items[slot].buffer != null) return self.context.sink.fail(eExpression, name, table_forms);
                    return;
                }
                self.work += self.context.program.functions.len;
                try self.take(name, depth);
                const index = try self.context.lookup(name) orelse return self.context.sink.fail(eName, name, "constant initializers may refer only to other constants");
                try self.validateDeclaration(index, depth + 1);
            },
            .unary => |unary| try self.validateExpression(unary.operand, depth + 1),
            .cast => |cast| try self.validateExpression(cast.value, depth + 1),
            .binary => |binary| {
                try self.validateExpression(binary.left, depth + 1);
                try self.validateExpression(binary.right, depth + 1);
            },
            else => return self.context.sink.fail(eExpression, node.span, "constant evaluation permits scalar expressions and source functions; allocation and external effects are excluded"),
        }
    }
    fn declaration(self: *Evaluator, index: usize, depth: usize) Error!typed.Value {
        const before = self.frame.locals.items.len;
        const base = self.frame.base;
        self.frame.base = before;
        defer {
            self.frame.locals.shrinkRetainingCapacity(before);
            self.frame.base = base;
        }
        const function = self.context.program.functions[index];
        if (depth >= 256) return self.context.sink.fail(eLimit, function.name, "constant dependency nesting exceeds 256");
        if (self.values[index]) |value| return value;
        if (self.visiting[index]) return self.context.sink.fail("E_CONSTANT_CYCLE", function.name, "constant initializers must have acyclic dependencies");
        self.visiting[index] = true;
        defer self.visiting[index] = false;
        const result_type = try self.context.resolveType(function.signature.return_type);
        const scalar_type = result_type.isInteger() or result_type == .bool;
        if (!scalar_type and !self.isFloat(result_type)) return self.context.sink.fail(eType, function.signature.return_type, "constant types currently require builtin integers, bool, float or f32");
        const body = self.context.program.statements.items[@backingInt(function.body)].data.block[0];
        const initializer = self.context.program.statements.items[@backingInt(body)].data.ret;
        const value = try self.expressionAs(initializer, result_type, depth + 1);
        if (value.typeOf() != result_type) return self.context.sink.fail("E_TYPE", function.signature.return_type, "constant initializer type differs from its declared type");
        self.values[index] = value;
        return value;
    }
    /// Whether a type is a floating domain, `float` or `f32`.
    fn isFloat(self: *Evaluator, ty: typed.Type) bool {
        const catalog = self.context.catalog orelse return false;
        return numeric_surface.isBinaryFloat(ty, catalog.records);
    }
    /// Whether a type is the binary32 domain.
    fn isF32(self: *Evaluator, ty: typed.Type) bool {
        const catalog = self.context.catalog orelse return false;
        return numeric_surface.isF32(ty, catalog.records);
    }
    /// A floating constant of the domain `ty` (`float` or `f32`) from its bit pattern.
    fn floatValueOf(self: *Evaluator, ty: typed.Type, bits: u64) Error!typed.Value {
        _ = self;
        return .{ .integer = .{ .ty = ty, .value = bits } };
    }
    /// A `float` constant value: the binary64 bit pattern under the float domain's type.
    fn floatValue(self: *Evaluator, bits: u64) Error!typed.Value {
        const catalog = self.context.catalog orelse return error.InternalError;
        return .{ .integer = .{ .ty = catalog.names.get("float") orelse return error.InternalError, .value = bits } };
    }
    /// The bit pattern of a `float` constant value.
    fn bitsOf(value: typed.Value) u64 {
        return @intCast(integer(value));
    }
    /// Whether a numeric literal is a float: spelled as one, or typed by a `float` context.
    fn floatContext(self: *Evaluator, span: source.Span, expected: ?typed.Type) bool {
        if (float_syntax.isLiteral(self.context.src.text(span))) return true;
        return if (expected) |ty| self.isFloat(ty) else false;
    }
    /// A float literal rounds to the nearest binary64 exactly as the checked program's literal does.
    fn floatLiteral(self: *Evaluator, span: source.Span, expected: ?typed.Type) Error!typed.Value {
        const text = self.context.src.text(span);
        const catalog = self.context.catalog orelse return error.InternalError;
        if (float_syntax.isF32Literal(text) or (expected != null and self.isF32(expected.?))) {
            const narrow = switch (try number_literal.floatAs(f32, self.context.sink.allocator, text)) {
                .ok => |value| value,
                .bad => |problem| return self.context.sink.fail(problem.code, span, problem.message),
            };
            if (!std.math.isFinite(narrow)) return self.context.sink.fail("E_FLOAT_RANGE", span, "floating-point literal overflows binary32");
            return self.floatValueOf(catalog.names.get("f32") orelse return error.InternalError, @as(u32, @bitCast(narrow)));
        }
        const magnitude = switch (try number_literal.float(self.context.sink.allocator, text)) {
            .ok => |value| value,
            .bad => |problem| return self.context.sink.fail(problem.code, span, problem.message),
        };
        if (!std.math.isFinite(magnitude)) return self.context.sink.fail("E_FLOAT_RANGE", span, "floating-point literal overflows binary64");
        return self.floatValue(@bitCast(magnitude));
    }
    /// The binary32 bit pattern of a constant of either floating domain, rounded to binary32; an integer
    /// converts, and a `float` is refused beside an `f32` (the repair writes the conversion).
    fn narrowBits(self: *Evaluator, value: typed.Value, span: source.Span) Error!u64 {
        const ty = value.typeOf();
        if (self.isF32(ty)) return bitsOf(value);
        if (self.isFloat(ty)) return self.context.sink.fail(numeric_surface.float_width_code, span, "f32 and float are different types; convert one side explicitly");
        if (!ty.isInteger()) return self.context.sink.fail("E_TYPE", span, "a constant float operation requires numbers");
        const unsigned = ty == .u64;
        const input: u64 = if (unsigned) @intCast(integer(value)) else @bitCast(@as(i64, @intCast(integer(value))));
        return floats.unary32(if (unsigned) .f32_from_u64 else .f32_from_i64, input) catch |err| return self.failure(span, err);
    }
    /// The nearest binary64 value of an integer constant, as `float(n)` and mixed arithmetic convert it.
    fn floatBits(self: *Evaluator, value: typed.Value, span: source.Span) Error!u64 {
        const ty = value.typeOf();
        if (self.isF32(ty)) return floats.unary32(.f64_from_f32, bitsOf(value)) catch |err| return self.failure(span, err);
        if (self.isFloat(ty)) return bitsOf(value);
        if (!ty.isInteger()) return self.context.sink.fail("E_TYPE", span, "a constant float operation requires numbers");
        const unsigned = ty == .u64;
        const input: u64 = if (unsigned) @intCast(integer(value)) else @bitCast(@as(i64, @intCast(integer(value))));
        return floats.unary(if (unsigned) .f64_from_u64 else .f64_from_i64, input) catch |err| return self.failure(span, err);
    }
    fn floatArithmetic(self: *Evaluator, op: typed.BinaryOp, operands: [2]u64, span: source.Span) Error!u64 {
        const result = floats.binary(op, operands[0], operands[1]) catch |err| return self.failure(span, err);
        return @intCast(result.integer.value);
    }
    /// Binary32 arithmetic and comparison over constants: every operation rounds to binary32, as the
    /// running program does, and a `float` operand is refused beside the `f32` one.
    fn narrowBinary(self: *Evaluator, op: ast.BinaryOp, values: [2]typed.Value, span: source.Span) Error!typed.Value {
        const left = try self.narrowBits(values[0], span);
        const right = try self.narrowBits(values[1], span);
        switch (op) {
            .add, .sub, .mul, .div, .python_div, .floor_div, .floor_rem => {
                const arithmetic: typed.BinaryOp = switch (op) {
                    .add => .f32_add,
                    .sub => .f32_sub,
                    .mul => .f32_mul,
                    else => .f32_div,
                };
                var result = (floats.binary32(arithmetic, left, right) catch |err| return self.failure(span, err)).integer.value;
                if (op == .floor_div or op == .floor_rem) result = floats.unary32(.f32_floor, @intCast(result)) catch |err| return self.failure(span, err);
                if (op == .floor_rem) {
                    const product = (floats.binary32(.f32_mul, @intCast(result), right) catch |err| return self.failure(span, err)).integer.value;
                    result = (floats.binary32(.f32_sub, left, @intCast(product)) catch |err| return self.failure(span, err)).integer.value;
                }
                return self.floatValueOf(values[0].typeOf(), @intCast(result));
            },
            .eq, .ne, .lt, .le, .gt, .ge => {
                const swapped = op == .gt or op == .ge;
                const ordered: typed.BinaryOp = switch (op) {
                    .eq, .ne => .f32_eq,
                    .lt, .gt => .f32_lt,
                    else => .f32_le,
                };
                const answer = floats.binary32(ordered, if (swapped) right else left, if (swapped) left else right) catch |err| return self.failure(span, err);
                return .{ .bool = answer.bool != (op == .ne) };
            },
            else => return self.context.sink.fail("E_FLOAT_OPERATION", span, "float supports arithmetic and numeric comparison"),
        }
    }
    /// Binary64 arithmetic and comparison over constants, spelled as the checked program spells
    /// them: an integer beside a float converts first, `/` always divides as floats, and `//` and
    /// `%` floor the quotient.
    fn floatBinary(self: *Evaluator, op: ast.BinaryOp, values: [2]typed.Value, span: source.Span) Error!typed.Value {
        if (self.isF32(values[0].typeOf()) or self.isF32(values[1].typeOf())) return self.narrowBinary(op, values, span);
        const left = try self.floatBits(values[0], span);
        const right = try self.floatBits(values[1], span);
        switch (op) {
            .add, .sub, .mul, .div, .python_div, .floor_div, .floor_rem => {
                const arithmetic: typed.BinaryOp = switch (op) {
                    .add => .f64_add,
                    .sub => .f64_sub,
                    .mul => .f64_mul,
                    else => .f64_div,
                };
                var result = try self.floatArithmetic(arithmetic, .{ left, right }, span);
                if (op == .floor_div or op == .floor_rem) result = floats.unary(.f64_floor, result) catch |err| return self.failure(span, err);
                if (op == .floor_rem) {
                    const product = try self.floatArithmetic(.f64_mul, .{ result, right }, span);
                    result = try self.floatArithmetic(.f64_sub, .{ left, product }, span);
                }
                return self.floatValue(result);
            },
            .eq, .ne, .lt, .le, .gt, .ge => {
                const swapped = op == .gt or op == .ge;
                const ordered: typed.BinaryOp = switch (op) {
                    .eq, .ne => .f64_eq,
                    .lt, .gt => .f64_lt,
                    else => .f64_le,
                };
                const answer = floats.binary(ordered, if (swapped) right else left, if (swapped) left else right) catch |err| return self.failure(span, err);
                return .{ .bool = answer.bool != (op == .ne) };
            },
            else => return self.context.sink.fail("E_FLOAT_OPERATION", span, "float supports arithmetic and numeric comparison"),
        }
    }
    /// A float constant truncated toward zero into an integer type; NaN, an infinity and a value
    /// the type cannot hold are `E_CONSTANT_ARITHMETIC`.
    fn floatToInteger(self: *Evaluator, ty: typed.Type, value: typed.Value, span: source.Span) Error!typed.Value {
        if (!ty.isInteger()) return self.context.sink.fail("E_TYPE", span, "a float constant converts only to an integer type");
        const wide = try self.floatBits(value, span);
        const converted = floats.toInteger(ty, wide) catch |err| return self.failure(span, err);
        return typed.Value.number(ty, converted);
    }
    /// The builtin a call spells when nothing declared claims its name: `float`, `int` or one of
    /// the float intrinsics `sqrt`, `floor`, `ceil`, `trunc` and `abs`.
    fn builtinName(self: *Evaluator, call: Call) Error!?Builtin {
        if (call.owner != null or call.type_arguments.len != 0) return null;
        const name = self.context.src.text(call.name);
        const builtin: Builtin = if (std.mem.eql(u8, name, "float"))
            .float
        else if (std.mem.eql(u8, name, "f32"))
            .f32
        else if (std.mem.eql(u8, name, "int"))
            .int
        else if (float_intrinsics.operation(name)) |op|
            .{ .intrinsic = op }
        else
            return null;
        if (self.context.names) |names| {
            if (try names.topLevel(call.name)) return null;
        } else for (self.context.program.functions) |function| {
            if (std.mem.eql(u8, self.context.src.text(function.name), name)) return null;
        }
        return builtin;
    }
    /// The value of a call: a byte constant (`ord("=")`), a builtin, or a source function.
    fn callValue(self: *Evaluator, id: ast.NodeId, invocation: Call, span: source.Span, depth: usize) Error!typed.Value {
        if (try self.foldedByte(id)) |byte| return typed.Value.number(.i64, byte);
        if (try self.builtinName(invocation)) |builtin| return self.builtinCall(builtin, invocation, span, depth + 1);
        if (try self.tableFunction(invocation)) |which| return self.tableOperation(which, invocation, span, depth + 1);
        return self.executeCall(invocation, span, depth + 1, false);
    }
    /// The value of a node no other arm evaluates: a byte constant (`b"="[0]`), else the expression is refused.
    fn otherValue(self: *Evaluator, id: ast.NodeId, node: ast.Node) Error!typed.Value {
        if (node.data != .index) return self.context.sink.fail(eExpression, node.span, "constant evaluation permits scalar expressions and source functions; allocation and external effects are excluded");
        if (try self.foldedByte(id)) |byte| return typed.Value.number(.i64, byte);
        return self.context.sink.fail(eExpression, node.span, "an index in a constant must select a byte of a literal: `b\"=\"[0]`");
    }
    /// The byte `ord("=")` or `b"="[0]` spells, unless a declaration claims the name `ord`.
    fn foldedByte(self: *Evaluator, id: ast.NodeId) Error!?u8 {
        const node = self.context.program.nodes.items[@backingInt(id)];
        const byte = byte_constants.fold(self.context.src, self.context.program.nodes.items, id) orelse return null;
        if (node.data != .call) return byte;
        if (self.context.names) |names| {
            if (try names.topLevel(node.data.call.name)) return null;
        } else for (self.context.program.functions) |function| {
            if (std.mem.eql(u8, self.context.src.text(function.name), "ord")) return null;
        }
        return byte;
    }
    fn validateBuiltin(self: *Evaluator, call: Call, span: source.Span, depth: usize) Error!void {
        if (call.arguments.len != 1 or call.argument_names.len != 0) return self.context.sink.fail(eExpression, span, "float, int, sqrt, floor, ceil, trunc and abs take one positional argument in a constant");
        try self.validateExpression(call.arguments[0], depth + 1);
    }
    fn builtinCall(self: *Evaluator, builtin: Builtin, call: Call, span: source.Span, depth: usize) Error!typed.Value {
        try self.validateBuiltin(call, span, depth);
        const argument = try self.expression(call.arguments[0], depth + 1);
        const is_float = self.isFloat(argument.typeOf());
        switch (builtin) {
            .float => return self.floatValue(try self.floatBits(argument, span)),
            .f32 => return self.floatValueOf(self.context.catalog.?.names.get("f32") orelse return error.InternalError, try self.narrowBits(argument, span)),
            .int => {
                if (is_float) return self.floatToInteger(.i64, argument, span);
                if (!argument.typeOf().isInteger()) return self.context.sink.fail("E_TYPE", span, "numeric conversion requires an integer or float");
                return integers.cast(.i64, integer(argument)) catch |err| return self.failure(span, err);
            },
            .intrinsic => |op| {
                if (!is_float) return self.context.sink.fail("E_TYPE", span, "this prelude operation requires a float argument");
                if (self.isF32(argument.typeOf())) return self.floatValueOf(argument.typeOf(), floats.unary32(narrowOp(op), bitsOf(argument)) catch |err| return self.failure(span, err));
                return self.floatValue(floats.unary(op, bitsOf(argument)) catch |err| return self.failure(span, err));
            },
        }
    }
    fn failure(self: *Evaluator, span: source.Span, err: integers.Error) Error {
        return self.context.sink.fail("E_CONSTANT_ARITHMETIC", span, switch (err) {
            error.Overflow => "constant arithmetic overflows its integer type",
            error.DivisionByZero => "constant arithmetic divides by zero",
            error.FloatConversion => "constant floating conversion is outside the integer range",
            error.InvalidShift => "constant shift count is outside its integer width",
            error.InternalError => "constant operation requires matching scalar operand types",
        });
    }
    fn expression(self: *Evaluator, id: ast.NodeId, depth: usize) Error!typed.Value {
        return self.expressionAs(id, null, depth);
    }
    /// Whether the node is an unsuffixed integer literal, possibly negated: the one
    /// expression whose type comes from its context rather than from its spelling.
    fn adoptsType(self: *Evaluator, id: ast.NodeId) bool {
        var node = self.context.program.nodes.items[@backingInt(id)];
        if (node.data == .unary and node.data.unary.op == .neg) node = self.context.program.nodes.items[@backingInt(node.data.unary.operand)];
        if (node.data != .integer) return false;
        const text = self.context.src.text(node.data.integer);
        return float_syntax.isLiteral(text) or integer_literal.unsuffixed(text);
    }
    /// Evaluate with an expected integer type, so an unsuffixed literal (and the operands
    /// of arithmetic around one) takes the declared type, as it does in checked code.
    /// The type an unsuffixed literal beside `sibling` takes: an integer or `f32` sibling's own, else the inherited one.
    fn siblingType(self: *Evaluator, sibling: typed.Value, inherited: ?typed.Type) ?typed.Type {
        return if (sibling.typeOf().isInteger() or self.isF32(sibling.typeOf())) sibling.typeOf() else inherited;
    }
    fn expressionAs(self: *Evaluator, id: ast.NodeId, expected: ?typed.Type, depth: usize) Error!typed.Value {
        const node = self.context.program.nodes.items[@backingInt(id)];
        try self.take(node.span, depth);
        switch (node.data) {
            .integer => |span| {
                if (self.floatContext(span, expected)) return self.floatLiteral(span, expected);
                const literal = try integer_literal.parseExpected(self.context.src, span, false, expected, self.context.sink);
                return typed.Value.number(literal.ty, literal.value);
            },
            .boolean => |value| return .{ .bool = value },
            .call => |invocation| return self.callValue(id, invocation, node.span, depth),
            .name => |name| {
                if (try self.local(name)) |index| return self.frame.locals.items[index].value orelse self.context.sink.fail("E_UNBOUND", name, "compile-time expression reads an uninitialized binding");
                self.work += self.context.program.functions.len;
                try self.take(name, depth);
                const index = try self.context.lookup(name) orelse return self.context.sink.fail(eName, name, "constant initializers may refer only to other constants");
                return self.declaration(index, depth + 1);
            },
            .cast => |cast| {
                const ty = try self.context.resolveType(cast.ty);
                const value = try self.expression(cast.value, depth + 1);
                if (self.isFloat(value.typeOf())) return self.floatToInteger(ty, value, node.span);
                if (!value.typeOf().isInteger()) return self.context.sink.fail("E_TYPE", node.span, "constant cast requires an integer or float");
                return integers.cast(ty, integer(value)) catch |err| return self.failure(node.span, err);
            },
            .unary => |unary| {
                if (unary.op == .is_none) return self.context.sink.fail("E_OPTION_TEST", node.span, "is None requires an Option value");
                const operand = self.context.program.nodes.items[@backingInt(unary.operand)];
                if (unary.op == .neg and operand.data == .integer and !self.floatContext(operand.data.integer, expected)) {
                    const literal = try integer_literal.parseExpected(self.context.src, operand.data.integer, true, expected, self.context.sink);
                    return integers.cast(literal.ty, -literal.value) catch |err| return self.failure(node.span, err);
                }
                const value = try self.expressionAs(unary.operand, if (unary.op == .neg) expected else null, depth + 1);
                if (self.isFloat(value.typeOf()) and (unary.op == .neg or float_intrinsics.floatwise(unary.op))) {
                    const float_op: typed.UnaryOp = if (unary.op == .neg) .f64_neg else std.meta.stringToEnum(typed.UnaryOp, @tagName(unary.op)).?;
                    if (self.isF32(value.typeOf())) {
                        const narrow = floats.unary32(if (unary.op == .neg) .f32_neg else narrowOp(float_op), bitsOf(value)) catch |err| return self.failure(node.span, err);
                        return self.floatValueOf(value.typeOf(), narrow);
                    }
                    const converted = floats.unary(float_op, bitsOf(value)) catch |err| return self.failure(node.span, err);
                    return self.floatValue(converted);
                }
                if (unary.op == .bit_not) {
                    if (!value.typeOf().isInteger()) return self.context.sink.fail("E_TYPE", node.span, "bit_not requires an integer");
                    return integers.bitNot(value.typeOf(), integer(value)) catch |err| return self.failure(node.span, err);
                }
                if (unary.op != .neg and unary.op != .not) {
                    if (value.typeOf() != .u64) return self.context.sink.fail("E_TYPE", node.span, "floating representation requires u64");
                    const converted = floats.unary(std.meta.stringToEnum(typed.UnaryOp, @tagName(unary.op)).?, @intCast(integer(value))) catch |err| return self.failure(node.span, err);
                    return typed.Value.number(.u64, converted);
                }
                if (unary.op == .not and value.typeOf() == .bool) return .{ .bool = !value.bool };
                if (unary.op == .neg and value.typeOf().isInteger()) return integers.cast(value.typeOf(), -integer(value)) catch |err| return self.failure(node.span, err);
                return self.context.sink.fail("E_TYPE", node.span, "invalid constant unary operand");
            },
            .binary => |binary| {
                if (binary.chained) return .{ .bool = (try self.chain(id, depth + 1)).holds };
                const inherited = if (typesResult(binary.op)) expected else null;
                // A literal operand takes its sibling's type, so the typed side goes first.
                const literal_first = self.adoptsType(binary.left) and !self.adoptsType(binary.right);
                var left: typed.Value = undefined;
                var right: typed.Value = undefined;
                if (literal_first) {
                    right = try self.expressionAs(binary.right, inherited, depth + 1);
                    left = try self.expressionAs(binary.left, self.siblingType(right, inherited), depth + 1);
                } else {
                    left = try self.expressionAs(binary.left, inherited, depth + 1);
                    if (left.typeOf() == .bool) {
                        if (binary.op == .logical_and and !left.bool) return left;
                        if (binary.op == .logical_or and left.bool) return left;
                    }
                    right = try self.expressionAs(binary.right, self.siblingType(left, inherited), depth + 1);
                }
                return self.binaryValues(node, left, right);
            },
            else => return self.otherValue(id, node),
        }
    }
    /// PY-CHAIN-1: one link of a comparison chain and the operand to its right,
    /// which the next link compares again without evaluating it twice. A false
    /// link leaves every later operand unevaluated.
    fn chain(self: *Evaluator, id: ast.NodeId, depth: usize) Error!struct { holds: bool, last: typed.Value } {
        const node = self.context.program.nodes.items[@backingInt(id)];
        const binary = node.data.binary;
        var left: typed.Value = undefined;
        var right: typed.Value = undefined;
        if (binary.chained) {
            const earlier = try self.chain(binary.left, depth + 1);
            if (!earlier.holds) return earlier;
            left = earlier.last;
            right = try self.expressionAs(binary.right, self.siblingType(left, null), depth + 1);
        } else if (self.adoptsType(binary.left) and !self.adoptsType(binary.right)) {
            // A literal operand takes its sibling's type, as an unchained comparison's does.
            right = try self.expressionAs(binary.right, null, depth + 1);
            left = try self.expressionAs(binary.left, self.siblingType(right, null), depth + 1);
        } else {
            left = try self.expression(binary.left, depth + 1);
            right = try self.expressionAs(binary.right, self.siblingType(left, null), depth + 1);
        }
        const holds = try self.binaryValues(node, left, right);
        return .{ .holds = holds.bool, .last = right };
    }
    /// Apply one binary operator to two evaluated constant operands.
    fn binaryValues(self: *Evaluator, node: ast.Node, left: typed.Value, right: typed.Value) Error!typed.Value {
        const binary = node.data.binary;
        if (binary.op == .python_div or self.isFloat(left.typeOf()) or self.isFloat(right.typeOf())) return self.floatBinary(binary.op, .{ left, right }, node.span);
        if (left.typeOf() != right.typeOf()) return self.context.sink.fail("E_TYPE", node.span, "constant binary operands must have the same type");
        if (left.typeOf() == .bool) return switch (binary.op) {
            .logical_and => .{ .bool = left.bool and right.bool },
            .logical_or => .{ .bool = left.bool or right.bool },
            .eq => .{ .bool = left.bool == right.bool },
            .ne => .{ .bool = left.bool != right.bool },
            else => self.context.sink.fail("E_TYPE", node.span, "invalid constant boolean operation"),
        };
        return integers.binary(left.typeOf(), std.meta.stringToEnum(typed.BinaryOp, @tagName(binary.op)).?, integer(left), integer(right)) catch |err| return self.failure(node.span, err);
    }
};
/// Whether a binary operator's result has its operands' type, so the expected type
/// flows into them; comparisons and logical operators produce `bool` instead.
fn typesResult(op: ast.BinaryOp) bool {
    return switch (op) {
        .eq, .ne, .lt, .le, .gt, .ge, .logical_and, .logical_or => false,
        else => true,
    };
}
/// The type a literal takes from its already evaluated sibling operand, or the
/// inherited expectation when that operand is not an integer.
/// The binary32 spelling of a binary64 unary operation, for an `f32` constant.
fn narrowOp(op: typed.UnaryOp) typed.UnaryOp {
    return switch (op) {
        .f64_sqrt => .f32_sqrt,
        .f64_floor => .f32_floor,
        .f64_ceil => .f32_ceil,
        .f64_trunc => .f32_trunc,
        .f64_abs => .f32_abs,
        .f64_neg => .f32_neg,
        else => op,
    };
}
fn integer(value: typed.Value) i128 {
    return if (value == .i64) value.i64 else value.integer.value;
}
