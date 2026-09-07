//! Synchronous request-boundary reload: retain one active and one prepared generation.
const std = @import("std");
const print = std.debug.print;
const application = @import("app.zig");
const diagnostics = @import("diagnostics.zig");
const Request = struct {
    action: enum { prepare, commit, discard, quit },
    project: ?[]const u8 = null,
    documents: ?[3][]const u8 = null,
};
const State = struct {
    active: ?*application.App = null,
    candidate: ?*application.App = null,
    fn release(allocator: std.mem.Allocator, slot: *?*application.App) void {
        if (slot.*) |app| {
            app.deinit();
            allocator.destroy(app);
            slot.* = null;
        }
    }
    fn prepare(self: *State, init: std.process.Init, request: Request) ![]u8 {
        release(init.gpa, &self.candidate);
        try validate(request);
        const root = request.project.?;
        const paths = request.documents.?;
        var arena = std.heap.ArenaAllocator.init(init.gpa);
        defer arena.deinit();
        var documents: [3][]const u8 = undefined;
        for (paths, &documents) |path, *out| out.* = try std.Io.Dir.cwd().readFileAlloc(init.io, path, arena.allocator(), .limited(1024 * 1024));
        const app = try init.gpa.create(application.App);
        errdefer init.gpa.destroy(app);
        try app.initDisk(init.gpa, init.io, root);
        errdefer app.deinit();
        const svg = app.run(init.gpa, &documents, .{ .max_steps = 100_000_000 }) catch |err| {
            if (app.issue) |issue| diagnostics.report(issue, &paths, &documents);
            if (app.trap) |trap| {
                const at = app.program.compilation.src.locate(trap.span.start);
                print("{s}:{d}:{d}: {s}: {s}\n", .{ at.path, at.line, at.column, trap.code, trap.message });
            }
            return err;
        };
        self.candidate = app;
        return svg;
    }
};
fn reply(init: std.process.Init, status: []const u8, svg: ?[]const u8, failure: ?[]const u8) !void {
    const bytes = try std.json.Stringify.valueAlloc(init.gpa, .{ .status = status, .svg = svg, .failure = failure }, .{});
    defer init.gpa.free(bytes);
    try std.Io.File.stdout().writeStreamingAll(init.io, bytes);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
/// The coordinator owns immutable input snapshots and chooses whether a prepared generation is current.
pub fn run(init: std.process.Init) (std.Io.Reader.DelimiterError || std.Io.File.Writer.Error || std.mem.Allocator.Error)!void {
    var state: State = .{};
    defer State.release(init.gpa, &state.active);
    defer State.release(init.gpa, &state.candidate);
    var buffer: [16384]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    while (try input.interface.takeDelimiter('\n')) |line| {
        const parsed = std.json.parseFromSlice(Request, init.gpa, line, .{}) catch |err| {
            try reply(init, "error", null, @errorName(err));
            continue;
        };
        defer parsed.deinit();
        switch (parsed.value.action) {
            .quit => return,
            .discard => {
                State.release(init.gpa, &state.candidate);
                try reply(init, "discarded", null, null);
            },
            .commit => {
                if (state.candidate == null) {
                    try reply(init, "error", null, "NoPreparedGeneration");
                    continue;
                }
                State.release(init.gpa, &state.active);
                state.active = state.candidate;
                state.candidate = null;
                try reply(init, "active", null, null);
            },
            .prepare => {
                const svg = state.prepare(init, parsed.value) catch |err| {
                    try reply(init, "error", null, @errorName(err));
                    continue;
                };
                defer init.gpa.free(svg);
                try reply(init, "prepared", svg, null);
            },
        }
    }
}

fn validate(request: Request) error{ MissingProject, MissingDocuments }!void {
    if (request.project == null) return error.MissingProject;
    if (request.documents == null) return error.MissingDocuments;
}
test "prepare validates required snapshot inputs before allocation" {
    try std.testing.expectError(error.MissingProject, validate(.{ .action = .prepare }));
    try std.testing.expectError(error.MissingDocuments, validate(.{ .action = .prepare, .project = "." }));
    try validate(.{ .action = .prepare, .project = ".", .documents = .{ "a", "b", "c" } });
}
