//! A package's devices (MCU-C1B). A package's `selka.json` may describe devices as an application's does (`devices`:
//! each a target, linker script, C files, include folders and image). Everything of a package that a build reads is
//! pinned by the lock, so `selka packages lock` records, for each device, every file it names (its linker script, its
//! C files and every file under its include folders) with its SHA-256, and `selka packages build` refuses a package
//! whose device files changed since, naming the file. The same walk lists the files of an application's own devices,
//! which `packages build` copies into its snapshot. No path may leave its folder, by its spelling or through a symbolic
//! link. A device may also describe itself (`memory`, `place`, `stack`, `boot` and `hooks`, MCU-NOC4E) as an application's does:
//! those keys name no file, so the lock records them as the file spells them and refuses a package whose description changed
//! since, as it refuses one whose file changed.
const std = @import("std");
const project_config = @import("compiler_root").compiler_language.project_config;
const Sha256 = std.crypto.hash.sha2.Sha256;

/// The largest file a device may name.
const file_byte_budget = 16 * 1024 * 1024;

/// One file a device names: its path relative to the folder of the `selka.json` that describes the device,
/// `/`-separated, the lowercase hexadecimal SHA-256 of its bytes, and the bytes.
pub const File = struct { path: []const u8, digest: []const u8, bytes: []const u8 };

/// One device of a `selka.json`: its name, its settings as the file spells them, and every file it names, sorted.
pub const Device = struct { name: []const u8, settings: project_config.Device, files: []const File };

/// Why a read was refused: `reject` records the message for the command to print.
pub const Error = error{ Rejected, OutOfMemory };

/// The allocator and I/O a read uses, and the message of its refusal.
const Context = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    message: []const u8 = "",

    fn reject(self: *Context, comptime format: []const u8, arguments: anytype) error{Rejected} {
        self.message = std.fmt.allocPrint(self.allocator, format, arguments) catch "out of memory";
        return error.Rejected;
    }
};

/// Whose devices are read: the folder of the configuration (real path, no symbolic links) and the configuration's path.
pub const Owner = struct { root: []const u8, config: []const u8 };

/// The devices the configuration bytes `bytes` of `owner` describe, each with every file it names; none without
/// `devices`. A path that leaves the folder, a file that cannot be read and a symbolic link to a folder are refused
/// through `Context.reject`, naming the configuration, the device and the path.
/// `message` receives the refusal's text.
pub fn read(allocator: std.mem.Allocator, io: std.Io, owner: Owner, bytes: []const u8, message: *[]const u8) Error![]const Device {
    var context: Context = .{ .allocator = allocator, .io = io };
    errdefer message.* = context.message;
    return devicesIn(&context, owner, bytes);
}

/// `read`, with its context.
fn devicesIn(session: *Context, owner: Owner, bytes: []const u8) Error![]const Device {
    const allocator = session.allocator;
    try checkDescriptions(session, owner, bytes);
    const settings = try project_config.deviceSettings(allocator, bytes);
    var devices: std.ArrayList(Device) = .empty;
    for (settings.devices.map.keys(), settings.devices.map.values()) |name, device| {
        try devices.append(allocator, .{ .name = name, .settings = device, .files = try filesOf(session, owner, name, device) });
    }
    return devices.items;
}

/// Refuse a device whose description (`memory`, `place`, `stack`, `boot`, `hooks`) a project's `selka.json` would refuse: the
/// same checks (`project_config.startupProblem`), naming the configuration and the device. A device with none is not read here.
fn checkDescriptions(session: *Context, owner: Owner, bytes: []const u8) Error!void {
    const document = std.json.parseFromSliceLeaky(std.json.Value, session.allocator, bytes, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return,
    };
    const listed = if (document == .object) document.object.get("devices") orelse return else return;
    if (listed != .object) return;
    var buffer: [384]u8 = undefined;
    for (listed.object.keys(), listed.object.values()) |name, device| {
        if (device != .object) continue;
        const keys = try project_config.startupKeys(session.allocator, device.object);
        if (keys.count() == 0) continue;
        if (try project_config.startupProblem(session.allocator, keys, device.object.contains("linker_script"), &buffer)) |line|
            return session.reject("{s}: device \"{s}\": {s}", .{ owner.config, name, line });
    }
}

