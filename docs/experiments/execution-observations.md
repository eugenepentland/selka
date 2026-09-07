# Execution observations and host replay

Embedding clients can set `vm.Options.memory.trace` to a caller-owned
`vm_trace.Trace` with a fixed event buffer. Events record source/function/PC,
instruction name and the top operand before execution. Branch instructions
therefore expose their Boolean condition. Aggregate/owner values expose type
identity only. Full buffers count omissions and do not alter instruction budgets
or retain guest allocations. The compilation supplies source mapping and must
remain alive while interpreting its events. This is a bounded debug sample, not
a proof of causality or a complete replay stream.

`host_replay.Transcript.wrap(name, binding)` wraps an explicit provider before
normal registration. Run once to record, close the session, call `finish()`, then
`replay()` and run again. Call `finish()` after replay: it rejects missing calls.
The adapter compares ordered names/argument fingerprints and the checked schema,
replays deep-copied values or callback failures, and charges recorded cooperative
work without repeating provider effects. Extra, reordered or changed arguments
produce `HostReplayMismatch`; incomplete recordings cannot be replayed. Caps and
allocator failures invalidate recordings that did not capture an outcome.

Transcripts are bounded, in-memory, single-threaded objects pinned to one checked
record schema. They are not portable source-change receipts or sanitized logs.
Close all registrations before destroying the transcript, and keep the checked
compilation alive. Callback effects during the recording are ordinary effects;
recording does not roll them back. Existing grants, boundary validation and VM
budgets remain active. Allocation-failure tests cover partial transcript storage
and mismatch cleanup. Persisted test-provider files and broader property-law
experiments remain separate work.
