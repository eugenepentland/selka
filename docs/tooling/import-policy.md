# Required project import policy

A project can make one import-direction policy mandatory for its ordinary
commands. The project opts in with a minimal `mylang.json` configuration beside
its entry source (or in an ancestor directory); the configuration names the
policy file. `check-policy --policy=path` stays available for explicit
inspection, but once configured, ordinary commands no longer need it to get
enforcement.

## Discovery and resolution

- The configuration filename is `mylang.json`.
- Discovery starts at the entry source file's directory and walks up toward the
  filesystem root. The first `mylang.json` found wins.
- The shell working directory never participates. Running the compiler from a
  different directory still selects the policy owned by the entry's project.
- `import_policy` is resolved relative to the directory containing the winning
  `mylang.json`, anchored to the entry project root.
- A project with no `mylang.json` keeps the previous behavior. A JSON policy
  file that merely sits beside the entry has no effect until a configuration
  names it.

## Configuration shape

Strict JSON; unknown fields, duplicate keys and unsupported versions reject:

```json
{"version": 1, "import_policy": "policy.json"}
```

`import_policy` is optional. When present it must be a nonempty relative or
absolute path; the file must exist and parse under the
[import policy rules](../experiments/import-policy.md). `check-policy` can be
used to inspect the same file explicitly.

## Enforcement

Once configured, `check`, `check-project`, `build`, `run`, `run-project`,
project variants and native test preparation apply the policy through the shared
frontend step. Evaluation covers every resolved direct import, including imports
whose declarations are unused, and runs before any cached success is returned.
Import-cycle checking is independent and cannot be disabled by policy.

Policy and configuration identity participates in successful-verdict caches and
in `project-dependencies-v1` and native-test receipts, so a stricter policy
invalidates an earlier pass even in a warm cache. Native test snapshots and the
offline package driver carry the entry project's configuration into their
isolated snapshots, so selected provider graphs and locked package builds
enforce the same policy as the live project. There is no inline suppression and
no ordinary-command bypass flag.

```console
$ cat mylang.json
{"version": 1, "import_policy": "policy.json"}
$ mylang check-project src/main.my
import-direction-v1: failed; scope=reachable-import-graph; edges=1; denied=1; ...
$ mylang check-project src/main.my --policy=policy.json   # check-policy is explicit
usage: mylang ... check-policy <file.my>
```

## Exit statuses

| Exit | Meaning |
| --- | --- |
| 0 | Language valid and policy passes |
| 1 | Source/import/interface/type/ownership/effect error; policy not evaluated |
| 2 | Usage, configuration, I/O, or host failure (including a missing or malformed `mylang.json`/policy) |
| 3 | Language valid, but at least one import violates the required policy |

Policy failures are not language-invalidity diagnostics. A type-invalid
dependency still exits 1 even when the policy configuration is malformed.

## A configured project

The configuration and policy files are host inputs, not guest modules; the
example below is the guest project they would govern.

```mylang
# doc: project import-policy-example
# doc: file helper.my
module helper
export value

def value() -> int effects():
    return 42
```

```mylang
# doc: project import-policy-example
# doc: file main.my
module main
import helper

def main() -> int:
    return helper.value() - 42
```
