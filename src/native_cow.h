#ifndef MYLANG_NATIVE_COW_H
#define MYLANG_NATIVE_COW_H
#include "native_collections.h"
#include "native_dictionary.h"
/* Copy on write over the tracing collector (D9 stage 3b, COW-SHARED-1,
 * COW-UNIQUE-1, COW-NESTED-1, COW-PIN-1; `docs/value-semantics.md`).
 *
 * A copy-on-write payload is a list, byte buffer, dictionary or set header.
 * A value transfer that value semantics calls a copy shares the payload
 * instead: it sets MYL_NATIVE_OBJECT_SHARED in the header and both holders
 * keep the pointer. A write first makes its payload unique: a shared payload
 * is copied one level deep — a fresh header and storage whose elements are
 * the same words — and the writer's slot is redirected to the copy. Every
 * payload the copy now shares with the original (a nested list, a
 * dictionary's value) is marked shared in turn, so it is copied when either
 * side first writes it. Nothing counts holders, so the flag is sticky: the
 * last holder of a shared payload still copies once on its first write.
 *
 * Generated code tests the flag inline and calls these functions only on the
 * slow path. Every function that allocates roots its own inputs; the caller
 * roots everything else it keeps across the call, as for any allocation. A
 * copy is allocated at the arena depth of the payload it replaces, because it
 * takes that payload's place and so has its lifetime. */
/* Whether `payload` is a copy-on-write payload. NULL is not. */
int myl_native_cow_payload(const void *payload);
/* The value a transfer stores: `payload` itself after it is marked shared, or,
 * for a payload a `mut` parameter holds (PINNED), a fresh unique copy, since
 * that holder's slot cannot be redirected. NULL payloads, immortal ones and
 * anything that is not a copy-on-write payload pass through unmarked. Returns
 * NULL only when the copy is refused. */
void *myl_native_cow_share(myl_native_heap *heap, void *payload);
/* Share every copy-on-write payload a value of `type` at `address` holds
 * directly: in its fields, array elements and active variant payload, never
 * through another payload or a `class` body, which carry their own flags. A
 * pinned payload is replaced at `address` by its copy, so `address` must be
 * the transfer's own private value. Returns 0 when a copy is refused. */
int myl_native_cow_share_value(myl_native_heap *heap, const myl_native_type *type, void *address);
/* Materialize one immutable recursive box body into private inline storage,
 * shallow-sharing mutable children before the guest can write through it. */
int myl_native_cow_unbox(myl_native_heap *heap, const myl_native_type *type,
                         void *box, void *output);
/* A transfer whose outer collection is already a fresh shallow copy keeps
 * that outer header unshared and marks the mutable payloads in its directly
 * held elements or entries. The caller roots the value at `address`. */
int myl_native_cow_share_children(myl_native_heap *heap, const myl_native_type *type, void *address);
/* A bulk operation reads a source collection that must stay untouched when a
 * pinned child is replaced. Give the operation a fresh outer header first. */
int myl_native_cow_copy_source_children(myl_native_heap *heap, const myl_native_type *type, void *address);
/* Consume the explicit descriptor/value depth-limit failure, if a COW
 * operation refused a transfer or shallow copy for that reason. */
int myl_native_cow_take_depth_failure(void);
/* QBE's one real-copy hook: copy into rooted output and share either the
 * value's direct payloads or, when `children` is set, a fresh outer
 * collection's directly held payloads. Returns zero after recording a trap
 * when any required shallow copy fails. */
int myl_qbe_cow_transfer(void *context, const myl_native_type *type,
                          const void *value, void *output, uint32_t children);
int myl_qbe_cow_unbox(void *context, const myl_native_type *type,
                      void *box, void *output);
/* The slow half of a uniqueness check: `payload` when it is not shared, else a
 * fresh unshared copy whose directly held payloads are marked shared. The
 * caller stores the answer back into the slot it loaded `payload` from.
 * Returns NULL only when the copy is refused. */
void *myl_native_cow_unique(myl_native_heap *heap, void *payload);
/* `myl_native_cow_unique` for a payload a nested place holds: `container` —
 * the list, dictionary or `class` body whose storage the caller writes the
 * copy into — is kept alive through the copy, because the local that named it
 * may already be dead. NULL `container` keeps nothing extra. */
void *myl_native_cow_unique_in(myl_native_heap *heap, void *payload, void *container);
void *myl_native_cow_rebox(myl_native_heap *heap, const myl_native_type *type,
                           void *old_box, void *body);
void *myl_native_cow_clone_box(myl_native_heap *heap, const myl_native_type *type,
                               void *old_box, void *container);
/* A fresh unshared copy of `payload` whatever its flags, with its directly
 * held payloads marked shared: an argument a `mut` argument of the same call
 * could reach must not share storage with it. NULL on refusal. */
void *myl_native_cow_copy(myl_native_heap *heap, void *payload);
/* Make every element of `list` unique where it lives: each shared element
 * payload is replaced in the list's storage by its unique copy. A loop whose
 * writes go through elements it cannot share runs this once on entry instead
 * of a check per write. Returns 0 when a copy is refused. */
int myl_native_cow_elements(myl_native_heap *heap, myl_native_list *list);
/* A pending inline-array receiver keeps its direct collection leaves unique
 * and pinned while later indices run guest code. The caller roots the linked
 * pin list through a native root of scope_type, restores it on every exit,
 * and keeps the addressed aggregate and its enclosing owners rooted while
 * preparing it. The nodes use the ordinary managed allocation budget. */
extern const myl_native_type myl_native_cow_scope_type;
int myl_native_cow_scope_pin(myl_native_heap *, void **pins, void *payload);
/* Each step selects every element of an array, or one field at offset. Its
 * descriptor names the source representation, including a boxed/class body. */
typedef struct { const myl_native_type *type; size_t offset; } myl_native_cow_path;
int myl_native_cow_scope_prepare(myl_native_heap *, void **pins, void *address,
                                 const myl_native_cow_path *path, size_t count);
void myl_native_cow_scope_release(void *pins);
/* Copy-on-write counters (COW-STATS-1). Only a counting build calls
 * `myl_native_cow_tally` at its inline mark, check and pin sites, enabling
 * copy counters and one `cow-stats {...}` JSON line at exit. An ordinary
 * checks build does not update counters. */
typedef struct {
    uint64_t marks, checks, hoisted, copies, copied_bytes, pinned_copies, pins;
} myl_native_cow_statistics;
/* The counters of this process. */
extern myl_native_cow_statistics myl_native_cow_counters;
/* The event kinds `myl_native_cow_tally` counts. */
enum { MYL_NATIVE_COW_MARK, MYL_NATIVE_COW_CHECK, MYL_NATIVE_COW_HOISTED, MYL_NATIVE_COW_PIN };
/* Count one inline event of `kind`. Only a counting build calls it. */
void myl_native_cow_tally(uint32_t kind);
/* Write the counters as one `cow-stats` JSON line to `stream`. */
void myl_native_cow_report(void *stream);
#endif
