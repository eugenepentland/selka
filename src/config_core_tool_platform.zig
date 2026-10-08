//! Reviewed default native execution platform used exclusively by Core.
//! An unfamiliar runtime or loader cache remains executable without reuse.
// Bounded reviewed native execution platform. Retained readelf/ldd receipts
// prove this loader/libc/libm/libgcc/libpthread closure has no RPATH/RUNPATH.
// Backtrace load receipts prove these cache bytes select captured libgcc;
// libpthread also covers the bundled-target C debug path. Unknown content bypasses
// reuse; this is not a generic ELF or ld.so.cache dependency parser.
pub const runtime_files = [_]struct { path: []const u8, resolved: []const u8, sha256: []const u8 }{
    .{
        .path = "/lib64/ld-linux-x86-64.so.2",
        .resolved = "/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2",
        .sha256 = "bda779ea9e9ad234f60315477d7cfd0bdde861cd8ddd9df8cdaf62f18c4cec14",
    },
    .{
        .path = "/lib/x86_64-linux-gnu/libc.so.6",
        .resolved = "/usr/lib/x86_64-linux-gnu/libc.so.6",
        .sha256 = "85e64f97e348786a8fb4d9f3d52fec289e2fb86bba20f0731dfe61990525e0f7",
    },
    .{
        .path = "/lib/x86_64-linux-gnu/libm.so.6",
        .resolved = "/usr/lib/x86_64-linux-gnu/libm.so.6",
        .sha256 = "1c488db6f4fe8cecb72456bc018de000b7a9b539c2994864b0416b5e8371b3d8",
    },
    .{
        .path = "/lib/x86_64-linux-gnu/libgcc_s.so.1",
        .resolved = "/usr/lib/x86_64-linux-gnu/libgcc_s.so.1",
        .sha256 = "9d339ecb409578d6a5d587e6c537a8f9589b8a13fefba30d167433a4b5758bee",
    },
    .{
        .path = "/lib/x86_64-linux-gnu/libpthread.so.0",
        .resolved = "/usr/lib/x86_64-linux-gnu/libpthread.so.0",
        .sha256 = "1327fc40710691dbd94e88b6cf4efce27fefe8fbb93f7d1164a75b4dccaea696",
    },
    .{
        .path = "/etc/ld.so.cache",
        .resolved = "/etc/ld.so.cache",
        .sha256 = "fe063c1bee92cacf27776b62c04e35a2c71e7ed111ec3eaa542ba339410fcde3",
    },
};
pub const preload_path = "/etc/ld.so.preload";

// Full native-driver discovery is additional to the runtime/bundled closure.
// Exact fixed-layout state comes from retained actual native traces and the
// reviewed 22.1.8 discovery branches. No exact tag-to-binary build attestation
// is claimed. Unknown content, member sets or sibling resources refuse reuse.
pub const discovery_files = [_]struct { path: []const u8 }{
    .{ .path = "/etc/os-release" },
    .{ .path = "/usr/lib/os-release" },
    .{ .path = "/etc/lsb-release" },
    .{ .path = "/etc/redhat-release" },
    .{ .path = "/etc/debian_version" },
    .{ .path = "/etc/SuSE-release" },
    .{ .path = "/etc/gentoo-release" },
};
pub const discovery_state = "614ce9f2e514299aea9aea24086e224bb2c8ed8467fcf4a98e453d2d86057ab1";

pub const discovery_predicates = [_][]const u8{
    "/opt/rh",                   "/etc/env.d/gcc",                       "/lib",                                 "/lib64",                    "/lib/x86_64-linux-gnu",
    "/usr/lib/x86_64-linux-gnu", "/usr/x86_64-linux-gnu/lib",            "/usr/x86_64-linux-gnu/lib64",          "/usr/x86_64-linux-gnu/bin", "/usr/lib/gcc/x86_64-linux-gnu/lib64",
    "/usr/include/c++/15",       "/usr/include/x86_64-linux-gnu/c++/15", "/usr/x86_64-linux-gnu/include/c++/15",
};
pub const discovery_installation = "/usr/lib/gcc/x86_64-linux-gnu/15";
pub const discovery_system_prefix = "/usr";
