//! The platform module of a compiler built with `-Dtest-system-root=DIR` (GH-3b): the reviewed platform with the
//! directory the system closure is read below. A test seam only; an ordinary build never compiles this file.
const reviewed = @import("reviewed_platform");
const options = @import("rooted_options");
pub const address_runtime = reviewed.address_runtime;
pub const discovery_files = reviewed.discovery_files;
pub const discovery_state = reviewed.discovery_state;
pub const discovery_predicates = reviewed.discovery_predicates;
pub const discovery_installation = reviewed.discovery_installation;
pub const discovery_system_prefix = reviewed.discovery_system_prefix;
/// The directory the system closure is read below.
pub const system_root: []const u8 = options.system_root;
