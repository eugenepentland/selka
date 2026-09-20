//! Common QBE instruction templates shared by operation emitters.
/// Load one normalized native word from a computed pointer.
pub const load_word = " %v{d} =l loadl %v{d}\n";
/// Sticky trap helper invoked when a managed allocation budget is exhausted.
pub const allocation_failure = "myl_qbe_fail_allocation";
/// Clear one local slot so a released managed reference is never traced again.
pub const zero_local = " call $memset(l %l{d}, w 0, l {d})\n";
/// Byte offset of the `storage` word in a native list header
/// (`native_collections.h`), shared by every emitter that reads element backing.
pub const list_storage_offset = 32;
