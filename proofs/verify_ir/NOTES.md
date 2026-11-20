# The IR verifier in Lean: notes (lane VL, stages V1 to V4)

The rule table (each rule of `src/core/verify_ir.zig`, its Lean rule, and the hypothesis it serves), the mutation classes
of the differential, where the Lean copy differs from the Zig verifier, and the findings. Line numbers are those of
`verify_ir.zig` on branch `proofs/verify-ir-lean` after the V1 fixes.

"H2" is `ModWf` / `SsaWf` of `proofs/facts` (every use dominated by its definition); "TY" the typed machine of
`proofs/facts` (TY1 to TY3: a step's value has its instruction's type, operations read operands of the kinds they need);
"A17" the trust point of `proofs/ownership` (a function value points to a function with its type's signature). "None:
hygiene" marks a rule neither theorem takes as a hypothesis.

## The rule table

### Module and declarations

| Zig rule | Line | Label | Lean | Serves |
| --- | --- | --- | --- | --- |
| Every type a compound names is a type of the module (new, F-VL-4) | 142 | `type-table` | `Module.namesValid` | none: robustness |
| Borrowed equality declarations and descriptor types (`build_equality.validateModule`) | 148 | `equality` | **not mirrored** | none: hygiene of a compiler marker |
| No compound stores a view: list, box, overlay, dictionary, array, record or union outside transit, function type; except a task thunk's environment and its record, whose borrowed fields are all views (FR58, the user's decision of 17 November 2026). Both checkers find the thunk by its generated name (`<task.thunk.`, `stable_names.generatedRole`), not by a signature, so the exception is closed to source, not to hand-made IR. Mutants `view-storage-box` (a box of a span no thunk takes) and `view-storage-task-field` (a thunk's environment with an overlay field) are refused by both | 155 | `view-storage` | `Module.escapes`, `Module.taskEnvironment` | none: hygiene (views are SSA only, C9, except the one a task's environment holds; `proofs/ownership/AXIOMS.md` A7.2) |
| Provider pin marker declaration (`aggregate_provider.marker`) | 184 | `marker-provider` | **not mirrored** | none: hygiene (no build emits it since 5C) |
| Borrowed provider declaration (`borrowed_provider.declaration`) | 188 | `marker-borrowed` | **not mirrored** | none: hygiene (no build emits it) |
| Selection marker declaration (`borrow_selection.declaration`) | 192 | `marker-selection` | **not mirrored** | none: hygiene of a compiler marker |
| Parameter types are the module's; a span convention only where admitted; a borrow only in a read-only parameter | 196 | `param-type` | `Module.checkHeader` | TY (a parameter's type), ownership's read-only parameters |
| Result type is the module's; passing conventions in range and disjoint; no span convention on an internal function | 205 | `result-type` | `Module.checkHeader`, `Passing.valid` | none: ABI hygiene |
| The declared borrow contract is well formed (`ir.Module.validBorrow`) | 212 | `borrow-contract` | `Module.validBorrow` | ownership's J1 `call-from` reads it; not a hypothesis |

### Structure of a body

| Zig rule | Line | Label | Lean | Serves |
| --- | --- | --- | --- | --- |
| A function with a body has blocks | 383 | `no-blocks` | `Fn.structure_` | H2 (an entry exists) |
| The entry block has no predecessors (new, F-VL-2) | 385 | `entry-preds` | `Fn.structure_` | H2's phi model; `proofs/facts` checks it itself (`entryOK`) |
| Every branch and jump target exists (in the reachability walk) | 442 | `target` | `Fn.reach` | H2 (`cfgSucc`) |
| A reachable block is not empty | 394 | `empty-block` | `Fn.listing` | H2 (a block ends in a terminator) |
| A listed reference names an instruction | 397 | `listed-range` | `Fn.listing` | H2 |
| An instruction is listed once | 398 | `listed-twice` | `Fn.listing` | H2 (one definition per value) |
| A block ends in its only terminator | 402 | `terminator` | `Fn.listing` | H2 (`Block.term`) |
| Phis come first | 405 | `phi-order` | `Fn.listing` | H2 (the phi model) |
| A phi has one operand per predecessor | 407 | `phi-arity` | `Fn.listing` | H2 (`SsaWf.phi`; facts' `phisOK`) |
| Each edge appears in its target's predecessors as often as the terminator names it | 460 | `edge-preds` | `Fn.edges` | H2 (predecessors are the reverse edges; facts' `edgesOK`) |
| A predecessor exists and, when reachable, branches here | 463, 467 | `pred-edge` | `Fn.edges` | H2 |
| Dominators (Cooper, Harvey and Kennedy) | 470 | none | `Fn.computeIdom` then **verified**, `Fn.treeOK` (`dom-tree`) | H2 (`TDom`) |

