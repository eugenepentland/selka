## Runs

| project | runtime | seed | modules | steps | built | on module path | off path | matched | findings | compiled mean/median/max | wall s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| lox | gc | 1 | 18 | 60 | 51 | 51 | 0 | 60 | 0 | 3.0 / 1 / 13 | 408.8 |
| lox | rc | 1 | 18 | 60 | 51 | 51 | 0 | 60 | 0 | 4.5 / 3 / 13 | 217.6 |
| lox | gc | 2 | 18 | 60 | 56 | 56 | 0 | 60 | 0 | 4.1 / 1 / 16 | 219.3 |
| lox | rc | 2 | 18 | 60 | 56 | 56 | 0 | 60 | 0 | 5.7 / 4 / 16 | 314.9 |
| lox | gc | 31 | 18 | 60 | 49 | 49 | 0 | 60 | 0 | 2.9 / 1 / 14 | 255.1 |
| lox | rc | 31 | 18 | 60 | 49 | 49 | 0 | 60 | 0 | 4.6 / 4 / 14 | 225.3 |
| lox | gc | 32 | 18 | 60 | 58 | 58 | 0 | 60 | 0 | 3.2 / 1 / 16 | 705.4 |
| lox | rc | 32 | 18 | 60 | 58 | 58 | 0 | 60 | 0 | 4.8 / 4 / 16 | 240.9 |
| lox | gc | 3 | 18 | 60 | 48 | 48 | 0 | 60 | 0 | 2.0 / 1 / 13 | 179.6 |
| lox | rc | 3 | 18 | 60 | 48 | 48 | 0 | 60 | 0 | 4.2 / 4 / 13 | 193.5 |
| synthetic | gc | 1 | 8 | 60 | 52 | 52 | 0 | 60 | 0 | 3.9 / 4 / 8 | 187.1 |
| synthetic | rc | 1 | 8 | 60 | 52 | 52 | 0 | 60 | 0 | 4.2 / 4 / 8 | 30.8 |
| synthetic | gc | 2 | 7 | 60 | 55 | 55 | 0 | 60 | 0 | 2.3 / 1 / 7 | 284.2 |
| synthetic | rc | 2 | 7 | 60 | 55 | 55 | 0 | 60 | 0 | 2.7 / 2 / 7 | 24.0 |
| synthetic | gc | 31 | 6 | 60 | 53 | 53 | 0 | 60 | 0 | 2.5 / 2 / 5 | 255.8 |
| synthetic | rc | 31 | 6 | 60 | 53 | 53 | 0 | 60 | 0 | 3.2 / 3 / 6 | 31.5 |
| synthetic | gc | 32 | 8 | 60 | 56 | 56 | 0 | 60 | 0 | 2.6 / 1 / 8 | 275.4 |
| synthetic | rc | 32 | 8 | 60 | 56 | 56 | 0 | 60 | 0 | 2.9 / 3 / 8 | 28.6 |
| synthetic | gc | 3 | 9 | 60 | 56 | 56 | 0 | 60 | 0 | 3.2 / 3 / 9 | 549.0 |
| synthetic | rc | 3 | 9 | 60 | 56 | 56 | 0 | 60 | 0 | 3.7 / 4 / 9 | 37.3 |

Total: 1200 edit steps, 1068 built (89%), 1200 matched the oracle, 0 findings, 132 revert checks.

## Edit kinds

| kind | applied | built | failed | off module path | compiled mean/median/max |
|---|---|---|---|---|---|
| int-literal | 118 | 118 | 0 | 0 | 2.6 / 1 / 10 |
| use-added | 84 | 84 | 0 | 0 | 2.4 / 2 / 11 |
| wrap-return | 78 | 78 | 0 | 0 | 3.4 / 3 / 9 |
| add-private-fn | 68 | 68 | 0 | 0 | 1.2 / 1 / 6 |
| add-public-fn | 68 | 68 | 0 | 0 | 5.0 / 4 / 13 |
| const-value | 62 | 62 | 0 | 0 | 6.5 / 6 / 14 |
| insert-statement | 58 | 58 | 0 | 0 | 2.5 / 2 / 9 |
| helper-call | 56 | 56 | 0 | 0 | 5.3 / 4 / 16 |
| record-field-add | 48 | 48 | 0 | 0 | 6.3 / 6 / 14 |
| add-default-param | 46 | 46 | 0 | 0 | 4.7 / 4 / 13 |
| remove-added | 44 | 44 | 0 | 0 | 3.9 / 3 / 12 |
| float-literal | 40 | 40 | 0 | 0 | 2.7 / 2 / 10 |
| start-alloc | 40 | 40 | 0 | 0 | 3.6 / 3 / 10 |
| rename-public-def | 38 | 12 | 26 | 0 | 2.7 / 4 / 5 |
| rename-added | 36 | 36 | 0 | 0 | 3.6 / 2 / 13 |
| add-const | 30 | 30 | 0 | 0 | 2.9 / 1 / 16 |
| comment | 30 | 30 | 0 | 0 | 1.7 / 1 / 4 |
| drop-record-field | 26 | 0 | 26 | 0 | - |
| toggle-visibility | 26 | 26 | 0 | 0 | 4.2 / 3 / 13 |
| add-required-param | 26 | 2 | 24 | 0 | 3.0 / 3 / 3 |
| noop | 24 | 24 | 0 | 0 | 0.0 / 0 / 0 |
| remove-public-fn | 24 | 6 | 18 | 0 | 1.3 / 1 / 2 |
| move-function | 24 | 24 | 0 | 0 | 1.2 / 1 / 2 |
| change-return-type | 20 | 0 | 20 | 0 | - |
| break-type | 18 | 0 | 18 | 0 | - |
| change-default | 16 | 16 | 0 | 0 | 6.4 / 5 / 14 |
| whitespace | 16 | 16 | 0 | 0 | 1.1 / 1 / 2 |
| record-field-remove | 14 | 14 | 0 | 0 | 7.9 / 7 / 13 |
| stop-alloc | 12 | 12 | 0 | 0 | 3.9 / 3 / 10 |
| change-field-default | 10 | 10 | 0 | 0 | 6.0 / 6 / 8 |

## Compiled-module counts (engaged incremental builds)

| compiled | builds |
|---|---|
| 0 | 24 |
| 1 | 398 |
| 2 | 136 |
| 3 | 95 |
| 4 | 115 |
| 5 | 100 |
| 6 | 41 |
| 7 | 44 |
| 8 | 26 |
| 9 | 15 |
| 10 | 7 |
| 11 | 5 |
| 12 | 16 |
| 13 | 29 |
| 14 | 9 |
| 16 | 8 |

## Why edits failed to build

| kind | diagnostic | count |
|---|---|---|
| rename-public-def | E_UNKNOWN_SYMBOL | 26 |
| add-required-param | E_ARITY | 24 |
| change-return-type | E_TYPE | 20 |
| remove-public-fn | E_UNKNOWN_SYMBOL | 18 |
| break-type | E_TYPE | 18 |
| drop-record-field | E_UNKNOWN_FIELD | 16 |
| drop-record-field | E_ARITY | 10 |

Failed steps where the two builds reported different error sets: 0.
