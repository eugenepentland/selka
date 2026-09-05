# Optional dependency-direction policy

`check-policy` first checks the complete reachable module program, then evaluates
an explicitly supplied policy file against its resolved direct imports:

```sh
zig build run -- check-policy examples/modules/main.my --policy=examples/modules/import-policy.json
```

Ordinary `check-project` and `run-project` do not load policy, even if a JSON file
exists alongside the entry. Language errors cannot be suppressed by policy. The
policy path is an explicit host CLI path, relative to the working directory unless
absolute; it is not implicitly searched in module directories.

```json
{
  "version": 1,
  "default_action": "deny",
  "rules": [
    {
      "from": "main",
      "to": "shared.*",
      "action": "allow",
      "reason": "The entry assembles shared domain interfaces."
    }
  ]
}
```

Rules are ordered: the first matching rule wins. Remaining edges use the required
`default_action`. A pattern is an exact logical module name, `*` for every module,
or `namespace.*` for descendants of that namespace. `core.*` matches `core.model`
and `core.model.detail`, but neither `core` nor `coreish.model`. Match the namespace
itself with a separate exact rule when needed. More specific rules do not silently
override earlier broad rules. From/to refer to resolved module names, not aliases
or filesystem paths. Every direct import counts, including imports whose declarations
are unused. Transitive architectural separation follows only from the actual rules
on every direct edge; this is not information-flow analysis.

Strict JSON parsing rejects unknown fields, duplicate keys, missing required fields,
unsupported versions/actions, invalid patterns, and repeated identical from/to
pairs. Every rule has a nonempty UTF-8 reason without control characters. Bounds are
1 MiB configuration bytes, 1,024 rules, 256 bytes per pattern, and 512 bytes per
reason. These are in addition to the module loader's source/graph limits. There are
no inline suppression annotations and no automatic policy changes.

The report identifies analysis version `import-direction-v1` and a SHA-256 of the exact
configuration bytes. It prints the reachable-graph scope, edge/denial counts, each
edge's source location and selected rule/default, and match counts for every rule.
Zero matches describe this invocation's reachable graph; they do not prove a rule
is globally stale or ineffective in other entry graphs. Evaluation is deterministic
in dependency-first/source-import order. Matching is bounded by edges times rules;
there is no unbounded regex or glob expansion.

Exit statuses deliberately distinguish outcomes:

| Exit | Meaning |
| --- | --- |
| 0 | Language valid and policy passes |
| 1 | Source/import/interface/type/ownership/effect error; policy not evaluated |
| 2 | Usage, configuration, I/O, or host failure |
| 3 | Language valid, but at least one import violates the selected policy |

The CLI emits `language: valid` only after successful semantic checking and policy
configuration/evaluation. Policy failures are not language-invalidity diagnostics.
The embedding evaluator needs a complete import graph but makes no type-validity
claim itself and never changes the graph's diagnostic or compilation state.

Acceptance covers directional rules, namespace boundaries, ordered broad/specific
rules, default denial, unused-rule counts, deterministic output, strict configuration
and size/rule limits, allocator-failure cleanup, and actual CLI separation of all
four exit outcomes. A type-invalid dependency still produces exit 1 even when the
policy configuration is invalid; ordinary project execution remains unaffected by
a separately failing policy. The documented shared-domain policy passes with one
allowed edge.

The module track now implements its core import/export/privacy, execution, and
optional direction-policy behavior. Broader module corpus/scaling acceptance and
module-aware formatting, quality/reference roots, duplicate identities, native
project parity, and schema/incremental integration remain on the roadmap.
