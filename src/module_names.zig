//! Semantic name adapter: mapped source spans retain their declaring module.
const std = @import("std");
const source = @import("source.zig");
const interfaces = @import("interfaces.zig");
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
pub const Names = struct {
    index: *interfaces.Index,
    src: source.Source,
    fn allocator(self: Names) std.mem.Allocator {
        return self.index.project.arena.allocator();
    }
    pub fn declaration(self: Names, span: source.Span) diagnostic.Error![]const u8 {
        const original = self.src.originalSpan(span) catch unreachable;
        return std.fmt.allocPrint(self.allocator(), "{s}::{s}", .{ self.index.project.modules.items[original.input].name, self.src.text(span) });
    }
    pub fn functionDeclaration(self: Names, owner: ?source.Span, name: source.Span) diagnostic.Error![]const u8 {
        if (owner) |domain| return std.fmt.allocPrint(self.allocator(), "{s}.{s}", .{ try self.declaration(domain), self.src.text(name) });
        return self.declaration(name);
    }
    pub fn reference(self: Names, span: source.Span, kind: interfaces.Kind, member: ?source.Span, current_owner: ?[]const u8, sink: *diagnostic.Sink) diagnostic.Error![]const u8 {
        const original = self.src.originalSpan(span) catch unreachable;
        const text = self.src.text(span);
        var tokens_sink: diagnostic.Sink = .{ .allocator = self.allocator() };
        const tokens = try lexer.lex(self.allocator(), text, &tokens_sink);
        const alias = if (tokens.len == 5) text[tokens[0].span.start..tokens[0].span.end] else null;
        const last = if (alias != null) tokens[3] else tokens[0];
        const bare = text[last.span.start..last.span.end];
        const name = if (member) |method| try std.fmt.allocPrint(self.allocator(), "{s}.{s}", .{ bare, self.src.text(method) }) else bare;
        const id = self.index.resolve(original.input, alias, name, kind, current_owner, original.span) catch |err| {
            if (err == error.OutOfMemory) return err;
            const problem = self.index.project.problem.?;
            const at = self.src.mappedSpan(problem.site.module, problem.site.span) catch unreachable;
            if (problem.related) |related| return sink.failRelated(problem.code, at, problem.message, .{ .span = self.src.mappedSpan(related.module, related.span) catch unreachable, .message = "declaration is here" });
            return sink.fail(problem.code, at, problem.message);
        };
        return std.fmt.allocPrint(self.allocator(), "{s}::{s}", .{ self.index.project.modules.items[id.module].name, self.index.units[id.module].symbols.items[id.symbol].name });
    }
    pub fn topLevel(self: Names, span: source.Span) bool {
        const original = self.src.originalSpan(span) catch unreachable;
        const name = self.src.text(span);
        if (self.index.units[original.input].names.contains(name)) return true;
        for (self.index.project.modules.items[original.input].imports) |imported| if (std.mem.eql(u8, name, imported.alias)) return true;
        return false;
    }
};
