# Aggregate stream output — 2026-10-11

The selected schema 10 body checker now admits aggregate Stream printing through
the existing native rendering contract. Its type closure covers retained and
fresh collection types, records, variants and fixed arrays. The original
aggregate profile fixture now requires success and exact output; 13 additional
fixtures bring the complete body-check corpus to 190 cases.

The installed producer passed 530 workflows and 1,060 comparisons in each of
four combinations: Debug and ReleaseFast native hosts, each with normal and
release/facts/leak guest verification. Every run had zero failures and skips,
and retained warm deployment, live session, forged reply, transport and
publication checks. The focused producer tests and all 103 body harness tests
passed; both host qualifications passed all 88 Guardian checks.

The [receipt](evidence/selka-stream-aggregates-20261011/receipt.json) binds the
unchanged qualified seed, installed packages, source closure, all 190 fixtures,
and both clean native installations. It preserves the initial formatter failure,
the invalid preliminary fixed-array fixture, and the first native installation
terminated by earlyoom, alongside their successful corrections and retries.

Dedicated qualification does not run coordinator edit verification. The full
repository gate remains required for final integration; its current failures
are tracked separately. This slice does not establish full compiler bootstrap
or the requested 1.5× performance acceptance.
