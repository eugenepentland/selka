//! Typed retirement repairs for scalar domains and their owned operations.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Names = @import("module_names.zig").Names;
const Span = source.Span;
const Edit = diagnostic.Edit;
const lex = @import("lexer.zig");
const syntax = @import("domain_migration_spans.zig");
const naming = @import("domain_migration_names.zig");
/// Stable removal diagnostic for scalar domains and their operation surface.
pub const removed_code = @import("domain_migration_protocol.zig").removed_code;
/// The fix driver uses this diagnostic to defer shared domain edits atomically.
pub const deferred_message = @import("domain_migration_protocol.zig").deferred_message;
const message = "scalar domains and type-owned operations were removed; use a record with a value field and ordinary functions";

/// Report retired domain forms, deferring repairs until typed facts are available.
pub fn reject(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, names: ?*Names, sink: *diagnostic.Sink, checked: ?*const typed.Program) diagnostic.Error!void {
    if (!hasRetired(program)) return;
    try ast.ensureAll(program);
    var pass: Pass = .{ .allocator = allocator, .src = src, .program = program, .names = names, .sink = sink, .tokens = try lex.lex(allocator, src.bytes, sink), .deferred = checked == null };
    try pass.declarations();
    try pass.expressions();
    try @import("domain_operation_migration.zig").reject(allocator, src, program, names, sink, checked);
    const deferred = for (sink.items.items) |item| {
        if (std.mem.eql(u8, item.code, removed_code) and std.mem.eql(u8, item.message, deferred_message)) break true;
    } else false;
    if (deferred) for (sink.items.items) |*item| {
        if (std.mem.eql(u8, item.code, removed_code)) item.provenance.fix = null;
    };
}

