# Native filesystem body validation — 2026-10-11

Selected schema 10 body graphs can now represent all nine open modes, the eight
whole-path helpers in both spellings, and the six scoped binary/text file
methods. The boundary verifies exact capability, path and data operands;
canonical Result payload and text failure identities; literal open mode;
method argument presence and type; and text/bytes/list result types. Existing
all-path scoped ownership, cleanup and file escape checks remain in force.

All 28 focused native resource tests and all 88 whole-tree Guardian checks
passed. Authentic native graphs cover helper spellings, every mode and method,
text handles matched from Result, and List[bytes] demand after List[str]. Forged
arity, mode, capability, payload, result, owner and method arguments are refused.
The general Result payload helper preserves the narrower file-only predicate
used by file-escape guards.

The [receipt](evidence/selka-filesystem-native-20261011/receipt.json) binds the
exact tested source and retains the first run, which passed its tests but failed
Guardian on two long test-source lines. Splitting those string literals produced
the successful rerun. The fixture adapter now associates each recipe with the
operation that demands its type, rather than assigning every new recipe the
first open operation's span.

This change qualifies native admission only. The matching Selka producer,
installed native host, final integration gate, full bootstrap and the 1.5×
performance acceptance remain outstanding.
