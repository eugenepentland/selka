# Focused declaration context

`mylang context` answers one focused question about one declaration — what does
an agent need to know about this declaration — inside a byte budget that fits an
agent which cannot afford to read the whole repository. It loads a project entry
the same way `mylang index-project` and `mylang tests-for` do, and it answers
from the facts those surfaces already publish: checked navigation from
`mylang index-project`, declared interfaces from `mylang list-interfaces`, static
test reachability from `mylang tests-for`, and classified interface changes from
`mylang api-diff`. It re-checks nothing and reimplements nothing.

The division of labour with the reference is deliberate: `mylang reference`
answers "what does this language feature do", while `mylang context` answers
"what do I need to know about this one declaration".

## `mylang context`

Exactly one of `--symbol` and `--at` is required. `--symbol` names one
declaration in the project rooted at the entry file; `--at` names one position in
the loaded source:

```bash
mylang context app/main.my --symbol 'model::validate'
mylang context app/main.my --symbol 'model::validate' --context-bytes=8192
mylang context app/main.my --symbol 'model::validate' --format=json
mylang context app/main.my --at 'model.my:42:12' --format=json
mylang context app/main.my --symbol 'model::validate' --against=api-baseline.json
```

| Selector | Selects |
| --- | --- |
| `--symbol 'module::name'` | One exact module-qualified declaration, in the `module::name` spelling `mylang index-project` and `mylang tests-for` already use. A name that matches several declarations is reported as ambiguous and a name that matches none as missing; neither is silently resolved to a near match. |
| `--at 'path:line:column'` | The innermost declaration, or the diagnostic, whose source span contains that one-based position. |

| Option | Meaning |
| --- | --- |
| `--context-bytes=N` | The total serialized response budget, metadata included. The default is 8192 and the documented minimum is 1024, below which the request is a usage error. |
| `--format=json` | The response format. `json` is the only format today. |
| `--against=FILE` | Classify the selected declaration against a baseline recorded by `mylang api-diff`. The `changes` section is present only when this option was supplied. |

The response is one JSON object, version `agent-context-v1`, carrying the
compiler and source identities of the snapshot it describes, the selector it
answers, the analysis status, the emitted byte count, the sections, and the
omissions per section.

## Sections and priority order

Sections are emitted in one fixed priority order, so the records an answer does
carry are the ones that matter most to the question:

| Order | Section | Carries |
| --- | --- | --- |
| 1 | `declaration` | The selected declaration (or diagnostic), its source span and its body. |
| 2 | `contract` | Signature, declared bound, checked effects, mutation footprint and return origin, each labeled with its fact status. |
| 3 | `types` | Definitions of directly relevant nominal types and the generic requirements in force. |
| 4 | `dependencies` | Resolved direct dependencies and caller signatures. |
| 5 | `tests` | Direct and transitive test callers, explicitly labeled as static reachability and never as coverage. |
| 6 | `changes` | Interface changes against the supplied `--against` baseline. |

The `contract` labels are the five fact statuses defined in
[Fact status](../reference.md#fact-status) — `checked`, `template`,
`declaration-only`, `declared` and `lexical-only` — the same vocabulary
`mylang index-project` and `mylang list-interfaces` label their own output with,
so a labeled contract and the listing it came from cannot disagree.

## Budget and omissions

`--context-bytes=N` bounds the whole serialized response — records, metadata and
JSON escaping included — and the byte count the answer reports never exceeds it.
When the answer does not fit, the command drops whole records from the
lowest-priority section first: `changes` before `tests`, `tests` before
`dependencies`, and so on. Every drop is counted per section in `omissions`, and
the envelope carries a `continuation` query that asks for a larger budget, so a
caller can trade bytes for the sections it did not receive on the first try. A
record is never cut in half: a declaration's contract is never truncated into a
misleading fragment.

## Incomplete projects

A project whose bodies do not check, or whose body syntax failed outright, still
gets an answer rather than an error. The command publishes the declarations it
could recover, marks the analysis status accordingly, labels each fact with the
status the analysis actually reached (`declaration-only`, or `lexical-only` when
the body syntax failed), and states the reason resolved relationships are
unavailable. `dependencies` and `tests` report that reason instead of edges: the
command never reuses edges from an earlier successful check as though they
described the current source. A partial answer is a statement about the snapshot
it names, not about the last version that happened to compile.

## Source confirmation

The envelope names the exact source identities the answer was assembled from, and
the command re-reads every one of them through the same provider the project was
loaded from before it prints anything. An answer therefore describes the snapshot
it names or it is rejected: a file that changed while the answer was being
assembled — an edit between the load and the response — is reported as a `stale`
snapshot instead of mixing two versions, and a file that can no longer be read at
all is reported as a failure to confirm rather than as a changed source.

## Exit statuses

| Exit | Meaning |
| --- | --- |
| 0 | A complete or partial answer. |
| 2 | A usage error, an ambiguous selector (a name matching several declarations), a selector matching nothing, a `--context-bytes` below the documented minimum, a source change detected while the answer was being assembled, or a source that could not be re-read to confirm the answer. |

An incomplete project is not a failure of this command: the partial answer is
the answer, so it exits 0. The rejections above are requests the command could
not answer as asked, and each of them is reported instead of a guessed or
silently narrowed answer.
