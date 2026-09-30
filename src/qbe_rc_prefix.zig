//! Frozen ABI5 counted prefix shared by generated allocation and count paths.

/// Native ownership/module ABI paired with this prefix.
pub const abi_version: u32 = 5;
/// Bytes before a counted payload; common GC/arena headers stay 16 bytes.
pub const bytes: u64 = 32;
/// Byte distance from a counted payload to its unsigned owner count.
pub const owners_offset: u64 = 32;
/// Byte distance from a counted payload to its unsigned lifetime hold count.
pub const holds_offset: u64 = 24;
/// Byte distance from every managed payload to its common mark word.
pub const mark_offset: u64 = 16;
/// Width in bits of either active count; retired links remain 64 bits.
pub const count_bits: u32 = 64;
/// Largest active count; acquiring at this value must refuse without change.
pub const count_max: u64 = 0xffffffffffffffff;
/// QBE type used for active count arithmetic and comparisons.
pub const count_type = "l";
/// QBE load opcode used for either active count.
pub const count_load = "loadl";
/// QBE store opcode used for either active count.
pub const count_store = "storel";
/// Load a marked prefix address and its active unsigned count.
pub const load_count = " %v{d} =l sub %v{d}, {d}\n # myl-rc %v{d}\n %v{d} =" ++ count_type ++ " " ++ count_load ++ " %v{d}\n";