/// The device of `devices` named `name`, or null.
pub fn named(devices: []const Device, name: []const u8) ?Device {
    for (devices) |device| if (std.mem.eql(u8, device.name, name)) return device;
    return null;
}

/// Every file `device` names, sorted by path, each once.
fn filesOf(session: *Context, owner: Owner, name: []const u8, device: project_config.Device) Error![]const File {
    const allocator = session.allocator;
    var paths: std.ArrayList([]const u8) = .empty;
    if (device.linker_script) |script| try paths.append(allocator, try normalized(session, owner, name, script));
    for (device.links) |link| try paths.append(allocator, try normalized(session, owner, name, link));
    for (device.include) |folder| try folderFiles(session, owner, .{ .device = name, .folder = try normalized(session, owner, name, folder) }, &paths);
    std.mem.sort([]const u8, paths.items, {}, lessThan);
    var files: std.ArrayList(File) = .empty;
    for (paths.items, 0..) |path, index| {
        if (index > 0 and std.mem.eql(u8, paths.items[index - 1], path)) continue;
        const absolute = try std.fs.path.join(allocator, &.{ owner.root, path });
        try inside(session, owner, name, path, absolute);
        const bytes = std.Io.Dir.cwd().readFileAlloc(session.io, absolute, allocator, .limited(file_byte_budget)) catch |err|
            return session.reject("{s}: device \"{s}\": cannot read {s} ({s}): {t}", .{ owner.config, name, path, absolute, err });
        var digest: [Sha256.digest_length]u8 = undefined;
        Sha256.hash(bytes, &digest, .{});
        try files.append(allocator, .{ .path = path, .digest = try allocator.dupe(u8, &std.fmt.bytesToHex(digest, .lower)), .bytes = bytes });
    }
    return files.items;
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// `path` without `.` parts and with its `..` parts applied, refused when it is empty, absolute or climbs out.
fn normalized(session: *Context, owner: Owner, name: []const u8, path: []const u8) Error![]const u8 {
    if (!project_config.staysInside(path))
        return session.reject("{s}: device \"{s}\": \"{s}\" leaves the folder of this selka.json; a device's paths stay inside it", .{ owner.config, name, path });
    return std.fs.path.resolvePosix(session.allocator, &.{path});
}

/// Refuse `path` (at `absolute`) when it names nothing, or when its real location is outside the owner's folder.
fn inside(session: *Context, owner: Owner, name: []const u8, path: []const u8, absolute: []const u8) Error!void {
    const real = std.Io.Dir.cwd().realPathFileAlloc(session.io, absolute, session.allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return session.reject("{s}: device \"{s}\": {s} names no file ({s})", .{ owner.config, name, path, absolute }),
    };
    if (!project_config.realPathInside(owner.root, real))
        return session.reject("{s}: device \"{s}\": {s} leaves the folder of this selka.json through a symbolic link (its real location is {s})", .{ owner.config, name, path, real });
}

/// One include folder of a device: the device's name and the folder, normalized.
const Folder = struct { device: []const u8, folder: []const u8 };

/// Append every file under `at.folder` to `paths`. A symbolic link to a folder is refused, since the walk does not follow
/// it and the compiler would read files the lock does not pin; a link to a file is checked like any path.
fn folderFiles(session: *Context, owner: Owner, at: Folder, paths: *std.ArrayList([]const u8)) Error!void {
    const allocator = session.allocator;
    const io = session.io;
    const absolute = try std.fs.path.join(allocator, &.{ owner.root, at.folder });
    try inside(session, owner, at.device, at.folder, absolute);
    var opened = std.Io.Dir.cwd().openDir(io, absolute, .{ .iterate = true }) catch |err|
        return session.reject("{s}: device \"{s}\": include folder {s} cannot be opened ({s}): {t}", .{ owner.config, at.device, at.folder, absolute, err });
    defer opened.close(io);
    var walker = try opened.walk(allocator);
    defer walker.deinit();
    while (walker.next(io) catch |err| return session.reject("{s}: device \"{s}\": cannot walk {s}: {t}", .{ owner.config, at.device, at.folder, err })) |entry| {
        if (entry.kind == .directory) continue;
        const path = try std.fs.path.join(allocator, &.{ at.folder, entry.path });
        if (entry.kind == .sym_link) {
            const info = opened.statFile(io, entry.path, .{}) catch |err|
                return session.reject("{s}: device \"{s}\": {s} is a symbolic link to nothing: {t}", .{ owner.config, at.device, path, err });
            if (info.kind == .directory)
                return session.reject("{s}: device \"{s}\": {s} is a symbolic link to a folder, which a device's include folder may not hold", .{ owner.config, at.device, path });
        }
        try paths.append(allocator, path);
    }
}

/// The lock's record of a package's devices: for each device, by name, every file it names with its SHA-256.
pub fn lockValue(allocator: std.mem.Allocator, devices: []const Device) error{OutOfMemory}!std.json.Value {
    var record: std.json.ObjectMap = .empty;
    for (devices) |device| {
        var files = std.json.Array.init(allocator);
        for (device.files) |file| {
            var object: std.json.ObjectMap = .empty;
            try object.put(allocator, "path", .{ .string = file.path });
            try object.put(allocator, "sha256", .{ .string = file.digest });
            try files.append(.{ .object = object });
        }
        try record.put(allocator, device.name, .{ .array = files });
    }
    return .{ .object = record };
}

/// The description of a device (`startup`) as the JSON object its file spells: only the keys it holds, none for an old-style device.
fn descriptionOf(allocator: std.mem.Allocator, device: Device) error{OutOfMemory}!std.json.ObjectMap {
    const text = try std.json.Stringify.valueAlloc(allocator, device.settings.startup, .{ .emit_null_optional_fields = false });
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, allocator, text, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .empty,
    };
    return if (parsed == .object) parsed.object else .empty;
}

