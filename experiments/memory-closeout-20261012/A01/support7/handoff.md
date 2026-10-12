# A01 Support7 handoff

Compiler source: `bed11cf3bf3102ffec44487e431a1573fdf02ad5`.
Compiler SHA256: `540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.
Evidence worker base: `ff99f6e1c03d552ef6336739919f39c5f9fed9df`.
Proposed commit: coordinator records the resulting evidence commit.

Owned changes are only this evidence directory, two native/control orchestration
scripts, frozen fixture/harness copies and the appended A01 handoff section.
No production or shared source changes requested.

Pass: counted source: 30 builds / 90 executions + 8 refusals; source TSan: 4 builds / 12 executions;
native scheduler: 2 builds / 12 executions including counted at 1/2/8 and TSan at 8. All 75 successful
counted guest runs and all successful counted native scheduler runs have RC0/live0.
Deliberate traps/refusals remain diagnostic lanes. Structural LLVM/symbol audits
pass. The ordinary RC tuple control separately passes with 2 retains / 6 releases / live0;
it is explicitly excluded from zero-RC qualification.

Exact commands, source/compiler/runtime/binary hashes and raw outputs are in
`inputs.json`, `installation.json`, `summary.json`, `sha256.json`, and `raw/`.
README.md lists frozen case/mode coverage, admission rules and reproduction paths.
No source or runtime failure was encountered in these lanes. Guardian status for
the evidence commit is reported by the normal commit hook.

Unresolved release work belongs to the coordinator and other owners: full combined
release inventory/gates, C1 freeze and paired measurement, C2 default promotion,
C3 actual legacy removal and final installed-package qualification. These scoped
A01 passes do not complete those milestones. The retirement drafts stay unapplied.
