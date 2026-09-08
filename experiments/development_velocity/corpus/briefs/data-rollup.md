# data-rollup

Version: 1. Family: data-text. Kind: feature. Tier: small.

Request: {"rows":[{"key":ID,"delta":INT}], "minimum":INT?}.
minimum is optional, defaults to -128000000, and ranges -128000000..128000000.
Group all rows by key, preserving zero totals; return {"groups":[{"key":ID,
"count":INT,"total":INT}]} sorted by key, including only groups with total >=
minimum. Counts include every row. Empty input yields an empty groups array.

Apply the shared PROCESS.md transport, type, schema and validation rules.
