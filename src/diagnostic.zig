//! Stable diagnostics are data; only the CLI chooses an output destination.
const std = @import("std");
const source = @import("source.zig");

pub const Severity = enum { err, warning };
pub const Trace = struct { function: []const u8, span: source.Span };
pub const Diagnostic = struct {
    code: []const u8,
    severity: Severity = .err,
    span: source.Span,
    message: []const u8,
    // Bounded by-value guest trace needs no separate cleanup on trap paths.
    trace: [16]Trace = undefined,
    trace_len: usize = 0,
    trace_omitted: usize = 0,

    pub fn render(self: Diagnostic, allocator: std.mem.Allocator, src: source.Source) ![]u8 {
        const loc = src.locate(self.span.start);
        const padding = try allocator.alloc(u8, loc.column - 1);
        defer allocator.free(padding);
        @memset(padding, ' ');
        // Preserve tabs so the caret tracks the source in terminal displays.
        for (loc.text[0..@min(padding.len, loc.text.len)], 0..) |ch, i| {
            if (ch == '\t') padding[i] = '\t';
        }
        const primary = try std.fmt.allocPrint(allocator, "{s}:{d}:{d}: {s}[{s}]: {s}\n  {s}\n  {s}^\n", .{
            src.path,  loc.line,     loc.column, if (self.severity == .err) "error" else "warning",
            self.code, self.message, loc.text,   padding,
        });
        defer allocator.free(primary);
        var output: std.Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();
        output.writer.writeAll(primary) catch return error.OutOfMemory;
        for (self.trace[0..self.trace_len]) |entry| {
            const at = src.locate(entry.span.start);
            output.writer.print("  in {s} at {s}:{d}:{d}\n", .{ entry.function, src.path, at.line, at.column }) catch return error.OutOfMemory;
        }
        if (self.trace_omitted != 0) output.writer.print("  ... {d} older frames omitted\n", .{self.trace_omitted}) catch return error.OutOfMemory;
        return output.toOwnedSlice();
    }
};

pub const Error = std.mem.Allocator.Error || error{SourceError};
pub const Sink = struct {
    items: std.ArrayList(Diagnostic) = .empty,
    allocator: std.mem.Allocator,

    pub fn fail(self: *Sink, code: []const u8, span: source.Span, message: []const u8) Error {
        self.items.append(self.allocator, .{ .code = code, .span = span, .message = message }) catch return error.OutOfMemory;
        return error.SourceError;
    }
};
