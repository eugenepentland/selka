//! Docstring examples as reachability evidence (FR-415): a project declaration
//! an example names is used, and the example itself is a test of what it calls.
//! The reading is syntactic: it lexes the prompt lines the transcript grammar
//! already validated, then resolves each identifier against the project's own
//! declarations (its module first, then its imports), and closes the result over
//! the resolved call graph so an example's indirect callees count too.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const grammar = @import("docstring_examples.zig");
const interfaces = @import("interfaces.zig");
const lexer = @import("lexer.zig");
const quality = @import("quality.zig");
const typed = @import("typed.zig");

/// One project declaration an example may name, by owning module and function.
const Decl = struct { module: usize, function: usize };

/// The two readings an example supplies: the declarations it names directly,
/// and everything those reach through the call graph.
pub const Evidence = struct { direct: []bool, reached: []bool };

/// Mark every function a docstring example names, and separately everything the
/// named declarations reach through the resolved call graph.
pub fn used(
    memory: std.mem.Allocator,
    index: *interfaces.Index,
    program: typed.Program,
    functions: []const quality.Function,
) std.mem.Allocator.Error!Evidence {
    const flags = try memory.alloc(bool, program.functions.len);
    @memset(flags, false);
    var exact: std.StringHashMapUnmanaged(usize) = .empty;
    for (program.functions, 0..) |function, id| try exact.put(memory, function.name, id);
    var declarations: std.ArrayList(Decl) = .empty;
    var by_name: std.StringHashMapUnmanaged(std.ArrayList(usize)) = .empty;
    for (index.project.order.items) |module| {
        if (exempt(index, module)) continue;
        const unit = index.units[module];
        for (unit.symbols.items) |symbol| {
            if (symbol.kind != .function or symbol.re_export != null or symbol.owner != null) continue;
            const qualified = try std.fmt.allocPrint(memory, "{s}::{s}", .{ index.project.modules.items[module].name, symbol.name });
            const id = exact.get(qualified) orelse continue;
            const position = declarations.items.len;
            try declarations.append(memory, .{ .module = module, .function = id });
            const entry = try by_name.getOrPut(memory, symbol.name);
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            try entry.value_ptr.append(memory, position);
        }
    }
    const evidence: Scan = .{
        .memory = memory,
        .index = index,
        .by_name = &by_name,
        .declarations = declarations.items,
        .flags = flags,
    };
    for (index.project.order.items) |module| {
        if (exempt(index, module)) continue;
        const unit = index.units[module];
        for (unit.syntax.functions) |function| {
            const doc = ast.docstringOf(unit.syntax, function.name) orelse continue;
            if (grammar.count(doc.text) == 0) continue;
            const examples = try grammar.parse(memory, doc.text, 1);
            for (examples) |example| {
                var text: std.ArrayList(u8) = .empty;
                for (example.lines) |line| {
                    try text.appendSlice(memory, line.text);
                    try text.append(memory, '\n');
                }
                try evidence.mark(module, text.items);
            }
        }
    }
    const reached = try memory.dupe(bool, flags);
    try close(memory, functions, reached);
    return .{ .direct = flags, .reached = reached };
}

/// The standard library is the compiler's own code, never a project declaration.
fn exempt(index: *interfaces.Index, module: usize) bool {
    return std.mem.startsWith(u8, index.project.modules.items[module].src.path, "@stdlib/");
}

/// One run's lookup tables, shared by every example scan.
const Scan = struct {
    memory: std.mem.Allocator,
    index: *interfaces.Index,
    by_name: *const std.StringHashMapUnmanaged(std.ArrayList(usize)),
    declarations: []const Decl,
    flags: []bool,

    /// Mark the declarations one example's identifiers name. A name is its own
    /// module's declaration first, then an imported module's, then any project
    /// declaration with that spelling; a same-module hit is never widened.
    fn mark(self: Scan, module: usize, bytes: []const u8) std.mem.Allocator.Error!void {
        var sink: diagnostic.Sink = .{ .allocator = self.memory };
        const tokens = lexer.lex(self.memory, bytes, &sink) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return;
        };
        var imported: std.AutoHashMapUnmanaged(usize, void) = .empty;
        for (self.index.project.modules.items[module].imports) |edge| try imported.put(self.memory, edge.target, {});
        for (tokens) |token| {
            if (token.tag != .ident) continue;
            const name = bytes[token.span.start..token.span.end];
            const positions = self.by_name.get(name) orelse continue;
            var local = false;
            for (positions.items) |position| {
                if (self.declarations[position].module != module) continue;
                self.flags[self.declarations[position].function] = true;
                local = true;
            }
            if (local) continue;
            var through_import = false;
            for (positions.items) |position| {
                if (!imported.contains(self.declarations[position].module)) continue;
                self.flags[self.declarations[position].function] = true;
                through_import = true;
            }
            if (through_import) continue;
            for (positions.items) |position| self.flags[self.declarations[position].function] = true;
        }
    }
};

/// Everything an example reaches through the resolved call graph runs too.
fn close(memory: std.mem.Allocator, functions: []const quality.Function, flags: []bool) std.mem.Allocator.Error!void {
    var pending: std.ArrayList(usize) = .empty;
    for (flags, 0..) |marked, id| if (marked) try pending.append(memory, id);
    while (pending.pop()) |id| {
        if (id >= functions.len) continue;
        for (functions[id].calls) |call| {
            const target = @backingInt(call.callee);
            if (target >= flags.len or flags[target]) continue;
            flags[target] = true;
            try pending.append(memory, target);
        }
    }
}
