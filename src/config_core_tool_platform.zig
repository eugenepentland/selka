//! Reviewed default native execution platform used exclusively by Core.
//! An unfamiliar runtime or loader cache remains executable without reuse.
// Bounded reviewed native execution platform. Retained readelf/ldd receipts
// prove this loader/libc/libm/libgcc/libpthread closure has no RPATH/RUNPATH.
// Backtrace load receipts prove these cache bytes select captured libgcc;
// libpthread also covers the bundled-target C debug path. Unknown content bypasses
// reuse; this is not a generic ELF or ld.so.cache dependency parser.
const loader_cache_path = "/etc/ld.so.cache";
pub const runtime_files = [_]RuntimeFile{
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
        .path = loader_cache_path,
        .resolved = loader_cache_path,
        .sha256 = "fe063c1bee92cacf27776b62c04e35a2c71e7ed111ec3eaa542ba339410fcde3",
    },
};
pub const preload_path = "/etc/ld.so.preload";

// Full native-driver discovery is additional to the runtime/bundled closure.
// Exact fixed-layout state comes from retained actual native traces and the
// reviewed 22.1.8 discovery branches. No exact tag-to-binary build attestation
// is claimed. Unknown content, member sets or sibling resources refuse reuse.
pub const discovery_files = [_]DiscoveryFile{
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

/// One reviewed runtime member, including its logical and canonical selection.
pub const RuntimeFile = struct { path: []const u8, resolved: []const u8, sha256: []const u8 };
/// One consumed distro or tool-selection file.
pub const DiscoveryFile = struct { path: []const u8 };
/// Complete runtime approval; no member is independently interchangeable.
pub const Runtime = struct { files: []const RuntimeFile, preload: []const u8 };
/// Complete reviewed compiler discovery branches and their exact state.
pub const Discovery = struct {
    state: []const u8,
    files: []const DiscoveryFile,
    predicates: []const []const u8,
    installation: []const u8,
    system_prefix: []const u8,
    installation_predicates: []const []const u8,
};
/// Runtime and discovery evidence must qualify the same named profile.
pub const Profile = struct { id: []const u8, runtime: Runtime, discovery: Discovery };
// Authenticated extraction-only Debian 13 bundle, not arbitrary Debian hosts.
// Signed package chain, repeatable loader cache, native traces and runtime
// receipts: experiments/debian13-native-cache-20261012/REPORT.md.
const debian_runtime_files = [_]RuntimeFile{
    .{ .path = "/lib64/ld-linux-x86-64.so.2", .resolved = "/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2", .sha256 = "c8438e4fde1934e61c88311633f00949ff645d5c04cdb8671fa3d78164d2f307" },
    .{ .path = "/lib/x86_64-linux-gnu/libc.so.6", .resolved = "/usr/lib/x86_64-linux-gnu/libc.so.6", .sha256 = "9792e3cbb541c8f44c7acf5f14f4022ea62998ecc787d326bed4d8b6547dfd92" },
    .{ .path = "/lib/x86_64-linux-gnu/libm.so.6", .resolved = "/usr/lib/x86_64-linux-gnu/libm.so.6", .sha256 = "6d567d53e895273ca14a1f9dc164fc6c8d39aed2f60aa46a733c2784228915f3" },
    .{ .path = "/lib/x86_64-linux-gnu/libgcc_s.so.1", .resolved = "/usr/lib/x86_64-linux-gnu/libgcc_s.so.1", .sha256 = "30c61ab012a4241bed033725a09b61f5fdd3bb7df95ee852d0b096520524c7af" },
    .{ .path = "/lib/x86_64-linux-gnu/libpthread.so.0", .resolved = "/usr/lib/x86_64-linux-gnu/libpthread.so.0", .sha256 = "85e21f7dba0394411d00959176fd18b470e575b0b05f1f4f41e5636802ce0500" },
    .{ .path = loader_cache_path, .resolved = loader_cache_path, .sha256 = "e89a171831da2084092baac36b0af6d096de3a7e09b8e40b267ee2f170926086" },
};

/// Reviewed complete profiles; unfamiliar hosts retain execution without reuse.
pub const profiles = [_]Profile{ .{
    .id = "reviewed-linux-x86_64-gcc15-v1",
    .runtime = .{ .files = &runtime_files, .preload = preload_path },
    .discovery = .{
        .state = discovery_state,
        .files = &discovery_files,
        .predicates = &discovery_predicates,
        .installation = discovery_installation,
        .system_prefix = discovery_system_prefix,
        .installation_predicates = &.{ "", "include/c++", "include/g++-v15", "include/g++-v15.-1" },
    },
}, .{
    .id = "debian13-amd64-minimal-20260912-v1",
    .runtime = .{ .files = &debian_runtime_files, .preload = preload_path },
    .discovery = .{
        .state = "ee3ccc02412999928f14b45c227bcbcb54cb446550403099cda01384fabca3d8",
        .files = &discovery_files,
        .predicates = &.{
            "/opt/rh",                   "/etc/env.d/gcc",                       "/lib",                                 "/lib64",                    "/lib/x86_64-linux-gnu",
            "/usr/lib/x86_64-linux-gnu", "/usr/x86_64-linux-gnu/lib",            "/usr/x86_64-linux-gnu/lib64",          "/usr/x86_64-linux-gnu/bin", "/usr/lib/gcc/x86_64-linux-gnu/lib64",
            "/usr/include/c++/14",       "/usr/include/x86_64-linux-gnu/c++/14", "/usr/x86_64-linux-gnu/include/c++/14",
        },
        .installation = "/usr/lib/gcc/x86_64-linux-gnu/14",
        .system_prefix = "/usr",
        .installation_predicates = &.{ "", "include/c++", "include/g++-v14", "include/g++-v14.-1" },
    },
} };
