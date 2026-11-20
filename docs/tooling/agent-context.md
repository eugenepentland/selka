# Focused declaration context

`selka context` answers one question about one declaration, "what do I need to know about this?", inside a byte budget
that fits an agent that cannot read the whole repository. It loads a project entry as `selka index-project` and
`selka tests-for` do, and answers from the facts they and `selka list-interfaces` and `selka api-diff` already publish. It
re-checks nothing. (`selka reference` answers "what does this language feature do".)

The contract section reports parsed declaration facts even when body checking fails: `mutates`, `return_origin` (`fresh`
or `params`) and `borrows` (sorted parameter positions, representable above 63). Only checked bodies provide
`mutation_writes`; lexical-only recovery leaves callable contract fields null.

`context` is front-end only, so it cannot say whether a local owns its value or borrows it. Ask
`selka dump-typed FILE.selka`: it prints each named local of a managed type with `owns`, `borrows from the caller`,
`borrows from all`, `borrows elements from all` or `borrows fields from names`.

## `selka context`

Exactly one of `--symbol` and `--at` is required. `--symbol` names one declaration in the project rooted at the entry
file; `--at` names one position in the loaded source:

```bash
selka context app/main.selka --symbol 'model::validate'
selka context app/main.selka --symbol 'model::validate' --context-bytes=8192
selka context app/main.selka --symbol 'model::validate' --format=json
selka context app/main.selka --at 'model.selka:42:12' --format=json
selka context app/main.selka --symbol 'model::validate' --against=api-baseline.json
```

| Selector | Selects |
| --- | --- |
| `--symbol 'module::name'` | One exact declaration, as `module::name` or the call-site spelling `module.name` (see [call-site spelling](navigation.md#call-site-spelling)). A name matching several declarations is reported as ambiguous and one matching none as missing; neither is resolved to a near match. |
| `--at 'path:line:column'` | The innermost declaration, or the diagnostic, whose source span contains that one-based position. |

| Option | Meaning |
| --- | --- |
| `--context-bytes=N` | The total serialized response budget, metadata included. Default 8192; below the minimum, 1024, it is a usage error. |
| `--format=json` | The response format; `json` is the only one. |
| `--against=FILE` | Classify the declaration against a baseline recorded by `selka api-diff`. The `changes` section exists only with this option. |

The response is one JSON object, version `agent-context-v1`: the compiler and source identities of the snapshot, the
selector, the analysis status, the emitted byte count, the sections, and the omissions per section.

## Sections and priority order

Sections come in one fixed priority order, so an answer carries the records that matter most:

| Order | Section | Carries |
| --- | --- | --- |
| 1 | `declaration` | The selected declaration (or diagnostic), its source span and its body. |
| 2 | `contract` | Signature, mutation footprint and return origin, each labeled with its fact status. |
| 3 | `types` | Definitions of directly relevant nominal types and the generic requirements in force. |
| 4 | `dependencies` | Resolved direct dependencies and caller signatures. |
| 5 | `tests` | Direct and transitive test callers, labeled as static reachability, never coverage. |
| 6 | `changes` | Interface changes against the `--against` baseline. |

The `contract` labels are the five fact statuses (`checked`, `template`, `declaration-only`, `declared`, `lexical-only`)
that `selka index-project` and `selka list-interfaces` use, defined in
[Fact status](navigation.md#fact-status-in-interface-and-navigation-output).

## Budget and omissions

`--context-bytes=N` bounds the whole serialized response, and the reported byte count never exceeds it. When the answer
does not fit, whole records are dropped from the lowest-priority section first: `changes` before `tests`, `tests` before
`dependencies`, and so on. Each drop is counted per section in `omissions` (embedded-file rows appear as
`source.embeds`), and `continuation` is a query that asks for a larger budget. A record is never cut in half.

## Incomplete projects

A project whose bodies do not check, or whose body syntax failed, still gets an answer. The command publishes the
declarations it could recover, labels each fact with the status the analysis reached (`declaration-only`, or
`lexical-only` when the body syntax failed), and states why resolved relationships are unavailable: `dependencies` and
`tests` report that reason instead of edges. Edges from an earlier successful check are never reused.

## Source confirmation

Before it prints, the command re-reads every source the answer was assembled from. An answer describes the snapshot it
names or is rejected: a file that changed while the answer was assembled is reported as a `stale` snapshot, and a file
that can no longer be read as a failure to confirm. `embed_bytes` and `embed_str` files are inputs too
(`snapshot.embeds` records module, path, read status, byte count and BLAKE3 digest, and `snapshot.embedded_files` the
count); a same-length edit or a missing file is stale.

## Exit statuses

| Exit | Meaning |
| --- | --- |
| 0 | A complete or partial answer. An incomplete project is not a failure. |
| 2 | A usage error, an ambiguous or unmatched selector, a `--context-bytes` below the minimum, a source change while the answer was assembled, or a source that could not be re-read. |

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/agent-context.md).
