# DL3 group-local verification contracts

The inventory export uses version 2. Every original registered action receives
one unique summary label, `verification action GROUP member ORDINAL`, after the
configure graph is complete. Top-level `action_metadata` retains its final
original label and Zig step kind. A cohort with several steps exports every
reachable member; duplicate registration is rejected. The coordinator validates
unique group IDs and labels, complete metadata, and the agreement between member
count and original-gate coverage before considering any reusable success.

Action receipts use the `selka-verification-action-v3` identity domain. The key
binds the group's exact contract, selected files/artifacts, original member
labels/kinds, configuration controls, and common execution/tool/environment
identities. Global inventory membership is no longer part of that key. Adding a
current group still requires its execution; adding or removing unrelated groups
can preserve existing group keys. Unknown actions retain the fresh original-gate
fallback. The global inventory is validated on every request, including reused
inventory exports, and its complete digest still protects inventory preparation.

Configuration dependencies remain conservative. Projection first requires an
explicit `DECLARATIVE_CONFIG_SHA256` qualification of the complete watched
`CONFIG_INPUTS` closure with the list file omitted. The default is `None`, which
keeps action identities broad. Coordinator scripts are watched in a separate
combined snapshot but excluded from this qualification to avoid hashing a
fingerprint embedded in its own source. Changed or added configuration consumers
disable projection until their complete dependency closure and uses of input
lists receive another review; the digest must never update automatically.

After that qualification, the coordinator can omit only
`build_test_inputs.zig` data bytes from the action configuration identity, when a
strict parser recognizes the complete file as public constant string arrays,
previously declared array references, and array concatenation, and the result
exactly matches all exported input lists. Each cohort still binds its selected
recipes. Unfamiliar syntax, inconsistent exports, or a symlinked declaration file
retain the full configuration identity. The file remains watched throughout the
request. Executable build wiring and other configuration files remain common
dependencies; changing `build.zig` still invalidates all groups. This is a reviewed
data-list boundary, not arbitrary build-code equivalence or function-level reuse.
Prepared artifact dependencies remain conservative unless a cohort explicitly
selects reviewed providers.

Reports expose `action_metadata`, each action's `action_key`, and a conservative
`budget_context` digest of the common execution context excluding global inventory
membership. Captures expose `capture_complete`. These fields help advisory
calibration compare compatible observations; they do not authorize reuse, select
tests, or enforce per-action deadlines. Member durations may overlap and must not
be summed into a cohort duration without additional evidence. Unknown or missing
measurements remain unknown.

Focused coordinator tests cover unrelated group additions/removals, current-group
member and recipe changes, renamed fixtures, unfamiliar declarative syntax,
missing/duplicate member metadata, and the retained broad configuration fallback.
No latency improvement or isolated performance result is claimed by this change.

To calculate the candidate digest after reviewing the final configuration closure,
run this from the repository root with the Guardian sibling available:

```python
import sys
sys.path.insert(0, "scripts")
from verify_cache import CONFIG_INPUTS, ROOT, key
from verification_snapshot import Snapshot
with Snapshot(ROOT, CONFIG_INPUTS) as snapshot:
    candidate = dict(snapshot.identity, files=[item for item in snapshot.identity["files"]
                                               if item["path"] != "build_test_inputs.zig"])
    print(key(candidate))
```

Computing this digest does not establish qualification. The reviewed configuration
must consume these lists solely through each group's declared dependencies or
through fresh global discovery/coverage. Any other use stays broadly keyed until
its full effect is represented in the affected group contract.