### Instructions

| Zig rule | Line | Label | Lean | Serves |
| --- | --- | --- | --- | --- |
| Every constant and parameter of the table is checked (was: only `func_ref`; F-VL-1) | 365 | (its rule) | `Fn.checkBody` | TY1, A17 |
| The result type is the module's | 667 | `type-valid` | `Fn.signature` | TY1 |
| The extra operand slice lies in the function's list | 670 | `extra-range` | `Fn.signature` | none: robustness |
| An operation that reads only its extra list (print, record_make; a call's `b`) has nothing in `a` or `b` (new, F-VL-8) | 684 | `unused-operand` | `Fn.signature` | H2 (the certificate reads those fields as registers) |
| Every value operand exists | 675 | `operand-range` | `Fn.signature` | H2 |
| Every value operand's forwarding chain ends in a value (new, F-VL-4) | 679 | `dom-forward` | `Fn.signature` | none: robustness |
| Every value operand has a type of the module (new, F-VL-4) | 680 | `operand-type` | `Fn.signature` | none: robustness |
| A view is made only at the boundary, as an undefined constant, or by a view operation, a copy, a phi or a projection | 704 | `view-def` | `Fn.viewDefOk` | none: hygiene (C9 views) |
| A view is read only in place: per family (text, bytes, list) the operations, positions and parameters that admit it | 710 | `view-use` | `Fn.viewUseOk` | none: hygiene (C9 views) |
| A `dict_insert`'s probe is a `dict_find` of the same dictionary and key | 692 | `insert-probe` | `Fn.insertProbe` | none: runtime protocol |
| The signature of each of the 92 operations (below) | 694 | `signature` | `Fn.sigOk` | TY1-TY3; A17 (`func_ref`, `call_indirect`, `param`, `undef`) |
| A call to a selection or provider marker has the marker's exact operand shape | 1020 | `signature` | **not mirrored** | none: hygiene of compiler markers |
| A union payload is read only where the tag facts confine its value's tag to the case it reads (new, V4, F-VL-10; `verify_union_tags.zig`); a `list_get` value is shape M, counted | after the instructions | `union-tag` | `Fn.unionTags` (`TagFlow.lean`), then **verified**, `Fn.tagOK` (`tag-facts`) | A17's V7 (`payload_of_verdict`) |
| A returned borrow derives from a declared argument or final owner (`borrow_result.valid`) | 697 | `borrow-result` | **not mirrored** | ownership A18's backstop (not a Lean statement) |
| A shallow copy never duplicates managed children (zero-RC) | 372 | `shallow-copy` | `Fn.shallowManagedCopy` | none: ownership hygiene |
| An operand is available where it is read: a constant no block lists anywhere (a listed one follows dominance, new, F-VL-7); else listed in a reachable block, earlier in the same block or in a dominating block; a phi operand at the end of its predecessor | 560 | `dom-undefined`, `dom-order`, `dom-block` | `Fn.available`, `Fn.dominance` | H2 (`SsaWf.inst`, `.phi`, `.branch`, `.ret`) |
| `available`'s `missing operand`, `does not exist` | 562, 563 | `dom-missing`, `dom-range` | `Fn.available` | dead in `verifyModule`; live for `verifyPlan` (F-VL-6, below) |
| `verifyPlan` (vector plans), `writtenCopies` (rule C) | 271, 61 | none | **not mirrored** (plans are not exported; rule C is not part of `verifyModule`) | none of the two proofs |

### The operation signatures (`sigOk`, `Rules.lean`)

Mirrored one for one, by family: buffers (`buffer_new`, `buffer_copy`, `buffer_pop`, `buffer_push`, `buffer_set`,
`buffer_append`); shifts and saturation; float extras (`float_unary`, `float_fma`, `vector_select`); dictionaries (12
operations); text (`str_char` to `text_frame`, 13 operations); arrays (`array_get`, `array_set`, `array_from_bytes`);
function values (`func_ref`: the type is the named function's signature and that function is internal; `call_indirect`:
a function-typed callee of internal linkage, the call's result and arguments are the type's); constants (`param` at its
signature's type, `iconst` an integer, Boolean or capability token, `fconst` a float or float lanes, `str_const` text or
bytes, `undef` holding no function type, `text_sentinel` text or a list); `borrow`; arithmetic, bit operations,
comparisons (lanes give a mask of the operands' length; function values compare for equality only), float arithmetic and
comparison, conversions, `bitcast`; lists (11 operations, field paths through `pathTarget`); unions (`union_make`,
`union_tag`, `union_payload`, `union_take`); records (`record_make` of a record or an inline array, `record_get`,
`record_take`, `record_set`); boxes and frames; `drop`, `err_trace`; `call` (each argument the parameter's type, or a span
for a text or bytes parameter that admits it, F-VL-9); `print`, `jump`, `branch`, `ret`, `unreachable`.

### Checks only the Lean checker's verdict has (the objects of the proofs)

| Lean check | Label | What | Read by |
| --- | --- | --- | --- |
| `Skel.ssaCheck` on `Fn.translate` (`Ssa.lean`) | `ssa-skeleton` | the SSA rule on the fact certificate's form, with the body's tree: reached set closed, tree parents ancestors of predecessors, every read available | `modWf_of_verdicts` |
| `Module.freeOK` and `Fn.typedCheck` (`FnValues.lean`) | `typed` | the function-free table is a fixed point; every constant and every listed instruction of a reached block satisfies its signature, and a constant made from nothing has a function-free type | `a17`, `reaches_holds` |

Neither refuses anything the mirrored rules accept, on the corpus or on any mutant (measured, 11 November); they restate
what the mirrored rules already check in the forms the proofs read.

### Candidate rules only the Lean copy has (`irverify --strict`)

| Lean rule | What it requires | Corpus | Why not in Zig |
| --- | --- | --- | --- |
| `strict-unused` | an operation that does not read `a` or `b` (jump, phi, call's `b`, print, record_make) has none there | clean | since F-VL-4 no rule reads those fields; hygiene only |
| `strict-lanes` | a Boolean `fcmp` reads scalars, a lane `fcmp` and a `vector_select` mask are as long as the lanes | clean | LLVM's verifier refuses a mismatched emission; hygiene |
| `strict-extern-fn` | a function without a body returns no value holding a function type, unless it takes one of its result type | clean | the runtime's deep copies return function values they were given; V2 states it as a trusted contract |

Counts: 47 labelled rules of the Zig verifier, of which 40 are mirrored and 7 are delegated and not mirrored
(`equality`, three marker declarations, the marker calls, `borrow-result`, and `verifyPlan`/`writtenCopies`, which
`verifyModule` does not run); 92 operation signatures mirrored; 3 Lean-only candidates. V4 adds the union-tag rule
(mirrored) and its Lean-only verified check (`tag-facts`).

## Mutation classes (`scripts/verify_ir_mutants.py`)

Each class edits one function (or the type table) of a corpus program so that it breaks one rule, and names the rule
both checkers must report. Sites are chosen deterministically (files in path order, functions in module order, sites in
instruction order, at most one per function and six per class).

Structure: `no-blocks`, `target`, `empty-block`, `listed-range`, `listed-twice`, `terminator`, `phi-order`, `phi-arity`,
`edge-preds`, `pred-edge`, `entry-preds`, `last-ref` (a block's last reference out of range: `listed-range`).
Types: `type-valid`, `extra-range`, `operand-range`, `operand-type`, `type-table`, `view-storage`, `param-type`,
`result-type`, `borrow-contract`. Signatures (each `signature`): `retype-result`, `call-argument`, `ret-value`,
`branch-condition`, `phi-operand`, `record-make-field`, `list-push-element`, `drop-unmanaged`, `record-field`,
`union-tag`, `func-ref-signature` (a `func_ref` naming a function of another signature: A17), `call-indirect-argument`,
`call-indirect-callee` (A17), `param-signature` (a parameter read at another type), `constant-type` (a `str_const` of
type `i64`), `span-argument` (a text span passed for a list-view parameter), `span-admission` (an external function's
span convention on an `i64` parameter: `param-type`), `unused-operand` (a value in a print's `a`). Views and probes: `view-def`, `view-use`, `insert-probe`, `shallow-copy` (no site in the corpus).
Dominance: `dom-order` (a use moved before its definition), `dom-block` (an operand replaced by a value of a block that
does not dominate the use), `dom-undefined` (a definition unlisted while its users remain), `copy-none` and `copy-cycle`
(`dom-forward`), `listed-constant` (a constant listed after its use: `dom-order`). Union tags (each `union-tag`, V4):
`tag-read-moved` (a payload read moved out of its guarded block into the block that tests), `tag-false-edge` (a tag test's
branch targets swapped: the read on the false edge, or another case's read under this case's branch), `tag-other-value`
(the test's `union_tag` reads an `undef` of the same union: the guard on a different value), `tag-equal-false-edge` (the
read of `b` on the false edge of `tag(a) == tag(b)`), `tag-third-value` (one side of `tag(a) == tag(b)` reads a third
value). Each skips a value that is a `union_make` (its own case justifies its reads whatever the test).
`tag-field-twin` and `tag-field-store` (the `record_get` of a read justified by shape R or S reads an `undef` record of its
type), `tag-phi-operand` (the first operand of a `phi` a read reads becomes an `undef`: shape P). Lean only:
`strict-unused` (both mirrored checkers accept).

## Deviations of the Lean copy from the Zig verifier

* **Totality.** Every Lean function is total. Where the Zig code indexed the compound table with a type it had not
  checked, Lean answers "not a compound of that kind". After the V1 fixes (F-VL-3, F-VL-4) the Zig verifier never reaches
  such an index on the inputs the rules let through, so the answers agree; the differential and the robustness mutants
  check it.
* **Dominators are verified.** `computeIdom` is the Zig algorithm; `treeOK` then checks the tree (root, parents reachable
  and one level up, each block's parent an ancestor of each reachable predecessor) and only the checked tree is read. A
  failure is `dom-tree`, which a correct computation never gives and the Zig verifier has no counterpart of. V2 will use
  `treeOK`, not the algorithm.
* **Fuel.** Walks over the type graph and copy chains carry fuel of the table's size; the walks that remember their path
  never need more.
* **Names stay escaped.** Lean prints a function's name as the text spells it; the Zig command re-escapes the name it
  read, which is the same text for every name the compiler writes.
* **Not mirrored**: the delegated rules in the table above. Both checkers accept every corpus module, so the
  differential cannot tell; no mutant targets them.

## Findings (`experiments/verify-ir-lean-20261111/DECISIONS.md` has the repros)

* **F-VL-1, hole (TY1, A17).** Constants and parameters are defined outside every block, and the Zig verifier checked the
  signature only of listed instructions and of `func_ref`. So a `param` read at another type than its signature's
  parameter, an `fconst` or `str_const` of any type (their rule was `true`), an unlisted `iconst` of any type, and an
  `undef` of a function type were accepted. A17 needs "a function value is made only by `func_ref`"; TY1 needs a constant
  to fit its type. **Fixed**: every constant and parameter of the table is checked, `param` reads its signature's type,
  `fconst` is a float or float lanes, `str_const` text or bytes, `undef` holds no function type. The corpus is clean
  under the tightened rules (18,887 functions).
* **F-VL-2, hygiene.** An entry block with predecessors was accepted (its phis would have no operand on entry).
  `proofs/facts` refuses it itself (`entryOK`, its finding 1). **Fixed** (`entry-preds`).
* **F-VL-3, robustness.** The Zig verifier panicked (index out of bounds in `Module.kind`) when a caller passed a view to a
  callee whose parameter type is not in the table, when the caller's body is verified before the callee's header.
  **Fixed**: the view-admission rules ask kinds only of valid types (`validKind`).
* **F-VL-4, robustness.** The Zig verifier looped for ever on a copy cycle, panicked on a copy forwarding to nothing, on a
  block whose last reference is out of range (in the reachability walk, before the listing check), on a jump with a
  stray `a`, and could reach `Module.kind` on a type the table does not have. **Fixed**: bounded resolution (`resolved`),
  every value operand must resolve (`dom-forward`) to a value of a module type (`operand-type`), `a` and `b` are typed
  only where they are value operands, successors ignore an out-of-range reference, and the table may name only its own
  types (`type-table`).
* **F-VL-5, inconsistency.** `iconst` of type `cap` (a stream handle) is emitted unlisted by every program that prints to
  standard error, and would have been refused had it been listed. **Fixed**: `iconst` admits `cap`.
* **F-VL-6, dead rules.** `dom-missing` and `dom-range` cannot fire in `verifyModule`: `dominance` runs on an instruction
  only after its `signature`, which refuses a value operand that is absent or past the table (`operand-range`) and one
  whose forwarding chain ends in nothing (`dom-forward`), and a phi's operands are value operands. They guard `verifyPlan`,
  whose plan values are not instruction operands. Recorded, not changed.
* **F-VL-7, hole (H2).** The verifier exempted every constant from dominance, but the fact certificate describes a
  constant that a block lists (a comparison the facts folded) as an instruction of that block, and `SsaWf` asks its uses
  to follow dominance. A use before a listed constant was accepted (the V1 compiler accepted six of six
  `listed-constant` mutants). **Fixed**: only a constant no block lists is exempt.
* **F-VL-8, hole (H2).** The certificate lists every field of `a` and `b` as a register an instruction reads; for a
  print, a record constructor and a call's `b` no rule read them, so a stray value there was never checked for
  dominance (six of six `unused-operand` mutants accepted). **Fixed**: those fields must be empty (`unused-operand`).
* **F-VL-9, hole (A17).** A call accepted a text span or bytes argument for any parameter the callee admits as a view,
  including a list view, which may hold function values. **Fixed**: the span exception holds only for a leaf parameter.
  Test "a text span is not an argument for a list-view parameter".
* **F-VL-10, unenforced (A17); enforced in V4.** A union payload is meaningful only under its own tag, and nothing in the
  compiler's checks said a `union_payload k` or `union_take k` runs only when the tag is `k`. V4 adds the rule
  (`union-tag`) to `verify_ir.zig` and the copy, and proves it sound for the tag semantics (`payload_of_verdict`); V7 is
  narrowed to the link between that semantics and A17's `Reaches`, and to the shape M reads (`AXIOMS.md`).
* **F-VL-11, regression caught before landing (V4).** The first V4 rule tracked unions of at most 64 cases and refused
  every payload read of a wider union: a 70-case `enum` matched in a debug build was an internal error
  (`E_CORE_INVALID_IR`). Sets of cases are now bit sets of any width (`Bits` in Zig, a natural number in Lean). Tests: "a
  union of more than 64 cases is read under a test of its own tag" and `tests/lang/wide_union_match.selka`.
* **F-VL-12, regression caught before landing (V4).** The first V4 freshness (a tag read made away from the test counts
  when its value's block is on no cycle) refused compiler output, a `match` after a loop on the loop's phi (`zero_rc_test`,
  found by the edit check). Fresh tag reads are now a must-fact of the dataflow (made where a block lists the read, ended
  where a block makes its value again). Test "a tag read away from its value's block counts while the value is not made
  again after it".
* **F-VL-13, false refusals in the real projects (V4, second round).** The rule refused 39 protobuf decoders and two port
  functions, in debug and `--release`: none a compiler defect. Shapes R (a field read twice), P (a `phi` of known cases)
  and S (a field stored and read back) are now in the rule, the copy and the lemma
  (`experiments/verify-ir-lean-20261111/DECISIONS.md`, D-VL-16 to D-VL-18). Tests: "a union payload read through a field
  read twice, a field stored and read back, or a merge of known cases" and `tests/lang/union_tag_places.selka`.
