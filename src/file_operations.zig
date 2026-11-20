//! Shared shapes for the Python file surface: whole-path helpers and the
//! methods of an open handle. Representation lives in `file_resources.zig`.
const std = @import("std");

/// Whole-path filesystem helpers; each takes a `Filesystem` capability first.
pub const Access = enum {
    open,
    read_file,
    read_text,
    write_file,
    write_text,
    exists,
    listdir,
    mkdir,
    remove,
    atomic_write_file,
    lock_directory,
    sync_directory,
    read_regular_file,
    list_directory,
    /// `rename_path(fs, from, to)`: move one path onto another inside one filesystem.
    rename_path,
    /// `stat_path(fs, path)`: the packed size, modification time, inode and kind of one path.
    stat_path,
    /// `lock_file(fs, path)`: an exclusive advisory lock on a file, waiting for its holder.
    lock_file,
    /// `try_lock_file(fs, path)`: the same lock, failing at once when it is held.
    try_lock_file,
    /// `canonical_path(fs, path)`: the symbolic-link-free name of a path (absolute without a restriction, relative to the
    /// granted directory with one).
    canonical_path,
    /// `chmod_path(fs, path, mode)`: set the permission bits of a path, whose final component is not followed.
    chmod_path,
    /// `touch_path(fs, path)`: create an empty file or set the modification time of a path to now.
    touch_path,
    /// `set_modified_path(fs, path, nanoseconds)`: set the modification time of a path, whose final component is not
    /// followed.
    set_modified_path,
    /// `atomic_write_file_mode(fs, path, data, mode)`: `atomic_write_file` publishing the file with the given permission
    /// bits (the process umask applies) instead of 0600.
    atomic_write_file_mode,
    /// `stat_follow_path(fs, path)`: `stat_path` that follows a symbolic link at the end of the path.
    stat_follow_path,
    /// `list_entries_path(fs, path)`: every entry of a directory, with its kind from the directory record, as packed
    /// octets (a kind octet, a little-endian u16 name length and the name for each entry).
    list_entries_path,
    /// `replace_file(fs, path, data)`: `atomic_write_file` without the synchronization, the way Zig's `AtomicFile` publishes: a
    /// temporary beside the destination, renamed over it, so a reader sees the old file or the new one, and nothing is
    /// forced to disk.
    replace_file,
    /// `replace_file_mode(fs, path, data, mode)`: `replace_file` publishing the file with the given permission bits.
    replace_file_mode,
    /// `replace_file_synced(fs, path, data)`: `replace_file` that forces the file to disk before the rename and not the
    /// directory after it: a reader sees the old file or the new one, a power loss leaves the old file or the complete new
    /// one, and the rename itself may not have reached the disk.
    replace_file_synced,
    /// `replace_file_synced_mode(fs, path, data, mode)`: `replace_file_synced` publishing the file with the given permission bits.
    replace_file_synced_mode,
    /// `symlink_path(fs, target, path)`: create the symbolic link `path` holding the text `target`, with the grant every other
    /// write has. The target is stored as written (it may be relative, absolute or name nothing) and is not checked.
    symlink_path,
    /// `statfs_path(fs, path)`: the packed size, free and available bytes of the filesystem that holds one path.
    statfs_path,
    /// `read_at_path(fs, path, offset, max_bytes)`: up to `max_bytes` octets of a regular file from byte `offset`, with the
    /// offset packed as eight little-endian octets (a `bytes` operand, as `atomic_write_file_mode` carries its data).
    read_at_path,
    /// `read_link_path(fs, path)`: the text stored in the symbolic link at `path`, as `readlink(2)` answers it. The final
    /// component is not followed, and the path is resolved as `stat_path` resolves it.
    read_link_path,
    /// `link_path(fs, target, path)`: create the hard link `path` to the existing regular file `target` (`link(2)`), a second name
    /// for one file. Each end is resolved on its own as `rename_path` resolves its two, both under a write grant, and a source
    /// that is not a regular file (a directory, a symbolic link) is refused.
    link_path,
    /// `mkdir_mode(fs, path, mode)`: create the directory `path` with the permission bits `mode` (`mkdir(2)`: the process umask
    /// applies), so no other program sees it with the default mode first.
    mkdir_mode,
    /// `create_mode(fs, path, mode)`: open `path` for writing as `open(path, "wb")` does, a new file created with the permission
    /// bits `mode` in the one `open(2)` that makes it (the umask applies, as `creat(2)`'s), an existing one truncated with its
    /// mode kept. It answers a `File`.
    create_mode,
    /// `run_process(proc, request, limit)`: run one program to completion (the first argument is a `Process`, not a
    /// `Filesystem`, and there is no method spelling); the request and the answer are packed octets.
    run_process,
    /// `process_control(proc, data, op)`: the standard library's channel to a scripted `Process` (its rules and its log of
    /// requests, `op` 0 to 3 and 5), to the running program's path (`op` 4) and to started programs on a real `Process`
    /// (`process.start`, `signal` and `wait_within`, `op` 6 to 8); `data` is the operand and the answer is packed octets.
    /// As for `run_process`, the first argument is a `Process` and there is no method spelling.
    process_control,
    /// `input.read(max)`: up to `max` octets from an `Input`, and an empty string at the end of the input. The three
    /// input kinds are methods of an `Input` receiver only (`streams.input_from` builds one for tests); none answers a
    /// `Result`. (`read_into` writes a buffer, so it is a buffer operation, `buffer_read_from`.)
    read,
    /// `input.read_exact(n)`: exactly `n` octets, or `None` when the input ends first.
    read_exact,
    /// `input.read_line()`: through the next newline, or the final unterminated line, or `None` at the end.
    read_line,
    /// `stop_control(stop, op)`: the standard library's channel to a `Stop` (FR5b): `op` 0 answers whether a stop has been
    /// heard on it (and marks the stop read), `op` 1 requests one. It answers a `bool`, never a `Result`, and has no method
    /// spelling.
    stop_control,
    /// Source argument count including the leading capability.
    pub fn arity(self: Access) usize {
        return switch (self) {
            .open, .write_file, .write_text, .atomic_write_file, .replace_file, .replace_file_synced, .read_regular_file, .list_directory, .rename_path, .symlink_path, .run_process, .process_control, .chmod_path, .set_modified_path => 3,
            .link_path, .mkdir_mode, .create_mode => 3,
            .atomic_write_file_mode, .replace_file_mode, .replace_file_synced_mode, .read_at_path => 4,
            .read_line => 1,
            else => 2,
        };
    }
    /// Whether this kind answers an open `File`, which a `with` may bind directly (a failure then traps): `open`, the three
    /// locks and `create_mode`.
    pub fn opensFile(self: Access) bool {
        return switch (self) {
            .open, .lock_directory, .lock_file, .try_lock_file, .create_mode => true,
            else => false,
        };
    }
    /// Whether this kind names two paths, the second as the text beside the first: a rename's destination, a link's target (written
    /// first, as `ln -s` takes it) and a hard link's new name.
    pub fn namesTwoPaths(self: Access) bool {
        return self == .rename_path or self == .symlink_path or self == .link_path;
    }
    /// Whether this kind publishes its third operand, the bytes, as a file: the durable atomic writes, the unsynchronized
    /// `replace_file` pair and the file-synchronized `replace_file_synced` pair.
    pub fn publishes(self: Access) bool {
        return switch (self) {
            .atomic_write_file, .atomic_write_file_mode, .replace_file, .replace_file_mode, .replace_file_synced, .replace_file_synced_mode => true,
            else => false,
        };
    }
    /// Whether this kind is one of the durable filesystem operations, which all lower to one runtime entry
    /// (`myl_core_durable_access`) and honour the granted directories rather than the plain provider.
    pub fn isDurable(self: Access) bool {
        return switch (self) {
            .atomic_write_file, .lock_directory, .sync_directory, .read_regular_file, .list_directory, .rename_path, .stat_path, .lock_file, .try_lock_file => true,
            .canonical_path, .chmod_path, .touch_path, .set_modified_path, .atomic_write_file_mode, .stat_follow_path, .list_entries_path => true,
            .replace_file, .replace_file_mode, .replace_file_synced, .replace_file_synced_mode, .symlink_path => true,
            .statfs_path, .read_at_path, .read_link_path, .link_path, .mkdir_mode, .create_mode => true,
            else => false,
        };
    }
    /// Whether the third operand of this kind is an `int`: a byte or entry bound, a process output limit, a mode or a time.
    pub fn takesIntegerThird(self: Access) bool {
        return switch (self) {
            .read_regular_file, .list_directory, .run_process, .process_control, .chmod_path, .set_modified_path, .mkdir_mode, .create_mode => true,
            else => false,
        };
    }
    /// Whether this kind is the channel to a `Stop` rather than an operation of a `Filesystem`, `Process` or `Input`.
    pub fn isStop(self: Access) bool {
        return self == .stop_control;
    }
    /// Whether this kind is a method of an `Input` rather than of a `Filesystem` or `Process`.
    pub fn isInput(self: Access) bool {
        return switch (self) {
            .read, .read_exact, .read_line => true,
            else => false,
        };
    }
    /// Argument count of the qualified `fs.name(...)` spelling, whose receiver is
    /// the capability itself: one fewer than the free-function count.
    pub fn methodArity(self: Access) usize {
        return self.arity() - 1;
    }
};

