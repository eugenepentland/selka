# Cache-plan retained owner reduction

Compiler: support5 source `a1f19edf255c8c0886731d8d7cce450d5f657720`, SHA-256
`8b1898be7ad2f95cf53bf709f9d468b3bcfbabcaab2aaa7b5aa48d0163b2a789`.
This is a reproduced in-scope lowering defect, owned by A07, not a passing
application or a proposed source workaround.

`original-raw.ir` is the full cache-plan Core dump before release passes;
`original-raw-close-group.ir` extracts the failing function. It has no retains.
The previously recorded support5 facts dump introduces a retain on `%45`, the
record after `closures.group_seen[group] = generation`, before a real loop phi.

`standalone.my` extracts the same close_group body, records and work check into
one executable fixture. It still retains `%45`. `small-one-loop.my` reduces the
ownership shape to a 19-line program: record with `seen: int[]` and
`generation: int`, a captured generation scalar, a pre-loop list-field write,
and a subsequent loop updating the same field. Its source SHA-256 is
`237ea7fc27ae17b8d2f41d3952c6714e9a289e7587a2fb2ec8c5b07e7209fe8e`.

| Probe | Observed retain after release passes |
| --- | --- |
| Standalone original body | `%45` |
| Remove all `try check_work` calls | `%45` |
| Remove completed-state branch | `%45` |
| Remove only pre-loop list-field write | None |
| Small graph traversal | `%24` |
| One simple loop and captured scalar field | `%22`, plus inlined caller `%66` |
| Replace captured field scalar with constant 1 | None |
| Replace captured field scalar with scalar argument | None |
| Keep captured field scalar but remove generation increment | `%18`, plus caller `%62` |
| Single list-field record and constant scalar | None |

Feature-removal probes are diagnostic experiments, not semantic migrations of the
component. The ordinary-mode control for `small-one-loop.my` builds and runs with
both no arguments and one argument, returning 0 and printing `1\n1 1\n`.
Its binary SHA-256 is
`029fa4ad92e3ae173c60e29d031632482a58c928ddc6b4e6afad554c1e9da84f`.
The same source's checked zero-RC release build refuses at line 8 with
`E_ZERO_RC_LOWERING`. `minimal-results.json` records both exact commands and the
successful ordinary execution. `dump-ir` success is diagnostic generation only;
the native build refusal remains authoritative for guest admission.

A07's independent phase-B instrumentation identifies the extra borrow introduced
by `borrow_fields.forward`: a captured scalar field read is reanchored to the old
record within the loop, extending its lifetime. Later simplification eliminates
the scalar read after ownership already inserted the retain. Captured scalar
values are independent; A07 is qualifying a narrow forwarding correction while
preserving managed/memory borrow behavior. No additional phi rewrite is proposed.

All commands ran through bounded ordinary build admission. Their incidental elapsed
values are not timing measurements. A corrected integrated compiler must rerun the
real cache-plan protocols, not only this reduced source.
