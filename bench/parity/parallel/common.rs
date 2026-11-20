// Shared helpers for the parallel scaling ports (PARALLEL.md): the thread count from SELKA_THREADS, the chunking the Selka
// runtime uses for parallel.map, and the one output line.
use std::env;

/// The number of task threads: SELKA_THREADS, or one when it is unset.
pub fn thread_count() -> usize {
    env::var("SELKA_THREADS").ok().and_then(|text| text.parse().ok()).unwrap_or(1)
}

/// The number of map chunks for `items` items on `threads` threads: one chunk on one thread, otherwise four per thread,
/// and never more chunks than items (`myl_core_map_chunks`).
pub fn chunk_count(items: usize, threads: usize) -> usize {
    if items == 0 {
        return 0;
    }
    let chunks = if threads == 1 { 1 } else { threads * 4 };
    chunks.min(items)
}

/// The first item and the item count of chunk `index` of `chunks` over `items` items: the quotient goes to every chunk and
/// the remainder adds one item to the first chunks.
pub fn chunk_range(items: usize, chunks: usize, index: usize) -> (usize, usize) {
    let quotient = items / chunks;
    let remainder = items % chunks;
    (index * quotient + index.min(remainder), quotient + usize::from(index < remainder))
}
