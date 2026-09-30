# WP-B3: LLVM induction result continuation

Source checkpoint: `178dad48c1eb76ec4124923589294f0b8ed57bfe`, based on
`cfee0070`. This is a scoped functional and code-shape checkpoint. Root owns
combined dev/full instruction acceptance, all 258 output comparisons, and the
final integration gate; this audit does not substitute simulated profiles for
those measurements.

## Observed float-loop cost

Symbol-preserving A5, publication, plain-query and targeted LLVM3/full-LTO
relinks matched every allocated section of their frozen original executables.
CPU 0 Callgrind runs went through the build slot, with no hardware timing claim.
All three profiled arms printed `4472024148`.

| Arm | Whole executable instructions | `entry_run` self instructions |
| --- | ---: | ---: |
| A5 | 164,311,098 | 164,000,173 |
| Plain-query | 164,308,445 | 164,000,173 |
| Targeted constant-overflow | 168,308,459 | 168,000,173 |

The targeted arm adds exactly 4,000,000 guest instructions: its five-way
unrolled loop tests the exit at the top and executes an extra unconditional
backedge. Its source QBE IL is identical to the plain arm. The LLVM IR delta
replaces the ordinary counter add and explicit bound with the overflow
intrinsic's result and flag. Bounds disappear in both optimized executables;
the added dynamic cost is the backedge, rather than an executed overflow check.
The optimizer's reason for choosing that layout is an inference, not a proven
compiler-internal cause.

## Frozen change and its proof boundary

`qbe_loop_facts.inductionAt` recognizes a unit counter update immediately before
the same counter's store and backward jump, with its matching header comparison
and exit. `qbe_scalar` writes a per-function `myl-affine` comment naming that
arithmetic producer. The LLVM translator uses the comment only after its existing
signed64, nonpointer, literal-bound proof succeeds. It emits the original ordinary
wrapped add/sub result and still obtains the overflow flag from the intrinsic.
There is no range, alias, capacity or cache authority in this hint. False/manual
hints retain the same mathematical result and flag. No load, call, branch, cleanup,
trap operand, `nsw` or `nuw` is introduced or removed.

The counted float loop now has the plain/A5 normalized loop body and conditional
latch. It prints `4472024148`; its sole new QBE comment is ignored by QBE, whose
actual assembly is byte-identical to the unmarked unit. All 410 Lox units also
have identical source IL after removing 37 comments and identical QBE assembly.
The actual LLVM VM unit is byte-identical to the frozen cfee control: MIN has
zero loads, MIN+1 has one, MAX-1 and MAX have zero, and all 76 `jo`/`jno` sites
remain. Its 32 subtract and 48 add intrinsics remain, and invocation prints
`30000`. These are static code-shape and output gates, not quantitative acceptance.

Installed tools remain frozen in the owned induction worktree:

- `mylang`: `f597868b0a961e75911442d4ff91499d6cfd53a6298bc84fe53e5314c2dec090`.
- QBE: `f5883ad202ecaff8d29e3846da020af7e358434de18a3ed7348f5b94d192434e`.

## Retained excluded experiments

| Experiment | Observed boundary | Disposition |
| --- | --- | --- |
| Ordinary results for every matched unit bound | Float latch restored; VM MIN loads 0→88 and overflow branches 76→8 | Rejected |
| Ordinary results for upward forms only | VM MIN remains 0, but MAX loads become 25; dynamic MAX loads 7,560,085 | Rejected |
| Feed the proved ±1 literal into the intrinsic RHS | VM MIN/MAX/overflow sites preserved; float retains the extra backedge | Excluded; no float improvement |

The upward trial's whole invocation instructions rise from 1,489,627,111 to
1,505,650,812, and VM self instructions rise from 591,499,382 to 598,729,286.
Both print `30000`. The control's symbol counterpart matches all 26 allocated
sections of its frozen original. These receipts explain rejection; none is an
accepted source or hardware sample. Their source patches, tool identities,
actual IR/assembly and raw profile receipts are retained separately from 178dad48.
The old worktrees and installed tools remain evidence and were not cleaned.

## Scoped verification and Guardian

All builds and guest runs used the build slot and this worktree's disk TMPDIR,
local cache and global cache. Focused runs pass 16 induction tests (four named
cases plus the harness blocks), 15 prior constant-overflow tests, 13 tests including
the complete LLVM golden corpus, and three CLI tests including the existing
all-width checked-arithmetic matrix. The structural fixtures cover all four unit
math forms, 17 broken/interior shapes, actual latch versus interior emission,
manual hints and refusal of missing literal/width/pointer authority.

The green install passes all 12 build steps and 88 diff-scoped Guardian checks;
the ordinary source commit passes all 88 whole-tree checks. Two development
install attempts were excluded: `spec` verification refused the new tag before
its tests were run, and `formatting` plus `repeated-string-literal` requested
formatting and shared test constants. The earlier all-producer experiment also
needed one install retry after `repeated-string-literal` found a duplicated
arithmetic format string. These cost three gate cycles; no unknown duration or
successful use of a stale failed-install binary is claimed.

Root committed the required [Guardian feedback log](/home/epentland/ai/canopy/guardian-zig/FEEDBACK.md)
entry as `22080f7b8c23a5c3e17859de0f223c1b26c0b937`, including the
checks, three excluded-trial gate cycles and combined text-row failure. This lane
did not append a duplicate entry.

## Independent review and combined disposition

Typing reviewed the exact source and installed tool identities in a fresh owned
worktree. Both control and candidate pass 400,856 separate result/flag assertions
at each of O0 and O3 under UBSan across 190 valid units: 182 literal/slot/copy,
hint-parser and refusal units plus eight general signed/unsigned formula controls.
The 60 admitted manual hint choices keep the intrinsic flag; the other 122 main
outputs and all eight general-formula IRs are byte-identical to cfee. The prior
54 admission decisions (19 positive/35 refusals) and 43 executable functions with
215,602 assertions also pass unchanged. Eleven malformed raw cases are admission
checks only. An independent eight-function source fixture verifies four latch
directions versus interior/non-unit/narrow updates, unchanged QBE assemblies, and
matching actual QBE/LLVM guest outputs. No actionable defect was found.

The independent receipt SHA-256 is
`0099070193f204a067afbdb07e7ddb86eba218c206080024af0533dda33320e0`.
Root verified all 895 member hashes, and this lane independently verified them
again while archiving. That is an additional integrity check, not repeated test
execution. The review's initial guessed CLI flags returned usage status 2; its
corrected actual flags and successful checks remain alongside that excluded log.

Root's frozen combined 5535 checkpoint matches all 258 outputs and passes every
dev row and cap, resolving the earlier float, raytrace and Lox failures. It is
still quantitatively rejected: full LLVM `text_ops` is +1.167106% against approved
A5. Same-binary executions vary by approximately four million instructions, and
a fresh pinned A5 control also shows that variation. No passing sample was
selected to waive the failure. Root retains the raw failed stage and control in
its runtime evidence commit `f7cc661a`; final combined acceptance remains open.

The read-only text follow-up bounds hint scope to six literal-bound producers:
two in `text_ops::main` and one each in `strings::table_index`, `all_in`, `lines`
and `ord`. Their actual build IL is unchanged apart from comments, and all six
switch only wrapped-result lowering while preserving the intrinsic flags and
branches. This is static scope evidence, not attribution of the variable native
path. The initial raw `emit-qbe` import refusal and corrected project emission
are retained; no text hardware/profile or executed output is claimed by this lane.

The durable raw bundle, independent review and verified member inventory are in
`experiments/wp-b3-layout-20260929/llvm-induction-result/`.