const Pass = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    names: ?*Names,
    sink: *diagnostic.Sink,
    tokens: []const lex.Token,
    deferred: bool,

    fn publish(self: Pass, at: Span, edits: []const Edit) !void {
        // A reused check summary may already carry this retirement diagnostic.
        for (self.sink.items.items) |item| if (std.mem.eql(u8, item.code, removed_code) and std.meta.eql(item.span, at)) return;
        const item: diagnostic.Diagnostic = .{
            .code = removed_code,
            .span = at,
            .message = if (self.deferred or edits.len == 0) deferred_message else message,
            .related = if (!self.deferred and edits.len == 0) .{
                .span = at,
                .message = "no certain automatic repair is available here; rewrite this declaration or operation manually before migrating dependent sites",
            } else null,
        };
        if (self.deferred or edits.len == 0) return self.sink.items.append(self.allocator, item);
        try self.sink.appendFix(item, edits[0]);
        self.sink.items.items[self.sink.items.items.len - 1].provenance.fix.?.more = edits[1..];
    }

    fn declarations(self: Pass) !void {
        for (self.program.types.domains) |domain| {
            var edits: std.ArrayList(Edit) = .empty;
            const start = lineStart(self.src.bytes, domain.name.start);
            const end = lineEnd(self.src.bytes, domain.backing.end);
            const last = domainEnd(self.src.bytes, end);
            const body = self.src.bytes[@min(end + 1, self.src.bytes.len)..last];
            const depth = suiteIndentation(body) orelse {
                try self.publish(domain.name, &.{});
                continue;
            };
            if (std.mem.indexOf(u8, body, "\"\"\"") != null or std.mem.indexOf(u8, body, "'''") != null) {
                try self.publish(domain.name, &.{});
                continue;
            }
            const spaces = try self.allocator.alloc(u8, depth);
            @memset(spaces, ' ');
            const newline = if (end > 0 and self.src.bytes[end - 1] == '\r') "\r\n" else "\n";
            const suffix = std.mem.trimEnd(u8, self.src.bytes[domain.backing.end..end], " \r");
            const comment = if (std.mem.indexOfScalar(u8, suffix, '#')) |hash| suffix[hash..] else "";
            const head = self.src.bytes[start..domain.name.start];
            const public = std.mem.indexOf(u8, head, "public") != null;
            const header = try std.fmt.allocPrint(self.allocator, "{s}record {s}:{s}{s}{s}{s}value: {s}{s}", .{
                if (public) "public " else "",
                self.src.text(domain.name),
                if (comment.len == 0) "" else " ",
                comment,
                newline,
                spaces,
                self.src.text(domain.backing),
                if (newline.len == 2) "\r" else "",
            });
            try edits.append(self.allocator, .{ .span = .{ .start = start, .end = end }, .text = header });
            var line = end + 1;
            var in_codec = false;
            while (line < last) {
                const close = lineEnd(self.src.bytes, line);
                const text = self.src.bytes[line..close];
                const trimmed = std.mem.trimStart(u8, text, " ");
                const line_depth = text.len - trimmed.len;
                if (line_depth == depth and std.mem.startsWith(u8, trimmed, "codec ")) in_codec = true else if (line_depth == depth and trimmed.len != 0 and trimmed[0] != '#') in_codec = false;
                const is_pass = std.mem.startsWith(u8, trimmed, "pass") and (trimmed.len == 4 or trimmed[4] == ' ' or trimmed[4] == '#' or trimmed[4] == '\r');
                if (in_codec or is_pass) {
                    const kept = if (std.mem.indexOfScalar(u8, trimmed, '#')) |hash| try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ std.mem.trimEnd(u8, trimmed[hash..], "\r"), newline }) else "";
                    try edits.append(self.allocator, .{ .span = .{ .start = line, .end = @min(close + 1, self.src.bytes.len) }, .text = kept });
                } else if (line_depth >= depth and trimmed.len != 0) {
                    try edits.append(self.allocator, .{ .span = .{ .start = line, .end = line + depth }, .text = "" });
                }
                line = close + 1;
            }
            for (self.program.functions) |function| {
                const owner = function.policy.owner orelse continue;
                if (!std.meta.eql(owner, domain.name)) continue;
                const renamed = try naming.memberName(self.allocator, self.src, self.program, function);
                if (!std.mem.eql(u8, renamed, self.src.text(function.name))) try edits.append(self.allocator, .{ .span = function.name, .text = renamed });
                const head_start = lineStart(self.src.bytes, function.name.start) + depth;
                const prefix = self.src.bytes[head_start..function.name.start];
                const keyword = std.mem.indexOf(u8, prefix, "func") orelse std.mem.indexOf(u8, prefix, "def") orelse continue;
                try edits.append(self.allocator, .{ .span = .{ .start = head_start, .end = head_start + keyword }, .text = if (public and !function.policy.restricted) "public " else "" });
            }
            try self.publish(domain.name, try edits.toOwnedSlice(self.allocator));
        }
    }

    fn expressions(self: Pass) diagnostic.Error!void {
        for (self.program.nodes.items) |node| switch (node.data) {
            .wrap => |wrap| {
                const keyword = syntax.keyword(self.tokens, node.span, .kw_wrap) orelse continue;
                const open = syntax.callOpen(self.tokens, wrap.ty.end) orelse continue;
                const edits = try self.allocator.dupe(Edit, &.{.{ .span = .{ .start = keyword.start, .end = open.end }, .text = try std.fmt.allocPrint(self.allocator, "{s}(value=", .{self.src.text(wrap.ty)}) }});
                try self.publish(node.span, edits);
            },
            .unwrap => {
                const keyword = syntax.keyword(self.tokens, node.span, .kw_unwrap) orelse
                    syntax.word(self.tokens, self.src.bytes, node.span, "unwrap") orelse continue;
                const close = syntax.callClose(self.tokens, keyword.end) orelse continue;
                const edits = try self.allocator.dupe(Edit, &.{
                    .{ .span = keyword, .text = "" },
                    .{ .span = .{ .start = close + 1, .end = close + 1 }, .text = ".value" },
                });
                try self.publish(node.span, edits);
            },
            .call => |call| {
                const owner = call.owner orelse continue;
                const function = try self.member(owner, call.name) orelse continue;
                const renamed = try naming.memberName(self.allocator, self.src, self.program, function);
                const prefix = self.src.text(owner);
                const qualifier = if (std.mem.lastIndexOfScalar(u8, prefix, '.')) |dot| prefix[0 .. dot + 1] else "";
                try self.publish(node.span, try self.allocator.dupe(Edit, &.{.{ .span = .{ .start = owner.start, .end = call.name.end }, .text = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ qualifier, renamed }) }}));
            },
            else => {},
        };
    }

    fn member(self: Pass, owner: Span, name: Span) diagnostic.Error!?ast.Function {
        if (!try naming.isDomainOwner(self.src, self.program, self.names, owner, self.sink)) return null;
        const identity = if (self.names) |names| names.reference(owner, .function, name, self.src.text(owner), self.sink) catch |err| switch (err) {
            error.SourceError => return null,
            else => return err,
        } else null;
        for (self.program.functions) |function| {
            const declaring = function.policy.owner orelse continue;
            if (!std.mem.eql(u8, self.src.text(function.name), self.src.text(name))) continue;
            if (identity) |resolved| {
                if (!std.mem.eql(u8, resolved, try self.names.?.functionDeclaration(declaring, function.name))) continue;
            } else if (!std.mem.eql(u8, self.src.text(declaring), self.src.text(owner))) continue;
            return function;
        }
        return null;
    }
};

fn lineStart(bytes: []const u8, offset: usize) usize {
    return if (std.mem.lastIndexOfScalar(u8, bytes[0..offset], '\n')) |at| at + 1 else 0;
}
fn lineEnd(bytes: []const u8, offset: usize) usize {
    return std.mem.indexOfScalarPos(u8, bytes, offset, '\n') orelse bytes.len;
}
fn domainEnd(bytes: []const u8, header_end: usize) usize {
    var line = @min(header_end + 1, bytes.len);
    while (line < bytes.len) {
        const end = lineEnd(bytes, line);
        const text = bytes[line..end];
        const trimmed = std.mem.trim(u8, text, " \t\r");
        if (trimmed.len != 0 and trimmed[0] != '#' and text[0] != ' ' and text[0] != '\t') return line;
        line = end + 1;
    }
    return bytes.len;
}

fn suiteIndentation(bytes: []const u8) ?usize {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const text = std.mem.trimStart(u8, line, " ");
        if (text.len == 0 or text[0] == '#' or text[0] == '\r') continue;
        if (text[0] == '\t') return null;
        return if (line.len > text.len) line.len - text.len else null;
    }
    return null;
}

fn hasRetired(program: ast.Program) bool {
    if (program.types.domains.len != 0 or program.types.constraints.len != 0) return true;
    for (program.functions) |function| for (function.signature.type_parameters) |parameter| {
        if (parameter.operation_requirements.len != 0 or parameter.named_requirements.len != 0) return true;
    };
    if (program.facts.retired) |held| return held.wrap;
    for (program.nodes.items) |node| switch (node.data) {
        .wrap, .unwrap => return true,
        else => {},
    };
    return false;
}
