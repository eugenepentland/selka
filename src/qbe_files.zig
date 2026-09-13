//! QBE lowering of the Python file surface. Whole-path helpers and open-handle
//! methods go through the native resource providers, so the native backend
//! reports the same `Result` error text and the same located `R_FILE` traps as
//! `src/file_resources.zig`. An open handle is one owned resource word, so the
//! ordinary local drop closes it at every scope exit.
const bytecode = @import("bytecode.zig");
const operations = @import("file_operations.zig");
const typed = @import("typed.zig");
/// Failures reported while emitting native file instructions.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const FileAccess = @FieldType(@FieldType(bytecode.Instruction, "op"), "file_access");
const FileMethod = @FieldType(@FieldType(bytecode.Instruction, "op"), "file_method");
const results = @import("qbe_results.zig");
const file_failure = "myl_qbe_fail_file";
const load_scratch = " %v{d} =l loadl %scratch\n";

/// Pack one operation ordinal, `open` mode letter and payload choice into the
/// request word the native helpers decode.
fn request(kind: usize, mode: u8, text: bool) u32 {
    return @intCast(kind | (@as(usize, mode) << 8) | (@as(usize, @intFromBool(text)) << 16));
}

/// Bind file lowering to the concrete emitter without an import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Lower one whole-path file helper against a `Filesystem` capability.
        pub fn access(self: *E, call: FileAccess, stack: []const typed.Type) Error!void {
            const base = stack.len - call.operands;
            const authority = try self.load("s", base);
            const path = try self.load("s", base + 1);
            const input = self.temp();
            if (call.operands > 2) try self.print(" %v{d} =l loadl %s{d}\n", .{ input, base + 2 }) else try self.print(" %v{d} =l copy 0\n", .{input});
            const status = self.temp();
            const word = request(@backingInt(call.kind), call.mode, call.text);
            try self.print(" %v{d} =w call $myl_qbe_file_access(l %ctx, l %v{d}, w {d}, l %v{d}, l %v{d}, l %scratch)\n", .{ status, authority, word, path, input });
            try self.checkFailure("failure");
            const value = self.temp();
            try self.print(load_scratch, .{value});
            if (call.kind == .exists) return self.store(base, value);
            if (typed.resultShape(call.output, self.program.records) == null) {
                // A `with open(...)` head declares the handle type directly and traps.
                const ok = self.temp();
                try self.print(" %v{d} =w ceqw %v{d}, 0\n", .{ ok, status });
                try self.require(ok, file_failure);
                return self.store(base, value);
            }
            return results.Lower(E).payload(self, .{ .ty = call.output, .status = status, .value = value, .slot = base });
        }
        /// Lower one method on an open handle held in a `with` binding.
        pub fn method(self: *E, call: FileMethod, stack: []const typed.Type) Error!void {
            const base = stack.len - @intFromBool(call.argument);
            const owner = try self.load("l", @backingInt(call.owner));
            var count = self.temp();
            var input = self.temp();
            try self.print(" %v{d} =l copy -1\n %v{d} =l copy 0\n", .{ count, input });
            if (call.argument) {
                if (call.kind == .read) count = try self.load("s", base) else input = try self.load("s", base);
            }
            const status = self.temp();
            const word = request(@backingInt(call.kind), 0, call.text);
            try self.print(" %v{d} =w call $myl_qbe_file_method(l %ctx, l %v{d}, w {d}, l %v{d}, l %v{d}, l %scratch)\n", .{ status, owner, word, count, input });
            try self.checkFailure("failure");
            const value = self.temp();
            try self.print(load_scratch, .{value});
            // A completed handle must not be closed again by the scope's own drop.
            if (call.kind == .close) try self.print(" storel 0, %l{d}\n", .{@backingInt(call.owner)});
            try self.store(base, value);
        }
    };
}

comptime {
    // These ordinals are the versioned C helper protocol, not native enum layout.
    const access_names = .{ "open", "read_file", "read_text", "write_file", "write_text", "exists", "listdir", "mkdir", "remove" };
    for (access_names, 0..) |name, index| if (@backingInt(@field(operations.Access, name)) != index) @compileError("QBE file access ABI changed");
    const method_names = .{ "read", "readline", "readlines", "write", "flush", "close" };
    for (method_names, 0..) |name, index| if (@backingInt(@field(operations.Method, name)) != index) @compileError("QBE file method ABI changed");
}
