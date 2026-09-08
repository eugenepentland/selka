# quota-boundary

Version: 1. Family: configuration. Kind: bugfix. Tier: small.

Request: {"limit":INT,"used":INT,"requests":[INT,...]}.
limit ranges 0..1000000, used ranges 0..limit, and request amounts range
0..1000000. Process amounts in order: accept exactly when used+amount <= limit;
on acceptance increase used, otherwise leave it unchanged. Zero is accepted
at full capacity. Return {"accepted":[BOOL],"used":INT,"remaining":limit-used}.
Repair the supplied equivalent starter's inclusive-boundary defect; preserve
its interface and unchanged behavior away from equality.

Apply the shared PROCESS.md transport, type, schema and validation rules.
