//! The new core's view of the existing front end (decision N3): load one entry
//! file and its imports, check them, and hand back the checked `typed.Program`
//! with the merged source its spans index. Nothing below the checker (bytecode,
//! QBE, the native build driver) is reached from here.
const std = @import("std");
const language = @import("mylang");

/// The checked program and the merged source its spans point into.
pub const Checked = struct {
    program: language.typed.Program,
    src: language.source.Source,
};

/// Why a load stopped: diagnostics were already rendered into `report`.
pub const Error = error{ SourceError, OutOfMemory, InternalError };

/// Owns the project arena every checked node lives in; keep it alive while the
/// IR builder reads the program, and release it with `deinit`.
pub const Session = struct {
    project: language.project.Project,
    index: language.interfaces.Index = undefined,
    compilation: language.project_compile.Compilation = undefined,
    files: language.project_files.Files,
    /// A file with no `module` header is checked alone, as `mylang build` does.
    single: ?language.Compilation = null,

    /// Prepare to load the module graph rooted at `root` (the entry file's directory).
    pub fn init(allocator: std.mem.Allocator, io: std.Io, root: []const u8) Session {
        return .{ .project = language.project.Project.init(allocator), .files = .{ .io = io, .root = root } };
    }

    /// Release the project arena and everything checked from it.
    pub fn deinit(self: *Session) void {
        if (self.single) |*unit| unit.deinit();
        self.project.deinit();
    }

    /// Check `path` alone when it opens without a `module` header, else as the
    /// entry of its module graph (`check`).
    pub fn checkFile(self: *Session, allocator: std.mem.Allocator, path: []const u8, report: *std.ArrayList(u8)) (Error || error{ReadFailed})!Checked {
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.files.io, path, allocator, .limited(64 << 20)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try report.print(allocator, "error: cannot read {s}: {s}\n", .{ path, @errorName(err) });
                return error.ReadFailed;
            },
        };
        if (language.opensAsModule(bytes)) return self.check(allocator, entryOf(path).module, report);
        self.single = try language.Compilation.init(self.project.arena.child_allocator, std.fs.path.basename(path), bytes);
        const unit = &self.single.?;
        unit.check() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                for (unit.diagnostics.items) |item| {
                    const text = try item.render(allocator, unit.src);
                    defer allocator.free(text);
                    try report.appendSlice(allocator, text);
                }
                return error.SourceError;
            },
        };
        return .{ .program = unit.program.?, .src = unit.src };
    }

    /// Load `entry` (a module name: the file stem) and check it. On a source error
    /// the rendered diagnostics are appended to `report` and `SourceError` returns.
    pub fn check(self: *Session, allocator: std.mem.Allocator, entry: []const u8, report: *std.ArrayList(u8)) Error!Checked {
        self.project.load(self.files.provider(), entry, .{}) catch |err| return self.loadFailure(allocator, err, report);
        self.index = language.interfaces.build(&self.project) catch |err| return self.loadFailure(allocator, err, report);
        self.compilation = language.project_compile.Compilation.init(&self.index) catch |err| return self.loadFailure(allocator, err, report);
        self.compilation.check() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                for (self.compilation.diagnostics.items.items) |item| {
                    const text = try item.render(allocator, self.compilation.src);
                    defer allocator.free(text);
                    try report.appendSlice(allocator, text);
                }
                return error.SourceError;
            },
        };
        return .{ .program = self.compilation.program.?, .src = self.compilation.src };
    }

    fn loadFailure(self: *Session, allocator: std.mem.Allocator, err: anyerror, report: *std.ArrayList(u8)) Error {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        if (self.project.problem != null) {
            const text = self.project.renderProblem(allocator) catch return error.OutOfMemory;
            defer allocator.free(text);
            try report.appendSlice(allocator, text);
        } else {
            try report.print(allocator, "error: cannot load the program: {s}\n", .{@errorName(err)});
        }
        return error.SourceError;
    }
};

/// Split a path such as `dir/prog.my` into the loader's root directory and
/// module name (`dir`, `prog`).
pub fn entryOf(path: []const u8) struct { root: []const u8, module: []const u8 } {
    const root = std.fs.path.dirname(path) orelse ".";
    const base = std.fs.path.basename(path);
    const module = if (std.mem.endsWith(u8, base, ".my")) base[0 .. base.len - 3] else base;
    return .{ .root = root, .module = module };
}

/// The 1-based line and column of byte `offset` in the merged source, mapped
/// back to the file it came from.
pub const Position = struct { path: []const u8, line: u32, column: u32 };

/// Resolve a merged-source span start to the original file, line and column.
pub fn position(src: language.source.Source, span: language.source.Span) Position {
    var file = src;
    var local = span;
    if (src.origins.len != 0) {
        if (src.originalSpan(span)) |found| {
            file = src.origins[found.input].original;
            local = found.span;
        } else |_| {}
    }
    const starts = file.line_starts;
    var low: usize = 0;
    var high: usize = starts.len;
    while (high - low > 1) {
        const middle = (low + high) / 2;
        if (starts[middle] <= local.start) low = middle else high = middle;
    }
    return .{ .path = file.path, .line = @intCast(low + 1), .column = @intCast(local.start - starts[low] + 1) };
}
