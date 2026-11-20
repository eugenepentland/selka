//! The native execution platform Core builds for: the address-sanitiser runtime's path and the C driver's discovery
//! inputs. The system libraries built programs load are not listed here: they are found the way the loader finds them
//! and keyed by their bytes (`src/core/native_closure.zig`, GH-3b), so no machine needs to be named or approved.
// Optional ASan dependency: only address-instrumented builds capture this file (its bytes are keyed; the digest
// here is for reference only).
// The target-pinned Zig driver instruments ASan but does not bundle its runtime.
pub const address_runtime = .{
    .path = "/usr/lib/x86_64-linux-gnu/libasan.so.8",
    .resolved = "/usr/lib/x86_64-linux-gnu/libasan.so.8.0.0",
    .sha256 = "b49a5ec136d444f8b40cf24964c20ef01434fc4e6dcf68dc272f5028d65b5496",
};

// Full native-driver discovery is additional to the runtime/bundled closure.
// Exact fixed-layout state comes from retained actual native traces and the
// reviewed 22.1.8 discovery branches. No exact tag-to-binary build attestation
// is claimed. Their contents, member sets and sibling resources are keyed (GH-3b: no longer a gate).
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
