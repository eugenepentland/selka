# Aggregate provider lifetime integration

Base `611c78b6ab7f06f8e471d277d80d53b0c429ed74`. Provider-bearing ordinary records use bounded type-graph classification and compiler-only borrowed lifetime markers, omitted from generated machine code. Moves invalidate the old lexical owner; provider copies and owner changes during active field scopes refuse. Lists, variants, arrays, boxed providers and aggregate-param resource-return inference remain outside this contract.

Six registered tests pass, including native output/cache replay, physical type identity invalidation, malformed marker refusal, allocation cost and copy/move/replacement negatives. See results.json and raw logs. First run includes fresh native execution; final run reuses identical native artifacts. The second attempt was stopped after omitted compiler filters selected unrelated tests; those errors remain archived. Full release inventory and final gate remain pending.

The core-test-binary build step permits focused registered test compilation while installed-component qualification is pending; it does not replace the complete gate.
