# Owned ledger maintenance sequence v1

This application summarizes exactly four signed integers. Inputs are in
[-100,100]; floor and ceiling are in [-100,100], with floor <= ceiling. Arithmetic
fits i64. Entries equal to floor are accepted. Allocation or append errors must
propagate through model.Answer. No capabilities other than the supplied allocator
are available. Preserve owned buffer allocation, the generic append helper and
its mutable borrow, and the model/ledger/report module boundary.

Edit only ledger.my, model.my and report.my. Do not edit tools, cases, compiler,
dependencies or task instructions; do not replace the application with constant
answers or test-specific behavior. Use language checking, run and navigation
commands. All commands, including reads, edits and public checks, must use the coordinator command gateway. Direct filesystem/tool access is a protocol violation. Each stage allows
20 tool invocations, 5 edited submissions and 15 minutes; the gateway records every invocation and candidate check, including failed checks. Use the check operation after each edited candidate; unchanged checks consume tool invocations but not edited submissions. Start each new stage from your own
sealed prior-stage submission. An unfinished stage remains an observed failure;
do not substitute another participant's solution.

Stage 2 — feature: add ceiling:i64 after floor to both summarize and report.score.
For each accepted original entry n >= floor, add min(n,ceiling) to total. Count
accepted entries, including entries whose value is capped. Keep the same Reply
fields and report encoding. When ceiling=100, all stage-1 behavior is preserved.


Run every command through the coordinator gateway. Use its check operation for public cases.