/// Methods of an open file binding, whose receiver must be a `with` local.
pub const Method = enum {
    read,
    readline,
    readlines,
    write,
    flush,
    close,
    /// `f.sync()`: everything written through the handle is on stable storage when it answers `Ok` (`fsync(2)`); a failure
    /// answers `Err` with the reason and the path. Last, so the request numbers of the methods before it do not move.
    sync,
    /// Whether this method accepts one optional or required argument.
    pub fn takesArgument(self: Method) bool {
        return self == .read or self == .write;
    }
    /// Whether the argument is required rather than optional.
    pub fn requiresArgument(self: Method) bool {
        return self == .write;
    }
};

/// Resolve a file method spelling, or null for an unknown member name.
pub fn method(name: []const u8) ?Method {
    return std.meta.stringToEnum(Method, name);
}

/// Resolve a whole-path helper spelling, or null for an ordinary call name.
pub fn access(name: []const u8) ?Access {
    return std.meta.stringToEnum(Access, name);
}

/// Decoded `open` mode: the provider request letter and whether reads are text.
/// The letters are the scoped provider's own request grammar.
pub const Mode = struct { letter: u8, text: bool };

/// Parse a Python open mode, rejecting combinations this surface does not offer.
pub fn parseMode(spelling: []const u8) ?Mode {
    if (spelling.len == 0 or spelling.len > 2) return null;
    const letter = switch (spelling[0]) {
        'r', 'w', 'a' => spelling[0],
        else => return null,
    };
    if (spelling.len == 1) return .{ .letter = letter, .text = true };
    return switch (spelling[1]) {
        'b' => .{ .letter = letter, .text = false },
        't' => .{ .letter = letter, .text = true },
        else => null,
    };
}