/// The lock's record of the descriptions of a package's devices: for each device that holds any of `memory`, `place`, `stack`,
/// `boot` and `hooks`, those keys as its file spells them, by name. Null when no device holds any, and the lock then has no
/// such record, as a lock written before descriptions had none.
pub fn descriptionsValue(allocator: std.mem.Allocator, devices: []const Device) error{OutOfMemory}!?std.json.Value {
    var record: std.json.ObjectMap = .empty;
    for (devices) |device| {
        const description = try descriptionOf(allocator, device);
        if (description.count() != 0) try record.put(allocator, device.name, .{ .object = description });
    }
    return if (record.count() == 0) null else .{ .object = record };
}

/// What a lock recorded of a package's devices: their files (`lockValue`) and their descriptions (`descriptionsValue`, null when
/// it recorded none).
pub const Locked = struct { files: std.json.Value, descriptions: std.json.Value = .null };

/// What changed in a package's devices since the lock recorded them (`locked`), as the refusal names it: `its devices`
/// when a device came or went, `its device NAME: PATH` for a file that changed, came or went, `its device NAME: the KEY key`
/// for a description that did; null when nothing did.
pub fn changed(allocator: std.mem.Allocator, devices: []const Device, locked: Locked) error{OutOfMemory}!?[]const u8 {
    const recorded_files = locked.files;
    if (recorded_files != .object or recorded_files.object.count() != devices.len) return "its devices";
    for (devices) |device| {
        const files = recorded_files.object.get(device.name) orelse return "its devices";
        if (files != .array) return "its devices";
        for (device.files) |file| {
            if (recorded(files.array.items, file.path, file.digest)) continue;
            const what = try fileChanged(allocator, device.name, file.path);
            return what;
        }
        for (files.array.items) |entry| {
            const path = stringField(entry, "path") orelse return "its devices";
            for (device.files) |file| {
                if (std.mem.eql(u8, file.path, path)) break;
            } else {
                const what = try fileChanged(allocator, device.name, path);
                return what;
            }
        }
        if (try descriptionChanged(allocator, device, locked.descriptions)) |what| return what;
    }
    return null;
}

