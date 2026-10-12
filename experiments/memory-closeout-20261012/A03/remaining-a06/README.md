# Remaining A06 source contracts

The incoming sources are frozen from integration revision
`868a0cd27a0aa92913d41ee65633d9c5b58cd27c`; the coordinator then refreshed A03
to `44947e696` before the single production edit. `C0/`, `incoming/`,
`reviewed/` and `identities.json` preserve exact source identities. The 18 set,
eight generator and seven move-elision public Boolean tests remain the oracle:
every result must be `True`. No test or assertion is removed.

Support6 source checks reproduced all three reported refusals:

| Fixture | Diagnostic | Resolution status |
| --- | --- | --- |
| sets, line 64, `set(evens)` | `E_SINGLE_OWNER_OVERLAP` | Compiler diagnosis assigned to A02; API unchanged |
| generator_arguments, line 41, managed `max` generator | `E_SINGLE_OWNER_LOOP` | Compiler diagnosis assigned to A02; API unchanged |
| move_elision, line 78, `both(p, replace(p, x=2))` | `E_SINGLE_OWNER_OVERLAP` | Explicit independent replacement source; source check passes |

The move-elision call becomes `both(p, replace(p.copy(), x=2))`. Its first
argument borrows the original owner for the call; the replacement now consumes
an independent copy. This preserves the expected `102` and argument evaluation
order without relaxing the original overlap rejection. Compared with the
incoming source, one line changes and one explicit copy is added. The fixture
has six explicit copies in total (C0 had zero, the incoming migration had five).
This is a source ownership/allocation change, not a compiler-only performance
claim. `proposed/` preserves the exact source that passed the check.

The six corrected reducers are source checks only. Both managed generator forms
(`max(w for w in words)` and copied yields) refuse with `E_SINGLE_OWNER_LOOP`.
The list-form extrema control followed by input clearing also refuses on
Support6; A04's later list-extrema implementation is absent from that compiler.
Simple set constructors from a set literal or list **admit**, as does explicit
set copying. Therefore the full set-fixture refusal must retain its surrounding
comprehension and earlier constructors while being reduced; it is not evidence
that every `set(iterable)` call is unsupported. Neither API is replaced to make
the fixture pass. A04 confirmed these defects are separate from its two-parent
selection work.

`corrected-reducer-results.json` and `source-support6/` retain compiler hashes,
commands, outputs and source identities. The initial files under `reducers/`
used Python-order conditional syntax and received syntax errors; those draft
errors are retained separately in `reducer-results.json` and are not ownership
evidence. `corrected-reducers/` uses the language's reading-order syntax.

No guest was executed by these source checks. Five-mode native qualification
must use the next integrated compiler. The pinned original-30 and 81+6 corpus
denominators are unchanged.
