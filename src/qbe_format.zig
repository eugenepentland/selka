//! Common QBE instruction templates shared by operation emitters.
/// Load one normalized native word from a computed pointer.
pub const load_word = " %v{d} =l loadl %v{d}\n";
/// Sticky trap helper invoked when a managed allocation budget is exhausted.
pub const allocation_failure = "myl_qbe_fail_allocation";
