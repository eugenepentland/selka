# Optional narrowing and dictionary defaults

The registered optional-narrowing and setdefault tests pass in the frozen reconstruction-test2 compiler. Each positive executes unoptimized debug and verified release with managed counting, zero RC events, zero exit-live bytes, LLVM and linked-symbol checks. The source negatives pass.

Optional narrowing keeps the generated successful payload available, excludes the literal-false impossible arm, and rebuilds mutable recursive payload paths from the same transferred parent. Ordinary borrowed optional payloads still cannot escape.

Zero-RC setdefault performs one lookup, inserts only on a miss, then borrows the selected entry from the final dictionary. A05 audited that a newly inserted entry is last even after stable compaction. The fixture covers key/default evaluation once, hit/miss, growth, tombstones, compaction, independent copies and input clearing.

The full batch passed 6 of 8 tests. Unrelated nested list-to-array transfer remained a lowering refusal; the conservative-array IR fixture lacked a required main. Neither is claimed qualified here. identity.json and candidate.patch identify the exact full frozen inputs, including concurrent A07 prototype changes; final integration must rerun these tests on its own compiler.
