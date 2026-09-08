# atomic-transfers

Version: 1. Family: multi-module-maintenance. Kind: bugfix. Tier: medium.

Request: {"accounts":[{"id":ID,"balance":INT}],
"batches":[[TRANSFER,...],...]}. At most 32 unique accounts, balances 0..1000000;
at most 32 batches with at most 32 transfers each. TRANSFER is exactly
{"from":ID,"to":ID,"amount":INT}, amount 0..1000000. Evaluate each batch in
order against tentative balances, and commit ONLY if all transfers succeed.
For each transfer check both accounts exist first, then sufficient source funds,
then debit source and credit target. Self-transfer still checks funds and has
zero net change. On the first failure discard ALL changes in that batch and
return "unknown-account" or "insufficient"; later batches use last committed
balances. Empty batches commit. Return {"results":[STATUS],"balances":[
{"id":ID,"balance":INT}]} with statuses "committed" or first error and final
balances sorted by ID. Repair the seeded partial-commit defect in the supplied
three-module starter, preserving generic state, module boundaries and errors.

Apply the shared PROCESS.md transport, type, schema and validation rules.
