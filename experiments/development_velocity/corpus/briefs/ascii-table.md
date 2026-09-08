# ascii-table

Version: 1. Family: data-text. Kind: feature. Tier: small.

Request: {"columns":INT,"rows":[[TEXT,...],...]}. columns ranges
0..8; there are at most 64 rows and exactly columns cells per row. TEXT has
0..32 printable ASCII bytes (32..126), including spaces. Compute each column's
maximum cell byte length, defaulting to zero when no rows. Return {"widths":[INT],
"lines":[TEXT]}: pad every cell on the RIGHT with ASCII spaces to its column
width, including the final column, and join with exactly " | ". Do not trim.
A row with zero columns emits an empty string. No Unicode display-width rule.

Apply the shared PROCESS.md transport, type, schema and validation rules.