/// `its device NAME: the KEY key` for the first key of `device`'s description that differs from the lock's record (`recorded`, the
/// object of descriptions by device name, or null), `its device NAME: its description` when only the record's own keys differ.
fn descriptionChanged(allocator: std.mem.Allocator, device: Device, recorded_descriptions: std.json.Value) error{OutOfMemory}!?[]const u8 {
    const current = try descriptionOf(allocator, device);
    const entry = if (recorded_descriptions == .object) recorded_descriptions.object.get(device.name) else null;
    if (entry != null and entry.? != .object) return try std.fmt.allocPrint(allocator, "its device {s}: its description", .{device.name});
    const locked: std.json.ObjectMap = if (entry) |value| value.object else .empty;
    for (project_config.startup_fields) |key| {
        if (sameValue(current.get(key), locked.get(key))) continue;
        return try std.fmt.allocPrint(allocator, "its device {s}: the {s} key", .{ device.name, key });
    }
    return if (sameValue(.{ .object = current }, .{ .object = locked })) null else try std.fmt.allocPrint(allocator, "its device {s}: its description", .{device.name});
}

/// Whether two JSON values are the same, an object's keys in the same order (a reordered `memory` writes another script).
fn sameValue(left: ?std.json.Value, right: ?std.json.Value) bool {
    const first = left orelse return right == null;
    const second = right orelse return false;
    if (std.meta.activeTag(first) != std.meta.activeTag(second)) return false;
    switch (first) {
        .null => return true,
        .bool => |value| return value == second.bool,
        .integer => |value| return value == second.integer,
        .float => |value| return value == second.float,
        .number_string => |text| return std.mem.eql(u8, text, second.number_string),
        .string => |text| return std.mem.eql(u8, text, second.string),
        .array => |items| {
            if (items.items.len != second.array.items.len) return false;
            for (items.items, second.array.items) |one, other| if (!sameValue(one, other)) return false;
            return true;
        },
        .object => |map| {
            if (map.count() != second.object.count()) return false;
            for (map.keys(), map.values(), second.object.keys(), second.object.values()) |key, value, other_key, other| {
                if (!std.mem.eql(u8, key, other_key) or !sameValue(value, other)) return false;
            }
            return true;
        },
    }
}

fn fileChanged(allocator: std.mem.Allocator, device: []const u8, path: []const u8) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, "its device {s}: {s}", .{ device, path });
}

/// Whether the lock's file list `entries` records `path` with `digest`.
fn recorded(entries: []const std.json.Value, path: []const u8, digest: []const u8) bool {
    for (entries) |entry| {
        const locked_path = stringField(entry, "path") orelse continue;
        if (!std.mem.eql(u8, locked_path, path)) continue;
        const locked_digest = stringField(entry, "sha256") orelse return false;
        return std.mem.eql(u8, locked_digest, digest);
    }
    return false;
}

fn stringField(value: std.json.Value, key: []const u8) ?[]const u8 {
    if (value != .object) return null;
    const field = value.object.get(key) orelse return null;
    return if (field == .string) field.string else null;
}

/// The staged configuration's entry for a package's device whose files are staged under `prefix` (`.devices/PKG`):
/// its settings with every path under that prefix, and its description (`memory`, `place`, `stack`, `boot`, `hooks`) unchanged:
/// it names no path, and a hook names a module as the program imports it.
pub fn stagedEntry(allocator: std.mem.Allocator, device: Device, prefix: []const u8) error{OutOfMemory}!std.json.Value {
    const settings = device.settings;
    var entry: std.json.ObjectMap = .empty;
    if (settings.target) |name| try entry.put(allocator, "target", .{ .string = name });
    if (settings.linker_script) |script| try entry.put(allocator, "linker_script", .{ .string = try under(allocator, prefix, script) });
    try entry.put(allocator, "links", try underAll(allocator, prefix, settings.links));
    try entry.put(allocator, "include", try underAll(allocator, prefix, settings.include));
    if (settings.image) |image| try entry.put(allocator, "image", .{ .string = image });
    if (settings.uf2_family) |family| try entry.put(allocator, "uf2_family", .{ .string = family });
    const description = try descriptionOf(allocator, device);
    for (description.keys(), description.values()) |key, value| try entry.put(allocator, key, value);
    return .{ .object = entry };
}

