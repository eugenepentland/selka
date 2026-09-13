//! Semantic name adapter: mapped source spans retain their declaring module.
const std = @import("std");
const source = @import("source.zig");
const interfaces = @import("interfaces.zig");
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
/// Module-aware name resolution over mapped source spans and a checked interface index.
pub const Names = struct {
    index: *interfaces.Index,
    src: source.Source,
    fn allocator(self: Names) std.mem.Allocator {
        return self.index.project.arena.allocator();
    }
    /// Allocate the module-qualified identity of a declaration in the project arena.
    pub fn declaration(self: Names, span: source.Span) diagnostic.Error![]const u8 {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        if (original.input >= self.index.units.len or original.input >= self.index.project.modules.items.len) return error.InternalError;
        return std.fmt.allocPrint(self.allocator(), "{s}::{s}", .{ self.index.project.modules.items[original.input].name, self.src.text(span) });
    }
    /// Allocate a qualified free-function or domain-member declaration name.
    pub fn functionDeclaration(self: Names, owner: ?source.Span, name: source.Span) diagnostic.Error![]const u8 {
        if (owner) |domain| return std.fmt.allocPrint(self.allocator(), "{s}.{s}", .{ try self.declaration(domain), self.src.text(name) });
        return self.declaration(name);
    }
    /// Resolve a symbol with module privacy checks and map failures back to source diagnostics.
    pub fn reference(self: Names, span: source.Span, kind: interfaces.Kind, member: ?source.Span, current_owner: ?[]const u8, sink: *diagnostic.Sink) diagnostic.Error![]const u8 {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        if (original.input >= self.index.units.len or original.input >= self.index.project.modules.items.len) return error.InternalError;
        const text = self.src.text(span);
        var tokens_sink: diagnostic.Sink = .{ .allocator = self.allocator() };
        const tokens = try lexer.lex(self.allocator(), text, &tokens_sink);
        const qualified = lexer.qualifiedName(text, tokens) orelse return error.InternalError;
        const bare = qualified.name;
        const name = if (member) |method| try std.fmt.allocPrint(self.allocator(), "{s}.{s}", .{ bare, self.src.text(method) }) else bare;
        const id = self.index.resolve(.{ .from = original.input, .alias = qualified.alias, .name = name, .kind = kind, .owner = current_owner, .span = original.span }) catch |err| {
            if (err != error.SourceError) return err;
            const problem = self.index.project.problem orelse return error.InternalError;
            const at = self.src.mappedSpan(problem.site.module, problem.site.span) catch return error.InternalError;
            if (problem.related) |related| return sink.failRelated(problem.code, at, problem.message, .{ .span = self.src.mappedSpan(related.module, related.span) catch return error.InternalError, .message = "declaration is here" });
            return sink.fail(problem.code, at, problem.message);
        };
        return std.fmt.allocPrint(self.allocator(), "{s}::{s}", .{ self.index.project.modules.items[id.module].name, self.index.units[id.module].symbols.items[id.symbol].name });
    }
    /// Inspect declaration kind before selecting a call or constructor resolver.
    /// The selected resolver still enforces import visibility and privacy.
    pub fn symbolKind(self: Names, span: source.Span) diagnostic.Error!?interfaces.Kind {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        const text = self.src.text(span);
        var sink: diagnostic.Sink = .{ .allocator = self.allocator() };
        const tokens = try lexer.lex(self.allocator(), text, &sink);
        const qualified = lexer.qualifiedName(text, tokens) orelse return null;
        var module = original.input;
        if (qualified.alias) |alias| {
            var found = false;
            for (self.index.project.modules.items[module].imports) |imported| if (std.mem.eql(u8, alias, imported.alias)) {
                module = imported.target;
                found = true;
                break;
            };
            if (!found) return null;
        }
        const unit = self.index.units[module];
        const id = unit.names.get(qualified.name) orelse return null;
        return unit.symbols.items[id].kind;
    }
    /// Check whether a name belongs to the originating module's declarations or import aliases.
    pub fn topLevel(self: Names, span: source.Span) error{InternalError}!bool {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        if (original.input >= self.index.units.len or original.input >= self.index.project.modules.items.len) return error.InternalError;
        const name = self.src.text(span);
        if (self.index.units[original.input].names.contains(name)) return true;
        const prefix = name[0 .. std.mem.indexOfAny(u8, name, " \t\r\n:.") orelse name.len];
        for (self.index.project.modules.items[original.input].imports) |imported| if (std.mem.eql(u8, prefix, imported.alias)) return true;
        return false;
    }
};
