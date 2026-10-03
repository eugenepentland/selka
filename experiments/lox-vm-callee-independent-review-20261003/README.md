# Independent VM callee and composition review

The reviewed VM callee descriptor has no actionable source defect. This is a
read-only review of the frozen VM 83-test source and root's composed 84-test
source, recorded by hashes in `review.json`. The reviewer did not author the VM
change. The review excludes the reviewer's own table probe implementation and
parameter changes from independent semantic approval; those were checked only
for expected composition bytes.

`NativeObj` is two integer fields. `BoundMethodObj` is a plain `Value` receiver
and integer method index; `Value` contains nil, bool, float, or integer ObjRef.
Consequently every `VmCallee` variant is plain data. The readonly object-table
projection ends when `vm_callee` returns, before a handler mutates Runtime.
Neither that descriptor nor a mylang object carrier creates a root in Lox's
collector. The source keeps the established Runtime roots instead.

The class path preserves allocation and error order: the class callee and every
argument remain on the Lox stack across `heap.allocate`; the new instance then
replaces the callee in its original stack slot before initializer lookup.
That instance roots its class through `heap.blacken`. The initializer remains
in the class method table. The unchanged `call` checks arity before the Lox
frame limit and publishes the closure in `Runtime.frames` before execution can
allocate. A missing initializer still checks zero arity after instance
allocation. These handlers are copied without reordering their actions.

Bound dispatch first installs the copied receiver into the callee stack slot,
then invokes unchanged `call` with the copied method index. Classification,
stack replacement, arity reads, and frame publication contain no Lox object
allocation, so retiring the bound object from the stack cannot create a gap
across Lox collection. Closure dispatch preserves the original closure index;
native dispatch checks its copied arity before invoking the native and retires
arguments only after obtaining the result. Invalid scalar and object kinds
reach the same ordinary non-callable error after argument evaluation.

Adjacent publication paths remain unchanged. `make_closure` keeps captured
upvalues in the open list or executing closure, publishes the completed
closure, then roots it on the stack. `define_method` writes the closure value
into the class's method table before popping its stack root. Binding keeps the
receiver on the stack while allocating the bound object. The native capability
implementation, allocation/cost/threshold code, stack range, frame roots,
snapshots, and normal indexed COW writes receive no changes from this VM arm.

The integration audit verifies all 37 final VM files against the author's frozen
descriptor and all 37 combined files against `combined.json`. The combined VM
is exactly the author's VM plus the expected global lookup argument projection.
Its driver tests and provider JSON are exactly the VM arm's versions. Every
existing provider remains intact, and all three new callee regression providers
are present. The composed source contains 84 public tests. Relevant author
regressions cover saved Runtime snapshots through all callee kinds, inherited
initializer arity errors after argument side effects, and invalid object callee
errors after argument evaluation. The author qualification receipt is hashed;
this review does not claim an independent test rerun.

Limits: source helper calls retain normal compiler frame/root admission, so
identical optional native frame/step quota cutoffs are not claimed across this
source reshape. No admission or semantic checks are relaxed. Exact Lox handler
errors and action order are preserved. The plain-reference argument relies on
the current roots and absence of allocating callbacks in classification/frame
publication; such a future change would require another review.

`composition-at-review.json`, `vm-final-descriptor-at-review.json`, and
`vm-callee.diff` preserve provenance. No compiler, source candidate, root
manifest, measurement, or benchmark input was modified.