fn under(allocator: std.mem.Allocator, prefix: []const u8, path: []const u8) error{OutOfMemory}![]const u8 {
    return std.fs.path.resolvePosix(allocator, &.{ prefix, path });
}

fn underAll(allocator: std.mem.Allocator, prefix: []const u8, paths: []const []const u8) error{OutOfMemory}!std.json.Value {
    var array = std.json.Array.init(allocator);
    for (paths) |path| try array.append(.{ .string = try under(allocator, prefix, path) });
    return .{ .array = array };
}

/// Write the files of the test's device under `dir`: each holds its own path.
fn writeDeviceFiles(dir: std.Io.Dir) !void {
    try dir.createDirPath(std.testing.io, "device/ram/inc/sub");
    for ([_][]const u8{ "device/ram/link.ld", "device/ram/platform.c", "device/ram/inc/a.h", "device/ram/inc/sub/b.h" }) |path|
        try dir.writeFile(std.testing.io, .{ .sub_path = path, .data = path });
}

test "a package device's files are its script, its C and every file under its include folders, and a change names the file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    try writeDeviceFiles(temp.dir);
    const root = try temp.dir.realPathFileAlloc(std.testing.io, ".", a);
    const config = "{\"version\": 1, \"devices\": {\"ram\": {\"target\": \"thumbv6m-none\", \"linker_script\": \"device/ram/link.ld\"," ++
        " \"links\": [\"device/ram/./platform.c\"], \"include\": [\"device/ram/inc\"], \"image\": \"bin\"}}}";
    var session: Context = .{ .allocator = a, .io = std.testing.io };
    const devices = try devicesIn(&session, .{ .root = root, .config = "selka.json" }, config);
    try std.testing.expectEqual(@as(usize, 1), devices.len);
    const paths = [_][]const u8{ "device/ram/inc/a.h", "device/ram/inc/sub/b.h", "device/ram/link.ld", "device/ram/platform.c" };
    try std.testing.expectEqual(paths.len, devices[0].files.len);
    for (paths, devices[0].files) |path, file| try std.testing.expectEqualStrings(path, file.path);
    const lock: Locked = .{ .files = try lockValue(a, devices) };
    try std.testing.expectEqual(@as(?[]const u8, null), try changed(a, devices, lock));
    // An old-style device records no description, and stages with none of its keys.
    try std.testing.expectEqual(@as(?std.json.Value, null), try descriptionsValue(a, devices));
    // A header edited since the lock is named.
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "device/ram/inc/sub/b.h", .data = "edited" });
    const edited = try devicesIn(&session, .{ .root = root, .config = "selka.json" }, config);
    try std.testing.expectEqualStrings("its device ram: device/ram/inc/sub/b.h", (try changed(a, edited, lock)).?);
    try std.testing.expectEqualStrings("its devices", (try changed(a, &.{}, lock)).?);
    const staged = try stagedEntry(a, devices[0], ".devices/rp2040");
    try std.testing.expectEqual(@as(usize, 5), staged.object.count());
    try std.testing.expectEqualStrings(".devices/rp2040/device/ram/link.ld", staged.object.get("linker_script").?.string);
    try std.testing.expectEqualStrings(".devices/rp2040/device/ram/platform.c", staged.object.get("links").?.array.items[0].string);
    // A symbolic link inside the folder that points out of it is refused, with its real location.
    try temp.dir.createDirPath(std.testing.io, "outside");
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "outside/x.h", .data = "x" });
    const package_root = try std.fs.path.join(a, &.{ root, "device" });
    try temp.dir.symLink(std.testing.io, "../../../outside/x.h", "device/ram/inc/x.h", .{});
    try std.testing.expectError(error.Rejected, devicesIn(&session, .{ .root = package_root, .config = "selka.json" }, "{\"devices\": {\"ram\": {\"include\": [\"ram/inc\"]}}}"));
    try std.testing.expect(std.mem.indexOf(u8, session.message, "ram/inc/x.h leaves the folder of this selka.json through a symbolic link") != null);
}

