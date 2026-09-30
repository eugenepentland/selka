## Runs

| project | runtime | seed | modules | steps | built | on module path | off path | matched | findings | compiled mean/median/max | wall s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| lox | gc | 21 | 18 | 40 | 31 | 31 | 0 | 40 | 0 | 8.2 / 7 / 15 | 125.9 |
| lox | rc | 21 | 18 | 40 | 31 | 31 | 0 | 40 | 0 | 10.5 / 10 / 15 | 163.2 |
| lox | gc | 22 | 18 | 40 | 30 | 30 | 0 | 40 | 0 | 7.5 / 7 / 16 | 136.5 |
| lox | rc | 22 | 18 | 40 | 30 | 30 | 0 | 40 | 0 | 9.2 / 10 / 16 | 166.0 |
| lox | gc | 23 | 18 | 40 | 29 | 29 | 0 | 40 | 0 | 7.4 / 6 / 16 | 104.2 |
| lox | rc | 23 | 18 | 40 | 29 | 29 | 0 | 40 | 0 | 9.8 / 9 / 16 | 126.0 |
| synthetic | gc | 21 | 6 | 40 | 29 | 29 | 0 | 40 | 0 | 3.9 / 4 / 6 | 90.3 |
| synthetic | rc | 21 | 6 | 40 | 29 | 29 | 0 | 40 | 0 | 4.0 / 4 / 6 | 14.3 |
| synthetic | gc | 22 | 9 | 40 | 30 | 30 | 0 | 40 | 0 | 5.9 / 6 / 9 | 55.6 |
| synthetic | rc | 22 | 9 | 40 | 30 | 30 | 0 | 40 | 0 | 6.3 / 6 / 9 | 20.6 |
| synthetic | gc | 23 | 7 | 40 | 24 | 24 | 0 | 40 | 0 | 4.8 / 5 / 7 | 45.8 |
| synthetic | rc | 23 | 7 | 40 | 24 | 24 | 0 | 40 | 0 | 5.0 / 5 / 7 | 15.5 |

Total: 480 edit steps, 346 built (72%), 480 matched the oracle, 0 findings, 134 revert checks.

## Edit kinds

| kind | applied | built | failed | off module path | compiled mean/median/max |
|---|---|---|---|---|---|
| int-literal | 164 | 138 | 26 | 0 | 6.7 / 6 / 16 |
| wrap-return | 100 | 78 | 22 | 0 | 6.8 / 6 / 16 |
| use-added | 96 | 80 | 16 | 0 | 7.5 / 7 / 16 |
| add-default-param | 78 | 66 | 12 | 0 | 7.2 / 6 / 16 |
| insert-statement | 78 | 60 | 18 | 0 | 7.1 / 6 / 14 |
| const-value | 72 | 50 | 22 | 0 | 8.5 / 8 / 15 |
| remove-added | 68 | 56 | 12 | 0 | 6.4 / 5 / 15 |
| start-alloc | 68 | 52 | 16 | 0 | 5.9 / 6 / 12 |
| add-public-fn | 64 | 56 | 8 | 0 | 6.9 / 7 / 15 |
| record-field-add | 50 | 42 | 8 | 0 | 8.2 / 9 / 15 |
| helper-call | 48 | 44 | 4 | 0 | 6.8 / 5 / 16 |
| add-const | 46 | 32 | 14 | 0 | 6.9 / 6 / 14 |
| toggle-visibility | 44 | 38 | 6 | 0 | 6.0 / 5 / 15 |
| add-required-param | 44 | 2 | 42 | 0 | 5.0 / 5 / 5 |
| float-literal | 40 | 36 | 4 | 0 | 5.8 / 5 / 11 |
| change-default | 38 | 30 | 8 | 0 | 6.5 / 6 / 13 |
| comment | 36 | 32 | 4 | 0 | 6.5 / 6 / 14 |
| remove-public-fn | 36 | 2 | 34 | 0 | 9.0 / 9 / 9 |
| add-private-fn | 34 | 32 | 2 | 0 | 8.2 / 6 / 15 |
| change-return-type | 34 | 0 | 34 | 0 | - |
| whitespace | 34 | 32 | 2 | 0 | 6.1 / 6 / 13 |
| rename-added | 28 | 18 | 10 | 0 | 10.1 / 12 / 15 |
| move-function | 26 | 12 | 14 | 0 | 6.1 / 6 / 10 |
| stop-alloc | 24 | 16 | 8 | 0 | 6.6 / 6 / 13 |
| rename-public-def | 22 | 4 | 18 | 0 | 5.0 / 7 / 7 |
| drop-record-field | 20 | 0 | 20 | 0 | - |
| break-type | 14 | 0 | 14 | 0 | - |
| record-field-remove | 14 | 12 | 2 | 0 | 9.2 / 11 / 14 |
| change-field-default | 12 | 10 | 2 | 0 | 6.3 / 5 / 14 |
| noop | 8 | 8 | 0 | 0 | 6.4 / 8 / 9 |

## Compiled-module counts (engaged incremental builds)

| compiled | builds |
|---|---|
| 1 | 2 |
| 2 | 21 |
| 3 | 48 |
| 4 | 41 |
| 5 | 42 |
| 6 | 39 |
| 7 | 23 |
| 8 | 25 |
| 9 | 22 |
| 10 | 13 |
| 11 | 13 |
| 12 | 14 |
| 13 | 11 |
| 14 | 16 |
| 15 | 12 |
| 16 | 4 |

## Why edits failed to build

| kind | diagnostic | count |
|---|---|---|
| (several edits in one step) | E_UNKNOWN_SYMBOL | 46 |
| (several edits in one step) | E_TYPE | 42 |
| (several edits in one step) | E_ARITY | 42 |
| (several edits in one step) | E_UNKNOWN_FIELD | 4 |

Failed steps where the two builds reported different error sets: 0.
