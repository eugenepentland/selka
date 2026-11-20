# M1b readout — diagnostic suggestions and representation

Cohort `m1b`, 112 scheduled cells, 4 arms × 14 cases × 2 repetitions, cohort and
decision rules fixed before the first cell ran. Frozen evidence:
`experiments/diagnostic-feedback/cohorts/m1b/` (`manifest.json`, per-attempt
`record.json`/`events.jsonl`, sealed snapshots), readout in `readout.json`,
delivery exceptions in `non-delivered.json`. Compiler
`4a9ad0c17789e422fa90dbb8e91497f007abdc2ef5152f3123889dbdc2cfbcb2`, model
`deepseek-v4-flash` at maximum effort, invocation limit 20.

The three conclusions are kept apart. Measurement validity does not follow from a
large effect, practical benefit does not follow from a small interval, and neither
stands in for the other.

## 1. Measurement validity

**Sound:** 112/112 scheduled cells completed, 0 missing, 0 identity mismatches, 0
grading incidents, 0 infrastructure or timeout incidents, 1 retry (frozen policy:
new attempt, reason recorded, attempt 1 preserved), 111/112 hidden acceptance with
the single miss inside `text_fix`.

The manifest's recorded identity was re-derived from the module after the last cell
and matches field for field: compiler `4a9ad0c17789…`, wrapper schema
`wrapper-v2-events`, prompt `ae2fba8f334f…`, remedy table `449d37b9adee…`, model
`deepseek-v4-flash`/`max`, invocation limit 20, deadline 900 s, cache policy, and the
held-out case corpus `7efcd5738e97…`. The cohort therefore ran and was read under one
fixed configuration, and the only module changes since are to `readout.py` itself,
which no run imports.

**Limits added 2026-09-19 (no number below changes): the corpus was not fully held
out.** Three of the four M2 development cases are byte-identical to cases in this
cohort's test split — `dev-bool` ≡ `bool-a`, `dev-checked` ≡ `checked-a`, `dev-variant`
≡ `variant-a`/`variant-b`; only `dev-generic` is a distinct instance. For those test
cases the remedy wording was therefore **not fully held out** from the evaluation it was
measured on: they are the same tasks, so any authoring or tuning that used the dev split
reached them too. The direction of that contamination is knowable and it runs **for the
treatment**: it can only have made the suggestion arms look better than they are, and
the treatment still failed its predeclared target (§2). The null is therefore **more
robust, not less** — it survives a bias that favours the arms it rejects. The duplicate
also matters for the paired counts: `variant-a` and `variant-b` are the same task, so
`variant-coverage` contributes one distinct task, not two, wherever the corpus is
counted. Separately, **111/112 is the cohort-wide hidden acceptance** (all four arms,
both repetitions) and the M2-matching `text` arm alone was **28/28**; the two figures
must not be conflated.

**Delivery, as finally measured:** 48 of 112 sessions met a diagnostic that made a
remedy applicable; 46 of those 48 were delivered exactly as their arm required; 64
sessions never met an eligible diagnostic and are not delivery failures — they stay
in their assigned arms. Every eligible session in a suggestion arm received remedy
text (28/28 `json_fix`, 26/28 `text_fix`, the two exceptions below).

Delivery accounting was wrong three times before it was trustworthy, and the
sequence is part of the result:

| Stage | Eligible | Failures | Defect |
| --- | --- | --- | --- |
| Final message (`session.txt`) | 23 | 19 | judged what the agent *said*, not what it *saw* |
| Whole session log, raw string | 55 | 10 | `diagnostics-v1` matched the wrapper's own source |
| Event-log eligibility (by code) | 102 | 51 | code granularity ignores which rule the message triggers |
| Log, shim source removed, escape-tolerant marker | 48 | 2 | — |

The last defect was that session logs JSON-escape tool output, so the unescaped
payload marker never matched in the JSON arms; the check passed only where the
shim's source happened to spell the payload inline. Representation is now detected
by the pretty-printed payload that `render()` actually emits, which the shim source
cannot produce, and eligibility is judged after removing shim-source lines.