/// The configuration of a package whose one device describes itself and names no file: QEMU's layout behind a boot stage, a stack in
/// the second region, and two hooks bound to the package's `board` module.
const described_config =
    \\{"version": 1, "devices": {"flash": {"target": "thumbv6m-none",
    \\ "memory": {"flash": ["0x10000000", "2044K"], "ram": ["0x20000000", "252K"]},
    \\ "place": {"vectors": "flash", "code": "flash", "data": "ram"}, "boot": "rp2040-read-03h", "stack": ["16K", "ram"],
    \\ "hooks": {"start": "rp2040.board.start", "exit": "rp2040.board.finish"}}}}
;

test "a described package device stages every description key, and a changed key is a changed lock that names it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const owner: Owner = .{ .root = "/", .config = "rp2040/selka.json" };
    var session: Context = .{ .allocator = a, .io = std.testing.io };
    const devices = try devicesIn(&session, owner, described_config);
    try std.testing.expectEqual(@as(usize, 0), devices[0].files.len);
    const staged = try stagedEntry(a, devices[0], ".devices/rp2040");
    try std.testing.expectEqualStrings("thumbv6m-none", staged.object.get("target").?.string);
    try std.testing.expect(staged.object.get("linker_script") == null);
    const memory = staged.object.get("memory").?.object;
    try std.testing.expectEqualStrings("flash", memory.keys()[0]);
    try std.testing.expectEqualStrings("2044K", memory.get("flash").?.array.items[1].string);
    try std.testing.expectEqualStrings("ram", staged.object.get("place").?.object.get("data").?.string);
    try std.testing.expectEqualStrings("ram", staged.object.get("stack").?.array.items[1].string);
    try std.testing.expectEqualStrings("rp2040-read-03h", staged.object.get("boot").?.string);
    // A hook names the module as the program imports it, and is staged as written.
    try std.testing.expectEqualStrings("rp2040.board.finish", staged.object.get("hooks").?.object.get("exit").?.string);
    const lock: Locked = .{ .files = try lockValue(a, devices), .descriptions = (try descriptionsValue(a, devices)).? };
    try std.testing.expectEqual(@as(?[]const u8, null), try changed(a, devices, lock));
    // Each edit of one key is named; a lock that recorded no description refuses the described device too.
    const edits = [_][3][]const u8{
        .{ "2044K", "2040K", "memory" },
        .{ "\"16K\"", "\"8K\"", "stack" },
        .{ "\"boot\": \"rp2040-read-03h\", ", "", "boot" },
        .{ "board.finish", "board.halt", "hooks" },
        .{ "\"vectors\": \"flash\", ", "", "place" },
    };
    for (edits) |edit| {
        const edited = try devicesIn(&session, owner, try std.mem.replaceOwned(u8, a, described_config, edit[0], edit[1]));
        const expected = try std.fmt.allocPrint(a, "its device flash: the {s} key", .{edit[2]});
        try std.testing.expectEqualStrings(expected, (try changed(a, edited, lock)).?);
    }
    try std.testing.expectEqualStrings("its device flash: the memory key", (try changed(a, devices, .{ .files = lock.files })).?);
}

test "a package device's description is refused as a project's is, naming the configuration and the device" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const owner: Owner = .{ .root = "/", .config = "rp2040/selka.json" };
    var session: Context = .{ .allocator = a, .io = std.testing.io };
    const refused = [_][2][]const u8{
        .{ "{\"devices\": {\"x\": {\"memory\": {\"ram\": [\"0x20000000\", \"0\"]}}}}", "rp2040/selka.json: device \"x\": region \"ram\": the length" },
        .{ "{\"devices\": {\"x\": {\"hooks\": {\"bogus\": \"a.b\"}}}}", "device \"x\": unknown hook \"bogus\"" },
        .{ "{\"devices\": {\"x\": {\"memory\": [1]}}}", "device \"x\": a device's memory is {\"NAME\"" },
        .{ "{\"devices\": {\"x\": {\"linker_script\": \"a.ld\", \"memory\": {\"ram\": [\"0x20000000\", \"1K\"]}}}}", "names a linker_script or describes its memory, not both" },
    };
    for (refused) |case| {
        try std.testing.expectError(error.Rejected, devicesIn(&session, owner, case[0]));
        try std.testing.expect(std.mem.indexOf(u8, session.message, case[1]) != null);
    }
}
