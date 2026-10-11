# Dictionary, set and Option body admission

This runner prepares B8 source admission. It does not claim compiler bootstrap or installed B8 support before an authenticated schema8 deployment passes every operation.

The committed inventory contains 34 sources: 24 successful programs and 10 ordered source-diagnostic cases, plus one imported donor. Native controls require 82 operations; selected admission requires 246 across reference, shadow and component modes. No profile refusal or skipped source can satisfy this selection. Other six component modes remain reference.

Successful cases cover insertion order, repeated keys, live dictionary values/items replacement, keys/values/items snapshots, nested value COW, mutable parameters, imported aliases, structural record keys, contextual integer widths, dictionary and set comprehensions, set methods and operators, Option presence tests, short-circuit branch facts, loop/rebinding invalidation, managed payload snapshots, and eager `unwrap_or` receiver/fallback effects. The eager-order control records 12 through two mutable helper calls even when the receiver is Some. Error cases pin code, message, byte span, ordered related notes and repair bytes, including private imports and invalidated Option facts.

Every successful program runs generated release code with fact verification and leak checks and must return status7 with stdout `7\n`. Each also emits nonempty typed output. Typed dumps supplement the mandatory full batch/catalog shadow comparison; they are not its replacement. Check/run commands use `--no-cache`; dump-typed creates a fresh frontend session and accepts no cache option (a third argument is a function filter).

All paths are resolved before private workspace creation. Reports preserve each raw status/stdout/stderr before assertions, source hashes and all seven authenticated package identities. Compiler and package identity must remain unchanged. Selected admission additionally requires coordinator qualified-seed receipt verification. Historical reference controls require an explicit body schema; this never relaxes selected schema8 validation.

Run through build admission with private on-disk TMPDIR and Zig cache:

```sh
scripts/build-slot.sh build python3 selfhost/tests/run_body_dictionary_admission.py \
  --compiler /absolute/install/bin/mylang \
  --component-dir /absolute/install/libexec/mylang/components \
  --builder /absolute/install/tools/selka-components \
  --source-root /absolute/source --zig /absolute/pinned/zig \
  --report /absolute/evidence/b8.json
```

For native-only preparation add `--native-controls --native-body-schema 5` when using the frozen B5 installation. Such a complete report still marks selected admission pending. Hostile schema8 catalog/operation validation belongs to separate authentic reply qualification; these source controls do not substitute for it.

The mandatory `zig build test-selfhost-body-dictionaries` target runs normal and
release qualification. Each lane requires all 246 distinct source operations
and all 27 ordered authenticated hostile replies; duplicate, absent or skipped
work cannot qualify. `test-selfhost-body-dictionaries-self` checks that accounting
without claiming installed schema 8 support. Every successful runtime control
uses release generation, fact verification and leak checks in both lanes; the
release lane additionally passes release/fact flags to source checking.
