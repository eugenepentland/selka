# Independent borrowing/support fixes

- Fresh text conversion and character results have no borrowed source root.
  The looped `str(float).encode()` reproducer and owned character comprehension
  pass, along with existing negative view and borrow tests.
- Nested scalar field writebacks propagate mutation only when the nested update
  reconstructs the exact parent NodeId/field index. Replacements from another
  record/field continue to move. A06 owns focused positive/negative tests.
- Explicit native contracts admit borrowed binary stream output, durable access,
  octet repetition, generic acquisition/I/O/completion and provider keepalive.
  Generated callable-digest adapters require the exact prefix plus 64 lowercase
  hexadecimal digits; their completed implementation returns static strings.

Validation: the working tree's full zero-RC core matrix passed 75/76. Its sole
failure was a new, unrelated resource-negative fixture rejected by the ordinary
front end for an unused capability parameter; no ownership test executed for that
fixture. Generic resource changes remain a separate pending commit. This is
focused development evidence, not final integrated-revision qualification.

A05 supplied complete native path audits and passing owned durable cleanup tests;
A04 supplied octet repetition allocation/bounds audit and terminator overflow fix.
The coordinator must rerun combined checks on the integrated compiler.