**Two non-delivered cells** (`non-delivered.json`): `text_fix/generic-a/2` and
`json_fix/checked-c/2`, both eligible on `E_TYPE:found Result[`, both with no remedy
text anywhere in the session. Both are treatment cells, so the primary comparison is
conservative against the treatment; per-protocol analysis would not rescue a benefit
claim. `valid` therefore reads `false` — not because measurement broke, but because
two eligible treatment cells were not treated.

**Information hygiene, kept visible.** The wrapper shim is readable inside the work
directory and embeds the remedy table for *every* arm (`conditions.py` line 87),
including the arms that must have no suggestions. 29 sessions' logs contain shim
source — the participants opened it to read the render logic. Reassuringly, 0 of the
56 control-arm sessions contain any remedy text, and 0 text-arm sessions contain a
rendered JSON payload: the suggestion manipulation did not leak into the arms that
must not have it. This is a latent threat that happened not to fire, and the shim
should be unreadable in the next cohort.

## 2. Practical benefit

Predeclared target: at least one fewer failed compiler invocation per successful
repair in each responsive family, with no hidden-acceptance regression. States are
`passes` / `fails` / `inconclusive`.

| Family | State | Treatment | Mean | Interval | Pairs |
| --- | --- | --- | --- | --- | --- |
| checked-result | **fails** | `text_fix` | 0.444 | [−0.444, 1.556] | 9 |
| generic-requirement | inconclusive | `text_fix` | −0.000 | [−0.400, 0.500] | 10 |

Overall: **fails**. `checked-result` fails on its reason rather than its interval —
the interval spans benefit — because a `text_fix` cell lost hidden acceptance, which
the target forbids outright. Pooled totals point the same way: failed checks over all
attempts are 10 (`text`) vs 23 (`text_fix`) and 5 (`json`) vs 18 (`json_fix`).

Arms (28 cells each):

| Arm | Hidden OK | Median failed checks (accepted) | All-attempt failed checks | Median invocations | Median output tokens |
| --- | --- | --- | --- | --- | --- |
| text | 28 | 0.0 | 10 | 11.5 | 3327 |
| text_fix | 27 | 0.0 | 23 | 11.0 | 3189 |
| json | 28 | 0.0 | 5 | 10.0 | 2916 |
| json_fix | 28 | 0.0 | 18 | 10.5 | 3462 |

## 3. Uncertainty

Both responsive families are `inconclusive`; the intervals do not separate the
predeclared benefit from no benefit. Contrasts (treatment − baseline, paired):

| Contrast | Mean | Interval | Reading |
| --- | --- | --- | --- |
| suggestion in text | 0.464 | [−0.179, 1.179] | inconclusive |
| suggestion in JSON | 0.464 | [0.071, 1.071] | harm-leaning, interval excludes 0 |
| format without suggestion | −0.179 | [−0.643, 0.179] | inconclusive |
| format with suggestion | −0.179 | [−0.929, 0.536] | inconclusive |

Positive means more failed checks under the treatment. The strongest single signal in
the experiment is therefore not the hoped-for benefit but a small harm signal for
suggestions rendered as JSON.

## What this licenses

1. **Suggestions do not reduce failed compiler invocations here.** The target fails,
   and the only contrast whose interval excludes zero points the wrong way.
2. **The trial could not have detected an acceptance gain.** The primary outcome sits
   at 111/112; the informative metric is the secondary one, so this is an efficiency
   finding, not a verdict on suggestions in general.
3. **The JSON harm signal is the one open question** and it needs headroom, not
   repetitions: harder cases where the ceiling is not already reached.
4. **Proceed to M2.** A null M1 does not invalidate M2: plain-text feedback remains a
   valid M2 treatment, and M2's budget machinery is being prepared separately so the
   two are not coupled.
