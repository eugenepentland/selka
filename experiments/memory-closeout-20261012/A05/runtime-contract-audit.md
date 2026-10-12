# A05 provider and container audit

Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`. This is an audit request, not helper admission or execution qualification.

The existing zero-RC branches in `core_io.c` use direct destruction. Root capabilities own provider state; narrowed capabilities own copied scope bytes and borrow the named parent. File/resource blocks borrow the capability. `core_io_finalize` closes still-open handles before provider state is destroyed. The language must keep the named provider live through this cleanup; observing zero counters alone cannot establish that ordering.

| Helper | Input/result ownership | Required boundary |
| --- | --- | --- |
| `myl_core_durable_access` | Borrows cap/path/input; produces fresh result, error text, read bytes or listing. A successful lock produces a resource borrowing the cap. | Only lexical lock scopes rooted in named capabilities may own the dependent resource. Ordinary read/list/error values are independent. |
| `myl_core_resource_acquire` | Copies request bytes into bounded provider scratch for the synchronous acquisition; produces a fresh result and resource on success. Provider callback cannot retain scratch. | The resource borrows the cap, which must survive every normal/error completion or destructor. |
| `myl_core_resource_read` | Borrows resource; allocates fresh zero-padded byte storage and result box, copies provider scratch before freeing it. Failure also owns its result/padded buffer. | Complete result cleanup, and live cap/resource through provider call. |
| `myl_core_resource_write` | Borrows resource and input; copies bytes to provider scratch, frees scratch synchronously, returns a fresh scalar result box. | Provider may not retain the scratch. |
| `myl_core_resource_complete` | Borrows resource memory; successful provider completion closes/unlinks its handle and returns a scalar. Failure leaves the handle open. | Guest completion consumes the source resource on success and transfers it into the failure payload on failure; resource memory still needs direct destruction once. |

No entries above were added to `zero_rc.contract` by A05. They require A07's source/IR/lowering audit as well as native paths. In particular, network `Connected` and `Closed` values carry resources through results, which the current prototype does not generally admit. Merely adding these helper names would not make that safe.

`core_durable_access` checks authority before opening paths, closes each parent descriptor, frees temporary read buffers, directly destroys partial listings on errors, and does not retry another root after a rename with uncertain directory sync. Directory leases use the same registered resource cleanup as files. Native durability is intentionally unavailable for `filesystem.memory()`; local dedicated directories are used for qualification instead.

Dictionary replacement destroys the old managed value; pop distinguishes transferred key/value fields from destroyed fields. Independent dictionary copies deep-copy managed children in zero-RC; the RC cloning branch remains pending retirement. Keyed owned sort consumes independent source/key storage and returns the permuted source; its temporary native scratch is freed and its managed key copy destroyed. Neither native scratch nor provider buffers are fully represented by managed allocation counters.
