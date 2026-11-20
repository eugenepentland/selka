# Required project import policy

A project can make one import-direction policy mandatory for its ordinary commands. A minimal `selka.json` beside the
entry source (or in an ancestor directory) names the policy file. `check-policy --policy=path` still inspects a policy
explicitly.

## Discovery and resolution

- The configuration filename is `selka.json`.
- Discovery starts at the entry source file's directory and walks up toward the filesystem root; the first `selka.json`
  wins. The shell working directory never takes part.
- `import_policy` is resolved relative to the directory containing the winning `selka.json`.
- A project with no `selka.json` is not enforced. A policy file beside the entry has no effect until a configuration
  names it.

## Configuration shape

Strict JSON; unknown fields, duplicate keys and unsupported versions reject:

```json
{"version": 1, "import_policy": "policy.json"}
```

- `import_policy` is optional; when present it is a relative or absolute path to an existing, valid import policy.
- `"interface_files": true` makes every module's generated interface file part of checking the project
  ([interface files](interface-files.md#enforcing-current-files-with-selkajson)).
- `"value_semantics"` is a JSON boolean kept for compatibility: `true` keeps the checked-ownership model described in
  [value semantics](../value-semantics.md#the-rules), and `false` is rejected when the project loads.
- `"limits"` sets per-project defaults for the execution budgets of `selka run` and `selka test`: an object with a `run`
  and a `test` entry, each any of `max_steps`, `max_frames` and `max_memory`
  ([runtime budgets](runtime-budgets.md#project-defaults-in-selkajson)).

```json
{"version": 1, "limits": {"run": {"max_frames": 200000, "max_memory": "8G"},
                          "test": {"max_steps": 4000000000, "max_frames": 30000, "max_memory": "1G"}}}
```

## Enforcement

Once configured, `check`, `check-project`, `build`, `run`, `run-project`, their project variants and native test
preparation apply the policy. It covers every resolved direct import, including imports whose declarations are unused.
Import-cycle checking is independent and cannot be disabled by policy. There is no inline suppression and no
ordinary-command bypass flag. A stricter policy invalidates an earlier pass, even in a warm cache. Native test
snapshots and locked package builds enforce the same policy.

```console
$ cat selka.json
{"version": 1, "import_policy": "policy.json"}
$ selka check-project src/main.selka
import-direction-v1: failed; scope=reachable-import-graph; edges=1; denied=1; ...
$ selka check-project src/main.selka --policy=policy.json   # check-policy is explicit
usage: selka ... check-policy <file.selka>
```

## Exit statuses

| Exit | Meaning |
| --- | --- |
| 0 | Language valid and policy passes |
| 1 | Source/import/interface/type/ownership/effect error; policy not evaluated |
| 2 | Usage, configuration, I/O, or host failure (including a missing or malformed `selka.json` or policy) |
| 3 | Language valid, but at least one import violates the required policy |

A type-invalid dependency exits 1 even when the policy configuration is malformed.

## A configured project

The configuration and policy files are host inputs. This is the guest project they would govern:

```selka
# doc: project import-policy-example
# doc: file helper.selka

public func value() -> int:
    return 42
```

```selka
# doc: project import-policy-example
# doc: file main.selka
import helper

func main() -> int:
    return helper.value() - 42
```

## Unused-import warnings

`import_policy` governs direction; a separate warning governs use. Every direct import that no reference in its module
resolves through is reported as `W_UNUSED_IMPORT` at the imported name:

```console
$ selka check-project src/main.selka
src/main.selka:2:8: warning[W_UNUSED_IMPORT]: import `helper` is never referenced in this module; remove it or use it
```

The check reads the references the checker resolved, not text: an alias mentioned only in a string literal or a comment
is not a reference. A project that
sets `lint.warnings: "deny"` refuses the check on `W_UNUSED_IMPORT`, as it does for `W_UNUSED_BINDING`, while
`import_policy` keeps evaluating every resolved direct import whether or not it is used.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/import-policy.md).
